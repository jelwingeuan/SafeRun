import Foundation

protocol OpenAITransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionOpenAITransport: OpenAITransport {
    static let maximumResponseBytes = 1_048_576
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirects())
        guard let response = response as? HTTPURLResponse else {
            throw AIPlannerError.invalidResponse
        }
        guard response.expectedContentLength <= Self.maximumResponseBytes else {
            throw AIPlannerError.responseTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.maximumResponseBytes else { throw AIPlannerError.responseTooLarge }
            data.append(byte)
        }
        return (data, response)
    }

    /// Prevents authorization forwarding or implicit POST resubmission through redirects.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
