import UIKit

/**
 * The opening the website plays, played natively over the web view while it loads.
 *
 * Follows the site's own sequence (components/miscellaneous/Loading): the aurora, the logo fading
 * in over black at 1.2 s, and the scene gone at 1.4 s. The logo then holds until the page says it
 * has drawn (`dismiss()`), so the reader never watches the site assemble itself; the site skips its
 * own aurora inside the app.
 */
final class IntroOverlayView: UIView {
    private static let logoDelay: TimeInterval = 1.2
    private static let logoFade: TimeInterval = 0.2
    private static let sceneDuration: TimeInterval = 1.4
    /// The site hides its logo at 1.8 s; nothing goes before that, however early the page is ready
    private static let minimumDuration: TimeInterval = 1.8

    private let aurora = AuroraIntroView()
    private let logoScreen = UIView()
    /// When the aurora's first frame reached the screen; the site's timings count from there
    private var startedAt: CFTimeInterval?
    private var dismissing = false

    init() {
        super.init(frame: .zero)
        backgroundColor = .black
        isUserInteractionEnabled = true

        if let aurora {
            aurora.frame = bounds
            aurora.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            aurora.onFirstFrame = { [weak self] in self?.play() }
            addSubview(aurora)
        }

        setUpLogoScreen()
        // Black until the aurora's first frame, which the launch screen is too; without Metal there is
        // no aurora to wait for, so the logo stands in for the whole of it
        logoScreen.alpha = aurora == nil ? 1 : 0
        addSubview(logoScreen)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The black screen with the logo the aurora hands over to, as the site's does
    private func setUpLogoScreen() {
        logoScreen.backgroundColor = .black
        logoScreen.frame = bounds
        logoScreen.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let logo = UIImageView(image: UIImage(named: "Logo"))
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        logoScreen.addSubview(logo)

        let credits = UILabel()
        credits.text = "Built by Hugo Lageneste and Adrien Mauduit"
        credits.font = .systemFont(ofSize: 10)
        credits.textColor = .systemGray2
        credits.translatesAutoresizingMaskIntoConstraints = false
        logoScreen.addSubview(credits)

        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: logoScreen.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: logoScreen.centerYAnchor),
            logo.heightAnchor.constraint(equalToConstant: 51),
            logo.widthAnchor.constraint(equalToConstant: 51),
            credits.centerXAnchor.constraint(equalTo: logoScreen.centerXAnchor),
            credits.bottomAnchor.constraint(equalTo: logoScreen.bottomAnchor, constant: -95)
        ])

        // Dimmed at night like the scene, as the site dims its logo
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 19 || hour < 7 { logo.alpha = 0.5 }
    }

    /// Runs the site's sequence from the aurora's first frame, straight out of the black launch screen
    private func play() {
        startedAt = CACurrentMediaTime()

        UIView.animate(withDuration: Self.logoFade, delay: Self.logoDelay, options: [.curveEaseInOut]) {
            self.logoScreen.alpha = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sceneDuration) { [weak self] in
            // Covered by the logo by now; nothing left to draw it for
            self?.aurora?.isPaused = true
            self?.aurora?.removeFromSuperview()
        }
    }

    /// Fades the intro out to the page underneath, once it has played for as long as the site's does
    func dismiss() {
        guard !dismissing else { return }
        dismissing = true

        // A page ready before the aurora has even started does not wait for it
        let remaining = startedAt.map { Self.minimumDuration - (CACurrentMediaTime() - $0) } ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, remaining)) {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut]) {
                self.alpha = 0
            } completion: { _ in
                self.aurora?.isPaused = true
                self.removeFromSuperview()
            }
        }
    }
}
