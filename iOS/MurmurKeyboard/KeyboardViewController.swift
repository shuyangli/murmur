import AVFoundation
import UIKit

/// The Step 0 harness, not the shipping keyboard. There is no QWERTY here on
/// purpose: the brief gates the whole design on one question, and a layout
/// would only add ways for the answer to be wrong.
final class KeyboardViewController: UIInputViewController {
    private static let keyboardHeight: CGFloat = 320

    private let spike = AudioSpike()
    private let readout = UITextView()
    private let holdButton = UIButton(type: .system)
    private let globeButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        // Precondition 2 from the brief. Documented only as suppressing the
        // system dictation button; whether it also gates the audio session is
        // exactly what this spike measures.
        hasDictationKey = true

        buildInterface()
        showPreconditions()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showPreconditions()
    }

    private func buildInterface() {
        view.backgroundColor = .secondarySystemBackground

        let height = view.heightAnchor.constraint(equalToConstant: Self.keyboardHeight)
        height.priority = .required - 1
        height.isActive = true

        readout.isEditable = false
        readout.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        readout.backgroundColor = .systemBackground
        readout.layer.cornerRadius = 8
        readout.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        var hold = UIButton.Configuration.filled()
        hold.title = "Hold to record"
        hold.baseBackgroundColor = .systemBlue
        holdButton.configuration = hold
        holdButton.addTarget(self, action: #selector(pressDown), for: [.touchDown])
        holdButton.addTarget(
            self,
            action: #selector(pressUp),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )

        var globe = UIButton.Configuration.gray()
        globe.image = UIImage(systemName: "globe")
        globeButton.configuration = globe
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let controls = UIStackView(arrangedSubviews: [globeButton, holdButton])
        controls.spacing = 8
        globeButton.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [readout, controls])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            controls.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    @objc private func pressDown() {
        spike.start()
        readout.text = "Recording…"
    }

    @objc private func pressUp() {
        render(spike.stop())
    }

    /// The two things that have to be true before the audio result means
    /// anything. Full Access off, or the microphone never granted in the
    /// container app, would produce a failure that says nothing about `!rec`.
    private func showPreconditions() {
        let microphone: String
        switch AVAudioApplication.shared.recordPermission {
        case .granted: microphone = "granted"
        case .denied: microphone = "denied"
        case .undetermined: microphone = "undetermined — open the Murmur app first"
        @unknown default: microphone = "unknown"
        }

        readout.text = """
        Step 0 — can a keyboard extension record?

        Full Access   \(hasFullAccess ? "on" : "OFF — enable it in Settings")
        Microphone    \(microphone)

        Hold the button and speak.
        """
    }

    private func render(_ report: SpikeReport) {
        readout.text = report.summary(host: "keyboard extension", fullAccess: hasFullAccess)
    }
}
