import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

/// Accès à la photothèque : liste, miniatures, suppression, favoris, albums.
enum PhotoLibrary {

    // MARK: Autorisation

    /// Demande l'accès si besoin. Répond (accordé, limité).
    static func authorize(_ done: @escaping (Bool, Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized: done(true, false)
        case .limited: done(true, true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
                DispatchQueue.main.async { done(s == .authorized || s == .limited, s == .limited) }
            }
        default: done(false, false)
        }
    }

    // MARK: Liste complète

    /// Toutes les photos (et vidéos si demandé), sans les photos masquées. Données compactes pour l'interface.
    static func list(videos: Bool, _ done: @escaping ([[String: Any]]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            if !videos {
                options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            } else {
                options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                                PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
            }
            let result = PHAsset.fetchAssets(with: options)
            var out: [[String: Any]] = []
            out.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                let date = asset.creationDate ?? asset.modificationDate ?? Date(timeIntervalSince1970: 0)
                let video = asset.mediaType == .video
                out.append([
                    "id": asset.localIdentifier,
                    "k": video ? "v" : "i",
                    "d": Int64(date.timeIntervalSince1970 * 1000),
                    "w": asset.pixelWidth,
                    "h": asset.pixelHeight,
                    "dur": video ? asset.duration : 0,
                    "shot": asset.mediaSubtypes.contains(.photoScreenshot),
                    "fav": asset.isFavorite,
                ])
            }
            DispatchQueue.main.async { done(out) }
        }
    }

    static func assets(_ ids: [String]) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        var list: [PHAsset] = []
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        return list
    }

    // MARK: Modifications (iOS demande lui-même confirmation pour la suppression)

    /// Met les photos dans « Supprimés récemment » (30 jours). Répond false si tu as annulé.
    static func delete(_ ids: [String], _ done: @escaping (Bool, Int) -> Void) {
        let list = assets(ids)
        guard !list.isEmpty else { done(true, 0); return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(list as NSArray)
        }, completionHandler: { ok, _ in
            DispatchQueue.main.async { done(ok, ok ? list.count : 0) }
        })
    }

    static func setFavorite(_ ids: [String], _ fav: Bool, _ done: @escaping (Bool) -> Void) {
        let list = assets(ids)
        guard !list.isEmpty else { done(true); return }
        PHPhotoLibrary.shared().performChanges({
            for asset in list { PHAssetChangeRequest(for: asset).isFavorite = fav }
        }, completionHandler: { ok, _ in
            DispatchQueue.main.async { done(ok) }
        })
    }

    /// Crée (ou complète) un album Photos par album Tri. Les photos ne sont pas copiées.
    static func makeAlbums(_ albums: [(name: String, ids: [String])], _ done: @escaping (Bool, Int) -> Void) {
        let prepared = albums.compactMap { item -> (String, [PHAsset])? in
            let list = assets(item.ids)
            return list.isEmpty ? nil : (item.name, list)
        }
        guard !prepared.isEmpty else { done(true, 0); return }
        PHPhotoLibrary.shared().performChanges({
            for (name, list) in prepared {
                let options = PHFetchOptions()
                options.predicate = NSPredicate(format: "title == %@", name)
                if let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject,
                   let change = PHAssetCollectionChangeRequest(for: existing) {
                    change.addAssets(list as NSArray)
                } else {
                    PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name).addAssets(list as NSArray)
                }
            }
        }, completionHandler: { ok, _ in
            DispatchQueue.main.async { done(ok, ok ? prepared.count : 0) }
        })
    }

    // MARK: Images

    /// Image JPEG d'au plus `size` px de côté, avec la taille du fichier d'origine et son nom.
    static func jpeg(id: String, size: CGFloat, _ done: @escaping (Data?, [String: String]) -> Void) {
        guard let asset = assets([id]).first else { done(nil, [:]); return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true      // photos iCloud
        options.version = .current
        let target = CGSize(width: size, height: size)
        PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: options) { image, _ in
            guard let image = image else { done(nil, [:]); return }
            DispatchQueue.global(qos: .userInitiated).async {
                let data = downscale(image, max: size).jpegData(compressionQuality: size > 1000 ? 0.88 : 0.8)
                var headers: [String: String] = [:]
                if let res = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo || $0.type == .video || $0.type == .fullSizePhoto })
                    ?? PHAssetResource.assetResources(for: asset).first {
                    headers["X-Name"] = res.originalFilename.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
                    if res.responds(to: NSSelectorFromString("fileSize")), let n = res.value(forKey: "fileSize") as? NSNumber {
                        headers["X-Size"] = n.stringValue
                    }
                }
                DispatchQueue.main.async { done(data, headers) }
            }
        }
    }

    private static func downscale(_ image: UIImage, max side: CGFloat) -> UIImage {
        let w = image.size.width * image.scale, h = image.size.height * image.scale
        let biggest = Swift.max(w, h)
        guard biggest > side, biggest > 0 else { return image }
        let ratio = side / biggest
        let size = CGSize(width: (w * ratio).rounded(), height: (h * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Fichiers originaux (photos) pour le menu Partager.
    static func originalFiles(_ ids: [String], _ done: @escaping ([URL]) -> Void) {
        let list = assets(ids).filter { $0.mediaType == .image }
        guard !list.isEmpty else { done([]); return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("partage-tri", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        for (index, asset) in list.enumerated() {
            group.enter()
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                defer { group.leave() }
                guard let data = data else { return }
                let ext = uti.flatMap { UTType($0)?.preferredFilenameExtension } ?? "jpg"
                let original = PHAssetResource.assetResources(for: asset).first?.originalFilename
                let name = original ?? "photo-\(index + 1).\(ext)"
                let url = folder.appendingPathComponent("\(index)-" + name)
                if (try? data.write(to: url)) != nil {
                    lock.lock(); urls.append(url); lock.unlock()
                }
            }
        }
        group.notify(queue: .main) { done(urls) }
    }
}
