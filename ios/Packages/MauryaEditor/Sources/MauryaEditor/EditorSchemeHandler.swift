#if os(iOS)
    import Foundation
    import WebKit

    @MainActor
    final class EditorSchemeHandler: NSObject, WKURLSchemeHandler {
        static let scheme = "maurya-editor"
        static let host = "bundle"

        private let bundle: VerifiedEditorBundle
        private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

        init(bundle: VerifiedEditorBundle) { self.bundle = bundle }

        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
            let task = Task { @MainActor [bundle] in
                defer { tasks[identifier] = nil }
                guard !Task.isCancelled,
                    let url = urlSchemeTask.request.url,
                    url.scheme == Self.scheme,
                    url.host == Self.host,
                    let path = Self.safePath(url),
                    let record = bundle.record(for: path)
                else {
                    urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                    return
                }
                do {
                    let data = try Data(contentsOf: bundle.rootURL.appending(path: path), options: .mappedIfSafe)
                    guard !Task.isCancelled else { return }
                    let headers = [
                        "Content-Type": record.mediaType,
                        "Content-Length": String(data.count),
                        "Cache-Control": "no-store",
                        "Content-Security-Policy":
                            "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self'; font-src 'self' data:; connect-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'",
                        "Cross-Origin-Resource-Policy": "same-origin",
                        "X-Content-Type-Options": "nosniff",
                    ]
                    guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
                        throw URLError(.badServerResponse)
                    }
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                } catch {
                    urlSchemeTask.didFailWithError(error)
                }
            }
            tasks[identifier] = task
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
            let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
            tasks.removeValue(forKey: identifier)?.cancel()
        }

        func cancelAll() {
            tasks.values.forEach { $0.cancel() }
            tasks.removeAll()
        }

        static func safePath(_ url: URL) -> String? {
            let path = url.path.removingPercentEncoding?.drop(while: { $0 == "/" }).description ?? ""
            return EditorBundleVerifier.isSafeRelativePath(path) ? path : nil
        }
    }
#endif
