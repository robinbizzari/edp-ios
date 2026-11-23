import UIKit
import WebKit

/// Affiche EDP (le site) en plein écran et fait le lien avec les fonctions du téléphone.
/// Le site appelle `window.EDPNative.call(type, données)` ; on répond par `window.EDPNative._done(...)`.
final class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let ent = EntAuth()
    private let refresher = UIRefreshControl()
    private var loadedOnce = false

    // MARK: Mise en place

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()             // garde ta connexion EDP d'une ouverture à l'autre
        config.allowsInlineMediaPlayback = true          // caméra du scanner QR, lecteur du podcast
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "EDPApp/1.0"

        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.add(WeakScriptHandler(self), name: "edp")
        config.userContentController = content

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false
        web.scrollView.contentInsetAdjustmentBehavior = .never   // le site gère lui-même l'encoche et la barre du bas
        web.isOpaque = false
        let background = UIColor(named: "LaunchBg") ?? .systemBackground
        web.backgroundColor = background
        web.scrollView.backgroundColor = background
        if #available(iOS 16.4, *) { web.isInspectable = true }

        refresher.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        web.scrollView.refreshControl = refresher

        webView = web
        view = web
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: Config.serverURL))
        NotificationCenter.default.addObserver(self, selector: #selector(cameBack),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ent.anchor = view.window
    }

    @objc private func pullToRefresh() {
        // le site relance une synchro Pronote complète
        webView.evaluateJavaScript("window.dispatchEvent(new Event('edp-native-refresh'))", completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.refresher.endRefreshing() }
    }

    @objc private func cameBack() {
        webView.evaluateJavaScript("window.dispatchEvent(new Event('edp-native-resume'))", completionHandler: nil)
    }

    // MARK: Pont site ↔ téléphone

    static let bridgeScript = """
    (function () {
      if (window.EDPNative) return;
      var pending = {}, next = 0;
      window.EDPNative = {
        isNative: true, platform: 'ios', version: '1.0',
        call: function (type, payload) {
          return new Promise(function (resolve, reject) {
            var id = ++next;
            pending[id] = [resolve, reject];
            window.webkit.messageHandlers.edp.postMessage({ id: id, type: type, payload: payload || {} });
          });
        },
        _done: function (id, ok, data) {
          var p = pending[id]; if (!p) return; delete pending[id];
          if (ok) p[0](data); else p[1](new Error(typeof data === 'string' ? data : 'Erreur de l’appli'));
        }
      };
    })();
    """

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // n'accepte que les demandes venant de ton serveur EDP
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.host == Config.serverURL.host,
              let body = message.body as? [String: Any],
              let id = (body["id"] as? NSNumber)?.intValue,
              let type = body["type"] as? String else { return }
        let payload = body["payload"] as? [String: Any] ?? [:]
        let reply: (Bool, Any) -> Void = { [weak self] ok, data in self?.reply(id: id, ok: ok, data: data) }

        switch type {
        case "session":
            Session.save(token: payload["token"] as? String, server: payload["server"] as? String)
            reply(true, [String: Any]())

        case "entLogin":
            guard let s = payload["url"] as? String, let url = URL(string: s), url.scheme == "https" else {
                reply(false, "Adresse de connexion invalide."); return
            }
            ent.anchor = view.window
            ent.start(url: url, scheme: (payload["scheme"] as? String) ?? "skoapp-prod") { result in
                switch result {
                case .success(let back): reply(true, ["url": back.absoluteString])
                case .failure(let error): reply(false, error.localizedDescription)
                }
            }

        case "getPosition":
            LocationService.shared.currentPosition { result in
                switch result {
                case .success(let l):
                    reply(true, ["lat": l.coordinate.latitude, "lng": l.coordinate.longitude, "acc": l.horizontalAccuracy])
                case .failure(let error):
                    reply(false, error.localizedDescription)
                }
            }

        case "notifyPermission":
            Reminders.requestPermission { granted in reply(true, ["granted": granted]) }

        case "schedule":
            Reminders.schedule(payload["items"] as? [[String: Any]] ?? []) { count in reply(true, ["count": count]) }

        case "theme":
            let mode = payload["mode"] as? String ?? "auto"
            view.window?.overrideUserInterfaceStyle = mode == "dark" ? .dark : (mode == "light" ? .light : .unspecified)
            reply(true, [String: Any]())

        case "openExternal":
            if let s = payload["url"] as? String, let url = URL(string: s) { UIApplication.shared.open(url) }
            reply(true, [String: Any]())

        default:
            reply(false, "Action inconnue : \(type)")
        }
    }

    private func reply(id: Int, ok: Bool, data: Any) {
        // encodé dans un tableau pour accepter aussi un simple texte ; vérifié avant pour ne jamais planter
        var json = "null"
        let wrapped: [Any] = [data]
        if JSONSerialization.isValidJSONObject(wrapped),
           let d = try? JSONSerialization.data(withJSONObject: wrapped),
           let s = String(data: d, encoding: .utf8), s.count >= 2 {
            json = String(s.dropFirst().dropLast())
        }
        webView.evaluateJavaScript("window.EDPNative && window.EDPNative._done(\(id), \(ok ? "true" : "false"), \(json))",
                                   completionHandler: nil)
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["about", "blob", "data", "javascript"].contains(scheme) || url.host == Config.serverURL.host {
            decisionHandler(.allow); return
        }
        if navigationAction.targetFrame != nil && navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow); return     // cadres intégrés
        }
        // liens externes (franceinfo, Spotify, Plans, pièces jointes…) : ouverts dans la bonne appli
        UIApplication.shared.open(url)
        decisionHandler(.cancel)
    }

    /// Liens « target=_blank ».
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if url.host == Config.serverURL.host { webView.load(navigationAction.request) } else { UIApplication.shared.open(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadedOnce = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let e = error as NSError
        if e.code == NSURLErrorCancelled { return }
        showOffline(e.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()     // iOS a libéré la mémoire de la page : on la recharge
    }

    private func showOffline(_ reason: String) {
        let server = Config.serverURL.absoluteString
        let safeReason = reason.replacingOccurrences(of: "<", with: "&lt;")
        let html = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <body style="font:16px -apple-system,system-ui;display:grid;place-items:center;height:100vh;margin:0;text-align:center;color:#0d0d0e;background:#f2f2f0">
        <div style="padding:24px"><h2 style="margin:0 0 8px">Pas de connexion</h2>
        <p style="color:#6b778d;margin:0 0 20px">EDP n’arrive pas à joindre ton serveur.<br><small>\(safeReason)</small></p>
        <a href="\(server)" style="display:inline-block;background:#111113;color:#fff;padding:12px 22px;border-radius:10px;text-decoration:none;font-weight:600">Réessayer</a></div></body>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: Caméra et boîtes de dialogue

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // une seule demande (celle d'iOS) pour scanner le QR Pronote, uniquement pour ton serveur
        decisionHandler(origin.host == Config.serverURL.host ? .grant : .deny)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }
}

/// Évite que la page garde l'écran en mémoire pour toujours (cycle de références WebKit).
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
