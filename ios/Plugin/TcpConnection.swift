import Foundation
import Network

/// One queue owns connection state and FIFO reads/writes. A timed-out receive
/// stays in flight and buffers its eventual bytes for the next read.
final class TcpConnection {
    private let queue = DispatchQueue(label: "TcpSocket.connection")
    private let connection: NWConnection
    private var buffer = Data()
    private var receiving = false
    private var readEnded = false
    private var terminalError: Error?
    private var connecting: ((Error?) -> Void)?
    private var pendingRead: ((Result<Data, Error>) -> Void)?
    private var queuedReads: [(Int, Int, (Result<Data, Error>) -> Void)] = []
    private var pendingSend: ((Error?) -> Void)?
    private var queuedSends: [(Data, (Error?) -> Void)] = []
    private var readLimit = 0
    private var readTimer: DispatchWorkItem?
    private var connectTimer: DispatchWorkItem?

    enum SocketError: LocalizedError, Equatable {
        case closed, timeout, eof
        var errorDescription: String? {
            switch self {
            case .closed: return "Connection closed locally"
            case .timeout: return "Operation timed out"
            case .eof: return "Peer closed its sending side"
            }
        }
    }

    init(host: String, port: UInt16) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    }
    init(connection: NWConnection) { self.connection = connection }

    func connect(timeout: Int = 10, completion: @escaping (Error?) -> Void) {
        queue.async {
            if let error = self.terminalError { completion(error); return }
            self.connecting = completion
            self.connection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.connectTimer?.cancel()
                    self.connectTimer = nil
                    let callback = self.connecting
                    self.connecting = nil
                    callback?(nil)
                case .failed(let error): self.finish(error)
                case .waiting(let error):
                    // A refused port is a definitive failure, not an elapsed timeout.
                    // Other waiting states may recover after network permission/connectivity.
                    if case .posix(.ECONNREFUSED) = error { self.finish(error) }
                case .cancelled: self.finish(SocketError.closed)
                default: break
                }
            }
            if timeout > 0 {
                let timer = DispatchWorkItem { [weak self] in self?.finish(SocketError.timeout) }
                self.connectTimer = timer
                self.queue.asyncAfter(deadline: .now() + .seconds(timeout), execute: timer)
            }
            self.connection.start(queue: self.queue)
        }
    }

    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        queue.async {
            self.queuedSends.append((data, completion))
            self.startNextSend()
        }
    }

    private func startNextSend() {
        guard pendingSend == nil, !queuedSends.isEmpty else { return }
        let (data, callback) = queuedSends.removeFirst()
        if let error = terminalError {
            callback(error)
            queue.async { self.startNextSend() }
            return
        }
        if data.isEmpty {
            callback(nil)
            queue.async { self.startNextSend() }
            return
        }
        pendingSend = callback
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            let callback = self.pendingSend
            self.pendingSend = nil
            callback?(error)
            if let error = error { self.finish(error) }
            else { self.startNextSend() }
        })
    }

    func read(length: Int, timeout: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        queue.async {
            self.queuedReads.append((length, timeout, completion))
            self.startNextRead()
        }
    }

    private func startNextRead() {
        guard pendingRead == nil, !queuedReads.isEmpty else { return }
        let (length, timeout, completion) = queuedReads.removeFirst()
        readLimit = min(length, 65536)
        pendingRead = completion
        if deliver() { return }
        if timeout > 0 {
            let timer = DispatchWorkItem { [weak self] in self?.completeRead(.failure(SocketError.timeout)) }
            readTimer = timer
            queue.asyncAfter(deadline: .now() + .seconds(timeout), execute: timer)
        }
        receive()
    }

    @discardableResult private func deliver() -> Bool {
        guard pendingRead != nil else { return false }
        if !buffer.isEmpty {
            let data = Data(buffer.prefix(readLimit))
            buffer.removeFirst(data.count)
            completeRead(.success(data))
            return true
        }
        if let error = terminalError { completeRead(.failure(error)); return true }
        if readEnded { completeRead(.failure(SocketError.eof)); return true }
        return false
    }

    private func receive() {
        guard !receiving, !readEnded, terminalError == nil else { return }
        receiving = true
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self = self else { return }
            self.receiving = false
            // Explicit close/failure wins over a late receive callback.
            guard self.terminalError == nil else { return }
            if let data = data { self.buffer.append(data) }
            if let error = error { self.terminalError = error }
            else if done { self.readEnded = true }
            if !self.deliver(), self.pendingRead != nil { self.receive() }
        }
    }

    private func completeRead(_ result: Result<Data, Error>) {
        readTimer?.cancel()
        readTimer = nil
        let callback = pendingRead
        pendingRead = nil
        callback?(result)
        queue.async { self.startNextRead() }
    }

    private func finish(_ error: Error) {
        if terminalError == nil { terminalError = error }
        connectTimer?.cancel()
        connectTimer = nil
        let callback = connecting
        connecting = nil
        callback?(terminalError)
        let sendCallback = pendingSend
        pendingSend = nil
        sendCallback?(terminalError)
        let sends = queuedSends
        queuedSends.removeAll()
        for (_, callback) in sends { callback(terminalError) }
        _ = deliver()
        connection.cancel()
    }

    func close() {
        queue.async {
            self.buffer.removeAll()
            self.terminalError = SocketError.closed
            self.finish(SocketError.closed)
        }
    }
}
