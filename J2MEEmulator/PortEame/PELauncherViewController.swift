//
//  PELauncherViewController.swift
//  Port/eame Java
//
//  The launcher: the player's games in a grid. Tap to play; hold for the
//  game's options (screen size, shortcut, saves, delete). "+" adds games from
//  the Files app, from a link, or from a repository. Every change to the
//  screen happens on the main thread (the old launcher refreshed itself from
//  a background thread and crashed).
//

import UIKit
import UniformTypeIdentifiers

final class PELauncherViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate,
                                      UIDocumentPickerDelegate {

    /// The launcher, for links opened from outside (shortcuts, "Open in").
    static weak var shared: PELauncherViewController?
    /// A link that arrived before the launcher was on screen.
    static var pendingURL: URL?

    private var games: [PEGame] = []
    private var collectionView: UICollectionView!
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let addButton = UIButton(type: .system)
    private let emptyLabel = UILabel()
    private var stateObserver: NSObjectProtocol?

    private static let background = UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)
    private static let accent = UIColor(red: 0.20, green: 0.78, blue: 0.45, alpha: 1)

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        Self.shared = self
        view.backgroundColor = Self.background
        setUpHeader()
        setUpGrid()
        setUpEmptyLabel()
        // The game screen says when a game stops; it may say so from any thread.
        stateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DecadeGameRunningStateChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
        reload()
    }

    deinit {
        if let stateObserver = stateObserver { NotificationCenter.default.removeObserver(stateObserver) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        reload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let url = Self.pendingURL {
            Self.pendingURL = nil
            handle(url)
        }
    }

    // MARK: - Layout

    private func setUpHeader() {
        titleLabel.text = "Port/eame Java"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .white
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = UIColor(white: 0.62, alpha: 1)

        var config = UIButton.Configuration.filled()
        config.title = "Agregar"
        config.image = UIImage(systemName: "plus")
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.baseBackgroundColor = Self.accent.withAlphaComponent(0.18)
        config.baseForegroundColor = Self.accent
        addButton.configuration = config
        addButton.showsMenuAsPrimaryAction = true
        rebuildAddMenu()

        for item in [titleLabel, subtitleLabel, addButton] as [UIView] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: addButton.leadingAnchor, constant: -12),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            addButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor, constant: 8),
            addButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
        ])
    }

    private func setUpGrid() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 22
        layout.sectionInset = UIEdgeInsets(top: 20, left: 20, bottom: 40, right: 20)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(PEGameCell.self, forCellWithReuseIdentifier: PEGameCell.reuse)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setUpEmptyLabel() {
        emptyLabel.text = "Aún no hay juegos.\nToca «Agregar» para traer tus archivos .jar\ndesde Archivos, un enlace o tu repositorio."
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = UIColor(white: 0.55, alpha: 1)
        emptyLabel.font = .systemFont(ofSize: 16)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let width = collectionView.bounds.width - layout.sectionInset.left - layout.sectionInset.right
        let columns: CGFloat = width > 600 ? 6 : 4
        let item = floor((width - layout.minimumInteritemSpacing * (columns - 1)) / columns)
        let size = CGSize(width: item, height: item + 34)
        if layout.itemSize != size {
            layout.itemSize = size
            layout.invalidateLayout()
        }
    }

    // MARK: - Games

    private var runningGame: GameViewController? {
        guard let vc = GameViewController.currentActiveGameVC, jvm_bridge_is_slot_running(0) != 0 else { return nil }
        return vc
    }

    func reload() {
        games = PELibrary.scan()
        let running = runningGame.map { _ in 1 } ?? 0
        subtitleLabel.text = games.count == 1 ? "1 juego" : "\(games.count) juegos"
        if running > 0 { subtitleLabel.text = (subtitleLabel.text ?? "") + " · 1 abierto" }
        emptyLabel.isHidden = !games.isEmpty
        collectionView.reloadData()
        rebuildAddMenu()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { games.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PEGameCell.reuse, for: indexPath) as! PEGameCell
        let game = games[indexPath.item]
        cell.configure(name: game.name, icon: PEIcons.tile(for: game, size: 120),
                       running: runningGame?.jarPath == game.path)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        play(games[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        let game = games[indexPath.item]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.menu(for: game)
        }
    }

    private func menu(for game: PEGame) -> UIMenu {
        let current = PELibrary.resolution(for: game)
        let sizes: [(String, (Int, Int)?)] = [
            ("Automático", nil), ("Vertical 240×320", (240, 320)), ("Horizontal 320×240", (320, 240)),
            ("176×208", (176, 208)), ("128×160", (128, 160)), ("Vertical 360×640", (360, 640)),
            ("Horizontal 640×360", (640, 360)),
        ]
        let custom = UserDefaults.standard.integer(forKey: "resW_\(game.id)") > 0
        let sizeActions = sizes.map { entry -> UIAction in
            let (title, size) = entry
            var chosen = !custom
            if let size = size { chosen = custom && size.0 == current.0 && size.1 == current.1 }
            return UIAction(title: title, state: chosen ? .on : .off) { [weak self] _ in
                PELibrary.setResolution(size, for: game)
                self?.reload()
            }
        }
        let screen = UIMenu(title: "Pantalla del juego: \(current.0)×\(current.1)", image: UIImage(systemName: "rectangle.portrait"),
                            children: sizeActions)
        var items: [UIMenuElement] = [
            UIAction(title: "Jugar", image: UIImage(systemName: "play.fill")) { [weak self] _ in self?.play(game) },
        ]
        if runningGame?.jarPath == game.path {
            items.append(UIAction(title: "Cerrar el juego", image: UIImage(systemName: "stop.fill"), attributes: .destructive) { [weak self] _ in
                self?.closeRunningGame { self?.reload() }
            })
        }
        items.append(screen)
        items.append(UIAction(title: "Crear acceso directo", image: UIImage(systemName: "square.and.arrow.down.on.square")) { [weak self] _ in
            self?.makeShortcut(for: game)
        })
        items.append(UIAction(title: "Borrar partidas", image: UIImage(systemName: "arrow.counterclockwise")) { [weak self] _ in
            self?.confirm("Borrar partidas", "¿Borrar todas las partidas de \(game.name)?", action: "Borrar") {
                PELibrary.deleteSaves(game)
            }
        })
        items.append(UIAction(title: "Eliminar juego", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.confirm("Eliminar juego", "¿Eliminar \(game.name) y sus partidas?", action: "Eliminar") {
                PELibrary.delete(game)
                self?.reload()
            }
        })
        return UIMenu(title: game.name, children: items)
    }

    // MARK: - Playing

    func play(_ game: PEGame) {
        if let running = runningGame {
            if running.jarPath == game.path {
                running.modalPresentationStyle = .fullScreen
                present(running, animated: true)
                return
            }
            confirm("Otro juego abierto", "Para abrir \(game.name) se cierra el juego que está abierto.", action: "Abrir") { [weak self] in
                self?.closeRunningGame { self?.launch(game) }
            }
            return
        }
        launch(game)
    }

    private func launch(_ game: PEGame) {
        let size = PELibrary.resolution(for: game)
        let supersample = UserDefaults.standard.object(forKey: "ss3d_\(game.id)") as? Bool ?? true
        print("Port/eame: play \(game.fileName) at \(size.0)x\(size.1)")
        let vc = GameViewController(jarPath: game.path, appName: game.name,
                                    appIcon: PEIcons.tile(for: game, size: 120),
                                    canvasWidth: size.0, canvasHeight: size.1,
                                    render3dScale: supersample ? 3 : 1, fpsLimit: PELibrary.fpsLimit(for: game))
        GameViewController.currentActiveGameVC = vc
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    /// Stops the game left open in the background, then goes on.
    private func closeRunningGame(then next: @escaping () -> Void) {
        guard GameViewController.currentActiveGameVC != nil else { return next() }
        GameViewController.currentActiveGameVC = nil
        jvm_bridge_request_stop_all()
        j2me_input_post_key(0, 0)
        DispatchQueue.global(qos: .userInitiated).async {
            jvm_bridge_destroy_all()
            DispatchQueue.main.async { next() }
        }
    }

    // MARK: - Adding games

    private func rebuildAddMenu() {
        var items: [UIMenuElement] = [
            UIAction(title: "Desde Archivos", image: UIImage(systemName: "folder")) { [weak self] _ in self?.pickFiles() },
            UIAction(title: "Desde un enlace", image: UIImage(systemName: "link")) { [weak self] _ in self?.askForLink() },
            UIAction(title: "Pegar repositorio", image: UIImage(systemName: "tray.full")) { [weak self] _ in self?.askForRepository() },
        ]
        let saved = PERepository.saved
        if !saved.isEmpty {
            let open = saved.map { link in
                UIAction(title: PERepoPickerViewController.shortName(link), image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                    self?.openRepository(link)
                }
            }
            let forget = saved.map { link in
                UIAction(title: PERepoPickerViewController.shortName(link), attributes: .destructive) { [weak self] _ in
                    PERepository.forget(link)
                    self?.rebuildAddMenu()
                }
            }
            items.append(UIMenu(title: "Mis repositorios", image: UIImage(systemName: "books.vertical"), children: [
                UIMenu(title: "", options: .displayInline, children: open),
                UIMenu(title: "Quitar de la lista", image: UIImage(systemName: "minus.circle"), children: forget),
            ]))
        }
        items.append(UIAction(title: "Ayuda", image: UIImage(systemName: "questionmark.circle")) { [weak self] _ in self?.showHelp() })
        addButton.menu = UIMenu(title: "", children: items)
    }

    private func pickFiles() {
        var types: [UTType] = []
        if let jar = UTType("com.sun.java-archive") { types.append(jar) }
        if let jar = UTType(filenameExtension: "jar") { types.append(jar) }
        types.append(.data)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let added = urls.compactMap { PELibrary.importFile(at: $0) }
        reload()
        if added.count < urls.count {
            alert("Algunos no se agregaron", "Solo se agregan archivos .jar.")
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}

    private func askForLink() {
        let ask = UIAlertController(title: "Desde un enlace", message: "Pega la dirección de un archivo .jar.", preferredStyle: .alert)
        ask.addTextField { field in
            field.placeholder = "https://…/juego.jar"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            if let text = UIPasteboard.general.string, text.lowercased().contains(".jar") { field.text = text }
        }
        ask.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        ask.addAction(UIAlertAction(title: "Descargar", style: .default) { [weak self, weak ask] _ in
            guard let self = self, let text = ask?.textFields?.first?.text, let url = PERepository.url(from: text) else { return }
            let progress = self.showProgress("Descargando…")
            PELibrary.download(url) { result in
                progress.dismiss(animated: true) {
                    switch result {
                    case .success: self.reload()
                    case .failure(let error): self.alert("No se pudo descargar", error.localizedDescription)
                    }
                }
            }
        })
        present(ask, animated: true)
    }

    private func askForRepository() {
        let ask = UIAlertController(title: "Pegar repositorio",
                                    message: "Pega el enlace de tu repositorio: un item de archive.org, una carpeta o los releases de GitHub, una página con archivos .jar o una lista JSON.",
                                    preferredStyle: .alert)
        ask.addTextField { field in
            field.placeholder = "https://…"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            if let text = UIPasteboard.general.string, text.lowercased().hasPrefix("http") { field.text = text }
        }
        ask.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        ask.addAction(UIAlertAction(title: "Ver juegos", style: .default) { [weak self, weak ask] _ in
            guard let text = ask?.textFields?.first?.text else { return }
            self?.openRepository(text)
        })
        present(ask, animated: true)
    }

    private func openRepository(_ link: String) {
        guard let url = PERepository.url(from: link) else { return alert("Enlace no válido", link) }
        let progress = showProgress("Leyendo el repositorio…")
        PERepository.list(url) { [weak self] result in
            progress.dismiss(animated: true) {
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    self.alert("No se pudo leer el repositorio", error.localizedDescription)
                case .success(let listing):
                    if listing.entries.isEmpty {
                        return self.alert("Sin juegos", "No encontré archivos .jar en ese enlace.")
                    }
                    PERepository.remember(link.trimmingCharacters(in: .whitespacesAndNewlines))
                    self.rebuildAddMenu()
                    let installed = Set(PELibrary.scan().map { $0.fileName })
                    let picker = PERepoPickerViewController(listing: listing, installed: installed) { [weak self] in
                        self?.reload()
                    }
                    let nav = UINavigationController(rootViewController: picker)
                    nav.overrideUserInterfaceStyle = .dark
                    self.present(nav, animated: true)
                }
            }
        }
    }

    // MARK: - Links from outside (shortcuts, "Open in")

    static func open(_ url: URL) {
        if let launcher = shared, launcher.view.window != nil {
            launcher.handle(url)
        } else {
            pendingURL = url
        }
    }

    private func handle(_ url: URL) {
        if url.isFileURL {
            if PELibrary.importFile(at: url) != nil { reload() } else { alert("No es un juego", "Solo se agregan archivos .jar.") }
            return
        }
        guard url.scheme == PEIcons.scheme,
              let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "juego" })?.value
        else { return }
        guard let game = PELibrary.game(fileName: item) else {
            return alert("Juego no encontrado", "\(item) ya no está en la carpeta de juegos.")
        }
        let start: () -> Void = { [weak self] in self?.play(game) }
        if let shown = presentedViewController {
            if let running = shown as? GameViewController, running.jarPath == game.path { return }
            shown.dismiss(animated: false, completion: start)
        } else {
            start()
        }
    }

    // MARK: - Shortcut with icon

    private func makeShortcut(for game: PEGame) {
        let link = PEIcons.link(for: game)
        UIPasteboard.general.string = link
        let icon = PEIcons.tile(for: game, size: 512)
        UIImageWriteToSavedPhotosAlbum(icon, nil, nil, nil)
        alert("Acceso directo de \(game.name)",
              "Ya copié el enlace y guardé el ícono en Fotos.\n\n1. Abre la app Atajos y crea un atajo nuevo.\n2. Agrega la acción «Abrir URL» y pega el enlace.\n3. Toca el nombre del atajo → «Agregar a pantalla de inicio».\n4. Toca el ícono → «Elegir foto» y elige el ícono del juego.\n\nEnlace: \(link)")
    }

    // MARK: - Help and small helpers

    private func showHelp() {
        alert("Ayuda",
              "• Agregar → Desde Archivos: elige tus .jar en la app Archivos. También puedes copiarlos a la carpeta «games» de Port/eame Java.\n• Desde un enlace: pega la dirección de un .jar.\n• Pegar repositorio: pega el enlace de tu repositorio (archive.org, GitHub, una página o una lista JSON) y agrega todos o algunos.\n• Mantén presionado un juego para cambiar su pantalla, crear un acceso directo o borrarlo.\n• El registro de la app está en la carpeta de Port/eame Java: port-eame-log.txt.")
    }

    private func alert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func confirm(_ title: String, _ message: String, action: String, then: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: action, style: .destructive) { _ in then() })
        present(alert, animated: true)
    }

    private func showProgress(_ text: String) -> UIViewController {
        let alert = UIAlertController(title: nil, message: text + "\n\n", preferredStyle: .alert)
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        alert.view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -20),
        ])
        present(alert, animated: true)
        return alert
    }
}

// MARK: - The grid's cell

final class PEGameCell: UICollectionViewCell {
    static let reuse = "PEGameCell"
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let dot = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.contentMode = .scaleAspectFill
        iconView.layer.cornerRadius = 18
        iconView.layer.cornerCurve = .continuous
        iconView.clipsToBounds = true
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = UIColor(white: 0.9, alpha: 1)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        dot.backgroundColor = UIColor(red: 0.20, green: 0.78, blue: 0.45, alpha: 1)
        dot.layer.cornerRadius = 5
        for item in [iconView, nameLabel, dot] as [UIView] {
            item.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(item)
        }
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor),
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: -4),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 4),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
            dot.topAnchor.constraint(equalTo: iconView.topAnchor, constant: 6),
            dot.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(name: String, icon: UIImage, running: Bool) {
        nameLabel.text = name
        iconView.image = icon
        dot.isHidden = !running
    }
}
