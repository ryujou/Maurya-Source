#if os(iOS)
    import SwiftUI
    import WebKit

    public struct MauryaEditorConfiguration: Sendable, Equatable {
        public enum Language: String, Sendable, Equatable {
            case simplifiedChinese = "zh"
            case japanese = "ja"
        }

        public let editor: EditorKind
        public let language: Language
        public let initialDocument: String

        public init(editor: EditorKind, language: Language, initialDocument: String) {
            self.editor = editor
            self.language = language
            self.initialDocument = initialDocument
        }
    }

    public struct MauryaEditorView: UIViewRepresentable {
        @ObservedObject private var model: MauryaEditorModel
        private let editorConfiguration: MauryaEditorConfiguration

        public init(model: MauryaEditorModel, configuration: MauryaEditorConfiguration) {
            self.model = model
            editorConfiguration = configuration
        }

        public func makeCoordinator() -> Coordinator {
            Coordinator(model: model, configuration: editorConfiguration)
        }

        public func makeUIView(context: Context) -> WKWebView {
            context.coordinator.makeWebView()
        }

        public func updateUIView(_ webView: WKWebView, context: Context) {
            context.coordinator.resize()
        }

        public static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
            coordinator.tearDown(webView)
        }

        @MainActor
        public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
            private let model: MauryaEditorModel
            private let editorConfiguration: MauryaEditorConfiguration
            private let nonce = UUID().uuidString.lowercased()
            private var verifiedBundle: VerifiedEditorBundle?
            private var schemeHandler: EditorSchemeHandler?
            private weak var webView: WKWebView?
            private var tasks: [UUID: Task<Void, Never>] = [:]
            private var didSendInitialDocument = false
            private var isTornDown = false

            init(model: MauryaEditorModel, configuration: MauryaEditorConfiguration) {
                self.model = model
                editorConfiguration = configuration
            }

            func makeWebView() -> WKWebView {
                let webConfiguration = WKWebViewConfiguration()
                webConfiguration.websiteDataStore = .nonPersistent()
                webConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = false
                webConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true
                webConfiguration.mediaTypesRequiringUserActionForPlayback = .all

                do {
                    let bundle = try EditorBundleVerifier.verify()
                    verifiedBundle = bundle
                    let handler = EditorSchemeHandler(bundle: bundle)
                    schemeHandler = handler
                    webConfiguration.setURLSchemeHandler(handler, forURLScheme: EditorSchemeHandler.scheme)
                } catch {
                    model.fail(error)
                }

                let controller = webConfiguration.userContentController
                controller.addUserScript(
                    WKUserScript(
                        source: EditorBootstrap.source(nonce: nonce, editor: editorConfiguration.editor),
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true,
                        in: .page
                    ))
                controller.add(self, contentWorld: .page, name: "mauryaBridge")

                let view = WKWebView(frame: .zero, configuration: webConfiguration)
                view.navigationDelegate = self
                view.uiDelegate = self
                view.allowsBackForwardNavigationGestures = false
                view.allowsLinkPreview = false
                // The bundled Blockly editor owns all one- and two-finger
                // gestures (block drag, workspace pan and pinch zoom).  Letting
                // WKWebView's outer UIScrollView recognize the same pan causes
                // it to cancel Blockly's pointer stream on iPad, which makes a
                // block drag move the workspace and rubber-band the whole page.
                view.scrollView.isScrollEnabled = false
                view.scrollView.bounces = false
                view.scrollView.alwaysBounceHorizontal = false
                view.scrollView.alwaysBounceVertical = false
                view.scrollView.panGestureRecognizer.isEnabled = false
                view.scrollView.pinchGestureRecognizer?.isEnabled = false
                view.scrollView.contentInsetAdjustmentBehavior = .never
                view.scrollView.keyboardDismissMode = .none
                view.isOpaque = false
                view.backgroundColor = .clear
                webView = view
                model.attach { [weak self] envelope in self?.dispatch(envelope) }

                if let verifiedBundle { beginLoad(in: view, bundle: verifiedBundle) }
                return view
            }

            func resize() {
                guard model.phase == .ready else { return }
                try? model.send(.resize)
            }

            func tearDown(_ view: WKWebView) {
                guard !isTornDown else { return }
                isTornDown = true
                tasks.values.forEach { $0.cancel() }
                tasks.removeAll()
                schemeHandler?.cancelAll()
                view.stopLoading()
                view.navigationDelegate = nil
                view.uiDelegate = nil
                let controller = view.configuration.userContentController
                controller.removeScriptMessageHandler(forName: "mauryaBridge", contentWorld: .page)
                controller.removeAllUserScripts()
                model.detach()
            }

            public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
                guard !isTornDown, message.name == "mauryaBridge", message.frameInfo.isMainFrame,
                    isAllowed(message.frameInfo.request.url), JSONSerialization.isValidJSONObject(message.body),
                    let data = try? JSONSerialization.data(withJSONObject: message.body)
                else {
                    model.onRejectedMessage?(.malformedEnvelope)
                    return
                }
                model.receive(data)
                if model.phase == .ready, !didSendInitialDocument {
                    didSendInitialDocument = true
                    startTask { [weak self] in
                        guard let self else { return }
                        let fallback = model.latestDocument ?? editorConfiguration.initialDocument
                        let document = await model.restoredDocument(fallback: fallback)
                        guard !Task.isCancelled else { return }
                        do { try model.send(.load(document)) } catch { model.fail(error) }
                    }
                }
            }

            public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async
                -> WKNavigationActionPolicy
            {
                guard navigationAction.targetFrame?.isMainFrame == true,
                    isAllowed(navigationAction.request.url)
                else { return .cancel }
                return .allow
            }

            public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async
                -> WKNavigationResponsePolicy
            {
                guard navigationResponse.isForMainFrame, navigationResponse.canShowMIMEType,
                    isAllowed(navigationResponse.response.url)
                else { return .cancel }
                return .allow
            }

            public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
                model.processTerminated()
                didSendInitialDocument = false
                guard let verifiedBundle else { return }
                beginLoad(in: webView, bundle: verifiedBundle)
            }

            public func webView(
                _ webView: WKWebView,
                createWebViewWith configuration: WKWebViewConfiguration,
                for navigationAction: WKNavigationAction,
                windowFeatures: WKWindowFeatures
            ) -> WKWebView? { nil }

            public func webView(
                _ webView: WKWebView,
                requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                initiatedByFrame frame: WKFrameInfo,
                type: WKMediaCaptureType,
                decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
            ) { decisionHandler(.deny) }

            private func beginLoad(in view: WKWebView, bundle: VerifiedEditorBundle) {
                model.beginLoading(
                    editor: editorConfiguration.editor,
                    nonce: nonce,
                    bundleVersion: bundle.editorVersion,
                    bundleSHA256: bundle.bundleSHA256
                )
                let page = editorConfiguration.editor == .blocks ? "index.html" : "script.html"
                var components = URLComponents()
                components.scheme = EditorSchemeHandler.scheme
                components.host = EditorSchemeHandler.host
                components.path = "/\(page)"
                components.queryItems = [
                    URLQueryItem(name: "v", value: bundle.editorVersion),
                    URLQueryItem(name: "lang", value: editorConfiguration.language.rawValue),
                ]
                guard let url = components.url else {
                    model.fail(URLError(.badURL))
                    return
                }
                view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15))
            }

            private func dispatch(_ envelope: EditorBridgeEnvelope) {
                guard let webView, !isTornDown else { return }
                do {
                    let encoded = try JSONEncoder().encode(envelope)
                    guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
                        throw EditorBridgeError.malformedEnvelope
                    }
                    startTask { [weak self, weak webView] in
                        guard let self, let webView else { return }
                        do {
                            _ = try await webView.callAsyncJavaScript(
                                "return window.__mauryaNativeReceive(envelope);",
                                arguments: ["envelope": object],
                                in: nil,
                                contentWorld: .page
                            )
                        } catch is CancellationError {
                            return
                        } catch {
                            model.fail(error)
                        }
                    }
                } catch {
                    model.fail(error)
                }
            }

            private func isAllowed(_ url: URL?) -> Bool {
                guard let url else { return false }
                return url.scheme == EditorSchemeHandler.scheme && url.host == EditorSchemeHandler.host
                    && EditorSchemeHandler.safePath(url) != nil
            }

            private func startTask(_ operation: @escaping @MainActor () async -> Void) {
                let identifier = UUID()
                tasks[identifier] = Task { [weak self] in
                    await operation()
                    self?.tasks[identifier] = nil
                }
            }
        }
    }
#endif
