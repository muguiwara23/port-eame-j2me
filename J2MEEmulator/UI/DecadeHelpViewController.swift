//
//  DecadeHelpViewController.swift
//  J2MEEmulator
//
//  Authentic Decade "Trợ giúp" screen with full user guide.
//

import UIKit

class DecadeHelpViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)
        title = "Ayuda"

        setupNavBar()
        setupUI()
    }

    private func setupNavBar() {
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1.0)
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 18, weight: .bold)]
        navigationController?.navigationBar.standardAppearance = navBarAppearance
        navigationController?.navigationBar.scrollEdgeAppearance = navBarAppearance
        navigationController?.navigationBar.tintColor = .white

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cerrar", style: .plain, target: self, action: #selector(closeTapped))
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func setupUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 16, bottom: 24, right: 16)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        stack.addArrangedSubview(makeSectionCard(
            title: "1. Agregar juegos Java (.jar)",
            content: "Toca el botón (+) de la pantalla principal y elige un archivo .jar en la app Archivos. También puedes copiar los .jar a la carpeta de Port/eame Java en Archivos."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "2. Varias pestañas",
            content: "• Toca [+] en la barra del juego para abrir otra pestaña.\n• Toca [++] para abrir varias a la vez.\n• Toca los números [1], [2], [3]... para cambiar de pestaña."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "3. Acomodar el teclado en pantalla",
            content: "• Toca [⋮] arriba a la derecha mientras juegas.\n• 'Mover teclas': arrastra cualquier tecla adonde quieras.\n• 'Cambiar tamaño de teclas': pellizca con dos dedos para agrandarlas o achicarlas.\n• Al terminar, toca [⋮] → 'Terminar edición' para guardar."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "4. Ocultar teclas",
            content: "• Toca [⋮] → 'Ocultar teclas'.\n• Marca o desmarca las teclas que quieres ver (1-9, 0, *, #, L, R, C, flechas, F...).\n• Toca 'OK' para aplicar."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "5. Escribir texto",
            content: "• Para escribir en el juego, toca el teclado [⌨] de la barra de arriba.\n• Al terminar, toca '✓ Listo' para enviarlo al juego."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "6. Proxies y servidor",
            content: "• En la pantalla principal, toca [⋮].\n• 'Proxies': conecta los juegos por un proxy HTTP o SOCKS5.\n• 'Cambiar servidor': cambia la IP del servidor de un juego."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "7. Ventana flotante y ventana pequeña",
            content: "• Ventana flotante (PiP): muestra el juego encima de otras apps.\n• Ventana pequeña: dentro de la app; pellizca o arrastra la esquina para cambiar su tamaño."
        ))

        stack.addArrangedSubview(makeSectionCard(
            title: "8. Créditos",
            content: "• Port/eame Java, basado en J2ME-Decade (iOS) de Vạn Trần.\n• Emulador J2ME para iOS de Alexander Goremykin, API de J2ME-Loader, miniJVM de digitalgust.\n• Licencia Apache 2.0."
        ))
    }

    private func makeSectionCard(title: String, content: String) -> UIView {
        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 12
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.05
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        card.layer.shadowRadius = 4

        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 8
        s.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        s.isLayoutMarginsRelativeArrangement = true
        s.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(s)

        let t = UILabel()
        t.text = title
        t.font = .systemFont(ofSize: 16, weight: .bold)
        t.textColor = UIColor(red: 0.12, green: 0.41, blue: 0.82, alpha: 1.0)
        s.addArrangedSubview(t)

        let c = UILabel()
        c.text = content
        c.font = .systemFont(ofSize: 14, weight: .regular)
        c.textColor = UIColor(red: 0.20, green: 0.20, blue: 0.25, alpha: 1.0)
        c.numberOfLines = 0
        s.addArrangedSubview(c)

        NSLayoutConstraint.activate([
            s.topAnchor.constraint(equalTo: card.topAnchor),
            s.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            s.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            s.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        return card
    }
}
