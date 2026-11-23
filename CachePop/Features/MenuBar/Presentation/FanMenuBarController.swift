import AppKit
import Observation
import QuartzCore
import SwiftUI

/// A native status button lets Core Animation turn the fan without redrawing SwiftUI every frame.
@MainActor
final class FanMenuBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private var item: NSStatusItem?
    private var visibility: NSKeyValueObservation?
    private let content = FanStatusContent()
    private let popover = NSPopover()
    private var accessibilityObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateReading() }
        }
        trackReadings()
    }

    isolated deinit {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        visibility = nil
        popover.delegate = nil
        popover.close()
        popover.contentViewController = nil
        content.rotor.update(rpm: 0, reduceMotion: true)
        if let item {
            NSStatusBar.system.removeStatusItem(item)
            model.monitor.end(SystemMonitorViewModel.menuBarClient)
        }
    }

    private func trackReadings() {
        withObservationTracking {
            popover.appearance = model.settings.appearance.nsAppearance
            let shown = model.settings.menuBarShowsFanSpeed
            _ = model.monitor.snapshot?.fans
            if shown, item == nil { insert() }
            if !shown, item != nil { remove() }
            updateReading()
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.trackReadings() }
        }
    }

    private func insert() {
        let item = NSStatusBar.system.statusItem(withLength: MenuBarItemLayout.nativeLength(for: MenuBarItemLayout.width))
        self.item = item
        item.autosaveName = "CachePopFanSpeed"
        item.behavior = .removalAllowed
        item.isVisible = true
        if let button = item.button {
            button.title = ""
            button.image = nil
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.addSubview(content)
            content.frame = button.bounds
            content.autoresizingMask = [.width, .height]
            button.setAccessibilityIdentifier("fanMenuBarItem")
            button.setAccessibilityChildren([])
        }
        visibility = item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard change.newValue == false, let self else { return }
            Task { @MainActor in self.model.settings.menuBarShowsFanSpeed = false }
        }
        model.monitor.begin(SystemMonitorViewModel.menuBarClient)
    }

    private func remove() {
        popover.performClose(nil)
        visibility = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        content.rotor.update(rpm: 0, reduceMotion: true)
        model.monitor.end(SystemMonitorViewModel.menuBarClient)
    }

    private func updateReading() {
        guard let item, let button = item.button else { return }
        let rpm = model.monitor.snapshot?.fans.map(\.rpm).max() ?? 0
        let value = SystemMonitorViewModel.menuBarFanSpeed(model.monitor.snapshot) ?? "—"
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if content.reading.stringValue != value {
            content.reading.stringValue = value
            content.needsLayout = true
        }
        let tint = NSColor.white
        content.reading.textColor = tint
        content.rotor.setTint(tint)
        content.rotor.update(rpm: rpm, reduceMotion: reduceMotion)
        button.setAccessibilityLabel("Fan speed, \(value)")
        button.setAccessibilityValue(rpm > 0 ? "Spinning" : "Stopped")
        button.toolTip = "Fan speed: \(value). Click for fan controls."
    }

    @objc private func togglePanel() {
        guard let button = item?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.fanControl.refreshStatus()
            popover.contentViewController = NSHostingController(rootView:
                FanMenuContent(model: model, close: { [weak self] in self?.popover.performClose(nil) })
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            button.highlight(true)
            updateReading()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        item?.button?.highlight(false)
        updateReading()
    }
}

@MainActor
final class FanStatusContent: NSView {
    let rotor = FanRotorImageView(frame: .zero)
    let reading = NSTextField(labelWithString: "—")

    override init(frame: NSRect) {
        super.init(frame: frame)
        reading.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        reading.textColor = .labelColor
        reading.usesSingleLineMode = true
        reading.setAccessibilityElement(false)
        rotor.setAccessibilityElement(false)
        addSubview(rotor)
        addSubview(reading)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        rotor.frame = NSRect(x: 6, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let width = max(bounds.width - 30, 1)
        let size = MenuBarItemLayout.fittedFontSize(reading.stringValue, preferred: 13, width: max(width - 4, 1))
        if reading.font?.pointSize != size { reading.font = .monospacedDigitSystemFont(ofSize: size, weight: .regular) }
        let height = reading.intrinsicContentSize.height
        reading.frame = NSRect(x: 26, y: (bounds.height - height) / 2,
                               width: max(bounds.width - 30, 0), height: height)
    }
}

enum FanRotation {
    static func duration(rpm: Double, reduceMotion: Bool) -> Double? {
        guard rpm.isFinite, rpm > 0, !reduceMotion else { return nil }
        // A readable visual indication, rather than a literal thousands of turns per minute.
        return min(max(3_600 / rpm, 0.6), 3)
    }
}

@MainActor
final class FanRotorImageView: NSView {
    private var desiredDuration: Double?
    private var activeDuration: Double?
    // AppKit owns a layer-backed NSView's geometry. Animate an independent child
    // layer so SwiftUI layout and NSImageView updates cannot reset the rotation.
    private let rotor = CALayer()
    private let symbolMask = CALayer()
    private var tint: NSColor = .labelColor
    private var imageSize: CGFloat = 0
    private var imageScale: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        rotor.mask = symbolMask
        symbolMask.contentsGravity = .resizeAspect
        layer?.addSublayer(rotor)
        layoutRotor()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTint(_ color: NSColor) {
        tint = color
        updateTint()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTint()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layoutRotor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layoutRotor()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutRotor()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        layoutRotor()
    }

    override func layout() {
        super.layout()
        layoutRotor()
    }

    private func updateTint() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance { rotor.backgroundColor = tint.cgColor }
        CATransaction.commit()
    }

    private func layoutRotor() {
        let side = min(bounds.width, bounds.height)
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Set bounds and position independently: `frame` is undefined for a rotated layer.
        rotor.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        rotor.position = CGPoint(x: bounds.midX, y: bounds.midY)
        symbolMask.bounds = rotor.bounds
        symbolMask.position = CGPoint(x: side / 2, y: side / 2)
        symbolMask.contentsScale = scale
        if side > 0, side != imageSize || scale != imageScale {
            imageSize = side
            imageScale = scale
            symbolMask.contents = Self.symbolImage(side: side, scale: scale)
        }
        CATransaction.commit()
        updateTint()
        synchronizeAnimation()
    }

    private static func symbolImage(side: CGFloat, scale: CGFloat) -> CGImage? {
        guard let image = NSImage(systemSymbolName: "fanblades", accessibilityDescription: nil),
              let context = CGContext(data: nil, width: Int(ceil(side * scale)), height: Int(ceil(side * scale)),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        // Keep the symbol's proportions while centering it on a square rotation surface.
        let ratio = side / max(image.size.width, image.size.height)
        let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                              width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    func update(rpm: Double, reduceMotion: Bool) {
        desiredDuration = FanRotation.duration(rpm: rpm, reduceMotion: reduceMotion)
        synchronizeAnimation()
    }

    private func synchronizeAnimation() {
        let next = window != nil && bounds.width > 0 && bounds.height > 0 ? desiredDuration : nil
        guard next != activeDuration || (next != nil && rotor.animation(forKey: "fanRotation") == nil) else { return }
        let angle = (rotor.presentation() ?? rotor).value(forKeyPath: "transform.rotation.z") as? Double ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rotor.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        rotor.removeAnimation(forKey: "fanRotation")
        activeDuration = next
        if let next {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = angle
            animation.toValue = angle + .pi * 2
            animation.duration = next
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            rotor.add(animation, forKey: "fanRotation")
        }
        CATransaction.commit()
    }
}

struct FanRotor: NSViewRepresentable {
    let rpm: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> FanRotorImageView { FanRotorImageView(frame: .zero) }
    static func dismantleNSView(_ view: FanRotorImageView, coordinator: ()) {
        view.update(rpm: 0, reduceMotion: true)
    }

    func updateNSView(_ view: FanRotorImageView, context: Context) {
        view.setTint(NSColor(Metric.fans.solid))
        view.update(rpm: rpm, reduceMotion: reduceMotion)
    }
}
