//
//  PEIcons.swift
//  Port/eame Java
//
//  Each game's tile: its own icon from the .jar, enlarged pixel by pixel (no
//  blur) on a dark rounded square, or its first letter when it has none. The
//  same picture, at 512 x 512, is the shortcut's icon. And the shortcut's
//  link: porteame-java://jugar?juego=<file name>.
//

import UIKit

enum PEIcons {
    static let scheme = "porteame-java"
    private static var cache: [String: UIImage] = [:]

    static func link(for game: PEGame) -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "jugar"
        components.queryItems = [URLQueryItem(name: "juego", value: game.fileName)]
        return components.string ?? "\(scheme)://jugar"
    }

    static func tile(for game: PEGame, size: CGFloat) -> UIImage {
        let key = "\(game.fileName)#\(Int(size))"
        if let cached = cache[key] { return cached }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = size >= 256 ? 1 : UIScreen.main.scale
        format.opaque = true
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            let cg = context.cgContext
            let colors = [UIColor(red: 0.13, green: 0.15, blue: 0.19, alpha: 1).cgColor,
                          UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
            }
            if let icon = game.icon, let source = icon.cgImage {
                // The largest whole multiple of the icon's pixels that fits
                // three quarters of the tile: sharp pixels, centred.
                let pixels = CGFloat(max(source.width, source.height))
                let device = size * format.scale
                var scale = floor(device * 0.75 / max(pixels, 1))
                if scale < 1 { scale = device * 0.75 / max(pixels, 1) }
                let w = CGFloat(source.width) * scale / format.scale, h = CGFloat(source.height) * scale / format.scale
                cg.interpolationQuality = .none
                icon.draw(in: CGRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h))
            } else {
                let letter = String(game.name.prefix(1)).uppercased()
                let attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                    .font: UIFont.systemFont(ofSize: size * 0.46, weight: .bold),
                ]
                let text = letter as NSString
                let textSize = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2), withAttributes: attributes)
            }
        }
        cache[key] = image
        return image
    }
}
