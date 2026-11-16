//
//  AppsListViewController.swift
//  J2MEEmulator
//
//  Springboard-style home screen with app grid.
//

import UIKit
import UniformTypeIdentifiers

class AppsListViewController: UIViewController,
                      UICollectionViewDataSource,
                      UICollectionViewDelegate,
                      UIDocumentPickerDelegate {

    private var springboardCollectionView: UICollectionView!
    private let emptyStateLabel = UILabel()
    private let creditContainer = UIView()
    private var lastLayoutWidth: CGFloat = 0

    /// Directory where imported JARs are stored
    private static var gamesDirectory: String {
        documentsDirectory + "/games"
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)

        // Top bar buttons matching Decade Android (Screenshot 4): 3-dots menu
        let moreMenu = UIMenu(title: "", children: [
            UIAction(title: "FB: Bùi Hoàng Minh", image: UIImage(systemName: "person.crop.circle")) { [weak self] _ in
                self?.openFacebookProfile()
            },
            UIAction(title: "Zalo: Bùi Hoàng Minh", image: UIImage(systemName: "message.circle")) { [weak self] _ in
                self?.openZaloProfile()
            },
            UIAction(title: "Quản lý Proxy", image: UIImage(systemName: "network")) { [weak self] _ in
                self?.showProxyDialog()
            },
            UIAction(title: "Thay IP Phiên Bản", image: UIImage(systemName: "globe")) { [weak self] _ in
                self?.showChangeIpDialog()
            },
            UIAction(title: "Thiết lập", image: UIImage(systemName: "gearshape")) { [weak self] _ in
                self?.showGlobalSettings()
            },
            UIAction(title: "Hồ sơ", image: UIImage(systemName: "person.circle")) { [weak self] _ in
                self?.showProfilesDialog()
            },
            UIAction(title: "Trợ giúp", image: UIImage(systemName: "questionmark.circle")) { [weak self] _ in
                self?.showHelpDialog()
            },
            UIAction(title: "Lưu log", image: UIImage(systemName: "doc.text")) { [weak self] _ in
                self?.saveLogs()
            },
            UIAction(title: "Thoát", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { _ in
                exit(0)
            },
        ])
        let moreItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: moreMenu)
        moreItem.target = self
        moreItem.action = #selector(showTopMoreMenuActionSheet(_:))
        moreItem.tintColor = UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)

        let addItem = UIBarButtonItem(
            systemItem: .add, primaryAction: UIAction { [weak self] _ in
                self?.addAppTapped()
            })
        addItem.tintColor = UIColor(red: 0.90, green: 0.22, blue: 0.21, alpha: 1.0)

        navigationItem.rightBarButtonItems = [moreItem, addItem]

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 10

        springboardCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        springboardCollectionView.dataSource = self
        springboardCollectionView.delegate = self
        springboardCollectionView.backgroundColor = .clear
        springboardCollectionView.alwaysBounceVertical = true
        springboardCollectionView.showsVerticalScrollIndicator = false
        springboardCollectionView.register(SpringboardCell.self,
                                           forCellWithReuseIdentifier: SpringboardCell.reuseID)
        springboardCollectionView.contentInsetAdjustmentBehavior = .always
        springboardCollectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(springboardCollectionView)

        NSLayoutConstraint.activate([
            springboardCollectionView.topAnchor.constraint(equalTo: view.topAnchor),
            springboardCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            springboardCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            springboardCollectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Empty state
        emptyStateLabel.text = "No Games Yet\nTap + to add a .jar file"
        emptyStateLabel.textColor = UIColor(red: 0.25, green: 0.25, blue: 0.30, alpha: 1.0)
        emptyStateLabel.font = .systemFont(ofSize: 17, weight: .medium)
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.isHidden = true
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
        ])

        title = "KamenRider Decade"
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = .white
        navBarAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0),
            .font: UIFont.systemFont(ofSize: 18, weight: .bold)
        ]
        navigationController?.navigationBar.standardAppearance = navBarAppearance
        navigationController?.navigationBar.scrollEdgeAppearance = navBarAppearance
        navigationController?.navigationBar.tintColor = UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)

        // Red Floating Action Button (+) matching Decade Android
        let fab = UIButton(type: .system)
        fab.setTitle("+", for: .normal)
        fab.titleLabel?.font = .systemFont(ofSize: 32, weight: .light)
        fab.setTitleColor(.white, for: .normal)
        fab.backgroundColor = UIColor(red: 0.96, green: 0.26, blue: 0.21, alpha: 1.0)
        fab.layer.cornerRadius = 28
        fab.layer.shadowColor = UIColor.black.cgColor
        fab.layer.shadowOffset = CGSize(width: 0, height: 4)
        fab.layer.shadowRadius = 6
        fab.layer.shadowOpacity = 0.35
        fab.addTarget(self, action: #selector(addAppTapped), for: .touchUpInside)
        fab.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fab)

        NSLayoutConstraint.activate([
            fab.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            fab.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            fab.widthAnchor.constraint(equalToConstant: 56),
            fab.heightAnchor.constraint(equalToConstant: 56),
        ])

        // Author credits at bottom: 4 rows, display only (non-tappable), level with the red + button
        creditContainer.translatesAutoresizingMaskIntoConstraints = false
        creditContainer.isUserInteractionEnabled = false
        creditContainer.backgroundColor = UIColor(white: 1.0, alpha: 0.90)
        creditContainer.layer.cornerRadius = 14
        creditContainer.layer.borderWidth = 1
        creditContainer.layer.borderColor = UIColor(white: 0.88, alpha: 0.8).cgColor
        creditContainer.layer.shadowColor = UIColor.black.cgColor
        creditContainer.layer.shadowOpacity = 0.05
        creditContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
        creditContainer.layer.shadowRadius = 6
        view.addSubview(creditContainer)

        let line1 = UILabel()
        line1.text = "J2ME IOS tạo bởi BlackLotus"
        line1.font = .systemFont(ofSize: 13, weight: .bold)
        line1.textColor = UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)
        line1.textAlignment = .center
        line1.adjustsFontSizeToFitWidth = true
        line1.minimumScaleFactor = 0.8

        let line2 = UILabel()
        line2.text = "https://www.facebook.com/blacklotus00x"
        line2.font = .systemFont(ofSize: 11, weight: .medium)
        line2.textColor = UIColor(red: 0.09, green: 0.45, blue: 0.95, alpha: 1.0)
        line2.textAlignment = .center
        line2.adjustsFontSizeToFitWidth = true
        line2.minimumScaleFactor = 0.8

        let line3 = UILabel()
        line3.text = "Zalo: 0339143765"
        line3.font = .systemFont(ofSize: 11, weight: .medium)
        line3.textColor = UIColor(red: 0.0, green: 0.52, blue: 0.88, alpha: 1.0)
        line3.textAlignment = .center
        line3.adjustsFontSizeToFitWidth = true
        line3.minimumScaleFactor = 0.8

        let line4 = UILabel()
        line4.text = "ủng hộ tuỳ tâm :)) : 9100128591109 MB Bank"
        line4.font = .systemFont(ofSize: 11, weight: .semibold)
        line4.textColor = UIColor(red: 0.85, green: 0.35, blue: 0.1, alpha: 1.0)
        line4.textAlignment = .center
        line4.adjustsFontSizeToFitWidth = true
        line4.minimumScaleFactor = 0.8

        let creditStack = UIStackView(arrangedSubviews: [line1, line2, line3, line4])
        creditStack.axis = .vertical
        creditStack.alignment = .center
        creditStack.spacing = 3
        creditStack.isUserInteractionEnabled = false
        creditStack.translatesAutoresizingMaskIntoConstraints = false
        creditContainer.addSubview(creditStack)

        NSLayoutConstraint.activate([
            creditStack.topAnchor.constraint(equalTo: creditContainer.topAnchor, constant: 8),
            creditStack.bottomAnchor.constraint(equalTo: creditContainer.bottomAnchor, constant: -8),
            creditStack.leadingAnchor.constraint(equalTo: creditContainer.leadingAnchor, constant: 12),
            creditStack.trailingAnchor.constraint(equalTo: creditContainer.trailingAnchor, constant: -12),

            creditContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            creditContainer.trailingAnchor.constraint(equalTo: fab.leadingAnchor, constant: -12),
            creditContainer.centerYAnchor.constraint(equalTo: fab.centerYAnchor),
        ])

        view.bringSubviewToFront(fab)

        // Ensure games directory exists
        try? FileManager.default.createDirectory(atPath: Self.gamesDirectory,
                                                  withIntermediateDirectories: true)
        scanApps()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func appDidBecomeActive() {
        scanApps()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = springboardCollectionView.bounds.width
        guard width > 0, width != lastLayoutWidth else { return }
        lastLayoutWidth = width

        let columns: CGFloat = 4
        let iconSize = SpringboardCell.iconSize
        let cellWidth = (width + iconSize) / (columns + 1)
        let horizontalInset = (cellWidth - iconSize) / 2

        guard let layout = springboardCollectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        layout.itemSize = CGSize(width: cellWidth, height: 96)
        layout.sectionInset = UIEdgeInsets(top: 20, left: horizontalInset,
                                            bottom: 96, right: horizontalInset)
    }

    // ============================================================
    // MARK: - Author Contact Actions (from 3-dots Menu)
    // ============================================================

    @objc private func openFacebookProfile() {
        if let url = URL(string: "https://www.facebook.com/blacklotus00x") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    @objc private func openZaloProfile() {
        UIPasteboard.general.string = "0339143765"
        if let url = URL(string: "https://zaloapp.com/qr/p/1o430u4aipvi?src=qr") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    // ============================================================
    // MARK: - Import JAR from Files
    // ============================================================

    @objc private func addAppTapped() {
        var contentTypes: [UTType] = []
        if let customJar = UTType("com.sun.java-archive") {
            contentTypes.append(customJar)
        }
        if let jarType = UTType(filenameExtension: "jar") {
            contentTypes.append(jarType)
        }
        if let zipType = UTType(filenameExtension: "zip") {
            contentTypes.append(zipType)
        }
        contentTypes.append(contentsOf: [.archive, .data, .item])

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        let fm = FileManager.default
        let gamesDir = Self.gamesDirectory
        try? fm.createDirectory(atPath: gamesDir, withIntermediateDirectories: true, attributes: nil)
        var imported = 0

        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ext == "jar" || ext == "zip" else { continue }

            let destURL = URL(fileURLWithPath: gamesDir)
                .appendingPathComponent(url.lastPathComponent)

            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { readURL in
                do {
                    try? fm.removeItem(at: destURL)
                    try fm.copyItem(at: readURL, to: destURL)
                    imported += 1
                } catch {
                    if let data = try? Data(contentsOf: readURL) {
                        do {
                            try data.write(to: destURL, options: .atomic)
                            imported += 1
                        } catch {
                            print("[Swift] Write failed for \(url.lastPathComponent): \(error)")
                        }
                    } else {
                        print("[Swift] Failed to import \(url.lastPathComponent): \(error)")
                    }
                }
            }
        }

        if imported > 0 {
            scanApps()
        }
    }

    // ============================================================
    // MARK: - App scanning (Documents/games/)
    // ============================================================

    struct AppInfo {
        let name: String
        let path: String
        let fileName: String
        let version: String?
        let vendor: String?
        let icon: UIImage
    }
    private var apps: [AppInfo] = []

    static func loadInstalledApps() -> [AppInfo] {
        let gamesDir = gamesDirectory
        var jarPaths: [(name: String, path: String)] = []
        if let files = try? FileManager.default.contentsOfDirectory(atPath: gamesDir) {
            for file in files where file.hasSuffix(".jar") {
                jarPaths.append((name: String(file.dropLast(4)), path: gamesDir + "/" + file))
            }
        }
        var unsorted = jarPaths.map { jar -> (String, String, String, String?, String?, UIImage?) in
            let meta = JARMetadata.read(from: jar.path)
            let jarIcon = meta?.readIcon(from: jar.path)
            let fileName = URL(fileURLWithPath: jar.path).lastPathComponent
            let appName = meta?.midletName ?? jar.name
            return (appName, jar.path, fileName, meta?.version, meta?.vendor, jarIcon)
        }
        unsorted.sort { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
        return unsorted.enumerated().map { (index, t) in
            AppInfo(name: t.0, path: t.1, fileName: t.2,
                    version: t.3, vendor: t.4,
                    icon: Self.springboardIcon(t.5, name: t.0, index: index))
        }
    }

    private func scanApps() {
        let gamesDir = Self.gamesDirectory

        DispatchQueue.global(qos: .userInitiated).async {
            var jarPaths: [(name: String, path: String)] = []

            if let files = try? FileManager.default.contentsOfDirectory(atPath: gamesDir) {
                for file in files where file.hasSuffix(".jar") {
                    jarPaths.append((name: String(file.dropLast(4)), path: gamesDir + "/" + file))
                }
            }

            var unsorted = jarPaths.map { jar -> (String, String, String, String?, String?, UIImage?) in
                let meta = JARMetadata.read(from: jar.path)
                let jarIcon = meta?.readIcon(from: jar.path)
                let fileName = URL(fileURLWithPath: jar.path).lastPathComponent
                let appName = meta?.midletName ?? jar.name
                return (appName, jar.path, fileName, meta?.version, meta?.vendor, jarIcon)
            }
            unsorted.sort { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }

            let scannedApps = unsorted.enumerated().map { (index, t) in
                AppInfo(name: t.0, path: t.1, fileName: t.2,
                        version: t.3, vendor: t.4,
                        icon: Self.springboardIcon(t.5, name: t.0, index: index))
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.apps = scannedApps
                self.springboardCollectionView.reloadData()
                self.emptyStateLabel.isHidden = !scannedApps.isEmpty
                print("[Swift] Found \(scannedApps.count) MIDlet JARs in \(gamesDir)")
            }
        }
    }

    // ============================================================
    // MARK: - Icon generation
    // ============================================================

    private static let iconSize: CGFloat = SpringboardCell.iconSize

    private static let placeholderGradients: [(UIColor, UIColor)] = [
        (UIColor(red: 0.20, green: 0.40, blue: 0.90, alpha: 1),
         UIColor(red: 0.35, green: 0.60, blue: 1.00, alpha: 1)),
        (UIColor(red: 0.00, green: 0.68, blue: 0.63, alpha: 1),
         UIColor(red: 0.20, green: 0.85, blue: 0.60, alpha: 1)),
        (UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1),
         UIColor(red: 1.00, green: 0.75, blue: 0.28, alpha: 1)),
        (UIColor(red: 0.88, green: 0.22, blue: 0.28, alpha: 1),
         UIColor(red: 1.00, green: 0.42, blue: 0.48, alpha: 1)),
        (UIColor(red: 0.58, green: 0.28, blue: 0.85, alpha: 1),
         UIColor(red: 0.72, green: 0.48, blue: 1.00, alpha: 1)),
        (UIColor(red: 0.22, green: 0.30, blue: 0.80, alpha: 1),
         UIColor(red: 0.38, green: 0.48, blue: 0.95, alpha: 1)),
        (UIColor(red: 0.90, green: 0.28, blue: 0.52, alpha: 1),
         UIColor(red: 1.00, green: 0.48, blue: 0.68, alpha: 1)),
        (UIColor(red: 0.15, green: 0.65, blue: 0.42, alpha: 1),
         UIColor(red: 0.28, green: 0.82, blue: 0.55, alpha: 1)),
    ]

    private static func springboardIcon(_ jarIcon: UIImage?, name: String, index: Int) -> UIImage {
        let size = CGSize(width: iconSize, height: iconSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)

            UIBezierPath(roundedRect: rect, cornerRadius: SpringboardCell.iconCornerRadius).addClip()

            if let img = jarIcon {
                UIColor(white: 0.22, alpha: 1).setFill()
                UIBezierPath(rect: rect).fill()
                img.draw(in: rect)
            } else if let decadeLogo = UIImage(named: "DecadeLogo") {
                decadeLogo.draw(in: rect)
            } else {
                let pair = placeholderGradients[index % placeholderGradients.count]
                let cgCtx = ctx.cgContext
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let gradient = CGGradient(colorsSpace: colorSpace,
                                              colors: [pair.0.cgColor, pair.1.cgColor] as CFArray,
                                              locations: [0, 1]) {
                    cgCtx.drawLinearGradient(gradient, start: .zero,
                                             end: CGPoint(x: iconSize, y: iconSize), options: [])
                }
                let letter = String(name.prefix(1)).uppercased()
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                    .font: UIFont.systemFont(ofSize: iconSize * 0.42, weight: .semibold)
                ]
                let strSize = (letter as NSString).size(withAttributes: attrs)
                (letter as NSString).draw(
                    at: CGPoint(x: (iconSize - strSize.width) / 2,
                                y: (iconSize - strSize.height) / 2),
                    withAttributes: attrs)
            }

            let borderPath = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                           cornerRadius: SpringboardCell.iconCornerRadius - 0.5)
            UIColor(white: 1.0, alpha: 0.12).setStroke()
            borderPath.lineWidth = 1
            borderPath.stroke()
        }
    }

    // ============================================================
    // MARK: - UICollectionView
    // ============================================================

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        apps.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SpringboardCell.reuseID, for: indexPath) as! SpringboardCell
        let app = apps[indexPath.item]
        cell.configure(name: app.name, icon: app.icon)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        return makeContextMenu(for: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first else { return nil }
        return makeContextMenu(for: indexPath)
    }

    private func makeContextMenu(for indexPath: IndexPath) -> UIContextMenuConfiguration {
        let app = apps[indexPath.item]
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            // Authentic Decade Android Context Menu matching Screenshot 5:
            // 1. Bắt đầu
            // 2. Thêm lối tắt
            // 3. Đổi tên
            // 4. Thiết lập -> opens DecadeConfigViewController (Screenshot 6)
            // 5. Cài đặt lại
            // 6. Xóa
            let startAction = UIAction(title: "Bắt đầu", image: UIImage(systemName: "play.fill")) { _ in
                self?.launchGame(app: app)
            }
            let shortcutAction = UIAction(title: "Thêm lối tắt", image: UIImage(systemName: "arrow.up.forward.app")) { _ in
                self?.launchGame(app: app)
            }
            let renameAction = UIAction(title: "Đổi tên", image: UIImage(systemName: "pencil")) { _ in
                self?.promptRenameApp(app: app)
            }
            let configAction = UIAction(title: "Thiết lập", image: UIImage(systemName: "gearshape.fill")) { _ in
                self?.openConfig(for: app)
            }
            let resetAction = UIAction(title: "Cài đặt lại", image: UIImage(systemName: "arrow.counterclockwise")) { _ in
                self?.confirmClearGameData(for: app)
            }
            let deleteAction = UIAction(title: "Xóa", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self?.confirmDeleteApp(at: indexPath)
            }

            return UIMenu(children: [startAction, shortcutAction, renameAction, configAction, resetAction, deleteAction])
        })
    }

    private func openConfig(for app: AppInfo) {
        let configVC = DecadeConfigViewController(app: app) { [weak self] w, h, fps in
            self?.launchGame(app: app, overrideW: w, overrideH: h, overrideFps: fps)
        }
        let nav = UINavigationController(rootViewController: configVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func promptRenameApp(app: AppInfo) {
        let alert = UIAlertController(title: "Đổi tên", message: "Nhập tên mới cho ứng dụng", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = app.name
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu", style: .default) { [weak self] _ in
            guard let self, let newName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), !newName.isEmpty else { return }
            UserDefaults.standard.set(newName, forKey: "name_\(Self.gameId(for: app))")
            self.scanApps()
        })
        present(alert, animated: true)
    }

    @objc private func showTopMoreMenuActionSheet(_ sender: UIBarButtonItem) {
        let alert = UIAlertController(title: "KamenRider Decade", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "🌐 FB: Bùi Hoàng Minh", style: .default) { [weak self] _ in self?.openFacebookProfile() })
        alert.addAction(UIAlertAction(title: "💬 Zalo: Bùi Hoàng Minh", style: .default) { [weak self] _ in self?.openZaloProfile() })
        alert.addAction(UIAlertAction(title: "🌐 Quản lý Proxy", style: .default) { [weak self] _ in self?.showProxyDialog() })
        alert.addAction(UIAlertAction(title: "🔄 Thay IP Phiên Bản", style: .default) { [weak self] _ in self?.showChangeIpDialog() })
        alert.addAction(UIAlertAction(title: "⚙ Thiết lập", style: .default) { [weak self] _ in self?.showGlobalSettings() })
        alert.addAction(UIAlertAction(title: "👤 Hồ sơ", style: .default) { [weak self] _ in self?.showProfilesDialog() })
        alert.addAction(UIAlertAction(title: "❓ Trợ giúp", style: .default) { [weak self] _ in self?.showHelpDialog() })
        alert.addAction(UIAlertAction(title: "📝 Lưu log", style: .default) { [weak self] _ in self?.saveLogs() })
        alert.addAction(UIAlertAction(title: "✕ Thoát", style: .destructive) { _ in exit(0) })
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = sender
        }
        present(alert, animated: true)
    }

    private func showProxyDialog() {
        let proxyVC = DecadeProxyViewController()
        let nav = UINavigationController(rootViewController: proxyVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func showChangeIpDialog() {
        let changeIpVC = DecadeChangeIpViewController()
        let nav = UINavigationController(rootViewController: changeIpVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func showGlobalSettings() {
        if let firstApp = apps.first {
            openConfig(for: firstApp)
        } else {
            let dummyApp = AppInfo(name: "KamenRider Decade", path: "", fileName: "", version: "1.0.0", vendor: "Havan", icon: UIImage())
            openConfig(for: dummyApp)
        }
    }

    private func showProfilesDialog() {
        let profilesVC = DecadeProfilesViewController()
        let nav = UINavigationController(rootViewController: profilesVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func showHelpDialog() {
        let helpVC = DecadeHelpViewController()
        let nav = UINavigationController(rootViewController: helpVC)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func saveLogs() {
        let logText = "KamenRider Decade J2ME iOS System Log\nTimestamp: \(Date())\nActive Games: \(apps.map { $0.name }.joined(separator: ", "))\n"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("decade_system.log")
        try? logText.write(to: tempURL, atomically: true, encoding: .utf8)
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        present(activityVC, animated: true)
    }

    func launchGame(app: AppInfo, overrideW: Int? = nil, overrideH: Int? = nil, overrideFps: Int? = nil) {
        let render3dScale = Self.is3DSupersampling(for: app) ? 3 : 1
        let res = (overrideW != nil && overrideH != nil) ? (overrideW!, overrideH!) : Self.resolution(for: app)
        let fps = overrideFps ?? Self.fpsLimit(for: app)
        let gameVC = GameViewController(jarPath: app.path, appName: app.name, appIcon: app.icon,
                                         canvasWidth: res.0, canvasHeight: res.1,
                                         render3dScale: render3dScale, fpsLimit: fps)
        gameVC.modalPresentationStyle = .fullScreen
        present(gameVC, animated: true)
    }

    // MARK: - Per-game settings

    private static func gameId(for app: AppInfo) -> String {
        let jarName = URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent
        return jarName.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
    }

    static func is3DSupersampling(for app: AppInfo) -> Bool {
        UserDefaults.standard.object(forKey: "ss3d_\(gameId(for: app))") as? Bool ?? true
    }

    static func set3DSupersampling(_ enabled: Bool, for app: AppInfo) {
        UserDefaults.standard.set(enabled, forKey: "ss3d_\(gameId(for: app))")
    }

    private static let resolutionOptions: [(label: String, w: Int, h: Int)] = [
        // Common J2ME resolutions (portrait / square only)
        ("101×80",   101,  80),
        ("128×128",  128, 128),
        ("128×160",  128, 160),
        ("132×176",  132, 176),
        ("160×128",  160, 128),
        ("176×208",  176, 208),
        ("176×220",  176, 220),
        ("208×208",  208, 208),
        ("220×220",  220, 220),
        ("240×266",  240, 266),
        ("240×320",  240, 320),
        ("240×400",  240, 400),
        ("320×480",  320, 480),
        ("352×416",  352, 416),
        ("360×640",  360, 640),
        ("480×800",  480, 800),
    ]

    static func resolution(for app: AppInfo) -> (w: Int, h: Int) {
        let gid = gameId(for: app)
        let w = UserDefaults.standard.object(forKey: "resW_\(gid)") as? Int ?? 240
        let h = UserDefaults.standard.object(forKey: "resH_\(gid)") as? Int ?? 320
        return (w, h)
    }

    private static func setResolution(w: Int, h: Int, for app: AppInfo) {
        let gid = gameId(for: app)
        UserDefaults.standard.set(w, forKey: "resW_\(gid)")
        UserDefaults.standard.set(h, forKey: "resH_\(gid)")
    }

    private static let fpsLimitOptions: [(label: String, value: Int)] = [
        ("Unlimited", 0),
        ("15 FPS",   15),
        ("20 FPS",   20),
        ("30 FPS",   30),
        ("60 FPS",   60),
    ]

    static func fpsLimit(for app: AppInfo) -> Int {
        UserDefaults.standard.object(forKey: "fpsLimit_\(gameId(for: app))") as? Int ?? 60
    }

    private static func setFpsLimit(_ fps: Int, for app: AppInfo) {
        UserDefaults.standard.set(fps, forKey: "fpsLimit_\(gameId(for: app))")
    }

    private static var documentsDirectory: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.path
    }

    private func confirmClearGameData(for app: AppInfo) {
        let alert = UIAlertController(title: "Clear Game Data",
                                       message: "Delete all save data for \(app.name)?",
                                       preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
            let gid = Self.gameId(for: app)
            try? FileManager.default.removeItem(atPath: Self.documentsDirectory + "/Games Data/" + gid)
        })
        present(alert, animated: true)
    }

    private func confirmDeleteApp(at indexPath: IndexPath) {
        let app = apps[indexPath.item]
        let alert = UIAlertController(title: "Delete Game",
                                       message: "Delete \(app.name) and all its save data?",
                                       preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }
            let gid = Self.gameId(for: app)
            try? FileManager.default.removeItem(atPath: Self.documentsDirectory + "/Games Data/" + gid)
            try? FileManager.default.removeItem(atPath: app.path)
            self.springboardCollectionView.performBatchUpdates {
                self.apps.remove(at: indexPath.item)
                self.springboardCollectionView.deleteItems(at: [indexPath])
            }
            self.emptyStateLabel.isHidden = !self.apps.isEmpty
        })
        present(alert, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < apps.count else { return }
        let app = apps[indexPath.item]

        let render3dScale = Self.is3DSupersampling(for: app) ? 3 : 1
        let res = Self.resolution(for: app)
        let fps = Self.fpsLimit(for: app)
        let gameVC = GameViewController(jarPath: app.path, appName: app.name, appIcon: app.icon,
                                         canvasWidth: res.w, canvasHeight: res.h,
                                         render3dScale: render3dScale, fpsLimit: fps)
        gameVC.modalPresentationStyle = .fullScreen
        gameVC.modalTransitionStyle = .coverVertical
        present(gameVC, animated: true)
    }
}


