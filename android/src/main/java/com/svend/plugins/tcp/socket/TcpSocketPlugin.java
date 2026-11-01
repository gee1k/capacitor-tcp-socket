package com.svend.plugins.tcp.socket;

import android.Manifest;
import android.util.Log;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import java.io.BufferedOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.Socket;
import java.net.ServerSocket;
import java.net.InetSocketAddress;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.Collections;
import java.net.SocketTimeoutException;
import java.util.ArrayList;
import java.util.List;
import java.nio.charset.StandardCharsets;
import android.util.Base64;

/**
 * TcpSocketPlugin - Capacitor plugin that provides TCP Socket communication functionality
 * Supports connection, data sending, data receiving and disconnection operations
 */
@CapacitorPlugin(
    name = "TcpSocket",
    permissions = { @Permission(alias = "network", strings = { Manifest.permission.ACCESS_NETWORK_STATE }) }
)
public class TcpSocketPlugin extends Plugin {
    private static final String TAG = "TcpSocketPlugin";
    public static final String READ_EOF_ERROR_CODE = "EOF";
    private List<Socket> clients = Collections.synchronizedList(new ArrayList<>());
    private final Map<Integer, ServerSocket> servers = new ConcurrentHashMap<>();
    private final java.util.Set<Integer> accepting = Collections.newSetFromMap(new ConcurrentHashMap<Integer, Boolean>());
    private final AtomicInteger nextServer = new AtomicInteger();
    private volatile boolean destroyed;

    private int registerClient(Socket socket) throws IOException {
        synchronized (clients) {
            if (destroyed) { socket.close(); throw new IOException("Plugin destroyed"); }
            clients.add(socket);
            return clients.size() - 1;
        }
    }

    @PluginMethod
    public void listen(PluginCall call) {
        int port = call.getInt("port", 0);
        String address = call.getString("ipAddress", "127.0.0.1");
        if (port < 0 || port > 65535 || address.isEmpty()) { call.reject("Invalid bind address or port"); return; }
        new Thread(() -> {
            ServerSocket server = null;
            try {
                server = new ServerSocket();
                server.bind(new InetSocketAddress(address, port));
                int id = nextServer.getAndIncrement();
                synchronized (servers) {
                    if (destroyed) throw new IOException("Plugin destroyed");
                    servers.put(id, server);
                }
                JSObject result = new JSObject();
                result.put("server", id);
                result.put("port", server.getLocalPort());
                call.resolve(result);
            } catch (IOException | IllegalArgumentException error) {
                if (server != null) try { server.close(); } catch (IOException ignored) { }
                call.reject("Listen failed: " + error.getMessage());
            }
        }).start();
    }

    @PluginMethod
    public void accept(PluginCall call) {
        int id = call.getInt("server", -1);
        int timeout = call.getInt("timeout", 10);
        ServerSocket server = servers.get(id);
        if (server == null) { call.reject("Unknown server"); return; }
        if (timeout < 0 || timeout > Integer.MAX_VALUE / 1000) { call.reject("Invalid timeout"); return; }
        if (!accepting.add(id)) { call.reject("An accept is already pending"); return; }
        new Thread(() -> {
            try {
                server.setSoTimeout(timeout * 1000);
                Socket socket = server.accept();
                JSObject result = new JSObject();
                result.put("client", registerClient(socket));
                accepting.remove(id);
                call.resolve(result);
            } catch (SocketTimeoutException error) {
                accepting.remove(id);
                call.reject("Accept timed out", "TIMEOUT");
            } catch (IOException error) {
                accepting.remove(id);
                call.reject("Accept failed: " + error.getMessage(), server.isClosed() ? "CLOSED" : null);
            }
        }).start();
    }

    @PluginMethod
    public void closeServer(PluginCall call) {
        int id = call.getInt("server", -1);
        ServerSocket server = servers.remove(id);
        if (server == null) { call.reject("Unknown server"); return; }
        try {
            server.close();
            JSObject result = new JSObject();
            result.put("server", id);
            call.resolve(result);
        } catch (IOException error) { call.reject(error.getMessage()); }
    }
    
    // Supported data encoding types
    private enum DataEncoding {
        UTF8("utf8"),
        BASE64("base64"),
        HEX("hex");
        
        private final String value;
        
        DataEncoding(String value) {
            this.value = value;
        }
        
        public String getValue() {
            return value;
        }
        
        public static DataEncoding fromString(String text) {
            for (DataEncoding encoding : DataEncoding.values()) {
                if (encoding.value.equalsIgnoreCase(text)) {
                    return encoding;
                }
            }
            return UTF8; // Default to UTF8 if not found
        }
    }

    /**
     * Connect to TCP server
     * Parameters:
     * - ipAddress: Server IP address (required)
     * - port: Server port, default 9100
     * Returns:
     * - client: Client index, used for subsequent operations
     */
    @PluginMethod
    public void connect(PluginCall call) {
        String ipAddress = call.getString("ipAddress");

        if (ipAddress == null || ipAddress.isEmpty()) {
            call.reject("IP address is required");
            return;
        }
        Integer port = call.getInt("port", 9100);

        try {
            Socket socket = new Socket(ipAddress, port);
            int id = registerClient(socket);
            JSObject ret = new JSObject();
            ret.put("client", id);
            call.resolve(ret);
        } catch (IOException e) {
            Log.e(TAG, "Connection failed: " + e.getMessage());
            call.reject("Connection failed: " + e.getMessage());
        }
    }

    /**
     * Send data to server with specified encoding
     * Parameters:
     * - client: Client index
     * - data: Data to send
     * - encoding: Data encoding (utf8, base64, hex), default is utf8
     */
    @PluginMethod
    public void send(final PluginCall call) {
        final Integer clientIndex = call.getInt("client", -1);

        if (clientIndex == -1) {
            call.reject("Client not specified or invalid index");
            return;
        }
        
        if (clientIndex >= clients.size() || clientIndex < 0) {
            call.reject("Client index out of range");
            return;
        }
        
        final String data = call.getString("data");
        if (data == null || data.isEmpty()) {
            call.reject("No data provided");
            return;
        }
        
        final String encodingString = call.getString("encoding", "utf8");
        final DataEncoding encoding = DataEncoding.fromString(encodingString);

        Socket socket = clients.get(clientIndex);
        if (!socket.isConnected()) {
            closeSocketSafely(socket);
            call.reject("Socket not connected");
            return;
        }

        Runnable runnable = new Runnable() {
            @Override
            public void run() {
                try {
                    final Socket socket = clients.get(clientIndex);
                    DataOutputStream bufferOut = new DataOutputStream(new BufferedOutputStream(socket.getOutputStream()));
                    
                    // Convert and send data according to the specified encoding
                    byte[] bytes;
                    switch (encoding) {
                        case BASE64:
                            bytes = Base64.decode(data, Base64.DEFAULT);
                            break;
                        case HEX:
                            bytes = hexStringToBytes(data);
                            break;
                        case UTF8:
                        default:
                            bytes = data.getBytes(StandardCharsets.UTF_8);
                            break;
                    }
                    
                    if (bytes != null) {
                        bufferOut.write(bytes);
                        bufferOut.flush();
                        call.resolve();
                    } else {
                        call.reject("Failed to decode data with encoding: " + encodingString);
                    }
                } catch (IOException e) {
                    Log.e(TAG, "Send failed: " + e.getMessage());
                    call.reject("Send failed: " + e.getMessage());
                }
            }
        };
        
        Thread thread = new Thread(runnable);
        thread.start();
    }

    /**
     * Read data from server
     * Parameters:
     * - client: Client index
     * - expectLen: Expected number of bytes to read, default 1024
     * - timeout: Read timeout in seconds, default 10
     * - encoding: Preferred encoding for returned data (utf8, base64, hex), default is utf8
     * Returns:
     * - result: Data read
     * - encoding: The encoding used for the result
     */
    @PluginMethod
    public void read(final PluginCall call) {
        final Integer clientIndex = call.getInt("client", -1);
        final Integer length = call.getInt("expectLen", 1024);
        final int timeoutSec = call.getInt("timeout", 10);

        if (clientIndex == -1) {
            call.reject("Client not specified or invalid index");
            return;
        }
        
        if (clientIndex >= clients.size() || clientIndex < 0) {
            call.reject("Client index out of range");
            return;
        }

        Socket socket = clients.get(clientIndex);
        if (!socket.isConnected()) {
            closeSocketSafely(socket);
            call.reject("Socket not connected");
            return;
        }
        
        final String encodingString = call.getString("encoding", "utf8");
        final DataEncoding encoding = DataEncoding.fromString(encodingString);

        Runnable runnable = new Runnable() {
            @Override
            public void run() {
                try {
                    final Socket socket = clients.get(clientIndex);
                    socket.setSoTimeout(timeoutSec * 1000);
                    InputStream inputStream = socket.getInputStream();
                    byte[] bytes = new byte[length];
                    int read = inputStream.read(bytes, 0, length);

                    if (read == -1) {
                        if (call.getBoolean("rejectOnEOF", true)) {
                            call.reject("Connection closed", READ_EOF_ERROR_CODE);
                        } else {
                            JSObject eof = new JSObject();
                            eof.put("result", "");
                            eof.put("encoding", encoding.getValue());
                            call.resolve(eof);
                        }
                        return;
                    }

                    JSObject ret = new JSObject();
                    String result = "";
                    String actualEncoding = encoding.getValue();

                    if (read > 0) {
                        byte[] actualData = new byte[read];
                        System.arraycopy(bytes, 0, actualData, 0, read);

                        switch (encoding) {
                            case UTF8:
                                try {
                                    result = new String(actualData, StandardCharsets.UTF_8);
                                } catch (Exception e) {
                                    result = Base64.encodeToString(actualData, Base64.NO_WRAP);
                                    actualEncoding = DataEncoding.BASE64.getValue();
                                }
                                break;
                            case BASE64:
                                result = Base64.encodeToString(actualData, Base64.NO_WRAP);
                                break;
                            case HEX:
                                result = bytesToHexString(actualData);
                                break;
                        }
                    }

                    ret.put("result", result);
                    ret.put("encoding", actualEncoding);
                    call.resolve(ret);
                } catch (SocketTimeoutException e) {
                    JSObject ret = new JSObject();
                    ret.put("result", "");
                    ret.put("encoding", encoding.getValue());
                    call.resolve(ret);
                } catch (IOException e) {
                    Log.e(TAG, "Read failed: " + e.getMessage());
                    call.reject("Read failed: " + e.getMessage());
                }
            }
        };

        Thread thread = new Thread(runnable);
        thread.start();
    }

    /**
     * Disconnect from server
     * Parameters:
     * - client: Client index
     * Returns:
     * - client: Disconnected client index
     */
    @PluginMethod
    public void disconnect(PluginCall call) {
        final Integer clientIndex = call.getInt("client", -1);
        if (clientIndex == -1) {
            call.reject("Client not specified or invalid index");
            return;
        }
        
        if (clients.isEmpty()) {
            call.reject("No active connections");
            return;
        }
        
        if (clientIndex >= clients.size() || clientIndex < 0) {
            call.reject("Client index out of range");
            return;
        }
        
        final Socket socket = clients.get(clientIndex);
        try {
            if (!socket.isConnected()) {
                socket.close();
                call.reject("Socket not connected");
                return;
            }
            socket.close();
        } catch (IOException e) {
            Log.e(TAG, "Disconnect failed: " + e.getMessage());
            call.reject("Disconnect failed: " + e.getMessage());
            return;
        }

        JSObject ret = new JSObject();
        ret.put("client", clientIndex);
        call.resolve(ret);
    }
    
    /**
     * Helper method to safely close a socket and handle any exceptions
     */
    private void closeSocketSafely(Socket socket) {
        if (socket != null) {
            try {
                socket.close();
            } catch (IOException e) {
                Log.e(TAG, "Error closing socket: " + e.getMessage());
            }
        }
    }
    
    /**
     * Clean up resources when plugin is destroyed
     */
    @Override
    protected void handleOnDestroy() {
        destroyed = true;
        synchronized (servers) {
            for (ServerSocket server : servers.values()) {
                try { server.close(); } catch (IOException ignored) { }
            }
            servers.clear();
        }
        synchronized (clients) {
            for (Socket socket : clients) closeSocketSafely(socket);
            clients.clear();
        }
        super.handleOnDestroy();
    }
    
    /**
     * Convert hex string to bytes
     * @param hex Hex string to convert
     * @return Byte array or null if invalid hex string
     */
    private byte[] hexStringToBytes(String hex) {
        // Remove 0x prefix, spaces, newlines, etc.
        String cleanHex = hex.replace("0x", "")
                             .replace(" ", "")
                             .replace("\n", "");
                             
        if (cleanHex.length() % 2 != 0) {
            // Invalid hex string
            return null;
        }
        
        byte[] data = new byte[cleanHex.length() / 2];
        
        try {
            for (int i = 0; i < cleanHex.length(); i += 2) {
                data[i / 2] = (byte) Integer.parseInt(cleanHex.substring(i, i + 2), 16);
            }
            return data;
        } catch (NumberFormatException e) {
            Log.e(TAG, "Invalid hex string: " + e.getMessage());
            return null;
        }
    }
    
    /**
     * Convert bytes to hex string
     * @param bytes Byte array to convert
     * @return Hex string representation
     */
    private String bytesToHexString(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }
}
