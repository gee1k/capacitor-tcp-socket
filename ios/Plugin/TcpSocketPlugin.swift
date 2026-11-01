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
    private var connecting: [UUID: TcpConnection] = [:]
    private var nextClient = 0
    private var servers: [Int: NWListener] = [:]
    private var listening: [UUID: (NWListener, CAPPluginCall)] = [:]
    private var incoming: [Int: [NWConnection]] = [:]
    private var accepts: [Int: CAPPluginCall] = [:]
    private var startingAccepts: [Int: TcpConnection] = [:]
    private var nextServer = 0

    private static func reject(_ call: CAPPluginCall, _ error: Error, fallback: String = "IO_ERROR") {
        let code: String
        switch error as? TcpConnection.SocketError {
        case .closed: code = "CLOSED"
        case .eof: code = "EOF"
        case .timeout: code = "TIMEOUT"
        default: code = fallback
        }
        call.reject(error.localizedDescription, code)
    }
    private static func validTimeout(_ call: CAPPluginCall) -> Int? {
        let value = call.getInt("timeout", 10)
        guard (0...2147483).contains(value) else { call.reject("Invalid timeout", "INVALID_ARGUMENT"); return nil }
        return value
    }

    @objc func listen(_ call: CAPPluginCall) {
        let port = call.getInt("port", 0)
        let host = call.getString("ipAddress", "127.0.0.1")
        guard (0...65535).contains(port), !host.isEmpty else { call.reject("Invalid bind address or port", "INVALID_ARGUMENT"); return }
        queue.async {
            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!)
                let listener = try NWListener(using: parameters)
                let token = UUID()
                self.listening[token] = (listener, call)
                var serverId: Int?
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self = self, let listener = listener else { return }
                    switch state {
                    case .ready:
                        if let (_, pending) = self.listening.removeValue(forKey: token) {
                            let id = self.nextServer
                            self.nextServer += 1
                            serverId = id
                            self.servers[id] = listener
                            self.incoming[id] = []
                            pending.resolve(["server": id, "port": Int(listener.port!.rawValue)])
                        }
                    case .failed(let error), .waiting(let error):
                        if let (_, pending) = self.listening.removeValue(forKey: token) {
                            pending.reject(error.localizedDescription, "LISTEN_FAILED")
                            listener.cancel()
                        }
                        if let id = serverId { self.stopServer(id) }
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self = self, let id = serverId, self.servers[id] != nil,
                          self.incoming[id, default: []].count < 128 else { connection.cancel(); return }
                    self.incoming[id, default: []].append(connection)
                    self.deliverAccepted(id)
                }
                listener.start(queue: self.queue)
            } catch { Self.reject(call, error, fallback: "LISTEN_FAILED") }
        }
    }

    @objc func accept(_ call: CAPPluginCall) {
        guard let timeout = Self.validTimeout(call) else { return }
        queue.async {
            guard let id = call.getInt("server"), id >= 0, id < self.nextServer else {
                call.reject("Unknown server", "INVALID_ARGUMENT"); return
            }
            guard self.servers[id] != nil else { call.reject("Server closed", "CLOSED"); return }
            guard self.accepts[id] == nil else { call.reject("An accept is already pending", "BUSY"); return }
            self.accepts[id] = call
            self.deliverAccepted(id)
            if timeout > 0 {
                self.queue.asyncAfter(deadline: .now() + .seconds(timeout)) { [weak self, weak call] in
                    guard let self = self, let call = call, self.accepts[id] === call else { return }
                    self.accepts.removeValue(forKey: id)
                    self.startingAccepts.removeValue(forKey: id)?.close()
                    call.reject("Accept timed out", "TIMEOUT")
                }
            }
        }
    }

    private func deliverAccepted(_ id: Int) {
        guard startingAccepts[id] == nil, let call = accepts[id], let connection = incoming[id]?.first else { return }
        incoming[id]?.removeFirst()
        let client = TcpConnection(connection: connection)
        startingAccepts[id] = client
        client.connect(timeout: 0) { [weak self] error in
            guard let self = self else { client.close(); return }
            self.queue.async {
                guard self.accepts[id] === call else { client.close(); return }
                self.accepts.removeValue(forKey: id)
                self.startingAccepts.removeValue(forKey: id)
                if let error = error { client.close(); Self.reject(call, error); return }
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
        startingAccepts.removeValue(forKey: id)?.close()
    }

    @objc func closeServer(_ call: CAPPluginCall) {
        queue.async {
            guard let id = call.getInt("server"), id >= 0, id < self.nextServer else {
                call.reject("Unknown server", "INVALID_ARGUMENT"); return
            }
            self.stopServer(id)
            call.resolve(["server": id])
        }
    }

    @objc func connect(_ call: CAPPluginCall) {
        guard let host = call.getString("ipAddress"), !host.isEmpty else {
            call.reject("IP address is required", "INVALID_ARGUMENT"); return
        }
        let port = call.getInt("port", 9100)
        guard (1...65535).contains(port) else { call.reject("Invalid port", "INVALID_ARGUMENT"); return }
        guard let timeout = Self.validTimeout(call) else { return }
        queue.async {
            let token = UUID()
            let connection = TcpConnection(host: host, port: UInt16(port))
            self.connecting[token] = connection
            connection.connect(timeout: timeout) { [weak self] error in
                guard let self = self else { connection.close(); call.reject("Plugin destroyed", "CLOSED"); return }
                self.queue.async {
                    self.connecting.removeValue(forKey: token)
                    if let error = error { connection.close(); Self.reject(call, error, fallback: "CONNECT_FAILED"); return }
                    let id = self.nextClient
                    self.nextClient += 1
                    self.clients[id] = connection
                    call.resolve(["client": id])
                }
            }
        }
    }

    private func withClient(_ call: CAPPluginCall, action: @escaping (TcpConnection) -> Void) {
        queue.async {
            guard let id = call.getInt("client"), id >= 0, id < self.nextClient else {
                call.reject("Unknown client", "INVALID_ARGUMENT"); return
            }
            guard let client = self.clients[id] else { call.reject("Client closed", "CLOSED"); return }
            action(client)
        }
    }

    @objc func send(_ call: CAPPluginCall) {
        guard let text = call.getString("data") else { call.reject("data is required", "INVALID_ARGUMENT"); return }
        let data: Data?
        switch call.getString("encoding", "utf8") {
        case "utf8": data = text.data(using: .utf8)
        case "base64":
            let decoded = Data(base64Encoded: text)
            data = decoded?.base64EncodedString() == text ? decoded : nil
        case "hex": data = Self.hexData(text)
        default: call.reject("Unsupported encoding", "INVALID_ARGUMENT"); return
        }
        guard let bytes = data else { call.reject("Invalid encoded data", "INVALID_ARGUMENT"); return }
        withClient(call) { client in
            client.send(bytes) { error in
                if let error = error { Self.reject(call, error) }
                else { call.resolve() }
            }
        }
    }

    @objc func read(_ call: CAPPluginCall) {
        let length = call.getInt("expectLen", 1024)
        let encoding = call.getString("encoding", "utf8")
        guard length > 0, length <= 2147483647 else { call.reject("Invalid read length", "INVALID_ARGUMENT"); return }
        guard let timeout = Self.validTimeout(call) else { return }
        guard ["utf8", "base64", "hex"].contains(encoding) else {
            call.reject("Unsupported encoding", "INVALID_ARGUMENT"); return
        }
        withClient(call) { client in
            client.read(length: length, timeout: timeout) { result in
                switch result {
                case .failure(let error): Self.reject(call, error)
                case .success(let data):
                    var actualEncoding = encoding
                    let text: String
                    switch encoding {
                    case "hex": text = data.map { String(format: "%02x", $0) }.joined()
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
                call.reject("Unknown client", "INVALID_ARGUMENT"); return
            }
            self.clients.removeValue(forKey: id)?.close()
            call.resolve(["client": id])
        }
    }

    deinit {
        for client in clients.values { client.close() }
        for client in connecting.values { client.close() }
        for client in startingAccepts.values { client.close() }
        for listener in servers.values {
            listener.stateUpdateHandler = nil
            listener.newConnectionHandler = nil
            listener.cancel()
        }
        for (listener, call) in listening.values {
            listener.stateUpdateHandler = nil
            listener.newConnectionHandler = nil
            listener.cancel()
            call.reject("Plugin destroyed", "CLOSED")
        }
        for call in accepts.values { call.reject("Plugin destroyed", "CLOSED") }
        for connections in incoming.values { connections.forEach { $0.cancel() } }
    }

    private static func hexData(_ text: String) -> Data? {
        guard text.count % 2 == 0 else { return nil }
        var bytes = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
