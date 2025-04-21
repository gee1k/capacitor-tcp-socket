import Foundation
import Capacitor
import SwiftSocket

/**
 * TcpSocketPlugin - Capacitor plugin that provides TCP Socket communication functionality
 * Supports connection, data sending, data receiving and disconnection operations
 */
@objc(TcpSocketPlugin)
public class TcpSocketPlugin: CAPPlugin {
    /// Stores all connected TCP clients
    private var clients: [TCPClient] = []
    
    // Data encoding types
    private enum DataEncoding: String {
        case utf8 = "utf8"
        case base64 = "base64"
        case hex = "hex"
    }
    
    /**
     * Connect to TCP server
     * Parameters:
     * - ipAddress: Server IP address (required)
     * - port: Server port, default 9100
     * Returns:
     * - client: Client index, used for subsequent operations
     */
    @objc func connect(_ call: CAPPluginCall) {
        guard let ip = call.getString("ipAddress") else {
            call.reject("IP address is required")
            return
        }
        let port = Int32(call.getInt("port", 9100))

        let client = TCPClient(address: ip, port: port)
        switch client.connect(timeout: 10) {
        case .success:
            clients.append(client)
            call.resolve(["client": clients.count - 1])
        case .failure(let error):
            call.reject("Connection failed: \(error.localizedDescription)")
        }
    }
    
    /**
     * Send data to server with specified encoding
     * Parameters:
     * - client: Client index
     * - data: Data to send
     * - encoding: Data encoding (utf8, base64, hex), default is utf8
     */
    @objc func send(_ call: CAPPluginCall) {
        guard let clientIndex = call.getInt("client"), clientIndex >= 0 else {
            call.reject("Client not specified or invalid index")
            return
        }
        
        guard clients.indices.contains(clientIndex) else {
            call.reject("Client index out of range")
            return
        }
        
        let client = clients[clientIndex]
        guard let data = call.getString("data") else {
            call.reject("No data provided")
            return
        }
        
        let encodingString = call.getString("encoding", "utf8")
        guard let encoding = DataEncoding(rawValue: encodingString) else {
            call.reject("Unsupported encoding: \(encodingString)")
            return
        }
        
        var byteData: [UInt8]?
        
        // Convert the string to bytes based on the specified encoding
        switch encoding {
        case .utf8:
            byteData = [UInt8](data.utf8)
        case .base64:
            if let decodedData = Data(base64Encoded: data) {
                byteData = [UInt8](decodedData)
            }
        case .hex:
            byteData = hexStringToBytes(data)
        }
        
        guard let bytes = byteData else {
            call.reject("Failed to decode data with encoding: \(encodingString)")
            return
        }
        
        switch client.send(data: bytes) {
        case .success:
            call.resolve()
        case .failure(let error):
            call.reject("Send failed: \(error.localizedDescription)")
        }
    }
    
    /**
     * Read data from server
     * Parameters:
     * - client: Client index
     * - expectLen: Expected number of bytes to read, default 1024
     * - timeout: Timeout in seconds, default 10 seconds
     * - encoding: Preferred encoding for returned data (utf8, base64, hex), default is utf8
     * Returns:
     * - result: Data read
     * - encoding: The encoding used for the result
     */
    @objc func read(_ call: CAPPluginCall) {
        guard let clientIndex = call.getInt("client"), clientIndex >= 0 else {
            call.reject("Client not specified or invalid index")
            return
        }
        
        guard clients.indices.contains(clientIndex) else {
            call.reject("Client index out of range")
            return
        }
        
        let client = clients[clientIndex]
        let expectLen = call.getInt("expectLen", 1024)
        let timeout = call.getInt("timeout", 10)
        let encodingString = call.getString("encoding", "utf8")
        
        guard let encoding = DataEncoding(rawValue: encodingString) else {
            call.reject("Unsupported encoding: \(encodingString)")
            return
        }
        
        guard let response = client.read(expectLen, timeout: timeout) else {
            call.resolve(["result": "", "encoding": encoding.rawValue])
            return
        }
        
        let result: String
        
        switch encoding {
        case .utf8:
            // Try to convert to UTF-8 string, fall back to base64 if not possible
            if let utf8String = String(bytes: response, encoding: .utf8) {
                result = utf8String
            } else {
                // Fall back to base64 if UTF-8 conversion fails
                result = Data(response).base64EncodedString()
                call.resolve(["result": result, "encoding": DataEncoding.base64.rawValue])
                return
            }
        case .base64:
            result = Data(response).base64EncodedString()
        case .hex:
            result = bytesToHexString(response)
        }
        
        call.resolve(["result": result, "encoding": encoding.rawValue])
    }
    
    /**
     * Disconnect from server
     * Parameters:
     * - client: Client index
     * Returns:
     * - client: Disconnected client index
     */
    @objc func disconnect(_ call: CAPPluginCall) {
        guard let clientIndex = call.getInt("client"), clientIndex >= 0 else {
            call.reject("Client not specified or invalid index")
            return
        }
        
        guard clients.indices.contains(clientIndex) else {
            call.reject("Client index out of range")
            return
        }
        
        clients[clientIndex].close()
        call.resolve(["client": clientIndex])
    }
    
    /**
     * Convert hex string to bytes
     * - Parameter hex: Hex string (can have spaces and 0x prefix)
     * - Returns: Byte array
     */
    private func hexStringToBytes(_ hex: String) -> [UInt8]? {
        // Remove spaces, 0x prefixes, etc
        let cleanHex = hex.replacingOccurrences(of: "0x", with: "")
                          .replacingOccurrences(of: " ", with: "")
                          .replacingOccurrences(of: "\n", with: "")
        
        var bytes = [UInt8]()
        var i = cleanHex.startIndex
        
        while i < cleanHex.endIndex {
            let nextIndex = cleanHex.index(i, offsetBy: 2, limitedBy: cleanHex.endIndex) ?? cleanHex.endIndex
            let byteString = cleanHex[i..<nextIndex]
            
            if let byte = UInt8(byteString, radix: 16) {
                bytes.append(byte)
            } else {
                return nil
            }
            
            i = nextIndex
        }
        
        return bytes
    }
    
    /**
     * Convert bytes to hex string
     * - Parameter bytes: Byte array
     * - Returns: Hex string
     */
    private func bytesToHexString(_ bytes: [UInt8]) -> String {
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
