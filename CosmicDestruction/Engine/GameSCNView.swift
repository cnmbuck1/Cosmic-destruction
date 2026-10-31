import SceneKit
import UIKit

/// Receives raw aiming touches from the 3D view.
@MainActor
protocol AimInputDelegate: AnyObject {
    func aimBegan(at point: CGPoint)
    func aimMoved(to point: CGPoint)
    func aimEnded(at point: CGPoint)
    func aimCancelled()
}

/// SCNView that forwards single-finger drags as aiming input. SwiftUI HUD
/// buttons sit above this view, so their touches never reach it.
final class GameSCNView: SCNView {
    weak var aimDelegate: AimInputDelegate?
    private weak var trackedTouch: UITouch?

    override init(frame: CGRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackedTouch == nil, let touch = touches.first else { return }
        trackedTouch = touch
        aimDelegate?.aimBegan(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        aimDelegate?.aimMoved(to: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        trackedTouch = nil
        aimDelegate?.aimEnded(at: touch.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        trackedTouch = nil
        aimDelegate?.aimCancelled()
    }
}
