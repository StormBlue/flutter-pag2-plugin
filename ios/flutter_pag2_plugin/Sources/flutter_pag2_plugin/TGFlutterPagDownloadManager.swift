import Foundation
import CryptoKit

/// Pag文件下载工具
class TGFlutterPagDownloadManager {
    private static let cacheDirectoryName = "pagCache"

    /// 下载pag文件
    static func download(_ urlStr: String, completionHandler: @escaping (Data?, Error?) -> Void) {
        guard let cachePath = cachePath(for: urlStr) else {
            completionHandler(nil, NSError(domain: NSURLErrorDomain, code: -1, userInfo: nil))
            return
        }

        if FileManager.default.fileExists(atPath: cachePath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: cachePath)) {
            completionHandler(data, nil)
            return
        }

        guard let url = URL(string: urlStr), url.scheme != nil, url.host != nil else {
            completionHandler(nil, NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL, userInfo: nil))
            return
        }

        let request = URLRequest(url: url)
        URLSession.shared.dataTask(with: request) { data, _, error in
            completionHandler(data, error)
            if let data = data {
                saveData(data, path: cachePath)
            }
        }.resume()
    }

    private static func cacheDir() -> String {
        let cachePaths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        return "\(cachePaths.first!)/\(cacheDirectoryName)"
    }

    private static func cachePath(for url: String) -> String? {
        guard !url.isEmpty else { return nil }
        let key = sha256(url)
        return "\(cacheDir())/\(key)"
    }

    private static func sha256(_ str: String) -> String {
        let data = Data(str.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func saveData(_ data: Data, path: String) {
        let dir = cacheDir()
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
