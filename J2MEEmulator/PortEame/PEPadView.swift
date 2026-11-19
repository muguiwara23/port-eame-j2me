//
//  PEPadView.swift
//  Port/eame Java
//
//  The on-screen phone keys, floating over the game in Port/eame's dark
//  glass: the D-pad (UP DOWN LEFT RIGHT, diagonals press two), OK (FIRE), the
//  two soft keys (L and R: the game's menus), MENU (the port's options) and
//  123, which opens the number keys (1-9, *, 0, #) only when a game needs them.
//  Several fingers at once (walk and shoot). A touch anywhere else goes
//  through to the game, for games that take touches.
//
//  Keys are J2ME's: UP -1, DOWN -2, LEFT -3, RIGHT -4, FIRE -5, soft keys -6
//  and -7, the digits their characters ('0'-'9', '*', '#').
//

import UIKit

final class PEPadView: UIView {
    enum Key: Int32 {
        case up = -1, down = -2, left = -3, right = -4, fire = -5, softLeft = -6, softRight = -7
        case n0 = 48, n1 = 49, n2 = 50, n3 = 51, n4 = 52, n5 = 53, n6 = 54, n7 = 55, n8 = 56, n9 = 57
        case star = 42, pound = 35
    }

    var onMenu: (() -> Void)?
    /// Hidden controls leave only MENU on screen.
    var controlsHidden = false { didSet { refreshVisibility() } }
    private(set) var numbersShown = false

    private final class Piece: UIView {
        let label = UILabel()
        let symbol = UIImageView()
        var lit = false { didSet { if lit != oldValue { paint() } } }
        var round = false

        init(text: String?, symbolName: String?, round: Bool) {
            self.round = round
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            layer.borderWidth = 1.5
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.35
            layer.shadowRadius = 4
            layer.shadowOffset = CGSize(width: 0, height: 2)
            label.text = text
            label.textColor = .white
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.5
            addSubview(label)
            if let name = symbolName {
                symbol.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(weight: .semibold))
                symbol.tintColor = .white
                symbol.contentMode = .scaleAspectFit
                addSubview(symbol)
            }
            paint()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        func paint() {
            backgroundColor = lit ? UIColor(white: 1, alpha: 0.34) : UIColor(white: 0.06, alpha: 0.42)
            layer.borderColor = UIColor(white: 1, alpha: lit ? 0.75 : 0.32).cgColor
            label.alpha = lit ? 1 : 0.9
            symbol.alpha = lit ? 1 : 0.9
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            layer.cornerRadius = round ? min(bounds.width, bounds.height) / 2 : min(bounds.width, bounds.height) * 0.28
            label.frame = bounds.insetBy(dx: 4, dy: 2)
            label.font = .systemFont(ofSize: max(11, bounds.height * 0.38), weight: .semibold)
            let s = min(bounds.width, bounds.height) * 0.45
            symbol.frame = CGRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s)
        }
    }

    // The D-pad: four arms and a middle, drawn as one cross.
    private let arms: [Key: Piece] = [
        .up: Piece(text: nil, symbolName: "chevron.up", round: false),
        .down: Piece(text: nil, symbolName: "chevron.down", round: false),
        .left: Piece(text: nil, symbolName: "chevron.left", round: false),
        .right: Piece(text: nil, symbolName: "chevron.right", round: false),
    ]
    private let hub = Piece(text: nil, symbolName: nil, round: false)
    private let ok = Piece(text: "OK", symbolName: nil, round: true)
    private let softLeft = Piece(text: "L", symbolName: nil, round: false)
    private let softRight = Piece(text: "R", symbolName: nil, round: false)
    private let menu = Piece(text: "MENU", symbolName: nil, round: false)
    private let numbersButton = Piece(text: "123", symbolName: nil, round: false)
    private let numberPanel = UIView()
    private var numberKeys: [(Key, Piece)] = []

    private var dpadCenter = CGPoint.zero
    private var unit: CGFloat = 60
    var menuView: UIView { menu }

    /// Which keys each finger holds.
    private var held: [ObjectIdentifier: Set<Int32>] = [:]
    private var zones: [ObjectIdentifier: String] = [:]
    private var counts: [Int32: Int] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        for piece in Array(arms.values) + [hub, ok, softLeft, softRight, menu, numbersButton] {
            addSubview(piece)
        }
        hub.layer.borderWidth = 0
        numberPanel.isUserInteractionEnabled = false
        numberPanel.isHidden = true
        addSubview(numberPanel)
        let labels: [(Key, String)] = [(.n1, "1"), (.n2, "2"), (.n3, "3"), (.n4, "4"), (.n5, "5"), (.n6, "6"),
                                       (.n7, "7"), (.n8, "8"), (.n9, "9"), (.star, "*"), (.n0, "0"), (.pound, "#")]
        for (key, text) in labels {
            let piece = Piece(text: text, symbolName: nil, round: false)
            numberPanel.addSubview(piece)
            numberKeys.append((key, piece))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Layout

    /// Lays the keys out around the game's picture: below it when the
    /// phone is upright, at its sides when it is turned.
    func layout(game: CGRect, safe: CGRect, landscape: Bool) {
        frame = superview?.bounds ?? frame
        let size: CGFloat
        if landscape {
            size = min(safe.height * 0.17, 72)
        } else {
            size = min(safe.width * 0.17, 72)
        }
        unit = size
        let pill = CGSize(width: size * 1.25, height: size * 0.55)
        let margin = size * 0.3
        let okRadius = size * 0.85
        if landscape {
            dpadCenter = CGPoint(x: safe.minX + margin + size * 1.5, y: safe.maxY - margin - size * 1.6)
            ok.frame = CGRect(x: safe.maxX - margin - size * 0.4 - okRadius * 2, y: dpadCenter.y - okRadius,
                              width: okRadius * 2, height: okRadius * 2)
            softLeft.frame = CGRect(origin: CGPoint(x: safe.minX + margin, y: safe.minY + margin), size: pill)
            softRight.frame = CGRect(origin: CGPoint(x: safe.maxX - margin - pill.width, y: safe.minY + margin), size: pill)
            menu.frame = CGRect(origin: CGPoint(x: safe.minX + margin, y: softLeft.frame.maxY + margin * 0.6), size: pill)
            numbersButton.frame = CGRect(origin: CGPoint(x: safe.maxX - margin - pill.width, y: softRight.frame.maxY + margin * 0.6), size: pill)
        } else {
            let top = game.maxY + margin
            let bottom = safe.maxY - margin
            softLeft.frame = CGRect(origin: CGPoint(x: safe.minX + margin, y: top), size: pill)
            softRight.frame = CGRect(origin: CGPoint(x: safe.maxX - margin - pill.width, y: top), size: pill)
            let middle = (softLeft.frame.maxY + bottom) / 2
            dpadCenter = CGPoint(x: safe.minX + margin + size * 1.5, y: middle)
            ok.frame = CGRect(x: safe.maxX - margin - size * 0.3 - okRadius * 2, y: middle - okRadius,
                              width: okRadius * 2, height: okRadius * 2)
            let small = CGSize(width: pill.width * 0.9, height: pill.height * 0.9)
            menu.frame = CGRect(origin: CGPoint(x: safe.midX - small.width - margin * 0.3, y: bottom - small.height), size: small)
            numbersButton.frame = CGRect(origin: CGPoint(x: safe.midX + margin * 0.3, y: bottom - small.height), size: small)
        }
        let arm = size, half = size / 2
        arms[.up]?.frame = CGRect(x: dpadCenter.x - half, y: dpadCenter.y - half - arm, width: arm, height: arm + 2)
        arms[.down]?.frame = CGRect(x: dpadCenter.x - half, y: dpadCenter.y + half - 2, width: arm, height: arm + 2)
        arms[.left]?.frame = CGRect(x: dpadCenter.x - half - arm, y: dpadCenter.y - half, width: arm + 2, height: arm)
        arms[.right]?.frame = CGRect(x: dpadCenter.x + half - 2, y: dpadCenter.y - half, width: arm + 2, height: arm)
        hub.frame = CGRect(x: dpadCenter.x - half, y: dpadCenter.y - half, width: arm, height: arm)

        // The number keys: a 3 x 4 block over the middle of the screen.
        let key = CGSize(width: size * 0.95, height: size * 0.72)
        let gap = size * 0.12
        let panel = CGSize(width: key.width * 3 + gap * 2, height: key.height * 4 + gap * 3)
        let panelY = landscape ? safe.midY - panel.height / 2 : max(game.maxY - panel.height - gap, safe.minY)
        numberPanel.frame = CGRect(x: safe.midX - panel.width / 2, y: panelY, width: panel.width, height: panel.height)
        for (index, entry) in numberKeys.enumerated() {
            let col = CGFloat(index % 3), row = CGFloat(index / 3)
            entry.1.frame = CGRect(x: col * (key.width + gap), y: row * (key.height + gap), width: key.width, height: key.height)
        }
        refreshVisibility()
    }

    private func refreshVisibility() {
        for piece in Array(arms.values) + [hub, ok, softLeft, softRight, numbersButton] {
            piece.isHidden = controlsHidden
        }
        numberPanel.isHidden = controlsHidden || !numbersShown
        numbersButton.lit = numbersShown
        menu.isHidden = false
    }

    func toggleNumbers() {
        numbersShown.toggle()
        refreshVisibility()
    }

    // MARK: - Touches

    /// Only the keys take touches; the rest of the screen is the game's.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        zone(at: point) != nil
    }

    private func grown(_ rect: CGRect) -> CGRect { rect.insetBy(dx: -unit * 0.15, dy: -unit * 0.15) }

    private func zone(at point: CGPoint) -> String? {
        if !menu.isHidden && grown(menu.frame).contains(point) { return "menu" }
        if controlsHidden { return nil }
        if numbersShown {
            for (key, piece) in numberKeys where grown(piece.frame.offsetBy(dx: numberPanel.frame.minX, dy: numberPanel.frame.minY)).contains(point) {
                return "n\(key.rawValue)"
            }
        }
        if grown(numbersButton.frame).contains(point) { return "123" }
        if hypot(point.x - dpadCenter.x, point.y - dpadCenter.y) <= unit * 1.9 { return "dpad" }
        if hypot(point.x - ok.frame.midX, point.y - ok.frame.midY) <= ok.frame.width * 0.7 { return "ok" }
        if grown(softLeft.frame).contains(point) { return "lsk" }
        if grown(softRight.frame).contains(point) { return "rsk" }
        return nil
    }

    /// The keys a finger in a zone presses at a point.
    private func keys(zone: String, at point: CGPoint) -> Set<Int32> {
        switch zone {
        case "dpad":
            let dx = point.x - dpadCenter.x, dy = point.y - dpadCenter.y, length = hypot(dx, dy)
            if length < unit * 0.25 || length > unit * 3 { return [] }
            var out = Set<Int32>()
            let c = dx / length, s = dy / length
            if c > 0.383 { out.insert(Key.right.rawValue) }
            if c < -0.383 { out.insert(Key.left.rawValue) }
            if s > 0.383 { out.insert(Key.down.rawValue) }
            if s < -0.383 { out.insert(Key.up.rawValue) }
            return out
        case "ok":
            return hypot(point.x - ok.frame.midX, point.y - ok.frame.midY) <= ok.frame.width ? [Key.fire.rawValue] : []
        case "lsk":
            return grown(softLeft.frame).contains(point) ? [Key.softLeft.rawValue] : []
        case "rsk":
            return grown(softRight.frame).contains(point) ? [Key.softRight.rawValue] : []
        default:
            if zone.hasPrefix("n"), let code = Int32(zone.dropFirst()) { return [code] }
            return []
        }
    }

    private func set(_ touch: UITouch, keys new: Set<Int32>) {
        let id = ObjectIdentifier(touch)
        let old = held[id] ?? []
        for code in old.subtracting(new) { release(code) }
        for code in new.subtracting(old) { press(code) }
        held[id] = new
        refreshLights()
    }

    private func press(_ code: Int32) {
        counts[code, default: 0] += 1
        if counts[code] == 1 { j2me_input_post_key(Int32(J2ME_INPUT_KEY_PRESSED), code) }
    }

    private func release(_ code: Int32) {
        guard let count = counts[code], count > 0 else { return }
        counts[code] = count - 1
        if count == 1 { j2me_input_post_key(Int32(J2ME_INPUT_KEY_RELEASED), code) }
    }

    private func refreshLights() {
        let down = Set(counts.filter { $0.value > 0 }.keys)
        for (key, piece) in arms { piece.lit = down.contains(key.rawValue) }
        ok.lit = down.contains(Key.fire.rawValue)
        softLeft.lit = down.contains(Key.softLeft.rawValue)
        softRight.lit = down.contains(Key.softRight.rawValue)
        for (key, piece) in numberKeys { piece.lit = down.contains(key.rawValue) }
    }

    /// Lets go of every key (the game paused, a menu opened).
    func releaseAll() {
        for (_, keys) in held { for code in keys { release(code) } }
        held.removeAll()
        zones.removeAll()
        counts.removeAll()
        refreshLights()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let zone = zone(at: point) else { continue }
            if zone == "menu" { menu.lit = true; zones[ObjectIdentifier(touch)] = zone; continue }
            if zone == "123" { toggleNumbers(); continue }
            zones[ObjectIdentifier(touch)] = zone
            set(touch, keys: keys(zone: zone, at: point))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let zone = zones[ObjectIdentifier(touch)], zone != "menu" else { continue }
            set(touch, keys: keys(zone: zone, at: touch.location(in: self)))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, tapped: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, tapped: false)
    }

    private func finish(_ touches: Set<UITouch>, tapped: Bool) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if zones[id] == "menu" {
                menu.lit = false
                zones[id] = nil
                if tapped && grown(menu.frame).contains(touch.location(in: self)) { onMenu?() }
                continue
            }
            if zones[id] != nil { set(touch, keys: []) }
            zones[id] = nil
            held[id] = nil
        }
    }
}
