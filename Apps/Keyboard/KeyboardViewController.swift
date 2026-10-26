import UIKit

final class KeyboardViewController: UIInputViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let globe = UIButton(type: .system)
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globe.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(globe)
        NSLayoutConstraint.activate([
            globe.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            globe.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            globe.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            view.heightAnchor.constraint(equalToConstant: 216),
        ])
    }
}
