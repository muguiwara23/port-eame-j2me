//
//  DecadeKeypadView.swift
//  J2MEEmulator
//
//  Authentic KamenRider Decade virtual keypad with full customization:
//  - Pure directional keycodes (Canvas.UP=-1, DOWN=-2, LEFT=-3, RIGHT=-4, FIRE=-5, etc.)
//    -> NEVER outputs numbers when navigating!
//  - "Công tắc cấu trúc phím" (Layout switcher): Arrows, Numpad, Combined
//  - "Ẩn nút" (Key visibility toggle matching Android Decade Screenshot 1)
//  - "Chế độ chỉnh sửa cấu trúc phím" (Drag to move keys freely anywhere)
//  - "Chế độ thay đổi kích cỡ cấu trúc phím" (Pinch to resize keys)
//  - "Hoàn thành chế độ chỉnh sửa" (Save and lock layout)
//

import UIKit

enum DecadeKeypadLayout: Int {
    case arrows = 0    // Decade 5x3 Directional Pad (Default)
    case numpad = 1    // Phone Numpad (0-9, *, #)
    case combined = 2  // Arrows + Numpad combined
}

class DecadeKeypadView: UIView, UIGestureRecognizerDelegate {

    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var repeatTimer: Timer?
    private var activeCode1: Int32 = 0
    private var activeCode2: Int32 = 0

    var onTextInputTapped: (() -> Void)?
    var onMenuTapped: (() -> Void)?

    let containerView = UIView()
    private var buttons: [DecadeKeyButton] = []

    // Customization state
    var gameId: String = "default" {
        didSet {
            loadSavedCustomLayout()
            rebuildKeypad()
        }
    }

    var currentLayout: DecadeKeypadLayout = .arrows {
        didSet {
            loadSavedCustomLayout()
            rebuildKeypad()
        }
    }

    var showDiagonalKeys: Bool = true {
        didSet { rebuildKeypad() }
    }
    var showSoftKeys: Bool = true {
        didSet { rebuildKeypad() }
    }
    var showFireKey: Bool = true {
        didSet { rebuildKeypad() }
    }
    var keypadAlphaValue: CGFloat = 0.70 {
        didSet {
            for btn in buttons {
                btn.backgroundColor = UIColor(white: 1.0, alpha: keypadAlphaValue)
            }
        }
    }

    // Hidden keys set from "Ẩn nút" dialog (checked = hidden)
    var hiddenKeys: Set<String> = [] {
        didSet {
            updateKeysVisibility()
        }
    }

    // Edit & Resize mode state
    var isEditLayoutMode: Bool = false {
        didSet {
            updateEditModeAppearance()
        }
    }

    var isResizeLayoutMode: Bool = false {
        didSet {
            updateEditModeAppearance()
        }
    }

    // Saved custom frames normalized (x/w, y/h, w/w, h/h)
    private var customFrames: [String: [CGFloat]] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupKeypad()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupKeypad()
    }

    private func setupKeypad() {
        backgroundColor = UIColor(red: 0.925, green: 0.937, blue: 0.953, alpha: 1.0)
        layer.cornerRadius = 16
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        clipsToBounds = true

        containerView.backgroundColor = .clear
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            containerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -6),
        ])

        loadSavedCustomLayout()
        rebuildKeypad()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyButtonPositions()
    }

    // ============================================================
    // MARK: - Rebuild Keypad
    // ============================================================

    func rebuildKeypad() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()

        let glyphColor = UIColor(red: 0.43, green: 0.49, blue: 0.66, alpha: 1.0)

        let items: [(title: String, c1: Int32, c2: Int32, defaultCol: Int, defaultRow: Int, totalCols: Int, totalRows: Int)]

        switch currentLayout {
        case .arrows:
            // Layout 1: Decade Mũi tên (Arrows - Pure Navigation, NO NUMBERS)
            // User requested: '*' and '#' at the two corners in Row 2!
            // Row 0: [ L ]  [ ↖ ]  [ ↑ ]  [ ↗ ]  [ R ]
            // Row 1: [   ]  [ ← ]  [ F ]  [ → ]  [   ]
            // Row 2: [ * ]  [ ↙ ]  [ ↓ ]  [ ↘ ]  [ # ]
            let upLeftCodes: (Int32, Int32) = showDiagonalKeys ? (-1, -3) : (0, 0)
            let upRightCodes: (Int32, Int32) = showDiagonalKeys ? (-1, -4) : (0, 0)
            let downLeftCodes: (Int32, Int32) = showDiagonalKeys ? (-2, -3) : (0, 0)
            let downRightCodes: (Int32, Int32) = showDiagonalKeys ? (-2, -4) : (0, 0)
            let soft1Code: Int32 = showSoftKeys ? -6 : 0
            let soft2Code: Int32 = showSoftKeys ? -7 : 0
            let fireCode: Int32 = showFireKey ? -5 : 0

            var list: [(String, Int32, Int32, Int, Int, Int, Int)] = []
            if showSoftKeys {
                list.append(("L", soft1Code, 0, 0, 0, 5, 3))
                list.append(("R", soft2Code, 0, 4, 0, 5, 3))
            }
            if showDiagonalKeys {
                list.append(("↖", upLeftCodes.0, upLeftCodes.1, 1, 0, 5, 3))
                list.append(("↗", upRightCodes.0, upRightCodes.1, 3, 0, 5, 3))
                list.append(("↙", downLeftCodes.0, downLeftCodes.1, 1, 2, 5, 3))
                list.append(("↘", downRightCodes.0, downRightCodes.1, 3, 2, 5, 3))
            }
            list.append(("↑", -1, 0, 2, 0, 5, 3))
            list.append(("←", -3, 0, 1, 1, 5, 3))
            if showFireKey {
                list.append(("F", fireCode, 0, 2, 1, 5, 3))
            }
            list.append(("→", -4, 0, 3, 1, 5, 3))
            list.append(("↓", -2, 0, 2, 2, 5, 3))

            // * and # at corners of Row 2:
            list.append(("*", 42, 0, 0, 2, 5, 3))
            list.append(("#", 35, 0, 4, 2, 5, 3))

            // Numbers 1-0: Available if unhidden in "Ẩn nút" dialog
            let numbers: [(String, Int32, Int, Int)] = [
                ("1", 49, 0, 0), ("2", 50, 1, 0), ("3", 51, 2, 0),
                ("4", 52, 0, 1), ("5", 53, 1, 1), ("6", 54, 2, 1),
                ("7", 55, 0, 2), ("8", 56, 1, 2), ("9", 57, 2, 2),
                ("0", 48, 1, 2)
            ]
            for num in numbers {
                list.append((num.0, num.1, 0, num.2, num.3, 5, 3))
            }

            items = list

        case .numpad:
            // Layout 2: Phone Numpad
            items = [
                ("1", 49, 0, 0, 0, 3, 4),
                ("2", 50, 0, 1, 0, 3, 4),
                ("3", 51, 0, 2, 0, 3, 4),
                ("4", 52, 0, 0, 1, 3, 4),
                ("5", 53, 0, 1, 1, 3, 4),
                ("6", 54, 0, 2, 1, 3, 4),
                ("7", 55, 0, 0, 2, 3, 4),
                ("8", 56, 0, 1, 2, 3, 4),
                ("9", 57, 0, 2, 2, 3, 4),
                ("*", 42, 0, 0, 3, 3, 4),
                ("0", 48, 0, 1, 3, 3, 4),
                ("#", 35, 0, 2, 3, 3, 4),
            ]

        case .combined:
            // Layout 3: Combined
            items = [
                ("1", 49, 0, 0, 0, 5, 3),
                ("2", 50, 0, 1, 0, 5, 3),
                ("3", 51, 0, 2, 0, 5, 3),
                ("↑", -1, 0, 3, 0, 5, 3),
                ("L", -6, 0, 4, 0, 5, 3),

                ("4", 52, 0, 0, 1, 5, 3),
                ("5", 53, 0, 1, 1, 5, 3),
                ("6", 54, 0, 2, 1, 5, 3),
                ("F", -5, 0, 3, 1, 5, 3),
                ("R", -7, 0, 4, 1, 5, 3),

                ("7", 55, 0, 0, 2, 5, 3),
                ("8", 56, 0, 1, 2, 5, 3),
                ("9", 57, 0, 2, 2, 5, 3),
                ("↓", -2, 0, 3, 2, 5, 3),
                ("#", 35, 0, 4, 2, 5, 3),
            ]
        }

        for item in items {
            let btn = DecadeKeyButton(title: item.title, c1: item.c1, c2: item.c2,
                                      defaultCol: item.defaultCol, defaultRow: item.defaultRow,
                                      totalCols: item.totalCols, totalRows: item.totalRows)
            btn.setTitle(item.title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
            btn.setTitleColor(glyphColor, for: .normal)
            btn.backgroundColor = UIColor(white: 1.0, alpha: keypadAlphaValue)
            btn.layer.cornerRadius = 12
            btn.layer.borderWidth = 1.0
            btn.layer.borderColor = UIColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 0.60).cgColor

            btn.layer.shadowColor = UIColor(red: 0.2, green: 0.25, blue: 0.35, alpha: 0.12).cgColor
            btn.layer.shadowOffset = CGSize(width: 0, height: 1.5)
            btn.layer.shadowRadius = 2.0
            btn.layer.shadowOpacity = 1.0

            btn.addTarget(self, action: #selector(buttonDown(_:)), for: .touchDown)
            btn.addTarget(self, action: #selector(buttonUp(_:)),
                          for: [.touchUpInside, .touchUpOutside, .touchCancel])

            // Pan gesture for dragging in edit mode
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            pan.isEnabled = isEditLayoutMode
            btn.addGestureRecognizer(pan)

            // Pinch gesture for resizing in resize mode
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            pinch.isEnabled = isResizeLayoutMode
            btn.addGestureRecognizer(pinch)

            containerView.addSubview(btn)
            buttons.append(btn)
        }

        updateKeysVisibility()
        updateEditModeAppearance()
        setNeedsLayout()
    }

    // ============================================================
    // MARK: - Key Positioning & Resizing
    // ============================================================

    private func applyButtonPositions() {
        let containerW = containerView.bounds.width
        let containerH = containerView.bounds.height
        guard containerW > 20, containerH > 20 else { return }

        for btn in buttons {
            if let norm = customFrames[btn.keyTitle], norm.count == 4 {
                let x = norm[0] * containerW
                let y = norm[1] * containerH
                let w = norm[2] * containerW
                let h = norm[3] * containerH
                btn.frame = CGRect(x: x, y: y, width: max(32, w), height: max(32, h))
            } else {
                // Default grid calculation
                let totalCols = CGFloat(btn.totalCols)
                let totalRows = CGFloat(btn.totalRows)
                let spacing: CGFloat = 8
                let availableW = containerW - (totalCols - 1) * spacing
                let availableH = containerH - (totalRows - 1) * spacing
                let cellW = availableW / totalCols
                let cellH = availableH / totalRows

                let x = CGFloat(btn.defaultCol) * (cellW + spacing)
                let y = CGFloat(btn.defaultRow) * (cellH + spacing)
                btn.frame = CGRect(x: x, y: y, width: cellW, height: cellH)
            }
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isEditLayoutMode, let btn = gesture.view as? DecadeKeyButton else { return }
        let translation = gesture.translation(in: containerView)
        var newCenter = CGPoint(x: btn.center.x + translation.x, y: btn.center.y + translation.y)

        let halfW = btn.bounds.width / 2
        let halfH = btn.bounds.height / 2
        newCenter.x = max(halfW, min(containerView.bounds.width - halfW, newCenter.x))
        newCenter.y = max(halfH, min(containerView.bounds.height - halfH, newCenter.y))

        btn.center = newCenter
        gesture.setTranslation(.zero, in: containerView)

        saveButtonPosition(btn)

        if gesture.state == .ended || gesture.state == .cancelled {
            saveCustomLayout()
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard isResizeLayoutMode, let btn = gesture.view as? DecadeKeyButton else { return }
        let scale = gesture.scale
        let newWidth = max(36, min(140, btn.bounds.width * scale))
        let newHeight = max(36, min(140, btn.bounds.height * scale))
        btn.bounds = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
        gesture.scale = 1.0

        saveButtonPosition(btn)

        if gesture.state == .ended || gesture.state == .cancelled {
            saveCustomLayout()
        }
    }

    private func saveButtonPosition(_ btn: DecadeKeyButton) {
        let containerW = containerView.bounds.width
        let containerH = containerView.bounds.height
        guard containerW > 0, containerH > 0 else { return }

        let normX = btn.frame.origin.x / containerW
        let normY = btn.frame.origin.y / containerH
        let normW = btn.frame.size.width / containerW
        let normH = btn.frame.size.height / containerH

        customFrames[btn.keyTitle] = [normX, normY, normW, normH]
    }

    func saveCustomLayout() {
        let key = "decade_keypad_frames_\(gameId)_\(currentLayout.rawValue)"
        UserDefaults.standard.set(customFrames, forKey: key)
    }

    func loadSavedCustomLayout() {
        let key = "decade_keypad_frames_\(gameId)_\(currentLayout.rawValue)"
        if let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: [CGFloat]] {
            customFrames = saved
        } else {
            customFrames = [:]
        }

        let hiddenKey = "decade_hidden_keys_\(gameId)"
        if let savedHidden = UserDefaults.standard.stringArray(forKey: hiddenKey) {
            hiddenKeys = Set(savedHidden)
        } else {
            // Default hidden keys for Kiểu 1 (Arrows): 0-9 are hidden, while *, #, arrows, F, L, R are visible!
            hiddenKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        }
    }

    func resetLayout() {
        customFrames.removeAll()
        let key = "decade_keypad_frames_\(gameId)_\(currentLayout.rawValue)"
        UserDefaults.standard.removeObject(forKey: key)
        rebuildKeypad()
    }

    func finishEditingLayout() {
        isEditLayoutMode = false
        isResizeLayoutMode = false
        saveCustomLayout()
        updateEditModeAppearance()
    }

    private func updateEditModeAppearance() {
        for btn in buttons {
            for g in btn.gestureRecognizers ?? [] {
                if g is UIPanGestureRecognizer {
                    g.isEnabled = isEditLayoutMode
                } else if g is UIPinchGestureRecognizer {
                    g.isEnabled = isResizeLayoutMode
                }
            }

            if isEditLayoutMode {
                btn.layer.borderColor = UIColor.systemBlue.cgColor
                btn.layer.borderWidth = 2.5
            } else if isResizeLayoutMode {
                btn.layer.borderColor = UIColor.systemOrange.cgColor
                btn.layer.borderWidth = 2.5
            } else {
                btn.layer.borderColor = UIColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 0.60).cgColor
                btn.layer.borderWidth = 1.0
            }
        }
    }

    private func updateKeysVisibility() {
        for btn in buttons {
            let isHidden = hiddenKeys.contains(btn.keyTitle)
            btn.isHidden = isHidden
            btn.isUserInteractionEnabled = !isHidden
        }
    }

    // ============================================================
    // MARK: - Key Press Handling
    // ============================================================

    @objc private func buttonDown(_ sender: DecadeKeyButton) {
        guard !isEditLayoutMode && !isResizeLayoutMode else { return }
        haptic.impactOccurred(intensity: 0.6)
        activeCode1 = sender.c1
        activeCode2 = sender.c2

        sender.backgroundColor = UIColor(white: 1.0, alpha: 0.95)
        sender.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)

        sendKey(pressed: true)

        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.startRepeating()
        }
    }

    @objc private func buttonUp(_ sender: DecadeKeyButton) {
        guard !isEditLayoutMode && !isResizeLayoutMode else { return }
        repeatTimer?.invalidate()
        repeatTimer = nil

        UIView.animate(withDuration: 0.1) { [weak self] in
            sender.backgroundColor = UIColor(white: 1.0, alpha: self?.keypadAlphaValue ?? 0.70)
            sender.transform = .identity
        }

        sendKey(pressed: false)
        activeCode1 = 0
        activeCode2 = 0
    }

    private func startRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self = self, self.activeCode1 != 0 else { return }
            self.sendKey(pressed: true)
            usleep(15000)
            self.sendKey(pressed: false)
        }
    }

    private func sendKey(pressed: Bool) {
        let eventType = pressed ? Int32(J2ME_INPUT_KEY_PRESSED) : Int32(J2ME_INPUT_KEY_RELEASED)
        if activeCode1 != 0 {
            j2me_input_post_key(eventType, activeCode1)
        }
        if activeCode2 != 0 {
            j2me_input_post_key(eventType, activeCode2)
        }
    }
}

// Custom UIButton holding keycodes & grid info
class DecadeKeyButton: UIButton {
    let keyTitle: String
    let c1: Int32
    let c2: Int32
    let defaultCol: Int
    let defaultRow: Int
    let totalCols: Int
    let totalRows: Int

    init(title: String, c1: Int32, c2: Int32,
         defaultCol: Int, defaultRow: Int,
         totalCols: Int, totalRows: Int) {
        self.keyTitle = title
        self.c1 = c1
        self.c2 = c2
        self.defaultCol = defaultCol
        self.defaultRow = defaultRow
        self.totalCols = totalCols
        self.totalRows = totalRows
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
}
