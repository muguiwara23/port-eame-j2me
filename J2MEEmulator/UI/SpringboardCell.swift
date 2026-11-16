//
//  SpringboardCell.swift
//  J2MEEmulator
//

import UIKit

class SpringboardCell: UICollectionViewCell {

    static let reuseID = "SpringboardCell"
    static let iconSize: CGFloat = 62
    static let iconCornerRadius: CGFloat = 14

    let iconView = UIImageView()
    let nameLabel = UILabel()

    // Clean dark label text for light background
    private static let labelAttributes: [NSAttributedString.Key: Any] = {
        return [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0),
        ]
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.clipsToBounds = false

        // Icon — corners are pre-rendered into the image, no layer masking needed
        iconView.contentMode = .scaleAspectFill
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        // App name label — shadow via NSShadow in attributed text (no layer shadow)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 5),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: -2),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 2),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.image = nil
        nameLabel.attributedText = nil
    }

    // Springboard-style press animation
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.iconView.alpha = self.isHighlighted ? 0.6 : 1.0
                self.iconView.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
            }
        }
    }

    func configure(name: String, icon: UIImage) {
        iconView.image = icon
        nameLabel.attributedText = NSAttributedString(string: name,
                                                      attributes: Self.labelAttributes)
    }
}
