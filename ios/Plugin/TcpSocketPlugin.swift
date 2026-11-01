import Foundation
import Capacitor
import Network

@objc(TcpSocketPlugin)
public class TcpSocketPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "TcpSocketPlugin"
    public let jsName = "TcpSocket"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "listen", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "accept", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "closeServer", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "connect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "send", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "read", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disconnect", returnType: CAPPluginReturnPromise)
    ]
    private let queue = DispatchQueue(label: "TcpSocket.clients")
    private var clients: [Int: TcpConnection] = [:]
    private var nextClient = 0

    private var servers: [Int: NWListener] = [:]
    private var incoming: [Int: [NWConnection]] = [:]
    private var accepts: [Int: CAPPluginCall] = [:]
    private var nextServer = 0

    @objc func listen(_ call: CAPPluginCall) {
        let port = call.getInt("port", 0)
        let host = call.getString("ipAddress", "127.0.0.1")
        guard (0...65535).contains(port), !host.isEmpty else { call.reject("Invalid bind address or port"); return }
        queue.async {
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!)
                let listener = try NWListener(using: parameters)
                let id = self.nextServer
                self.nextServer += 1
                self.servers[id] = listener
                self.incoming[id] = []
                var resolved = false
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self = self, let listener = listener else { return }
                    switch state {
                    case .ready:
                        if !resolved {
                            resolved = true
                            call.resolve(["server": id, "port": Int(listener.port!.rawValue)])
                        }
                    case .failed(let error):
                        if !resolved { resolved = true; call.reject(error.localizedDescription) }
                        self.stopServer(id)
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self = self, self.servers[id] != nil else { connection.cancel(); return }
                    self.incoming[id, default: []].append(connection)
                    self.deliverAccepted(id)
                }
                listener.start(queue: self.queue)
            } catch { call.reject(error.localizedDescription) }
        }
    }

    @objc func accept(_ call: CAPPluginCall) {
        queue.async {
            guard let id = call.getInt("server"), self.servers[id] != nil else { call.reject("Unknown server"); return }
            let timeout = call.getInt("timeout", 10)
            guard timeout >= 0 else { call.reject("Invalid timeout"); return }
            guard self.accepts[id] == nil else { call.reject("An accept is already pending"); return }
            self.accepts[id] = call
            self.deliverAccepted(id)
            if timeout > 0 {
                self.queue.asyncAfter(deadline: .now() + .seconds(timeout)) { [weak self, weak call] in
                    guard let self = self, let call = call, self.accepts[id] === call else { return }
                    self.accepts.removeValue(forKey: id)
                    call.reject("Accept timed out", "TIMEOUT")
                }
            }
        }
    }

    private func deliverAccepted(_ id: Int) {
        guard let call = accepts[id], let connection = incoming[id]?.first else { return }
        incoming[id]?.removeFirst()
        accepts.removeValue(forKey: id)
        let client = TcpConnection(connection: connection)
        client.connect { error in
            if let error = error { call.reject(error.localizedDescription); return }
            self.queue.async {
                let clientId = self.nextClient
                self.nextClient += 1
                self.clients[clientId] = client
                call.resolve(["client": clientId])
            }
        }
    }

    private func stopServer(_ id: Int) {
        let listener = servers.removeValue(forKey: id)
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        incoming.removeValue(forKey: id)?.forEach { $0.cancel() }
        accepts.removeValue(forKey: id)?.reject("Server closed", "CLOSED")
    }

    @objc func closeServer(_ call: CAPPluginCall) {
        queue.async {
            guard let id = call.getInt("server"), self.servers[id] != nil else { call.reject("Unknown server"); return }
            self.stopServer(id)
            call.resolve(["server": id])
        }
    }

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
        guard let text = call.getString("data") else { call.reject("No data provided"); return }
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
                    if code == "EOF", !call.getBool("rejectOnEOF", false) {
                        call.resolve(["result": "", "encoding": encoding])
                    } else {
                        call.reject("Read failed: \(error.localizedDescription)", code)
                    }
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
            guard let id = call.getInt("client"), id >= 0, id < self.nextClient else {
                call.reject("Client not specified or disconnected"); return
            }
            self.clients.removeValue(forKey: id)?.close()
            call.resolve(["client": id])
        }
    }

    deinit {
        for client in clients.values { client.close() }
        for listener in servers.values {
            listener.stateUpdateHandler = nil
            listener.newConnectionHandler = nil
            listener.cancel()
        }
        for call in accepts.values { call.reject("Server closed", "CLOSED") }
        for connections in incoming.values { connections.forEach { $0.cancel() } }
    }

    private static func hexStringToBytes(_ hex: String) -> [UInt8]? {
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
    private static func bytesToHexString(_ bytes: [UInt8]) -> String {
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
