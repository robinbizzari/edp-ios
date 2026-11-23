import SwiftUI
import UIKit

/// Tri : l'appli de tri de galerie, branchée directement sur la photothèque de l'iPhone.
@main
struct TriApp: App {
    var body: some Scene {
        WindowGroup {
            TriContainer()
                .ignoresSafeArea()
        }
    }
}

struct TriContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TriWebViewController {
        TriWebViewController()
    }

    func updateUIViewController(_ uiViewController: TriWebViewController, context: Context) {}
}

/// Erreur lisible renvoyée à l'interface.
struct TriError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
