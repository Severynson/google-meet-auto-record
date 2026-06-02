import Foundation

// Minimal synchronous Chrome DevTools Protocol client.
// Connects to one tab's WebSocket debugger URL and sends Runtime.evaluate calls.
final class CDPClient {
    private let wsURL: URL
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var nextID = 1
    private let semaphore = DispatchSemaphore(value: 0)
    private var pendingResults: [Int: Result<Any?, Error>] = [:]
    private let lock = NSLock()

    init(wsURL: URL) {
        self.wsURL = wsURL
    }

    func connect() {
        session = URLSession(configuration: .default)
        task = session!.webSocketTask(with: wsURL)
        task!.resume()
        receiveLoop()
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
    }

    // Executes JavaScript in the tab. Returns the result value or nil.
    // Blocks until response received (or timeout).
    @discardableResult
    func evaluate(_ js: String, timeout: TimeInterval = 5.0) -> Any? {
        let id = nextID
        nextID += 1

        let msg: [String: Any] = [
            "id": id,
            "method": "Runtime.evaluate",
            "params": [
                "expression": js,
                "returnByValue": true,
                "awaitPromise": false
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let str = String(data: data, encoding: .utf8) else { return nil }

        lock.lock()
        pendingResults[id] = nil
        lock.unlock()

        task?.send(.string(str)) { _ in }

        let deadline = DispatchTime.now() + timeout
        if semaphore.wait(timeout: deadline) == .timedOut {
            Logger.log("CDP evaluate timeout for id \(id)")
            lock.lock()
            pendingResults.removeValue(forKey: id)
            lock.unlock()
            return nil
        }

        lock.lock()
        let result = pendingResults.removeValue(forKey: id)
        lock.unlock()

        switch result {
        case .success(let val): return val
        case .failure(let err):
            Logger.log("CDP error: \(err)")
            return nil
        case .none: return nil
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                self.handle(msg)
                self.receiveLoop()
            case .failure(let err):
                Logger.log("CDP WebSocket error: \(err)")
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let str) = message,
              let data = str.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? Int else { return }

        let value: Any? = (json["result"] as? [String: Any])?["result"]

        lock.lock()
        if pendingResults.keys.contains(id) {
            pendingResults[id] = .success(value)
            lock.unlock()
            semaphore.signal()
        } else {
            lock.unlock()
        }
    }
}

// MARK: - Tab discovery

struct ChromeTab: Decodable {
    let id: String
    let type: String
    let url: String
    let webSocketDebuggerUrl: String?
}

// Fetches tab list from Chrome's debugging endpoint.
func fetchChromeTabs(port: Int = 9222) -> [ChromeTab] {
    guard let url = URL(string: "http://localhost:\(port)/json/list") else { return [] }
    var request = URLRequest(url: url, timeoutInterval: 2.0)
    request.httpMethod = "GET"

    var tabs: [ChromeTab] = []
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, _, _ in
        if let data,
           let decoded = try? JSONDecoder().decode([ChromeTab].self, from: data) {
            tabs = decoded
        }
        sem.signal()
    }.resume()
    sem.wait()
    return tabs
}

// Returns a connected CDPClient for the first Meet tab, or nil.
func cdpClientForMeetTab(port: Int = 9222) -> CDPClient? {
    let tabs = fetchChromeTabs(port: port)
    guard let tab = tabs.first(where: {
        $0.type == "page" && $0.url.contains("meet.google.com")
    }),
    let wsURLStr = tab.webSocketDebuggerUrl,
    let wsURL = URL(string: wsURLStr) else { return nil }

    Logger.log("CDP: attaching to tab \(tab.url)")
    let client = CDPClient(wsURL: wsURL)
    client.connect()
    Thread.sleep(forTimeInterval: 0.3) // let WS handshake complete
    return client
}
