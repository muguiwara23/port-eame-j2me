//
//  PELog.swift
//  Port/eame Java
//
//  An iOS app has no console: everything the app and the Java games print
//  (stdout and stderr, unbuffered) goes to Documents/port-eame-log.txt, which
//  the Files app shows; the previous run's log is kept as
//  port-eame-log-previous.txt. As the Port/eame kit's pe_ios_startup.
//

import Foundation

enum PELog {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var logURL: URL { documents.appendingPathComponent("port-eame-log.txt") }

    /// First thing at launch.
    static func start() {
        let fm = FileManager.default
        let previous = documents.appendingPathComponent("port-eame-log-previous.txt")
        try? fm.removeItem(at: previous)
        try? fm.moveItem(at: logURL, to: previous)
        fflush(stdout)
        fflush(stderr)
        let path = logURL.path
        if freopen(path, "a", stdout) != nil {
            setvbuf(stdout, nil, _IONBF, 0)
        }
        if freopen(path, "a", stderr) != nil {
            setvbuf(stderr, nil, _IONBF, 0)
        }
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        print("Port/eame Java \(version) (\(build)): started \(Date())")
        print("Port/eame: documents \(documents.path)")
    }
}
