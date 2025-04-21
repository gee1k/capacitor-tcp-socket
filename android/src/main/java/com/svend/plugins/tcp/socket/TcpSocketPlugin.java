package com.svend.plugins.tcp.socket;

import android.Manifest;
import android.util.Log;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.Socket;
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
    private List<Socket> clients = new ArrayList<>();
    
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
            clients.add(socket);
            
            JSObject ret = new JSObject();
            ret.put("client", clients.size() - 1);
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
     * - timeout: Timeout in seconds (Note: Android implementation doesn't support timeout yet)
     * - encoding: Preferred encoding for returned data (utf8, base64, hex), default is utf8
     * Returns:
     * - result: Data read
     * - encoding: The encoding used for the result
     */
    @PluginMethod
    public void read(final PluginCall call) {
        final Integer clientIndex = call.getInt("client", -1);
        final Integer length = call.getInt("expectLen", 1024);

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
                    DataInputStream bufferIn = new DataInputStream(new BufferedInputStream(socket.getInputStream()));
                    byte[] bytes = new byte[length];
                    int read = bufferIn.read(bytes, 0, length);

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
                                    // If UTF-8 conversion fails, fall back to base64
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
        for (Socket socket : clients) {
            closeSocketSafely(socket);
        }
        clients.clear();
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
