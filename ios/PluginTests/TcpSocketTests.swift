import XCTest
import Network
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
            XCTAssertEqual(try? result.get(), Data()); timeout.fulfill()
        }
        wait(for: [timeout], timeout: 3)
        let received = expectation(description: "receive after timeout")
        client.read(length: 1024, timeout: 2) { result in
            XCTAssertEqual(try? result.get(), Data("late".utf8)); received.fulfill()
        }
        client.send(Data("late".utf8)) { XCTAssertNil($0) }
        wait(for: [received], timeout: 5)
        let closed = expectation(description: "closed")
        client.read(length: 1024, timeout: 0) { result in
            if case .success = result { XCTFail("Expected EOF") }
            closed.fulfill()
        }
        client.close()
        wait(for: [closed], timeout: 3)
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
            case .failure(let error): XCTAssertEqual(error as? TcpConnection.SocketError, .closed)
            }
            eof.fulfill()
        }
        client.send(Data("CLOSE\n".utf8)) { XCTAssertNil($0) }
        wait(for: [eof], timeout: 5)
    }
}
