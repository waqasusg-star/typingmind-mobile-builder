import Foundation

// DeepSeek Pulse — a minimal HTTP/1.1 loopback responder for the Home Screen icon page.
//
// Written against Network.framework so it needs no third-party dependency:
//   * binds to 127.0.0.1 only, so nothing outside the phone can reach it
//   * answers two paths and nothing else
//   * serves no file from disk, so it cannot leak stored data
//
// Failure is a normal result: the caller falls back to the in-app icon preview.

import Network

final class LoopbackHTTPServer {

    typealias Handler = (String) -> (Int, String, Data)

    private let listener: NWListener
    private let handler: Handler
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    private init(listener: NWListener, handler: @escaping Handler) {
        self.listener = listener
        self.handler = handler
    }

    /// Starts a listener on 127.0.0.1:port. Returns nil when the port is busy or binding fails.
    static func start(port: UInt16, handler: @escaping Handler) -> LoopbackHTTPServer? {
        guard let targetPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters, on: targetPort) else { return nil }

        let server = LoopbackHTTPServer(listener: listener, handler: handler)
        listener.newConnectionHandler = { [weak server] connection in
            server?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed = state {
                listener.cancel()
            }
        }
        listener.start(queue: .main)
        return server
    }

    private func accept(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var request = buffer
            if let data = data { request.append(data) }

            if error != nil || isComplete {
                self.finish(connection)
                return
            }
            // A complete request head is enough; this server ignores headers and bodies.
            guard let head = String(data: request, encoding: .utf8) else {
                self.finish(connection)
                return
            }
            let path = LoopbackHTTPServer.path(fromRequestHead: head)
            let (status, contentType, body) = self.handler(path)
            self.write(status: status, contentType: contentType, body: body, to: connection)
        }
    }

    /// Extracts the request target from the first request line, e.g. "GET /icon.png HTTP/1.1".
    static func path(fromRequestHead head: String) -> String {
        guard let firstLine = head.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: true).first else {
            return "/"
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        return String(parts[1])
    }

    private func write(status: Int, contentType: String, body: Data, to connection: NWConnection) {
        var head = "HTTP/1.1 " + String(status) + " " + (status == 200 ? "OK" : "Not Found") + "\r\n"
        head += "Content-Type: " + contentType + "\r\n"
        head += "Content-Length: " + String(body.count) + "\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
            self?.finish(connection)
        })
    }

    private func finish(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }

    deinit {
        listener.cancel()
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }
}
