//
//  PELibrary.swift
//  Port/eame Java
//
//  The player's games: the .jar files in Documents/games (the folder the Files
//  app shows), each game's own settings, and the ways to add games: from the
//  Files app, from a link, or from a repository (archive.org, GitHub, a web
//  page that lists .jar files, or a Port/eame JSON list). No repository is
//  built in: each player pastes their own.
//

import UIKit

struct PEGame {
    let name: String
    let path: String
    let fileName: String
    let vendor: String?
    let version: String?
    let icon: UIImage?

    /// The id the games' saves and settings use ("Documents/Games Data/<id>").
    var id: String { PELibrary.gameId(fileName: fileName) }
}

enum PELibrary {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var gamesFolder: URL { documents.appendingPathComponent("games", isDirectory: true) }

    static func gameId(fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        return base.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
    }

    /// The games, by name. Reads each .jar's manifest (no Java runs).
    static func scan() -> [PEGame] {
        let fm = FileManager.default
        try? fm.createDirectory(at: gamesFolder, withIntermediateDirectories: true)
        let files = (try? fm.contentsOfDirectory(atPath: gamesFolder.path)) ?? []
        var games: [PEGame] = []
        for file in files where file.lowercased().hasSuffix(".jar") {
            let path = gamesFolder.appendingPathComponent(file).path
            let meta = JARMetadata.read(from: path)
            let fallback = (file as NSString).deletingPathExtension
            let name = (meta?.midletName.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            games.append(PEGame(name: name, path: path, fileName: file, vendor: meta?.vendor,
                                version: meta?.version, icon: meta?.readIcon(from: path)))
        }
        return games.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func game(fileName: String) -> PEGame? {
        scan().first { $0.fileName == fileName }
    }

    // MARK: - Per-game settings (the keys the game screen already reads)

    /// The game's screen in pixels. Most phone games are 240 x 320; a name
    /// like "Game_320x240.jar" says otherwise. The player can change it.
    static func resolution(for game: PEGame) -> (Int, Int) {
        let defaults = UserDefaults.standard
        let w = defaults.integer(forKey: "resW_\(game.id)"), h = defaults.integer(forKey: "resH_\(game.id)")
        if w > 0 && h > 0 { return (w, h) }
        if let hinted = resolutionHint(in: game.fileName) { return hinted }
        return (240, 320)
    }

    static func setResolution(_ size: (Int, Int)?, for game: PEGame) {
        let defaults = UserDefaults.standard
        if let size = size {
            defaults.set(size.0, forKey: "resW_\(game.id)")
            defaults.set(size.1, forKey: "resH_\(game.id)")
        } else {
            defaults.removeObject(forKey: "resW_\(game.id)")
            defaults.removeObject(forKey: "resH_\(game.id)")
        }
    }

    static func resolutionHint(in text: String) -> (Int, Int)? {
        let pattern = "(\\d{3})\\s*[xX×]\\s*(\\d{3})"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let wr = Range(match.range(at: 1), in: text), let hr = Range(match.range(at: 2), in: text),
              let w = Int(text[wr]), let h = Int(text[hr]),
              (96...800).contains(w), (64...800).contains(h) else { return nil }
        return (w, h)
    }

    static func fpsLimit(for game: PEGame) -> Int {
        UserDefaults.standard.object(forKey: "fpsLimit_\(game.id)") as? Int ?? 60
    }

    static func delete(_ game: PEGame) {
        try? FileManager.default.removeItem(atPath: game.path)
        deleteSaves(game)
    }

    static func deleteSaves(_ game: PEGame) {
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("Games Data/\(game.id)"))
    }

    // MARK: - Adding games

    /// Copies a .jar from anywhere (the Files app, another app's "Open in")
    /// into the games folder. Returns its file name.
    @discardableResult
    static func importFile(at url: URL) -> String? {
        guard url.pathExtension.lowercased() == "jar" else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: gamesFolder, withIntermediateDirectories: true)
        let destination = gamesFolder.appendingPathComponent(url.lastPathComponent)
        if destination.standardizedFileURL == url.standardizedFileURL { return url.lastPathComponent }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        var copied = false
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { readURL in
            try? fm.removeItem(at: destination)
            if (try? fm.copyItem(at: readURL, to: destination)) != nil {
                copied = true
            } else if let data = try? Data(contentsOf: readURL), (try? data.write(to: destination, options: .atomic)) != nil {
                copied = true
            }
        }
        print("Port/eame: import \(url.lastPathComponent): \(copied ? "ok" : "failed")")
        return copied ? url.lastPathComponent : nil
    }

    /// A file name for a downloaded game, from its link.
    static func fileName(for url: URL, suggested: String? = nil) -> String {
        var name = suggested ?? url.lastPathComponent
        name = name.removingPercentEncoding ?? name
        name = name.replacingOccurrences(of: "/", with: "_")
        if name.isEmpty || name == "/" { name = "game" }
        if !name.lowercased().hasSuffix(".jar") { name += ".jar" }
        return name
    }

    /// Downloads one .jar into the games folder. Calls back on the main queue.
    static func download(_ url: URL, name: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { location, response, error in
            var result: Result<String, Error>
            if let error = error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(PEError.message("El servidor respondió \(http.statusCode)"))
            } else if let location = location {
                let fileName = self.fileName(for: response?.url ?? url, suggested: name ?? response?.suggestedFilename)
                let destination = gamesFolder.appendingPathComponent(fileName)
                let fm = FileManager.default
                try? fm.createDirectory(at: gamesFolder, withIntermediateDirectories: true)
                try? fm.removeItem(at: destination)
                do {
                    try fm.moveItem(at: location, to: destination)
                    if isZip(destination) {
                        result = .success(fileName)
                    } else {
                        try? fm.removeItem(at: destination)
                        result = .failure(PEError.message("\(fileName) no es un archivo .jar"))
                    }
                } catch {
                    result = .failure(error)
                }
            } else {
                result = .failure(PEError.message("No llegó ningún archivo"))
            }
            if case .failure(let error) = result {
                print("Port/eame: download \(url.absoluteString) failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
    }

    /// A .jar is a zip file: it starts with "PK".
    static func isZip(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 2)
        return head.count == 2 && head[head.startIndex] == 0x50 && head[head.startIndex + 1] == 0x4B
    }
}

enum PEError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
