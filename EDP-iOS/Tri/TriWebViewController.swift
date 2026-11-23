import UIKit
import WebKit
import AVKit
import Photos

/// Affiche l'interface de Tri (embarquée dans l'appli, donc utilisable hors connexion)
/// et lui donne accès à la photothèque via `window.TriNative` et les adresses `tri://app/ph/…`.
final class TriWebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let scheme = TriSchemeHandler()

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()           // garde tes décisions de tri (IndexedDB) d'une ouverture à l'autre
        config.setURLSchemeHandler(scheme, forURLScheme: "tri")
        config.allowsInlineMediaPlayback = true

        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.add(TriWeakHandler(self), name: "tri")
        config.userContentController = content

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.isOpaque = false
        let background = UIColor(named: "LaunchBg") ?? .systemBackground
        web.backgroundColor = background
        web.scrollView.backgroundColor = background
        if #available(iOS 16.4, *) { web.isInspectable = true }
        webView = web
        view = web
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: URL(string: "tri://app/index.html")!))
    }

    // MARK: Pont interface ↔ téléphone

    static let bridgeScript = """
    (function () {
      if (window.TriNative) return;
      var pending = {}, next = 0;
      window.TriNative = {
        isNative: true, platform: 'ios', version: '1.0',
        call: function (type, payload) {
          return new Promise(function (resolve, reject) {
            var id = ++next;
            pending[id] = [resolve, reject];
            window.webkit.messageHandlers.tri.postMessage({ id: id, type: type, payload: payload || {} });
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
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.`protocol` == "tri",
              let body = message.body as? [String: Any],
              let id = (body["id"] as? NSNumber)?.intValue,
              let type = body["type"] as? String else { return }
        let payload = body["payload"] as? [String: Any] ?? [:]
        let reply: (Bool, Any) -> Void = { [weak self] ok, data in self?.reply(id: id, ok: ok, data: data) }
        let ids = (payload["ids"] as? [String]) ?? []

        switch type {
        case "photos.list":
            PhotoLibrary.authorize { granted, limited in
                guard granted else { reply(true, ["granted": false, "limited": false, "assets": [Any]()]); return }
                PhotoLibrary.list(videos: (payload["videos"] as? Bool) ?? true) { assets in
                    reply(true, ["granted": true, "limited": limited, "assets": assets])
                }
            }

        case "photos.delete":
            PhotoLibrary.delete(ids) { ok, count in reply(true, ["deleted": ok, "count": count]) }

        case "photos.favorite":
            PhotoLibrary.setFavorite(ids, (payload["fav"] as? Bool) ?? true) { ok in
                if ok { reply(true, ["ok": true]) } else { reply(false, "Favoris non modifiés dans Photos.") }
            }

        case "photos.albums":
            let raw = payload["albums"] as? [[String: Any]] ?? []
            let albums = raw.compactMap { a -> (name: String, ids: [String])? in
                guard let name = a["name"] as? String, !name.isEmpty, let list = a["ids"] as? [String] else { return nil }
                return (name: String(name.prefix(80)), ids: list)
            }
            PhotoLibrary.makeAlbums(albums) { ok, count in
                if ok { reply(true, ["count": count]) } else { reply(false, "Albums non créés dans Photos.") }
            }

        case "photos.share":
            PhotoLibrary.originalFiles(Array(ids.prefix(200))) { [weak self] urls in
                guard let self = self, !urls.isEmpty else { reply(false, "Rien à partager (photos introuvables)."); return }
                self.presentShare(urls)
                reply(true, ["count": urls.count])
            }

        case "photos.play":
            guard let pid = payload["id"] as? String, let asset = PhotoLibrary.assets([pid]).first else {
                reply(false, "Vidéo introuvable."); return
            }
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
                DispatchQueue.main.async {
                    guard let self = self, let item = item else { reply(false, "Lecture impossible."); return }
                    let player = AVPlayerViewController()
                    player.player = AVPlayer(playerItem: item)
                    self.present(player, animated: true) { player.player?.play() }
                    reply(true, [String: Any]())
                }
            }

        case "saveFile":
            let name = ((payload["name"] as? String) ?? "export.txt").replacingOccurrences(of: "/", with: "-")
            guard let b64 = payload["data"] as? String, let data = Data(base64Encoded: b64) else {
                reply(false, "Fichier invalide."); return
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do { try data.write(to: url); presentShare([url]); reply(true, [String: Any]()) }
            catch { reply(false, "Impossible de préparer le fichier.") }

        case "haptic":
            let strong = (payload["strong"] as? Bool) ?? false
            UIImpactFeedbackGenerator(style: strong ? .medium : .light).impactOccurred()
            reply(true, [String: Any]())

        case "openSettings":
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            reply(true, [String: Any]())

        default:
            reply(false, "Action inconnue : \(type)")
        }
    }

    private func presentShare(_ items: [Any]) {
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 80, width: 1, height: 1)
        present(sheet, animated: true)
    }

    private func reply(id: Int, ok: Bool, data: Any) {
        var json = "null"
        let wrapped: [Any] = [data]
        if JSONSerialization.isValidJSONObject(wrapped),
           let d = try? JSONSerialization.data(withJSONObject: wrapped),
           let s = String(data: d, encoding: .utf8), s.count >= 2 {
            json = String(s.dropFirst().dropLast())
        }
        webView.evaluateJavaScript("window.TriNative && window.TriNative._done(\(id), \(ok ? "true" : "false"), \(json))",
                                   completionHandler: nil)
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
        let s = url.scheme?.lowercased() ?? ""
        if ["tri", "about", "blob", "data", "javascript"].contains(s) { decisionHandler(.allow); return }
        UIApplication.shared.open(url)       // liens externes : Safari
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme != "tri", url.scheme != "blob" { UIApplication.shared.open(url) }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
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

final class TriWeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Sert `tri://app/…` : les fichiers de l'interface (dossier web de l'appli) et les images de la photothèque.
///   tri://app/ph/thumb?id=…&s=480   miniature pour l'analyse et la grille
///   tri://app/ph/full?id=…&s=2400   grande image pour la visionneuse
final class TriSchemeHandler: NSObject, WKURLSchemeHandler {
    private var active = Set<ObjectIdentifier>()
    private let lock = NSLock()
    private let webRoot: URL = Bundle.main.url(forResource: "web", withExtension: nil) ?? Bundle.main.bundleURL

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        setActive(urlSchemeTask, true)
        if url.path.hasPrefix("/ph/") {
            servePhoto(urlSchemeTask, url: url)
        } else {
            serveFile(urlSchemeTask, path: url.path)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        setActive(urlSchemeTask, false)
    }

    private func setActive(_ task: WKURLSchemeTask, _ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        if on { active.insert(ObjectIdentifier(task)) } else { active.remove(ObjectIdentifier(task)) }
    }

    private func isActive(_ task: WKURLSchemeTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active.contains(ObjectIdentifier(task))
    }

    private func serveFile(_ task: WKURLSchemeTask, path: String) {
        let clean = (path.isEmpty || path == "/") ? "/index.html" : path
        let file = webRoot.appendingPathComponent(String(clean.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(webRoot.standardizedFileURL.path), let data = try? Data(contentsOf: file) else {
            respond(task, status: 404, mime: "text/plain", data: Data("Introuvable".utf8)); return
        }
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "css": "text/css; charset=utf-8",
                     "json": "application/json", "webmanifest": "application/manifest+json", "png": "image/png",
                     "svg": "image/svg+xml", "jpg": "image/jpeg", "ico": "image/x-icon"]
        respond(task, mime: types[file.pathExtension.lowercased()] ?? "application/octet-stream", data: data)
    }

    private func servePhoto(_ task: WKURLSchemeTask, url: URL) {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let id = query.first(where: { $0.name == "id" })?.value, !id.isEmpty else {
            respond(task, status: 400, mime: "text/plain", data: Data("id manquant".utf8)); return
        }
        let wanted = Double(query.first(where: { $0.name == "s" })?.value ?? "") ?? (url.path.hasSuffix("full") ? 2400 : 480)
        let size = CGFloat(min(max(wanted, 64), 4096))
        PhotoLibrary.jpeg(id: id, size: size) { [weak self] data, headers in
            guard let self = self else { return }
            if let data = data {
                self.respond(task, mime: "image/jpeg", data: data, headers: headers)
            } else {
                self.respond(task, status: 404, mime: "text/plain", data: Data("Photo introuvable".utf8))
            }
        }
    }

    private func respond(_ task: WKURLSchemeTask, status: Int = 200, mime: String, data: Data, headers: [String: String] = [:]) {
        let send = { [weak self] in
            guard let self = self, self.isActive(task), let url = task.request.url else { return }
            var fields = headers
            fields["Content-Type"] = mime
            fields["Content-Length"] = String(data.count)
            fields["Access-Control-Allow-Origin"] = "*"
            fields["Access-Control-Expose-Headers"] = "X-Size, X-Name"
            fields["Cache-Control"] = "no-cache"
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: fields) else { return }
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
            self.setActive(task, false)
        }
        if Thread.isMainThread { send() } else { DispatchQueue.main.async(execute: send) }
    }
}
