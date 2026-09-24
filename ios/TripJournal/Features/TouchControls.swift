import SwiftUI
import UIKit

struct TouchBall: UIViewRepresentable {
    @Environment(TouchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .headline) private var diameter = 22.0
    var active: Bool
    func makeUIView(context: Context) -> SpringDotView {
        let view = SpringDotView()
        view.seedAnimation(store.animation?.id)
        return view
    }
    func updateUIView(_ view: SpringDotView, context: Context) {
        view.reduceMotion = reduceMotion
        view.diameter = diameter
        view.dotColor = UIColor(TripStyle.green).resolvedColor(with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light))
        view.send = { kind in
            guard store.paired else {
                if store.profile == nil && !store.revoked { store.showingWelcome = true }
                else { store.showingSettings = true }
                return
            }
            guard store.canSend else {
                if store.archive.pending != nil { store.showingSettings = true }
                return
            }
            Task { await store.send(kind) }
        }
        view.receive(store.animation)
        if !active { view.cancelInteraction() }
    }
    static func dismantleUIView(_ view: SpringDotView, coordinator: ()) { view.cancelInteraction() }
}

/// Integrates a damped 2D spring at display cadence, retaining velocity on re-grab.
final class SpringDotView: UIView {
    var send: ((TouchKind) -> Void)?
    var reduceMotion = false
    var diameter: CGFloat = 22 { didSet { setNeedsLayout() } }
    var dotColor = UIColor(TripStyle.green) { didSet { setNeedsLayout() } }
    private let ball = CALayer()
    private let heart = UIImageView(image: UIImage(systemName: "heart.fill"))
    private var displacement = CGPoint.zero
    private var velocity = CGPoint.zero
    private var origin = CGPoint.zero
    private var start = CGPoint.zero
    private var last = CGPoint.zero
    private var lastTime: TimeInterval = 0
    private var link: CADisplayLink?
    private var hold: Timer?
    private var touching = false
    private var moved = false
    private var sentHeart = false
    private var ready = false
    private var pulse: CGFloat = 0
    private var receivedID: String?
    private var heartHide: DispatchWorkItem?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = "弹一弹"
        accessibilityIdentifier = "touch.ball"
        accessibilityTraits = .button
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: "送爱心", target: self, selector: #selector(accessibleHeart))]
        layer.addSublayer(ball)
        heart.tintColor = UIColor(red: 0.93, green: 0.08, blue: 0.18, alpha: 1)
        heart.layer.shadowColor = UIColor(red: 0.85, green: 0.08, blue: 0.16, alpha: 1).cgColor
        heart.layer.shadowOpacity = 0.22; heart.layer.shadowRadius = 4; heart.layer.shadowOffset = CGSize(width: 0, height: 2)
        heart.alpha = 0; heart.isUserInteractionEnabled = false; heart.isAccessibilityElement = false
        addSubview(heart)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancelInteraction() } }
    override func layoutSubviews() { super.layoutSubviews(); render() }
    override func accessibilityActivate() -> Bool { trigger(.poke); return true }
    @objc private func accessibleHeart() -> Bool { trigger(.heart); return true }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touching = true; moved = false; sentHeart = false; ready = false
        start = touch.location(in: window); last = start; origin = displacement; lastTime = touch.timestamp
        hold?.invalidate()
        hold = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.touching, !self.moved else { return }
                self.sentHeart = true; self.trigger(.heart)
            }
        }
        pulse = -0.10; startDisplay()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touching else { return }
        let point = touch.location(in: window)
        let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
        let distance = hypot(delta.x, delta.y)
        if distance > 9 { moved = true; hold?.invalidate(); hold = nil }
        let damping = 1 / (1 + distance / 160)
        displacement = CGPoint(x: origin.x + delta.x * damping, y: origin.y + delta.y * damping)
        let dt = max(0.008, touch.timestamp - lastTime)
        velocity = CGPoint(x: max(-700, min(700, (point.x - last.x) / dt * 0.3)), y: max(-700, min(700, (point.y - last.y) / dt * 0.3)))
        last = point; lastTime = touch.timestamp
        let nowReady = TouchBallActivation.isArmed(delta: delta, origin: start, bounds: window?.bounds ?? bounds)
        if nowReady && !ready && !sentHeart { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4) }
        ready = nowReady; render()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let poke = ready && !sentHeart
        touching = false; hold?.invalidate(); hold = nil
        if poke { trigger(.poke) }
        startDisplay()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        hold?.invalidate(); hold = nil; touching = false; ready = false; startDisplay()
    }
    func seedAnimation(_ id: String?) { receivedID = id }
    func cancelInteraction() {
        hold?.invalidate(); hold = nil; touching = false; ready = false
        link?.invalidate(); link = nil; heartHide?.cancel(); heartHide = nil
        displacement = .zero; velocity = .zero; pulse = 0; heart.alpha = 0; render()
    }
    func receive(_ event: TouchEvent?) {
        guard let event, event.id != receivedID else { return }
        receivedID = event.id
        animate(event.kind)
    }
    private func trigger(_ kind: TouchKind) { animate(kind); send?(kind) }
    private func animate(_ kind: TouchKind) {
        UIImpactFeedbackGenerator(style: kind == .poke ? .light : .soft).impactOccurred(intensity: 0.65)
        pulse = kind == .heart ? 0.25 : 0.12
        if kind == .heart {
            heartHide?.cancel(); heart.layer.removeAllAnimations(); heart.alpha = 1
            let bloom = CAKeyframeAnimation(keyPath: "transform.scale")
            bloom.values = reduceMotion ? [0.95, 1.03, 1] : [0.35, 1.22, 0.94, 1.06, 1]
            bloom.duration = 0.6; bloom.calculationMode = .cubic
            heart.layer.add(bloom, forKey: "bloom")
            let hide = DispatchWorkItem { [weak self] in UIView.animate(withDuration: 0.25) { self?.heart.alpha = 0 } }
            heartHide = hide; DispatchQueue.main.asyncAfter(deadline: .now() + 1.05, execute: hide)
        } else if displacement == .zero { velocity = CGPoint(x: -110, y: 150) }
        startDisplay()
    }
    private func startDisplay() {
        guard link == nil else { return }
        let display = CADisplayLink(target: self, selector: #selector(step(_:)))
        display.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        display.add(to: .main, forMode: .common); link = display
    }
    @objc private func step(_ display: CADisplayLink) {
        let dt = min(1.0 / 30, display.targetTimestamp - display.timestamp)
        if !touching {
            // Substeps keep the spring stable if a frame takes longer than expected.
            for _ in 0..<2 {
                let h = dt / 2
                velocity.x += (-330 * displacement.x - 19 * velocity.x) * h
                velocity.y += (-330 * displacement.y - 19 * velocity.y) * h
                displacement.x += velocity.x * h; displacement.y += velocity.y * h
            }
        }
        pulse *= exp(-dt * 8)
        render()
        if !touching && hypot(displacement.x, displacement.y) < 0.15 && hypot(velocity.x, velocity.y) < 1 && abs(pulse) < 0.002 {
            displacement = .zero; velocity = .zero; pulse = 0; render()
            link?.invalidate(); link = nil
        } else if touching && abs(pulse) < 0.002 { link?.invalidate(); link = nil }
    }
    private func render() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let d = hypot(displacement.x, displacement.y)
        let angle = atan2(displacement.y, displacement.x)
        let stretch = reduceMotion ? 0 : min(0.30, d / 260 + hypot(velocity.x, velocity.y) / 5000)
        let factor: CGFloat = reduceMotion ? 0.12 : 1
        ball.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        ball.cornerRadius = diameter / 2
        ball.backgroundColor = dotColor.cgColor
        ball.position = CGPoint(x: bounds.midX + displacement.x * factor, y: bounds.midY + displacement.y * factor)
        let size = 1 + pulse * (reduceMotion ? 0.2 : 1)
        ball.setAffineTransform(CGAffineTransform(rotationAngle: angle).scaledBy(x: (1 + stretch) * size, y: (1 - stretch * 0.65) * size).rotated(by: -angle))
        heart.bounds = CGRect(x: 0, y: 0, width: 34, height: 31)
        heart.center = CGPoint(x: ball.position.x, y: ball.position.y - 5)
        CATransaction.commit()
    }
}

/// Near a screen edge, the same gesture remains possible in the limited finger travel.
enum TouchBallActivation {
    static func isArmed(delta: CGPoint, origin: CGPoint, bounds: CGRect) -> Bool {
        let distance = hypot(delta.x, delta.y)
        guard distance > 0 else { return false }
        let x = delta.x / distance, y = delta.y / distance
        let horizontal = x > 0 ? (bounds.maxX - origin.x) / x : x < 0 ? (bounds.minX - origin.x) / x : CGFloat.infinity
        let vertical = y > 0 ? (bounds.maxY - origin.y) / y : y < 0 ? (bounds.minY - origin.y) / y : CGFloat.infinity
        let threshold = min(64, max(18, min(horizontal, vertical) * 0.65))
        return distance >= threshold
    }
}
