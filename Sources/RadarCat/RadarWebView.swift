import SwiftUI
import WebKit

/// `WKWebView` retingut en un singleton per sobreviure al cicle de vida del
/// popover (s'obre i es tanja): es rehostatja dins un contenidor NSView.
struct RadarWebView: NSViewRepresentable {
    static let webView: WKWebView = {
        let userContent = WKUserContentController()
        // CSS per treure la franja de branding de Meteocat i fer que el mapa
        // (radar) ompli el popover.
        let css = """
        html, body { margin:0 !important; padding:0 !important; height:100%; background:transparent !important; }
        #root, .App { height:100% !important; }
        .mc-widget-header { display:none !important; }
        .mc-widget-nav { display:none !important; }
        .main-wrapper, .WidgetMapaRadar, .mc-widget-wrapper, .mc-widget-content {
            height:100% !important; max-height:100% !important; padding:0 !important; margin:0 !important;
        }
        .mc-widget-content { display:flex !important; flex-direction:column; }
        .map-wrapper { flex:1 1 auto !important; min-height:0 !important; height:auto !important; }
        #map-radar { width:100% !important; height:100% !important; }
        .legend { flex:0 0 auto !important; }
        .mc-widget-nav { flex:0 0 auto !important; }
        """
        let js = """
        (function(){var s=document.createElement('style');s.textContent=`\(css)`;(document.head||document.documentElement).appendChild(s);})();
        """
        userContent.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        let config = WKWebViewConfiguration()
        config.userContentController = userContent
        config.suppressesIncrementalRendering = false
        let v = WKWebView(frame: .zero, configuration: config)
        v.setValue(false, forKey: "drawsTransparentBackground")
        v.allowsMagnification = true
        return v
    }()

    let url: URL
    var onLoaded: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onLoaded: onLoaded) }

    func makeNSView(context: Context) -> ContainerView {
        let container = ContainerView()
        let wv = Self.webView
        wv.frame = container.bounds
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = context.coordinator
        if wv.superview !== container {
            wv.removeFromSuperview()
            container.addSubview(wv)
        }
        if wv.url?.absoluteString != url.absoluteString {
            wv.load(URLRequest(url: url))
        }
        return container
    }

    func updateNSView(_ container: ContainerView, context: Context) {
        guard let wv = container.subviews.first(where: { $0 === Self.webView }) as? WKWebView else { return }
        if wv.url?.absoluteString != url.absoluteString {
            wv.load(URLRequest(url: url))
        }
    }

    final class ContainerView: NSView {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onLoaded: (() -> Void)?
        init(onLoaded: (() -> Void)?) { self.onLoaded = onLoaded }
        func webView(_ wv: WKWebView, didFinish: WKNavigation!) { onLoaded?() }
    }
}
