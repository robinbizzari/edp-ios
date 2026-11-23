import Foundation
import UIKit
import AuthenticationServices

/// Connexion à l'ENT comme dans l'appli Skolengo officielle : la vraie page (ÉduConnect compris) s'ouvre
/// directement sur le téléphone, puis l'ENT renvoie vers « skoapp-prod://… ?code=… », que l'on récupère ici.
/// Le mot de passe est tapé sur la page de l'ENT : l'appli ne le voit jamais.
final class EntAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    weak var anchor: UIWindow?

    func start(url: URL, scheme: String, done: @escaping (Result<URL, Error>) -> Void) {
        let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
            DispatchQueue.main.async {
                self?.session = nil
                if let callback = callback {
                    done(.success(callback))
                } else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    done(.failure(BridgeError("Connexion annulée")))
                } else {
                    done(.failure(BridgeError("Connexion à l'ENT impossible : " + (error?.localizedDescription ?? "erreur inconnue"))))
                }
            }
        }
        auth.presentationContextProvider = self
        // garde la session ÉduConnect dans Safari : moins de reconnexions la fois suivante
        auth.prefersEphemeralWebBrowserSession = false
        session = auth
        if !auth.start() {
            session = nil
            done(.failure(BridgeError("Impossible d'ouvrir la page de connexion de l'ENT.")))
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let anchor = anchor { return anchor }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
