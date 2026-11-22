import RecipeCore
import RecipeImport
import SwiftUI
import WebKit

/// The browser fallback: some recipe pages render their content only
/// with JavaScript, so plain HTML has nothing to extract. This opens
/// the page in a NON-PERSISTENT, isolated web view, lets it finish
/// rendering, and takes the finished DOM — nothing is stored, no
/// cookies, no cache, no history. The first navigation away cancels.
struct BrowserFallbackView: View {
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var importer: ImportModel
    @Environment(\.dismiss) private var dismiss

    let url: URL

    var body: some View {
        NavigationStack {
            FallbackWebView(url: url) { html in
                Task {
                    await importer.importHTML(
                        html, url: url.absoluteString, into: library)
                    dismiss()
                }
            }
            .navigationTitle("Open in browser")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use this page") {
                        NotificationCenter.default.post(
                            name: .fallbackCaptureRequested, object: nil)
                    }
                }
            }
        }
    }
}

extension Notification.Name {
    static let fallbackCaptureRequested = Notification.Name("fallbackCaptureRequested")
}

/// The isolated web view. Non-persistent data store; the page renders,
/// then the capture button (or auto-capture after the load settles)
/// hands the rendered HTML to the extractor.
struct FallbackWebView: View {
    let url: URL
    let onCapture: (String) -> Void

    var body: some View {
        #if os(iOS)
            FallbackWebViewIOS(url: url, onCapture: onCapture)
        #else
            FallbackWebViewMac(url: url, onCapture: onCapture)
        #endif
    }
}

#if os(iOS)
    struct FallbackWebViewIOS: UIViewRepresentable {
        let url: URL
        let onCapture: (String) -> Void

        func makeUIView(context: Context) -> WKWebView {
            let configuration = WKWebViewConfiguration()
            // The isolation is the point: nothing persists.
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = context.coordinator
            context.coordinator.onCapture = onCapture
            webView.load(URLRequest(url: url))
            return webView
        }

        func updateUIView(_ webView: WKWebView, context: Context) {
            context.coordinator.onCapture = onCapture
        }

        func makeCoordinator() -> FallbackCoordinator { FallbackCoordinator() }
    }
#else
    struct FallbackWebViewMac: NSViewRepresentable {
        let url: URL
        let onCapture: (String) -> Void

        func makeNSView(context: Context) -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = context.coordinator
            context.coordinator.onCapture = onCapture
            webView.load(URLRequest(url: url))
            return webView
        }

        func updateNSView(_ webView: WKWebView, context: Context) {
            context.coordinator.onCapture = onCapture
        }

        func makeCoordinator() -> FallbackCoordinator {
            FallbackCoordinator()
        }
    }
#endif

final class FallbackCoordinator: NSObject, WKNavigationDelegate {
    var onCapture: ((String) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Capture shortly after the load settles so scripts have a
        // moment to render content.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.capture(webView)
        }
    }

    func capture(_ webView: WKWebView) {
        webView.evaluateJavaScript("document.documentElement.outerHTML") {
            [weak self] result, _ in
            guard let self, let html = result as? String, !html.isEmpty else { return }
            self.onCapture?(html)
        }
    }
}
