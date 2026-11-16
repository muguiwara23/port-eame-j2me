//
//  DecadeHideButtonsDialog.swift
//  J2MEEmulator
//
//  Authentic 1:1 Decade "Ẩn nút" dialog matching Android Decade Screenshot 1.
//  In Android Decade, checked = HIDDEN (Ẩn), unchecked = VISIBLE (Hiện).
//

import UIKit

class DecadeHideButtonsDialog: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let gameId: String
    private let onApply: (Set<String>) -> Void

    // All keys matching Android Decade VirtualKeyboard order
    private let allKeys: [String] = [
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
        "*", "#",
        "L", "R", "F",
        "↑", "↓", "←", "→",
        "↖", "↗", "↙", "↘"
    ]

    // Set of keys that are currently HIDDEN (checked in dialog)
    private var hiddenKeys: Set<String>

    private let dialogView = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(gameId: String, currentHiddenKeys: Set<String>, onApply: @escaping (Set<String>) -> Void) {
        self.gameId = gameId
        self.hiddenKeys = currentHiddenKeys
        self.onApply = onApply
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor(white: 0, alpha: 0.5)

        // Dialog card matching Android Material AlertDialog
        dialogView.backgroundColor = .white
        dialogView.layer.cornerRadius = 12
        dialogView.clipsToBounds = true
        dialogView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dialogView)

        let titleLabel = UILabel()
        titleLabel.text = "Ẩn nút"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .black
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        dialogView.addSubview(titleLabel)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .white
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        dialogView.addSubview(tableView)

        // Bottom OK button in red (#E53935) matching Android screenshot 1
        let okButton = UIButton(type: .system)
        okButton.setTitle("OK", for: .normal)
        okButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        okButton.setTitleColor(UIColor(red: 0.90, green: 0.22, blue: 0.21, alpha: 1.0), for: .normal)
        okButton.addTarget(self, action: #selector(okTapped), for: .touchUpInside)
        okButton.translatesAutoresizingMaskIntoConstraints = false
        dialogView.addSubview(okButton)

        let screenH = UIScreen.main.bounds.height

        NSLayoutConstraint.activate([
            dialogView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dialogView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            dialogView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.82),
            dialogView.heightAnchor.constraint(equalToConstant: min(540, screenH * 0.72)),

            titleLabel.topAnchor.constraint(equalTo: dialogView.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: dialogView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: dialogView.trailingAnchor, constant: -20),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: dialogView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: dialogView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: okButton.topAnchor, constant: -8),

            okButton.trailingAnchor.constraint(equalTo: dialogView.trailingAnchor, constant: -24),
            okButton.bottomAnchor.constraint(equalTo: dialogView.bottomAnchor, constant: -14),
            okButton.heightAnchor.constraint(equalToConstant: 36),
            okButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ])
    }

    @objc private func okTapped() {
        // Save to UserDefaults
        let key = "decade_hidden_keys_\(gameId)"
        UserDefaults.standard.set(Array(hiddenKeys), forKey: key)

        onApply(hiddenKeys)
        dismiss(animated: true)
    }

    // ============================================================
    // MARK: - TableView DataSource & Delegate
    // ============================================================

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return allKeys.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 44
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "KeyCell")
            ?? UITableViewCell(style: .default, reuseIdentifier: "KeyCell")

        cell.backgroundColor = .white
        cell.selectionStyle = .none

        let key = allKeys[indexPath.row]
        // In Android Decade: Checked means HIDDEN (Ẩn nút)
        let isHidden = hiddenKeys.contains(key)

        let iconName = isHidden ? "checkmark.square.fill" : "square"
        let iconColor = isHidden ? UIColor(red: 0.90, green: 0.22, blue: 0.21, alpha: 1.0) : UIColor.systemGray3
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        cell.imageView?.image = UIImage(systemName: iconName, withConfiguration: config)
        cell.imageView?.tintColor = iconColor

        cell.textLabel?.text = "    " + key
        cell.textLabel?.font = .systemFont(ofSize: 18, weight: .regular)
        cell.textLabel?.textColor = .black

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let key = allKeys[indexPath.row]
        if hiddenKeys.contains(key) {
            hiddenKeys.remove(key)
        } else {
            hiddenKeys.insert(key)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}
