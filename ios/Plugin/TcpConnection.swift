import Foundation
import Network

/// One serial queue owns the connection, pending receive, timeout and buffered bytes.
/// A timed-out receive stays in flight: its bytes belong to the next read, never discarded.
final class TcpConnection {
    private let queue = DispatchQueue(label: "TcpSocket.connection")
    private let connection: NWConnection
    private var buffer = Data()
    private var receiving = false
    private var terminalError: Error?
    private var connecting: ((Error?) -> Void)?
    private var pendingRead: ((Result<Data, Error>) -> Void)?
    private var readLimit = 0
    private var readTimer: DispatchWorkItem?
    private var connectTimer: DispatchWorkItem?

    enum SocketError: LocalizedError, Equatable {
        case closed, timeout, busy
        var errorDescription: String? {
            switch self {
            case .closed: return "Connection closed"
            case .timeout: return "Connection timed out"
            case .busy: return "A read is already pending for this client"
            }
        }
    }

    init(host: String, port: UInt16) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    }

    func connect(completion: @escaping (Error?) -> Void) {
        queue.async {
            self.connecting = completion
            self.connection.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.connectTimer?.cancel()
                    let callback = self.connecting
                    self.connecting = nil
                    callback?(nil)
                case .failed(let error): self.finish(error)
                case .cancelled: self.finish(SocketError.closed)
                default: break
                }
            }
            let timer = DispatchWorkItem { [weak self] in self?.finish(SocketError.timeout) }
            self.connectTimer = timer
            self.queue.asyncAfter(deadline: .now() + 10, execute: timer)
            self.connection.start(queue: self.queue)
        }
    }

    func send(_ data: Data, completion: @escaping (Error?) -> Void) {
        queue.async {
            if let error = self.terminalError { completion(error); return }
            self.connection.send(content: data, completion: .contentProcessed { error in completion(error) })
        }
    }

    func read(length: Int, timeout: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        queue.async {
            guard self.pendingRead == nil else { completion(.failure(SocketError.busy)); return }
            self.readLimit = length
            self.pendingRead = completion
            if self.deliver() { return }
            if timeout > 0 {
                let timer = DispatchWorkItem { [weak self] in self?.completeRead(.success(Data())) }
                self.readTimer = timer
                self.queue.asyncAfter(deadline: .now() + .seconds(timeout), execute: timer)
            }
            self.receive()
        }
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
        return false
    }

    private func receive() {
        guard !receiving, terminalError == nil else { return }
        receiving = true
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self = self else { return }
            self.receiving = false
            if let data = data { self.buffer.append(data) }
            if let error = error { self.terminalError = error }
            else if done { self.terminalError = SocketError.closed }
            if !self.deliver(), self.pendingRead != nil { self.receive() }
        }
    }

    private func completeRead(_ result: Result<Data, Error>) {
        readTimer?.cancel()
        readTimer = nil
        let callback = pendingRead
        pendingRead = nil
        callback?(result)
    }

    private func finish(_ error: Error) {
        // Cancellation can follow a failure; preserve the original cause.
        if terminalError == nil { terminalError = error }
        connectTimer?.cancel()
        let callback = connecting
        connecting = nil
        callback?(error)
        _ = deliver()
        connection.cancel()
    }

    func close() {
        queue.async {
            self.buffer.removeAll()
            self.finish(SocketError.closed)
        }
    }
}
