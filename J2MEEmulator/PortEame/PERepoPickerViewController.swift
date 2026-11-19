//
//  PERepoPickerViewController.swift
//  Port/eame Java
//
//  The games a repository holds, to add all of them or the ones ticked. The
//  ones already in the games folder are marked. Downloads go one at a time,
//  with the count in the title.
//

import UIKit

final class PERepoPickerViewController: UITableViewController {
    private let listing: PERepoListing
    private var installed: Set<String>
    private var chosen = Set<Int>()
    private let onChange: () -> Void
    private var downloading = false

    static func shortName(_ link: String) -> String {
        guard let url = PERepository.url(from: link) else { return link }
        let path = url.pathComponents.filter { $0 != "/" }.prefix(3).joined(separator: "/")
        return (url.host ?? link) + (path.isEmpty ? "" : "/" + path)
    }

    init(listing: PERepoListing, installed: Set<String>, onChange: @escaping () -> Void) {
        self.listing = listing
        self.installed = installed
        self.onChange = onChange
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = listing.title
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "game")
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cerrar", style: .plain, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Agregar todos", style: .done, target: self, action: #selector(addAll))
        navigationController?.isToolbarHidden = false
        updateToolbar()
    }

    private func fileName(_ entry: PERepoEntry) -> String { PELibrary.fileName(for: entry.url) }

    private func updateToolbar() {
        let add = UIBarButtonItem(title: chosen.isEmpty ? "Toca los juegos que quieras" : "Agregar \(chosen.count)",
                                  style: .done, target: self, action: #selector(addChosen))
        add.isEnabled = !chosen.isEmpty && !downloading
        navigationItem.rightBarButtonItem?.isEnabled = !downloading
        toolbarItems = [UIBarButtonItem(systemItem: .flexibleSpace), add, UIBarButtonItem(systemItem: .flexibleSpace)]
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { listing.entries.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "\(listing.entries.count) juegos"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "game", for: indexPath)
        let entry = listing.entries[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = entry.name
        var detail: [String] = []
        if let size = entry.size { detail.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        if installed.contains(fileName(entry)) { detail.append("ya está agregado") }
        content.secondaryText = detail.isEmpty ? nil : detail.joined(separator: " · ")
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = chosen.contains(indexPath.row) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !downloading else { return }
        if chosen.contains(indexPath.row) { chosen.remove(indexPath.row) } else { chosen.insert(indexPath.row) }
        tableView.reloadRows(at: [indexPath], with: .none)
        updateToolbar()
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func addAll() { download(Array(listing.entries.indices)) }

    @objc private func addChosen() { download(chosen.sorted()) }

    private func download(_ rows: [Int]) {
        guard !rows.isEmpty, !downloading else { return }
        downloading = true
        updateToolbar()
        var failed: [String] = []
        var index = 0
        func next() {
            guard index < rows.count else {
                downloading = false
                title = listing.title
                chosen.removeAll()
                tableView.reloadData()
                updateToolbar()
                onChange()
                let added = rows.count - failed.count
                let message = failed.isEmpty ? "Se agregaron \(added) juegos." :
                    "Se agregaron \(added) juegos. No se pudieron bajar: \(failed.joined(separator: ", "))"
                let alert = UIAlertController(title: "Listo", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
            let entry = listing.entries[rows[index]]
            title = "Descargando \(index + 1) de \(rows.count)…"
            PELibrary.download(entry.url, name: fileName(entry)) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let name): self.installed.insert(name)
                case .failure: failed.append(entry.name)
                }
                index += 1
                next()
            }
        }
        next()
    }
}
