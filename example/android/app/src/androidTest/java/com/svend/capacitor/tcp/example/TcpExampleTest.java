package com.svend.capacitor.tcp.example;

import static org.junit.Assert.*;

import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.runner.lifecycle.ActivityLifecycleCallback;
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry;
import androidx.test.runner.lifecycle.Stage;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Runs the packaged example UI -> JS import -> Capacitor bridge -> native TCP -> real echo server. */
@RunWith(AndroidJUnit4.class)
public class TcpExampleTest {

    private final Handler main = new Handler(Looper.getMainLooper());

    private void launchExample() throws Exception {
        CountDownLatch resumed = new CountDownLatch(1);
        AtomicReference<Throwable> failure = new AtomicReference<>();
        ActivityLifecycleCallback observer = (activity, stage) -> {
            if (activity instanceof MainActivity && stage == Stage.RESUMED) resumed.countDown();
        };
        main.post(() -> {
            try {
                ActivityLifecycleMonitorRegistry.getInstance().addLifecycleCallback(observer);
                android.content.Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
                context.startActivity(new Intent(context, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            } catch (Throwable error) {
                failure.set(error);
                resumed.countDown();
            }
        });
        try {
            assertTrue("Example Activity did not resume", resumed.await(120, TimeUnit.SECONDS));
            if (failure.get() != null) throw new AssertionError("Example launch failed", failure.get());
        } finally {
            main.post(() -> ActivityLifecycleMonitorRegistry.getInstance().removeLifecycleCallback(observer));
        }
    }

    private String evaluate(String script) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        AtomicReference<String> result = new AtomicReference<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();
        // Do not wait for global UI idleness: WebView may be drawing continuously.
        main.post(() -> {
            try {
                MainActivity activity = (MainActivity) ActivityLifecycleMonitorRegistry.getInstance()
                    .getActivitiesInStage(Stage.RESUMED)
                    .stream()
                    .filter(candidate -> candidate instanceof MainActivity)
                    .findFirst()
                    .orElseThrow(() -> new IllegalStateException("Example Activity is not resumed"));
                activity
                    .getBridge()
                    .getWebView()
                    .evaluateJavascript(script, value -> {
                        result.set(value);
                        done.countDown();
                    });
            } catch (Throwable error) {
                failure.set(error);
                done.countDown();
            }
        });
        assertTrue("WebView callback timed out", done.await(30, TimeUnit.SECONDS));
        if (failure.get() != null) throw new AssertionError("WebView evaluation failed", failure.get());
        return result.get();
    }

    private void finishExample() throws Exception {
        CountDownLatch finishing = new CountDownLatch(1);
        main.post(() -> {
            for (Stage stage : new Stage[] { Stage.RESUMED, Stage.PAUSED, Stage.STARTED, Stage.STOPPED, Stage.CREATED }) {
                for (android.app.Activity activity : new java.util.ArrayList<>(
                    ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(stage)
                )) {
                    if (activity instanceof MainActivity) activity.finish();
                }
            }
            finishing.countDown();
        });
        finishing.await(30, TimeUnit.SECONDS);
    }

    @Test
    public void packagedExampleRunsRealTcpSmokeTest() throws Exception {
        ExecutorService executor = Executors.newSingleThreadExecutor();
        try (ServerSocket server = new ServerSocket(0)) {
            Future<?> echo = executor.submit(() -> {
                try (Socket socket = server.accept()) {
                    socket.setSoTimeout(20000);
                    byte[] buffer = new byte[1024];
                    java.io.ByteArrayOutputStream pending = new java.io.ByteArrayOutputStream();
                    int count;
                    while ((count = socket.getInputStream().read(buffer)) != -1) {
                        pending.write(buffer, 0, count);
                        byte[] data = pending.toByteArray();
                        String text = new String(data, StandardCharsets.UTF_8);
                        if (("DELAY\n".startsWith(text) || "CLOSE\n".startsWith(text)) && !text.endsWith("\n")) continue;
                        pending.reset();
                        if (text.equals("CLOSE\n")) {
                            socket.shutdownOutput();
                            java.io.ByteArrayOutputStream afterEOF = new java.io.ByteArrayOutputStream();
                            while ((count = socket.getInputStream().read(buffer)) != -1) afterEOF.write(buffer, 0, count);
                            assertEquals("AFTER_EOF\n", afterEOF.toString("UTF-8"));
                            break;
                        }
                        if (text.equals("DELAY\n")) Thread.sleep(3000);
                        socket.getOutputStream().write(data);
                        socket.getOutputStream().flush();
                    }
                } catch (Exception error) {
                    throw new RuntimeException(error);
                }
            });
            launchExample();
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(120);
            while (!evaluate("!!document.querySelector('capacitor-welcome')?.shadowRoot?.querySelector('#smoke-btn')").equals("true")) {
                assertTrue("Example did not load", System.nanoTime() < deadline);
                Thread.sleep(500);
            }
            evaluate(
                "(() => { const root = document.querySelector('capacitor-welcome').shadowRoot;" +
                "root.querySelector('#ip-address').value = '127.0.0.1';" +
                "root.querySelector('#port').value = '" +
                server.getLocalPort() +
                "';" +
                "root.querySelector('#smoke-btn').click(); })()"
            );
            deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(60);
            String result;
            do {
                result = evaluate("document.querySelector('capacitor-welcome').dataset.smokeResult || ''");
                assertTrue("Native smoke test timed out: " + result, System.nanoTime() < deadline);
                Thread.sleep(500);
            } while (result.equals("\"\""));
            assertEquals("\"passed\"", result);
            echo.get(5, TimeUnit.SECONDS);
        } finally {
            try {
                finishExample();
            } finally {
                executor.shutdownNow();
            }
        }
    }

    @Test
    public void pluginDestructionSettlesPendingOperations() throws Exception {
        try {
            launchExample();
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(120);
            while (!evaluate("!!window.Capacitor?.Plugins?.TcpSocket").equals("true")) {
                assertTrue("Plugin not registered", System.nanoTime() < deadline);
                Thread.sleep(100);
            }
            evaluate(
                "(async () => {" +
                "const tcp = window.Capacitor.Plugins.TcpSocket;" +
                "const {server, port} = await tcp.listen({});" +
                "const accepting = tcp.accept({server});" +
                "const {client} = await tcp.connect({ipAddress:'127.0.0.1',port});" +
                "await accepting;" +
                "const code = p => p.then(() => 'unexpected success', e => e.code);" +
                "const pending = [code(tcp.read({client,timeout:0})), code(tcp.read({client,timeout:0})), code(tcp.accept({server,timeout:0}))];" +
                "await tcp.send({client,data:''});" +
                "window.__destroyReady = true;" +
                "const results = await Promise.all(pending);" +
                "results.push(await code(tcp.connect({ipAddress:'127.0.0.1',port})));" +
                "window.__destroyResult = results.join(',');" +
                "})().catch(e => {window.__destroyResult = 'failed: '+e.message; window.__destroyReady = true;});"
            );
            deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(15);
            while (!evaluate("!!window.__destroyReady").equals("true")) {
                assertTrue("Lifecycle setup timed out", System.nanoTime() < deadline);
                Thread.sleep(100);
            }
            AtomicReference<Throwable> failure = new AtomicReference<>();
            CountDownLatch destroyed = new CountDownLatch(1);
            main.post(() -> {
                try {
                    MainActivity activity = (MainActivity) ActivityLifecycleMonitorRegistry.getInstance()
                        .getActivitiesInStage(Stage.RESUMED)
                        .stream()
                        .filter(a -> a instanceof MainActivity)
                        .findFirst()
                        .get();
                    Object plugin = activity.getBridge().getPlugin("TcpSocket").getInstance();
                    java.lang.reflect.Method method = plugin.getClass().getDeclaredMethod("handleOnDestroy");
                    method.setAccessible(true);
                    method.invoke(plugin);
                } catch (Throwable error) {
                    failure.set(error);
                } finally {
                    destroyed.countDown();
                }
            });
            assertTrue("Destroy callback stalled", destroyed.await(5, TimeUnit.SECONDS));
            if (failure.get() != null) throw new AssertionError(failure.get());
            deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
            String result;
            do {
                result = evaluate("window.__destroyResult || ''");
                assertTrue("Pending operations were not settled", System.nanoTime() < deadline);
                Thread.sleep(100);
            } while (result.equals("\"\""));
            assertEquals("\"CLOSED,CLOSED,CLOSED,CLOSED\"", result);
        } finally {
            finishExample();
        }
    }
}
