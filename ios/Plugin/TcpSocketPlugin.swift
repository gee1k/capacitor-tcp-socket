import Foundation
import Capacitor

@objc(TcpSocketPlugin)
public class TcpSocketPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "TcpSocketPlugin"
    public let jsName = "TcpSocket"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "connect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "send", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "read", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disconnect", returnType: CAPPluginReturnPromise)
    ]
    private let queue = DispatchQueue(label: "TcpSocket.clients")
    private var clients: [Int: TcpConnection] = [:]
    private var nextClient = 0

    @objc func connect(_ call: CAPPluginCall) {
        guard let host = call.getString("ipAddress"), !host.isEmpty else {
            call.reject("IP address is required"); return
        }
        let port = call.getInt("port", 9100)
        guard (1...65535).contains(port) else { call.reject("Invalid port"); return }
        let connection = TcpConnection(host: host, port: UInt16(port))
        connection.connect { error in
            if let error = error { call.reject("Connection failed: \(error.localizedDescription)"); return }
            self.queue.async {
                let id = self.nextClient
                self.nextClient += 1
                self.clients[id] = connection
                call.resolve(["client": id])
            }
        }
    }

    private func withClient(_ call: CAPPluginCall, action: @escaping (TcpConnection) -> Void) {
        queue.async {
            guard let id = call.getInt("client"), let client = self.clients[id] else {
                call.reject("Client not specified or disconnected"); return
            }
            action(client)
        }
    }

    @objc func send(_ call: CAPPluginCall) {
        guard let text = call.getString("data"), !text.isEmpty else { call.reject("No data provided"); return }
        let encoding = call.getString("encoding", "utf8")
        let data: Data?
        switch encoding {
        case "utf8": data = text.data(using: .utf8)
        case "base64": data = Data(base64Encoded: text)
        case "hex": data = Self.hexStringToBytes(text).map { Data($0) }
        default: call.reject("Unsupported encoding: \(encoding)"); return
        }
        guard let bytes = data else { call.reject("Failed to decode data"); return }
        withClient(call) { client in
            client.send(bytes) { error in
                if let error = error { call.reject("Send failed: \(error.localizedDescription)") }
                else { call.resolve() }
            }
        }
    }

    @objc func read(_ call: CAPPluginCall) {
        let length = call.getInt("expectLen", 1024)
        let timeout = call.getInt("timeout", 10)
        let encoding = call.getString("encoding", "utf8")
        guard length > 0, timeout >= 0 else { call.reject("Invalid read length or timeout"); return }
        guard ["utf8", "base64", "hex"].contains(encoding) else {
            call.reject("Unsupported encoding: \(encoding)"); return
        }
        withClient(call) { client in
            client.read(length: length, timeout: timeout) { result in
                switch result {
                case .failure(let error):
                    let code = (error as? TcpConnection.SocketError) == .closed ? "EOF" : nil
                    call.reject("Read failed: \(error.localizedDescription)", code)
                case .success(let data):
                    var actualEncoding = encoding
                    let text: String
                    switch encoding {
                    case "hex": text = Self.bytesToHexString(Array(data))
                    case "base64": text = data.base64EncodedString()
                    default:
                        if let decoded = String(data: data, encoding: .utf8) { text = decoded }
                        else { text = data.base64EncodedString(); actualEncoding = "base64" }
                    }
                    call.resolve(["result": text, "encoding": actualEncoding])
                }
            }
        }
    }

    @objc func disconnect(_ call: CAPPluginCall) {
        queue.async {
            guard let id = call.getInt("client"), let client = self.clients.removeValue(forKey: id) else {
                call.reject("Client not specified or disconnected"); return
            }
            client.close()
            call.resolve(["client": id])
        }
    }

    deinit { for client in clients.values { client.close() } }

    private static func hexStringToBytes(_ hex: String) -> [UInt8]? {
        // Remove spaces, 0x prefixes, etc
        let cleanHex = hex.replacingOccurrences(of: "0x", with: "")
                          .replacingOccurrences(of: " ", with: "")
                          .replacingOccurrences(of: "\n", with: "")
        
        guard cleanHex.count % 2 == 0 else { return nil }
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
    private static func bytesToHexString(_ bytes: [UInt8]) -> String {
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
