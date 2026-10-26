import UIKit

final class KeyboardView: UIView {
    enum Mic {
        case idle, recording, busy
    }

    let statusLabel = UILabel()
    let micButton = UIButton(type: .system)
    let globeButton = KeyboardView.key(systemImage: "globe")
    let spaceButton = KeyboardView.key(title: "space")
    let deleteButton = KeyboardView.key(systemImage: "delete.left")
    let returnButton = KeyboardView.key(systemImage: "return")
    private let micStack = UIStackView()
    private let fullAccessLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        micButton.configuration = config
        micButton.accessibilityLabel = "Dictate"

        fullAccessLabel.text = "To dictate, turn on Full Access: Settings → General → Keyboard → Keyboards → Speak → Allow Full Access."
        fullAccessLabel.font = .preferredFont(forTextStyle: .callout)
        fullAccessLabel.numberOfLines = 0
        fullAccessLabel.textAlignment = .center
        fullAccessLabel.isHidden = true

        micStack.axis = .vertical
        micStack.alignment = .center
        micStack.spacing = 10
        micStack.addArrangedSubview(statusLabel)
        micStack.addArrangedSubview(micButton)
        micStack.addArrangedSubview(fullAccessLabel)

        let keys = UIStackView(arrangedSubviews: [globeButton, spaceButton, deleteButton, returnButton])
        keys.spacing = 6
        keys.distribution = .fill

        let column = UIStackView(arrangedSubviews: [micStack, keys])
        column.axis = .vertical
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            micButton.widthAnchor.constraint(equalToConstant: 140),
            micButton.heightAnchor.constraint(equalToConstant: 72),
            statusLabel.widthAnchor.constraint(equalTo: column.widthAnchor),
            fullAccessLabel.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -24),
            keys.heightAnchor.constraint(equalToConstant: 44),
            globeButton.widthAnchor.constraint(equalToConstant: 52),
            deleteButton.widthAnchor.constraint(equalToConstant: 64),
            returnButton.widthAnchor.constraint(equalToConstant: 76),
            heightAnchor.constraint(equalToConstant: 236),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(fullAccess: Bool) {
        fullAccessLabel.isHidden = fullAccess
        micButton.isHidden = !fullAccess
        statusLabel.isHidden = !fullAccess
    }

    func setMic(_ mic: Mic) {
        var config = micButton.configuration ?? .filled()
        switch mic {
        case .idle:
            config.image = UIImage(systemName: "mic.fill")
            config.baseBackgroundColor = .tintColor
            config.showsActivityIndicator = false
        case .recording:
            config.image = UIImage(systemName: "stop.fill")
            config.baseBackgroundColor = .systemRed
            config.showsActivityIndicator = false
        case .busy:
            config.image = nil
            config.baseBackgroundColor = .systemGray
            config.showsActivityIndicator = true
        }
        micButton.configuration = config
        micButton.isEnabled = mic != .busy
    }

    private static func key(title: String? = nil, systemImage: String? = nil) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .secondarySystemBackground
        config.baseForegroundColor = .label
        config.cornerStyle = .medium
        config.title = title
        config.image = systemImage.map { UIImage(systemName: $0) } ?? nil
        return UIButton(configuration: config)
    }
}
