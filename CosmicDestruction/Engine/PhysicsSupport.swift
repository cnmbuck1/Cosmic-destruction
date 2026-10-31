import SceneKit
import simd

/// Collision category masks. Keeping them explicit avoids needless contact
/// callbacks (e.g. effects never collide with anything).
enum PhysicsCategory {
    static let orb = 1 << 0
    static let block = 1 << 1
    static let platform = 1 << 2
}

extension SCNVector3 {
    var asSIMD: SIMD3<Float> { SIMD3<Float>(Float(x), Float(y), Float(z)) }

    init(simd v: SIMD3<Float>) {
        self.init(x: v.x, y: v.y, z: v.z)
    }
}

extension Float {
    var degreesToRadians: Float { self * .pi / 180 }
    var radiansToDegrees: Float { self * 180 / .pi }

    func clamped(_ lower: Float, _ upper: Float) -> Float { Swift.min(Swift.max(self, lower), upper) }
}

/// A contact recorded on SceneKit's physics thread, consumed on the main thread.
struct RecordedContact {
    let nodeA: SCNNode
    let nodeB: SCNNode
    let point: SIMD3<Float>
    let impulse: Float
}

/// Collects physics contacts from SceneKit's render/physics thread into a
/// lock-protected buffer. The game loop drains it on the main thread, so all
/// gameplay logic stays single-threaded.
final class ContactCollector: NSObject, SCNPhysicsContactDelegate {
    private let lock = NSLock()
    private var buffer: [RecordedContact] = []
    private let capacity = 96

    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        // collisionImpulse is sometimes 0 at the moment contact begins, so
        // fall back to an estimate from relative speed and the lighter mass.
        var impulse = Float(contact.collisionImpulse)
        if let a = contact.nodeA.physicsBody, let b = contact.nodeB.physicsBody {
            let relative = simd_length(a.velocity.asSIMD - b.velocity.asSIMD)
            let massA = a.type == .dynamic ? Float(a.mass) : .greatestFiniteMagnitude
            let massB = b.type == .dynamic ? Float(b.mass) : .greatestFiniteMagnitude
            impulse = max(impulse, relative * min(massA, massB))
        }
        let record = RecordedContact(
            nodeA: contact.nodeA,
            nodeB: contact.nodeB,
            point: contact.contactPoint.asSIMD,
            impulse: impulse
        )
        lock.lock()
        if buffer.count < capacity { buffer.append(record) }
        lock.unlock()
    }

    func drain() -> [RecordedContact] {
        lock.lock()
        defer { lock.unlock() }
        let contacts = buffer
        buffer.removeAll(keepingCapacity: true)
        return contacts
    }
}

/// Deterministic RNG so procedural textures and platform shapes look the same
/// on every launch.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func float(_ range: ClosedRange<Float>) -> Float { Float.random(in: range, using: &self) }
    mutating func cg(_ range: ClosedRange<CGFloat>) -> CGFloat { CGFloat.random(in: range, using: &self) }
}
