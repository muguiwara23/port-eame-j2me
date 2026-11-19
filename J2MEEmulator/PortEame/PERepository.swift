//
//  PERepository.swift
//  Port/eame Java
//
//  "Pegar repositorio": the player pastes the link of a place that holds .jar
//  files and gets the list of them, to add them all or some at once. It reads:
//    - an archive.org item (archive.org/details/ID or archive.org/download/ID),
//      through archive.org's public metadata API;
//    - a GitHub folder (github.com/owner/repo, .../tree/branch/folder), through
//      GitHub's contents API;
//    - GitHub releases (github.com/owner/repo/releases, .../releases/tag/T);
//    - a Port/eame JSON list: {"name": "...", "games": [{"name": "...", "url": "..."}]}
//      (or just an array of such games);
//    - any other web page or text file: every link in it that ends in .jar.
//  The links the player pastes are remembered, to look again later.
//

import Foundation

struct PERepoEntry {
    let name: String
    let url: URL
    let size: Int64?
}

struct PERepoListing {
    let title: String
    let entries: [PERepoEntry]
}

enum PERepository {
    private static let savedKey = "porteame_repositories"

    static var saved: [String] {
        UserDefaults.standard.stringArray(forKey: savedKey) ?? []
    }

    static func remember(_ link: String) {
        var list = saved.filter { $0 != link }
        list.insert(link, at: 0)
        UserDefaults.standard.set(Array(list.prefix(20)), forKey: savedKey)
    }

    static func forget(_ link: String) {
        UserDefaults.standard.set(saved.filter { $0 != link }, forKey: savedKey)
    }

    /// A link the player typed or pasted, made into a URL.
    static func url(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        return URL(string: trimmed) ?? URL(string: trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
    }

    /// Reads the list of .jar files at a link. Calls back on the main queue.
    static func list(_ link: URL, completion: @escaping (Result<PERepoListing, Error>) -> Void) {
        let finish: (Result<PERepoListing, Error>) -> Void = { result in
            if case .failure(let error) = result {
                print("Port/eame: repository \(link.absoluteString): \(error.localizedDescription)")
            }
            DispatchQueue.main.async { completion(result) }
        }
        let host = (link.host ?? "").lowercased()
        let parts = link.pathComponents.filter { $0 != "/" }
        if host.hasSuffix("archive.org"), parts.count >= 2, parts[0] == "details" || parts[0] == "download" {
            archiveOrg(item: parts[1], folder: parts.dropFirst(2).joined(separator: "/"), completion: finish)
        } else if host == "github.com" || host == "www.github.com", parts.count >= 2 {
            gitHub(owner: parts[0], repo: parts[1], rest: Array(parts.dropFirst(2)), completion: finish)
        } else {
            generic(link, completion: finish)
        }
    }

    // MARK: - Fetching

    private static func fetch(_ url: URL, completion: @escaping (Result<(Data, URLResponse), Error>) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("Port-eame-Java", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { return completion(.failure(error)) }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return completion(.failure(PEError.message("El servidor respondió \(http.statusCode)")))
            }
            guard let data = data, let response = response else {
                return completion(.failure(PEError.message("No llegó respuesta")))
            }
            completion(.success((data, response)))
        }.resume()
    }

    private static func isJar(_ name: String) -> Bool { name.lowercased().hasSuffix(".jar") }

    private static func displayName(_ fileName: String) -> String {
        let base = ((fileName as NSString).lastPathComponent as NSString).deletingPathExtension
        return (base.removingPercentEncoding ?? base).replacingOccurrences(of: "_", with: " ")
    }

    private static func pathEncoded(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    // MARK: - archive.org

    private static func archiveOrg(item: String, folder: String, completion: @escaping (Result<PERepoListing, Error>) -> Void) {
        guard let api = URL(string: "https://archive.org/metadata/\(pathEncoded(item))") else {
            return completion(.failure(PEError.message("Enlace de archive.org no válido")))
        }
        fetch(api) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let (data, _)):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let files = json["files"] as? [[String: Any]] else {
                    return completion(.failure(PEError.message("archive.org no dio la lista de archivos")))
                }
                let metadata = json["metadata"] as? [String: Any]
                let title = (metadata?["title"] as? String) ?? item
                var entries: [PERepoEntry] = []
                for file in files {
                    guard let name = file["name"] as? String, isJar(name) else { continue }
                    if !folder.isEmpty && !name.hasPrefix(folder) { continue }
                    guard let url = URL(string: "https://archive.org/download/\(pathEncoded(item))/\(pathEncoded(name))") else { continue }
                    let size = (file["size"] as? String).flatMap { Int64($0) }
                    entries.append(PERepoEntry(name: displayName(name), url: url, size: size))
                }
                completion(.success(PERepoListing(title: title, entries: entries)))
            }
        }
    }

    // MARK: - GitHub

    private static func gitHub(owner: String, repo: String, rest: [String], completion: @escaping (Result<PERepoListing, Error>) -> Void) {
        let base = "https://api.github.com/repos/\(pathEncoded(owner))/\(pathEncoded(repo))"
        if rest.first == "releases" {
            let api: String
            if rest.count >= 3 && rest[1] == "tag" {
                api = base + "/releases/tags/" + pathEncoded(rest[2])
            } else {
                api = base + "/releases?per_page=30"
            }
            guard let url = URL(string: api) else { return completion(.failure(PEError.message("Enlace de GitHub no válido"))) }
            fetch(url) { result in
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let (data, _)):
                    let object = try? JSONSerialization.jsonObject(with: data)
                    let releases = (object as? [[String: Any]]) ?? ((object as? [String: Any]).map { [$0] } ?? [])
                    var entries: [PERepoEntry] = []
                    for release in releases {
                        for asset in (release["assets"] as? [[String: Any]]) ?? [] {
                            guard let name = asset["name"] as? String, isJar(name),
                                  let link = asset["browser_download_url"] as? String, let url = URL(string: link) else { continue }
                            entries.append(PERepoEntry(name: displayName(name), url: url, size: (asset["size"] as? NSNumber)?.int64Value))
                        }
                    }
                    completion(.success(PERepoListing(title: "\(owner)/\(repo)", entries: entries)))
                }
            }
            return
        }
        // github.com/owner/repo[/tree/branch[/folder...]]
        var api = base + "/contents"
        if rest.count >= 2 && (rest[0] == "tree" || rest[0] == "blob") {
            let folder = rest.dropFirst(2).joined(separator: "/")
            if !folder.isEmpty { api += "/" + pathEncoded(folder) }
            api += "?ref=" + (rest[1].addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rest[1])
        }
        guard let url = URL(string: api) else { return completion(.failure(PEError.message("Enlace de GitHub no válido"))) }
        fetch(url) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let (data, _)):
                guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    return completion(.failure(PEError.message("GitHub no dio la lista de la carpeta")))
                }
                var entries: [PERepoEntry] = []
                for item in items {
                    guard (item["type"] as? String) == "file", let name = item["name"] as? String, isJar(name),
                          let link = item["download_url"] as? String, let url = URL(string: link) else { continue }
                    entries.append(PERepoEntry(name: displayName(name), url: url, size: (item["size"] as? NSNumber)?.int64Value))
                }
                completion(.success(PERepoListing(title: "\(owner)/\(repo)", entries: entries)))
            }
        }
    }

    // MARK: - JSON lists and web pages

    private static func generic(_ link: URL, completion: @escaping (Result<PERepoListing, Error>) -> Void) {
        fetch(link) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let (data, response)):
                let base = response.url ?? link
                if let listing = jsonListing(data, base: base) {
                    return completion(.success(listing))
                }
                let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
                let entries = jarLinks(in: text, base: base)
                let title = base.host ?? base.absoluteString
                completion(.success(PERepoListing(title: title, entries: entries)))
            }
        }
    }

    private static func jsonListing(_ data: Data, base: URL) -> PERepoListing? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var title = base.host ?? "Repositorio"
        var games: [[String: Any]] = []
        if let dict = object as? [String: Any] {
            if let name = dict["name"] as? String { title = name }
            games = (dict["games"] as? [[String: Any]]) ?? (dict["apps"] as? [[String: Any]]) ?? []
        } else if let array = object as? [[String: Any]] {
            games = array
        }
        var entries: [PERepoEntry] = []
        for game in games {
            guard let link = (game["url"] as? String) ?? (game["downloadURL"] as? String),
                  let url = URL(string: link, relativeTo: base)?.absoluteURL else { continue }
            let name = (game["name"] as? String) ?? displayName(url.lastPathComponent)
            entries.append(PERepoEntry(name: name, url: url, size: (game["size"] as? NSNumber)?.int64Value))
        }
        return entries.isEmpty ? nil : PERepoListing(title: title, entries: entries)
    }

    /// Every href="..." (or bare link) ending in .jar, made absolute, once each.
    private static func jarLinks(in text: String, base: URL) -> [PERepoEntry] {
        let pattern = "(?:href\\s*=\\s*[\"']([^\"']+?\\.jar)[\"'])|(https?://[^\\s\"'<>]+?\\.jar)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        var seen = Set<String>()
        var entries: [PERepoEntry] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            var found: String?
            for group in 1...2 {
                if let range = Range(match.range(at: group), in: text) { found = String(text[range]) }
            }
            guard var link = found else { continue }
            link = link.replacingOccurrences(of: "&amp;", with: "&")
            let url = URL(string: link, relativeTo: base)?.absoluteURL
                ?? URL(string: link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "", relativeTo: base)?.absoluteURL
            guard let absolute = url, !seen.contains(absolute.absoluteString) else { continue }
            seen.insert(absolute.absoluteString)
            entries.append(PERepoEntry(name: displayName(absolute.lastPathComponent), url: absolute, size: nil))
        }
        return entries
    }
}
