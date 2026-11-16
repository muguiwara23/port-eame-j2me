//
//  DecadeConfigViewController.swift
//  J2MEEmulator
//
//  Authentic Decade 1:1 Configuration / Settings screen (matches Android Decade ConfigActivity).
//

import UIKit

class DecadeConfigViewController: UIViewController {

    private let app: AppsListViewController.AppInfo
    private let onStartGame: ((Int, Int, Int) -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIStackView()

    // Form inputs
    private let widthField = UITextField()
    private let heightField = UITextField()
    private let aspectSwitch = UISwitch()
    private let fpsLimitSegment = UISegmentedControl(items: ["Không giới hạn", "15", "20", "30", "60"])
    private let layoutSegment = UISegmentedControl(items: ["Mũi tên", "Số & Mũi tên", "Điện thoại"])
    private let alphaSlider = UISlider()
    private let alphaLabel = UILabel()
    private let fullscreenSwitch = UISwitch()
    private let showFpsSwitch = UISwitch()

    init(app: AppsListViewController.AppInfo, onStart: ((Int, Int, Int) -> Void)? = nil) {
        self.app = app
        self.onStartGame = onStart
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .white

        setupNavBar()
        setupUI()
        loadSavedValues()
    }

    // ============================================================
    // MARK: - Navigation Bar matching Screenshot 3
    // ============================================================

    private func setupNavBar() {
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0)
        navBarAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 18, weight: .bold)
        ]
        navigationController?.navigationBar.standardAppearance = navBarAppearance
        navigationController?.navigationBar.scrollEdgeAppearance = navBarAppearance
        navigationController?.navigationBar.tintColor = .white

        title = app.name

        // Back button on left
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.left"),
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )

        // "BẮT ĐẦU" (Start) button on right matching Screenshot 3
        let startBtn = UIBarButtonItem(
            title: "BẮT ĐẦU",
            style: .done,
            target: self,
            action: #selector(startTapped)
        )
        startBtn.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: UIColor.white
        ], for: .normal)

        let moreBtn = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            style: .plain,
            target: self,
            action: #selector(moreTapped)
        )

        navigationItem.rightBarButtonItems = [moreBtn, startBtn]
    }

    @objc private func backTapped() {
        saveValues()
        if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc private func startTapped() {
        saveValues()
        let w = Int(widthField.text ?? "") ?? 240
        let h = Int(heightField.text ?? "") ?? 320
        let fpsIdx = fpsLimitSegment.selectedSegmentIndex
        let fpsValues = [0, 15, 20, 30, 60]
        let fps = (fpsIdx >= 0 && fpsIdx < fpsValues.count) ? fpsValues[fpsIdx] : 0

        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.onStartGame?(w, h, fps)
        }
    }

    @objc private func moreTapped() {
        let alert = UIAlertController(title: "Tùy chọn", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Khôi phục mặc định", style: .default) { [weak self] _ in
            self?.resetDefaults()
        })
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        present(alert, animated: true)
    }

    // ============================================================
    // MARK: - UI Layout matching Screenshot 3
    // ============================================================

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentView.axis = .vertical
        contentView.spacing = 16
        contentView.layoutMargins = UIEdgeInsets(top: 16, left: 14, bottom: 30, right: 14)
        contentView.isLayoutMarginsRelativeArrangement = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        // 1. "Tùy chọn màn hình" Card
        contentView.addArrangedSubview(buildScreenOptionsCard())

        // 2. "Tùy chọn phông chữ" Card
        contentView.addArrangedSubview(buildFontOptionsCard())

        // 3. "Bàn phím ảo" Card
        contentView.addArrangedSubview(buildVirtualKeyboardCard())
    }

    /// Card 1: "Tùy chọn màn hình" matching Screenshot 3
    private func buildScreenOptionsCard() -> UIView {
        let card = makeRedBorderCard(title: "Tùy chọn màn hình")
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 36),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])

        // Resolution Row: [Preset List Icon] [ Width ] [ ⇄ ] [ Height ] [ Swap ]
        let resRow = UIStackView()
        resRow.axis = .horizontal
        resRow.spacing = 10
        resRow.alignment = .center

        let presetBtn = UIButton(type: .system)
        presetBtn.setImage(UIImage(systemName: "list.bullet"), for: .normal)
        presetBtn.tintColor = UIColor(red: 0.90, green: 0.22, blue: 0.21, alpha: 1.0)
        presetBtn.addTarget(self, action: #selector(showPresets), for: .touchUpInside)

        widthField.borderStyle = .none
        widthField.font = .systemFont(ofSize: 22, weight: .bold)
        widthField.textAlignment = .center
        widthField.keyboardType = .numberPad
        widthField.textColor = .black
        let wUnderline = makeUnderlineView(for: widthField)

        let swapBtn = UIButton(type: .system)
        swapBtn.setImage(UIImage(systemName: "arrow.left.arrow.right"), for: .normal)
        swapBtn.tintColor = UIColor(red: 0.90, green: 0.22, blue: 0.21, alpha: 1.0)
        swapBtn.addTarget(self, action: #selector(swapResolution), for: .touchUpInside)

        heightField.borderStyle = .none
        heightField.font = .systemFont(ofSize: 22, weight: .bold)
        heightField.textAlignment = .center
        heightField.keyboardType = .numberPad
        heightField.textColor = .black
        let hUnderline = makeUnderlineView(for: heightField)

        resRow.addArrangedSubview(presetBtn)
        resRow.addArrangedSubview(wUnderline)
        resRow.addArrangedSubview(swapBtn)
        resRow.addArrangedSubview(hUnderline)

        stack.addArrangedSubview(resRow)

        // Checkbox: Giữ tỷ lệ khung hình
        let aspectRow = UIStackView()
        aspectRow.axis = .horizontal
        aspectRow.spacing = 10
        aspectRow.alignment = .center

        let aspectLabel = UILabel()
        aspectLabel.text = "Giữ tỷ lệ khung hình"
        aspectLabel.font = .systemFont(ofSize: 16)
        aspectLabel.textColor = .black
        aspectRow.addArrangedSubview(aspectLabel)
        aspectRow.addArrangedSubview(UIView()) // spacer
        aspectRow.addArrangedSubview(aspectSwitch)
        stack.addArrangedSubview(aspectRow)

        // Background Color preview: [NỀN] D0D0D0
        let bgRow = UIStackView()
        bgRow.axis = .horizontal
        bgRow.spacing = 12
        bgRow.alignment = .center

        let bgBtn = UIButton(type: .system)
        bgBtn.setTitle("NỀN", for: .normal)
        bgBtn.backgroundColor = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1.0)
        bgBtn.setTitleColor(.white, for: .normal)
        bgBtn.layer.cornerRadius = 4
        bgBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        bgBtn.widthAnchor.constraint(equalToConstant: 80).isActive = true
        bgBtn.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let hexLabel = UILabel()
        hexLabel.text = "D0D0D0"
        hexLabel.font = .systemFont(ofSize: 15, weight: .medium)
        hexLabel.textColor = .darkGray

        let colorSwatch = UIView()
        colorSwatch.backgroundColor = UIColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1.0)
        colorSwatch.layer.cornerRadius = 4
        colorSwatch.widthAnchor.constraint(equalToConstant: 32).isActive = true
        colorSwatch.heightAnchor.constraint(equalToConstant: 32).isActive = true

        bgRow.addArrangedSubview(bgBtn)
        bgRow.addArrangedSubview(hexLabel)
        bgRow.addArrangedSubview(UIView())
        bgRow.addArrangedSubview(colorSwatch)
        stack.addArrangedSubview(bgRow)

        // Hiển thị FPS
        let fpsRow = UIStackView()
        fpsRow.axis = .horizontal
        fpsRow.alignment = .center
        let fpsLabel = UILabel()
        fpsLabel.text = "Hiển thị FPS"
        fpsLabel.font = .systemFont(ofSize: 16)
        fpsLabel.textColor = .black
        fpsRow.addArrangedSubview(fpsLabel)
        fpsRow.addArrangedSubview(UIView())
        fpsRow.addArrangedSubview(showFpsSwitch)
        stack.addArrangedSubview(fpsRow)

        // Giới hạn FPS
        let fpsLimitRow = UIStackView()
        fpsLimitRow.axis = .vertical
        fpsLimitRow.spacing = 6
        let fpsTitle = UILabel()
        fpsTitle.text = "Giới hạn FPS"
        fpsTitle.font = .systemFont(ofSize: 15)
        fpsTitle.textColor = .darkGray
        fpsLimitRow.addArrangedSubview(fpsTitle)
        fpsLimitRow.addArrangedSubview(fpsLimitSegment)
        stack.addArrangedSubview(fpsLimitRow)

        // Bắt buộc toàn màn hình
        let fsRow = UIStackView()
        fsRow.axis = .horizontal
        fsRow.alignment = .center
        let fsLabel = UILabel()
        fsLabel.text = "Bắt buộc toàn màn hình"
        fsLabel.font = .systemFont(ofSize: 16)
        fsLabel.textColor = .black
        fsRow.addArrangedSubview(fsLabel)
        fsRow.addArrangedSubview(UIView())
        fsRow.addArrangedSubview(fullscreenSwitch)
        stack.addArrangedSubview(fsRow)

        return card
    }

    /// Card 2: "Tùy chọn phông chữ"
    private func buildFontOptionsCard() -> UIView {
        let card = makeRedBorderCard(title: "Tùy chọn phông chữ")
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 36),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])

        let fontDesc = UILabel()
        fontDesc.text = "Cỡ chữ: Nhỏ (18), Trung bình (22), Lớn (26)\nKhử răng cưa phông chữ được kích hoạt."
        fontDesc.numberOfLines = 0
        fontDesc.font = .systemFont(ofSize: 14)
        fontDesc.textColor = .darkGray
        stack.addArrangedSubview(fontDesc)

        return card
    }

    /// Card 3: "Bàn phím ảo"
    private func buildVirtualKeyboardCard() -> UIView {
        let card = makeRedBorderCard(title: "Bàn phím ảo")
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 36),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])

        let layoutTitle = UILabel()
        layoutTitle.text = "Cấu trúc phím"
        layoutTitle.font = .systemFont(ofSize: 15)
        layoutTitle.textColor = .darkGray
        stack.addArrangedSubview(layoutTitle)
        stack.addArrangedSubview(layoutSegment)

        // Opacity Slider
        let alphaRow = UIStackView()
        alphaRow.axis = .horizontal
        alphaRow.spacing = 8
        alphaRow.alignment = .center

        let alphaTitle = UILabel()
        alphaTitle.text = "Độ trong suốt:"
        alphaTitle.font = .systemFont(ofSize: 15)
        alphaTitle.textColor = .darkGray

        alphaSlider.minimumValue = 10
        alphaSlider.maximumValue = 255
        alphaSlider.value = 64
        alphaSlider.addTarget(self, action: #selector(alphaChanged), for: .valueChanged)

        alphaLabel.text = "64 (25%)"
        alphaLabel.font = .systemFont(ofSize: 14, weight: .bold)
        alphaLabel.textColor = .black
        alphaLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true

        alphaRow.addArrangedSubview(alphaTitle)
        alphaRow.addArrangedSubview(alphaSlider)
        alphaRow.addArrangedSubview(alphaLabel)
        stack.addArrangedSubview(alphaRow)

        return card
    }

    // ============================================================
    // MARK: - Helpers
    // ============================================================

    private func makeRedBorderCard(title: String) -> UIView {
        let container = UIView()
        container.backgroundColor = .white
        container.layer.cornerRadius = 8
        container.layer.borderWidth = 1.5
        container.layer.borderColor = UIColor(red: 0.90, green: 0.22, blue: 0.21, alpha: 0.7).cgColor

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])

        return container
    }

    private func makeUnderlineView(for textField: UITextField) -> UIView {
        let box = UIView()
        box.translatesAutoresizingMaskIntoConstraints = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(textField)

        let line = UIView()
        line.backgroundColor = .black
        line.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(line)

        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: box.topAnchor),
            textField.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -4),

            line.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 2),
            line.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 1.5),
            box.widthAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])
        return box
    }

    @objc private func swapResolution() {
        let w = widthField.text
        widthField.text = heightField.text
        heightField.text = w
    }

    @objc private func showPresets() {
        let alert = UIAlertController(title: "Độ phân giải mẫu", message: nil, preferredStyle: .actionSheet)
        let presets = [
            ("240 × 320 (Chuẩn)", 240, 320),
            ("320 × 240 (Ngang)", 320, 240),
            ("128 × 160", 128, 160),
            ("176 × 220", 176, 220),
            ("360 × 640", 360, 640),
            ("480 × 800", 480, 800),
        ]
        for (label, w, h) in presets {
            alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                self?.widthField.text = "\(w)"
                self?.heightField.text = "\(h)"
            })
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func alphaChanged() {
        let v = Int(alphaSlider.value)
        let pct = Int((Double(v) / 255.0) * 100)
        alphaLabel.text = "\(v) (\(pct)%)"
    }

    private var gid: String {
        let jarName = URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent
        return jarName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
    }

    private func loadSavedValues() {
        let defaults = UserDefaults.standard
        let w = defaults.object(forKey: "resW_\(gid)") as? Int ?? 240
        let h = defaults.object(forKey: "resH_\(gid)") as? Int ?? 320
        widthField.text = "\(w)"
        heightField.text = "\(h)"

        aspectSwitch.isOn = defaults.object(forKey: "aspect_\(gid)") as? Bool ?? true

        let fps = defaults.object(forKey: "fpsLimit_\(gid)") as? Int ?? 0
        let fpsMap = [0: 0, 15: 1, 20: 2, 30: 3, 60: 4]
        fpsLimitSegment.selectedSegmentIndex = fpsMap[fps] ?? 0

        let layoutIdx = defaults.object(forKey: "keypad_layout_\(gid)") as? Int ?? 0
        layoutSegment.selectedSegmentIndex = layoutIdx

        let alpha = defaults.object(forKey: "keypad_alpha_\(gid)") as? Float ?? 64.0
        alphaSlider.value = alpha
        alphaChanged()

        fullscreenSwitch.isOn = defaults.object(forKey: "fullscreen_\(gid)") as? Bool ?? false
        showFpsSwitch.isOn = defaults.object(forKey: "show_fps_\(gid)") as? Bool ?? false
    }

    private func saveValues() {
        let defaults = UserDefaults.standard
        let w = Int(widthField.text ?? "") ?? 240
        let h = Int(heightField.text ?? "") ?? 320
        defaults.set(w, forKey: "resW_\(gid)")
        defaults.set(h, forKey: "resH_\(gid)")
        defaults.set(aspectSwitch.isOn, forKey: "aspect_\(gid)")

        let fpsValues = [0, 15, 20, 30, 60]
        let fpsIdx = fpsLimitSegment.selectedSegmentIndex
        if fpsIdx >= 0 && fpsIdx < fpsValues.count {
            defaults.set(fpsValues[fpsIdx], forKey: "fpsLimit_\(gid)")
        }

        defaults.set(layoutSegment.selectedSegmentIndex, forKey: "keypad_layout_\(gid)")
        defaults.set(alphaSlider.value, forKey: "keypad_alpha_\(gid)")
        defaults.set(fullscreenSwitch.isOn, forKey: "fullscreen_\(gid)")
        defaults.set(showFpsSwitch.isOn, forKey: "show_fps_\(gid)")
    }

    private func resetDefaults() {
        widthField.text = "240"
        heightField.text = "320"
        aspectSwitch.isOn = true
        fpsLimitSegment.selectedSegmentIndex = 0
        layoutSegment.selectedSegmentIndex = 0
        alphaSlider.value = 64
        alphaChanged()
        fullscreenSwitch.isOn = false
        showFpsSwitch.isOn = false
    }
}
