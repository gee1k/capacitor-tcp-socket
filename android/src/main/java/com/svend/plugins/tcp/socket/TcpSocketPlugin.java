package com.svend.plugins.tcp.socket;

import android.util.Base64;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

@CapacitorPlugin(name = "TcpSocket")
public class TcpSocketPlugin extends Plugin {

    public static final String READ_EOF_ERROR_CODE = "EOF";
    private final Map<Integer, Client> clients = new ConcurrentHashMap<>();
    private final Map<Integer, ServerSocket> servers = new ConcurrentHashMap<>();
    private final Set<Integer> accepting = Collections.newSetFromMap(new ConcurrentHashMap<Integer, Boolean>());
    private final Set<PendingConnect> connecting = Collections.newSetFromMap(new ConcurrentHashMap<PendingConnect, Boolean>());
    private final ConcurrentHashMap<PluginCall, ServerSocket> pendingListens = new ConcurrentHashMap<>();
    private final AtomicInteger nextClient = new AtomicInteger();
    private final AtomicInteger nextServer = new AtomicInteger();
    private final ExecutorService workers = Executors.newCachedThreadPool();
    private final ScheduledExecutorService timers = Executors.newSingleThreadScheduledExecutor();
    private volatile boolean destroyed;

    private static ExecutorService serialWorker() {
        // Idle connections do not keep a pair of permanent native threads alive.
        return new ThreadPoolExecutor(0, 1, 30, TimeUnit.SECONDS, new LinkedBlockingQueue<Runnable>());
    }

    private static void close(Socket socket) {
        try {
            socket.close();
        } catch (IOException ignored) {}
    }

    private static void close(ServerSocket socket) {
        try {
            socket.close();
        } catch (IOException ignored) {}
    }

    private static final class Client {

        final Socket socket;
        final ExecutorService reads = serialWorker();
        final ExecutorService writes = serialWorker();
        volatile boolean closed;

        Client(Socket socket) {
            this.socket = socket;
        }

        void close() {
            closed = true;
            TcpSocketPlugin.close(socket);
            // Drain queued calls so each observes CLOSED and settles its Promise.
            reads.shutdown();
            writes.shutdown();
        }
    }

    private synchronized int registerClient(Socket socket) throws IOException {
        if (destroyed) {
            close(socket);
            throw new IOException("Plugin destroyed");
        }
        int id = nextClient.getAndIncrement();
        clients.put(id, new Client(socket));
        return id;
    }

    private Integer number(PluginCall call, String key, int fallback, int min, int max) {
        int value = call.getInt(key, fallback);
        if (value < min || value > max) {
            call.reject("Invalid " + key, "INVALID_ARGUMENT");
            return null;
        }
        return value;
    }

    private Integer timeout(PluginCall call) {
        return number(call, "timeout", 10, 0, Integer.MAX_VALUE / 1000);
    }

    private Client client(PluginCall call) {
        Integer id = number(call, "client", -1, 0, nextClient.get() - 1);
        if (id == null) return null;
        Client client = clients.get(id);
        if (client == null) call.reject("Client closed", "CLOSED");
        return client;
    }

    private boolean submit(ExecutorService executor, PluginCall call, Runnable action) {
        try {
            executor.execute(action);
            return true;
        } catch (RejectedExecutionException error) {
            call.reject("Plugin or client closed", "CLOSED");
            return false;
        }
    }

    private void ioFailure(PluginCall call, Client client, Exception error) {
        call.reject(error.getMessage(), client.closed ? "CLOSED" : error instanceof SocketTimeoutException ? "TIMEOUT" : "IO_ERROR");
    }

    private final class PendingConnect {

        final Socket socket = new Socket();
        final PluginCall call;
        boolean finished;
        ScheduledFuture<?> timer;

        PendingConnect(PluginCall call) {
            this.call = call;
        }

        synchronized void fail(String message, String code) {
            if (finished) return;
            finished = true;
            if (timer != null) timer.cancel(false);
            connecting.remove(this);
            close(socket);
            call.reject(message, code);
        }

        synchronized void succeed() {
            if (finished) {
                close(socket);
                return;
            }
            try {
                int id = registerClient(socket);
                finished = true;
                if (timer != null) timer.cancel(false);
                connecting.remove(this);
                JSObject result = new JSObject();
                result.put("client", id);
                call.resolve(result);
            } catch (IOException error) {
                fail(error.getMessage(), "CLOSED");
            }
        }
    }

    @PluginMethod
    public void connect(PluginCall call) {
        String host = call.getString("ipAddress");
        if (host == null || host.isEmpty()) {
            call.reject("IP address is required", "INVALID_ARGUMENT");
            return;
        }
        Integer port = number(call, "port", 9100, 1, 65535);
        Integer seconds = timeout(call);
        if (port == null || seconds == null) return;
        PendingConnect pending = new PendingConnect(call);
        synchronized (this) {
            if (destroyed) {
                pending.fail("Plugin destroyed", "CLOSED");
                return;
            }
            connecting.add(pending);
            if (seconds > 0) pending.timer = timers.schedule(() -> pending.fail("Connect timed out", "TIMEOUT"), seconds, TimeUnit.SECONDS);
        }
        try {
            workers.execute(() -> {
                try {
                    // DNS and connect happen off the Capacitor thread. The timer above
                    // includes DNS and settles the call even if OS DNS is slow.
                    pending.socket.connect(new InetSocketAddress(host, port), seconds * 1000);
                    pending.succeed();
                } catch (IOException | IllegalArgumentException error) {
                    pending.fail(
                        error.getMessage(),
                        destroyed ? "CLOSED" : error instanceof SocketTimeoutException ? "TIMEOUT" : "CONNECT_FAILED"
                    );
                }
            });
        } catch (RejectedExecutionException error) {
            pending.fail("Plugin destroyed", "CLOSED");
        }
    }

    @PluginMethod
    public void listen(PluginCall call) {
        Integer port = number(call, "port", 0, 0, 65535);
        String host = call.getString("ipAddress", "127.0.0.1");
        if (port == null) return;
        if (host.isEmpty()) {
            call.reject("Invalid bind address", "INVALID_ARGUMENT");
            return;
        }
        final ServerSocket server;
        try {
            server = new ServerSocket();
        } catch (IOException error) {
            call.reject(error.getMessage(), "LISTEN_FAILED");
            return;
        }
        synchronized (this) {
            if (destroyed) {
                close(server);
                call.reject("Plugin destroyed", "CLOSED");
                return;
            }
            pendingListens.put(call, server);
            // Submit while holding the registry lock so destroy cannot shut down
            // the executor between registration and submission.
            workers.execute(() -> {
                try {
                    server.setReuseAddress(true);
                    server.bind(new InetSocketAddress(host, port), 128);
                    int boundPort = server.getLocalPort();
                    int id;
                    synchronized (this) {
                        if (pendingListens.remove(call) == null) {
                            close(server);
                            return;
                        }
                        if (destroyed) {
                            close(server);
                            call.reject("Plugin destroyed", "CLOSED");
                            return;
                        }
                        id = nextServer.getAndIncrement();
                        servers.put(id, server);
                    }
                    JSObject result = new JSObject();
                    result.put("server", id);
                    result.put("port", boundPort);
                    call.resolve(result);
                } catch (IOException | IllegalArgumentException error) {
                    close(server);
                    if (pendingListens.remove(call) != null) call.reject(error.getMessage(), destroyed ? "CLOSED" : "LISTEN_FAILED");
                }
            });
        }
    }

    @PluginMethod
    public void accept(PluginCall call) {
        Integer id = number(call, "server", -1, 0, nextServer.get() - 1);
        Integer seconds = timeout(call);
        if (id == null || seconds == null) return;
        ServerSocket server = servers.get(id);
        if (server == null) {
            call.reject("Server closed", "CLOSED");
            return;
        }
        if (!accepting.add(id)) {
            call.reject("An accept is already pending", "BUSY");
            return;
        }
        if (
            !submit(workers, call, () -> {
                Socket socket = null;
                try {
                    server.setSoTimeout(seconds * 1000);
                    socket = server.accept();
                    int clientId;
                    synchronized (this) {
                        if (server.isClosed()) throw new IOException("Server closed");
                        clientId = registerClient(socket);
                    }
                    JSObject result = new JSObject();
                    result.put("client", clientId);
                    accepting.remove(id);
                    call.resolve(result);
                } catch (IOException error) {
                    if (socket != null) close(socket);
                    accepting.remove(id);
                    call.reject(
                        error.getMessage(),
                        server.isClosed() || destroyed ? "CLOSED" : error instanceof SocketTimeoutException ? "TIMEOUT" : "IO_ERROR"
                    );
                }
            })
        ) accepting.remove(id);
    }

    @PluginMethod
    public synchronized void closeServer(PluginCall call) {
        Integer id = number(call, "server", -1, 0, nextServer.get() - 1);
        if (id == null) return;
        ServerSocket server = servers.remove(id);
        if (server != null) close(server);
        JSObject result = new JSObject();
        result.put("server", id);
        call.resolve(result);
    }

    private String encoding(PluginCall call) {
        String value = call.getString("encoding", "utf8");
        if (!value.equals("utf8") && !value.equals("hex") && !value.equals("base64")) {
            call.reject("Unsupported encoding", "INVALID_ARGUMENT");
            return null;
        }
        return value;
    }

    private byte[] decode(String data, String encoding) {
        switch (encoding) {
            case "hex":
                if (!data.matches("(?:[0-9a-fA-F]{2})*")) throw new IllegalArgumentException("Hex must contain complete bytes");
                byte[] bytes = new byte[data.length() / 2];
                for (int i = 0; i < bytes.length; i++) bytes[i] = (byte) Integer.parseInt(data.substring(i * 2, i * 2 + 2), 16);
                return bytes;
            case "base64":
                byte[] decoded = Base64.decode(data, Base64.NO_WRAP);
                if (!Base64.encodeToString(decoded, Base64.NO_WRAP).equals(data)) throw new IllegalArgumentException("Invalid Base64");
                return decoded;
            default:
                return data.getBytes(StandardCharsets.UTF_8);
        }
    }

    @PluginMethod
    public void send(PluginCall call) {
        Client client = client(call);
        if (client == null) return;
        String encoding = encoding(call);
        if (encoding == null) return;
        String data = call.getString("data");
        if (data == null) {
            call.reject("data is required", "INVALID_ARGUMENT");
            return;
        }
        final byte[] bytes;
        try {
            bytes = decode(data, encoding);
        } catch (IllegalArgumentException error) {
            call.reject(error.getMessage(), "INVALID_ARGUMENT");
            return;
        }
        submit(client.writes, call, () -> {
            if (client.closed) {
                call.reject("Client closed", "CLOSED");
                return;
            }
            try {
                if (bytes.length > 0) client.socket.getOutputStream().write(bytes);
                call.resolve();
            } catch (IOException error) {
                ioFailure(call, client, error);
            }
        });
    }

    @PluginMethod
    public void read(PluginCall call) {
        Client client = client(call);
        if (client == null) return;
        Integer length = number(call, "expectLen", 1024, 1, Integer.MAX_VALUE);
        Integer seconds = timeout(call);
        String encoding = encoding(call);
        if (length == null || seconds == null || encoding == null) return;
        submit(client.reads, call, () -> {
            if (client.closed) {
                call.reject("Client closed", "CLOSED");
                return;
            }
            try {
                client.socket.setSoTimeout(seconds * 1000);
                // TCP may return a short read. Never allocate caller-sized gigabyte arrays.
                byte[] buffer = new byte[Math.min(length, 65536)];
                int count = client.socket.getInputStream().read(buffer);
                if (client.closed) {
                    call.reject("Client closed", "CLOSED");
                    return;
                }
                if (count == -1) {
                    call.reject("Peer closed its sending side", "EOF");
                    return;
                }
                byte[] data = Arrays.copyOf(buffer, count);
                String actualEncoding = encoding;
                String text;
                switch (encoding) {
                    case "hex":
                        StringBuilder hex = new StringBuilder(count * 2);
                        final char[] digits = "0123456789abcdef".toCharArray();
                        for (byte b : data) {
                            hex.append(digits[(b & 255) >>> 4]);
                            hex.append(digits[b & 15]);
                        }
                        text = hex.toString();
                        break;
                    case "base64":
                        text = Base64.encodeToString(data, Base64.NO_WRAP);
                        break;
                    default:
                        try {
                            text = StandardCharsets.UTF_8.newDecoder()
                                .onMalformedInput(CodingErrorAction.REPORT)
                                .onUnmappableCharacter(CodingErrorAction.REPORT)
                                .decode(ByteBuffer.wrap(data))
                                .toString();
                        } catch (CharacterCodingException error) {
                            text = Base64.encodeToString(data, Base64.NO_WRAP);
                            actualEncoding = "base64";
                        }
                }
                JSObject result = new JSObject();
                result.put("result", text);
                result.put("encoding", actualEncoding);
                call.resolve(result);
            } catch (IOException error) {
                ioFailure(call, client, error);
            }
        });
    }

    @PluginMethod
    public void disconnect(PluginCall call) {
        Integer id = number(call, "client", -1, 0, nextClient.get() - 1);
        if (id == null) return;
        Client client = clients.remove(id);
        if (client != null) client.close();
        JSObject result = new JSObject();
        result.put("client", id);
        call.resolve(result);
    }

    @Override
    protected void handleOnDestroy() {
        synchronized (this) {
            destroyed = true;
            for (ServerSocket server : servers.values()) close(server);
            servers.clear();
            for (Map.Entry<PluginCall, ServerSocket> pending : pendingListens.entrySet()) {
                if (pendingListens.remove(pending.getKey(), pending.getValue())) {
                    close(pending.getValue());
                    pending.getKey().reject("Plugin destroyed", "CLOSED");
                }
            }
            pendingListens.clear();
            for (Client client : clients.values()) client.close();
            clients.clear();
        }
        // Do not hold the registry lock while acquiring a PendingConnect lock.
        for (PendingConnect pending : connecting) pending.fail("Plugin destroyed", "CLOSED");
        timers.shutdownNow();
        workers.shutdown();
        super.handleOnDestroy();
    }
}
