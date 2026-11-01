import XCTest
import Network
import Capacitor
#if SWIFT_PACKAGE
@testable import TcpSocketPlugin
#else
@testable import Plugin
#endif

final class TcpSocketTests: XCTestCase {
    private var listener: NWListener!
    private var accepted: [NWConnection] = []
    private let serverQueue = DispatchQueue(label: "TcpSocketTests.server")

    override func tearDown() {
        listener?.cancel()
        listener = nil
        serverQueue.sync { accepted.forEach { $0.cancel() }; accepted.removeAll() }
        super.tearDown()
    }

    private func startServer() throws -> UInt16 {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "server listening")
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            self.accepted.append(connection)
            connection.start(queue: self.serverQueue)
            self.echo(connection)
        }
        listener.start(queue: serverQueue)
        wait(for: [ready], timeout: 5)
        return try XCTUnwrap(listener.port).rawValue
    }

    private func echo(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, error in
            if let data = data, !data.isEmpty {
                if data == Data("CLOSE\n".utf8) {
                    connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                                    completion: .contentProcessed { _ in })
                    return
                }
                self.serverQueue.asyncAfter(deadline: .now() + 0.2) {
                    connection.send(content: data, completion: .contentProcessed { _ in })
                }
            }
            if !done && error == nil { self.echo(connection) }
        }
    }

    func testRepeatedReadsAndBufferedRemainder() throws {
        let client = TcpConnection(host: "127.0.0.1", port: try startServer())
        defer { client.close() }
        let connected = expectation(description: "connected")
        client.connect { XCTAssertNil($0); connected.fulfill() }
        wait(for: [connected], timeout: 5)
        for payload in [Data("first".utf8), Data([0, 1, 127, 255])] {
            let sent = expectation(description: "sent")
            client.send(payload) { XCTAssertNil($0); sent.fulfill() }
            wait(for: [sent], timeout: 5)
            var received = Data()
            for _ in 0..<payload.count {
                if received.count == payload.count { break }
                let read = expectation(description: "read")
                client.read(length: 2, timeout: 2) { result in
                    switch result {
                    case .success(let data): XCTAssertFalse(data.isEmpty); received.append(data)
                    case .failure(let error): XCTFail(error.localizedDescription)
                    }
                    read.fulfill()
                }
                wait(for: [read], timeout: 5)
                if received.isEmpty { break }
            }
            XCTAssertEqual(received, payload)
        }
    }

    func testTimeoutDoesNotLoseNextReceiveAndCloseRejectsPendingRead() throws {
        let client = TcpConnection(host: "127.0.0.1", port: try startServer())
        defer { client.close() }
        let connected = expectation(description: "connected")
        client.connect { XCTAssertNil($0); connected.fulfill() }
        wait(for: [connected], timeout: 5)
        let timeout = expectation(description: "timeout")
        client.read(length: 1024, timeout: 1) { result in
            if case .failure(let error) = result { XCTAssertEqual(error as? TcpConnection.SocketError, .timeout) } else { XCTFail("Expected timeout") }; timeout.fulfill()
        }
        wait(for: [timeout], timeout: 3)
        let received = expectation(description: "receive after timeout")
        client.read(length: 1024, timeout: 2) { result in
            XCTAssertEqual(try? result.get(), Data("late".utf8)); received.fulfill()
        }
        client.send(Data("late".utf8)) { XCTAssertNil($0) }
        wait(for: [received], timeout: 5)
        let closed = expectation(description: "closed")
        client.read(length: 1024, timeout: 30) { result in
            if case .success = result { XCTFail("Expected EOF") }
            closed.fulfill()
        }
        client.close()
        wait(for: [closed], timeout: 3)
    }

    func testZeroTimeoutWaitsForData() throws {
        let client = TcpConnection(host: "127.0.0.1", port: try startServer())
        defer { client.close() }
        let connected = expectation(description: "connected")
        client.connect { XCTAssertNil($0); connected.fulfill() }
        wait(for: [connected], timeout: 5)
        let received = expectation(description: "indefinite read")
        client.read(length: 1024, timeout: 0) { result in
            XCTAssertEqual(try? result.get(), Data("afterWait".utf8)); received.fulfill()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            client.send(Data("afterWait".utf8)) { XCTAssertNil($0) }
        }
        wait(for: [received], timeout: 5)
    }

    func testConcurrentReadsAreQueuedWithoutLosingBytes() throws {
        let client = TcpConnection(host: "127.0.0.1", port: try startServer())
        defer { client.close() }
        let connected = expectation(description: "connected")
        client.connect { XCTAssertNil($0); connected.fulfill() }
        wait(for: [connected], timeout: 5)
        let first = expectation(description: "first queued read")
        let second = expectation(description: "second queued read")
        client.read(length: 1, timeout: 2) { result in
            XCTAssertEqual(try? result.get(), Data("a".utf8)); first.fulfill()
        }
        client.read(length: 1, timeout: 2) { result in
            XCTAssertEqual(try? result.get(), Data("b".utf8)); second.fulfill()
        }
        client.send(Data("ab".utf8)) { XCTAssertNil($0) }
        wait(for: [first, second], timeout: 5, enforceOrder: true)
    }

    func testPeerHalfCloseStillAllowsSending() throws {
        let port = try startServer()
        let received = expectation(description: "peer receives after its write side closes")
        listener.newConnectionHandler = { connection in
            self.accepted.append(connection)
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                                    completion: .contentProcessed { error in XCTAssertNil(error) })
                }
            }
            connection.start(queue: self.serverQueue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
                XCTAssertNil(error)
                XCTAssertEqual(data, Data("afterEOF".utf8))
                received.fulfill()
            }
        }
        let client = TcpConnection(host: "127.0.0.1", port: port)
        defer { client.close() }
        let connected = expectation(description: "connected")
        client.connect { XCTAssertNil($0); connected.fulfill() }
        wait(for: [connected], timeout: 5)
        let eof = expectation(description: "read EOF")
        client.read(length: 1024, timeout: 2) { result in
            if case .success = result { XCTFail("Expected EOF") }
            eof.fulfill()
        }
        wait(for: [eof], timeout: 5)
        client.send(Data("afterEOF".utf8)) { XCTAssertNil($0) }
        wait(for: [received], timeout: 5)
    }

    func testPeerCloseReportsEOF() throws {
        let client = TcpConnection(host: "127.0.0.1", port: try startServer())
        defer { client.close() }
        let connected = expectation(description: "connected")
        client.connect { XCTAssertNil($0); connected.fulfill() }
        wait(for: [connected], timeout: 5)
        let eof = expectation(description: "peer EOF")
        client.read(length: 1024, timeout: 2) { result in
            switch result {
            case .success: XCTFail("Expected EOF rejection")
            case .failure(let error): XCTAssertEqual(error as? TcpConnection.SocketError, .eof)
            }
            eof.fulfill()
        }
        client.send(Data("CLOSE\n".utf8)) { XCTAssertNil($0) }
        wait(for: [eof], timeout: 5)
    }

    func testRefusedConnectionIsNotReportedAsTimeout() throws {
        let port = try startServer()
        let stopped = expectation(description: "listener stopped")
        listener.stateUpdateHandler = { state in if case .cancelled = state { stopped.fulfill() } }
        listener.cancel()
        wait(for: [stopped], timeout: 3)
        let client = TcpConnection(host: "127.0.0.1", port: port)
        defer { client.close() }
        let refused = expectation(description: "connection refused")
        client.connect(timeout: 2) { error in
            XCTAssertNotNil(error)
            XCTAssertNotEqual(error as? TcpConnection.SocketError, .timeout)
            refused.fulfill()
        }
        wait(for: [refused], timeout: 3)
    }

    func testCloseSettlesAllQueuedReadsAndRejectsSend() throws {
        let client = TcpConnection(host: "127.0.0.1", port: try startServer())
        let connected = expectation(description: "connected")
        client.connect { XCTAssertNil($0); connected.fulfill() }
        wait(for: [connected], timeout: 5)
        let reads = expectation(description: "all reads closed")
        reads.expectedFulfillmentCount = 3
        for _ in 0..<3 {
            client.read(length: 1, timeout: 0) { result in
                if case .failure(let error) = result { XCTAssertEqual(error as? TcpConnection.SocketError, .closed) }
                else { XCTFail("Read must reject CLOSED") }
                reads.fulfill()
            }
        }
        client.close()
        let sent = expectation(description: "send closed")
        client.send(Data()) { error in
            XCTAssertEqual(error as? TcpConnection.SocketError, .closed)
            sent.fulfill()
        }
        wait(for: [reads, sent], timeout: 3)
    }

    func testPluginDeinitClosesPendingAcceptAndRead() throws {
        var plugin: TcpSocketPlugin? = TcpSocketPlugin()
        weak var released = plugin
        var server = -1
        var port = -1
        var client = -1
        let listening = expectation(description: "plugin listening")
        plugin?.listen(CAPPluginCall(callbackId: "listen", methodName: "listen", options: [:], success: { result, _ in
            server = result?.data?["server"] as? Int ?? -1
            port = result?.data?["port"] as? Int ?? -1
            listening.fulfill()
        }, error: { error in XCTFail(error?.message ?? "listen failed"); listening.fulfill() }))
        wait(for: [listening], timeout: 5)
        let connected = expectation(description: "plugin connected")
        plugin?.connect(CAPPluginCall(callbackId: "connect", methodName: "connect", options: ["ipAddress": "127.0.0.1", "port": port], success: { result, _ in
            client = result?.data?["client"] as? Int ?? -1
            connected.fulfill()
        }, error: { error in XCTFail(error?.message ?? "connect failed"); connected.fulfill() }))
        wait(for: [connected], timeout: 5)
        let accepted = expectation(description: "first accept")
        plugin?.accept(CAPPluginCall(callbackId: "accept", methodName: "accept", options: ["server": server], success: { _, _ in accepted.fulfill() }, error: { _ in XCTFail("accept failed"); accepted.fulfill() }))
        wait(for: [accepted], timeout: 5)
        let closed = expectation(description: "pending calls closed on deinit")
        closed.expectedFulfillmentCount = 2
        let onError: CAPPluginCallErrorHandler = { error in
            XCTAssertEqual(error?.code, "CLOSED"); closed.fulfill()
        }
        plugin?.accept(CAPPluginCall(callbackId: "pendingAccept", methodName: "accept", options: ["server": server, "timeout": 0], success: { _, _ in XCTFail("unexpected accept") }, error: onError))
        plugin?.read(CAPPluginCall(callbackId: "pendingRead", methodName: "read", options: ["client": client, "timeout": 0], success: { _, _ in XCTFail("unexpected read") }, error: onError))
        plugin = nil
        wait(for: [closed], timeout: 5)
        XCTAssertNil(released, "Pending operations must not retain the plugin")
    }

}
