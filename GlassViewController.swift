import UIKit

@MainActor
final class GlassViewController: UIViewController {
    private let glass = GenerativeGlassView()
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        label.text = """
            Never gonna give you up
            Never gonna let you down
            Never gonna run around and desert you
            """
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .label
        label.font = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2).withSymbolicTraits(.traitBold)!, size: 0)
        label.adjustsFontForContentSizeCategory = true

        // Shortcuts puts the text below the glass and uses an opaque page background.
        view.addSubview(label)
        view.addSubview(glass)
        updateBackground()
        glass.setCausticEnabled(true)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: GlassViewController, _) in
            self.updateBackground()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = min(view.bounds.width - 64, 440)
        let frame = CGRect(x: (view.bounds.width - width) / 2, y: view.safeAreaInsets.top + 90, width: width, height: 240)
        glass.frame = frame
        label.frame = frame.insetBy(dx: 24, dy: 24)
    }

    private func updateBackground() {
        let color = traitCollection.userInterfaceStyle == .dark ? UIColor.black : .systemGray6
        view.backgroundColor = color
        // For a uniform background, its sampled color is the background color itself.
        glass.configuration.shadowColor = color.resolvedColor(with: traitCollection).cgColor
    }
}
