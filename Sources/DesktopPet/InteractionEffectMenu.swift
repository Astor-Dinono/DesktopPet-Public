import AppKit

/// Embedded controls receive their own actions, leaving the surrounding menu open.
@MainActor
final class InteractionEffectMenuView: NSView {
    private let selection: () -> InteractionEffectSelection
    private let onToggle: (InteractionEffect) -> Void
    private var choices: [NSButton] = []

    init(selection: @escaping () -> InteractionEffectSelection,
         onToggle: @escaping (InteractionEffect) -> Void) {
        self.selection = selection
        self.onToggle = onToggle
        super.init(frame: NSRect(x: 0, y: 0, width: 154, height: 124))
        autoresizingMask = [.width]
        setAccessibilityElement(false)
        for effect in InteractionEffect.allCases {
            let button = NSButton(checkboxWithTitle: effect.title, target: self, action: #selector(toggle(_:)))
            button.tag = effect.rawValue
            button.frame = NSRect(x: 12, y: 92 - effect.rawValue * 28, width: 130, height: 28)
            button.autoresizingMask = [.width]
            addSubview(button)
            choices.append(button)
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func refresh() {
        let current = selection()
        for button in choices {
            guard let effect = InteractionEffect(rawValue: button.tag) else { continue }
            button.state = current.contains(effect) ? .on : .off
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { refresh() }
    }

    @objc private func toggle(_ sender: NSButton) {
        guard let effect = InteractionEffect(rawValue: sender.tag) else { return }
        onToggle(effect)
        refresh()
    }
}
