import AVFoundation

/// Procedurally synthesized sound effects. Generated at launch, so the game
/// ships with zero audio files and no licensing concerns. Swap any effect for
/// a recorded asset later by loading a buffer in AudioManager instead.
enum SoundSynth {
    static let sampleRate: Double = 44_100

    static var format: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    /// Renders `duration` seconds by calling `sample(t, i)` per frame.
    static func render(duration: Double, _ sample: (_ t: Double, _ i: Int) -> Float) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            data[i] = max(-1, min(1, sample(Double(i) / sampleRate, i)))
        }
        return buffer
    }

    private struct Noise {
        var state: UInt32 = 0x1234_5678
        mutating func next() -> Float {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Float(state >> 8) / Float(1 << 24) * 2 - 1
        }
    }

    /// One-pole low-pass filter.
    private struct LowPass {
        var y: Float = 0
        let a: Float
        init(cutoff: Double) {
            let dt = 1 / SoundSynth.sampleRate
            let rc = 1 / (2 * .pi * cutoff)
            a = Float(dt / (rc + dt))
        }
        mutating func process(_ x: Float) -> Float { y += a * (x - y); return y }
    }

    private static func sine(_ phase: Double) -> Float { Float(sin(2 * .pi * phase)) }

    // MARK: Effects

    static func charge() -> AVAudioPCMBuffer? {
        var phase = 0.0
        let d = 0.45
        return render(duration: d) { t, _ in
            let f = 220 + 700 * (t / d) * (t / d)
            phase += f / sampleRate
            let env = Float(min(1, t / 0.05)) * Float(1 - pow(t / d, 4))
            return 0.22 * env * (sine(phase) + 0.35 * sine(phase * 2.01))
        }
    }

    static func launch() -> AVAudioPCMBuffer? {
        var noise = Noise()
        var lp = LowPass(cutoff: 2400)
        var phase = 0.0
        return render(duration: 0.55) { t, _ in
            let f = 950 * exp(-t * 7) + 90
            phase += f / sampleRate
            let env = Float(exp(-t * 6)) * Float(min(1, t / 0.004))
            let whoosh = lp.process(noise.next()) * Float(exp(-t * 9))
            return 0.5 * env * sine(phase) + 0.45 * whoosh
        }
    }

    static func impact() -> AVAudioPCMBuffer? {
        var noise = Noise()
        var lp = LowPass(cutoff: 900)
        var phase = 0.0
        return render(duration: 0.6) { t, _ in
            let f = 85 * exp(-t * 3) + 40
            phase += f / sampleRate
            let thump = sine(phase) * Float(exp(-t * 7))
            let crunch = lp.process(noise.next()) * Float(exp(-t * 14)) * 1.6
            let ring = sine(t * 1760) * Float(exp(-t * 18)) * 0.12
            return 0.7 * thump + 0.5 * crunch + ring
        }
    }

    static func blockHit() -> AVAudioPCMBuffer? {
        var noise = Noise()
        var lp = LowPass(cutoff: 1400)
        return render(duration: 0.2) { t, _ in
            let knock = sine(t * 150) * Float(exp(-t * 30))
            let tick = lp.process(noise.next()) * Float(exp(-t * 45))
            return 0.5 * knock + 0.6 * tick
        }
    }

    static func collapse() -> AVAudioPCMBuffer? {
        var noise = Noise()
        var lp = LowPass(cutoff: 220)
        var lp2 = LowPass(cutoff: 600)
        let d = 1.6
        return render(duration: d) { t, _ in
            let env = Float(min(1, t / 0.08)) * Float(exp(-t * 2.2))
            let rumble = lp.process(noise.next()) * 3.2
            let grit = lp2.process(noise.next()) * Float(0.5 + 0.5 * sin(t * 31))
            let sub = sine(t * 42) * 0.5
            return env * (0.55 * rumble + 0.25 * grit + 0.35 * sub)
        }
    }

    static func victory() -> AVAudioPCMBuffer? {
        let notes: [Double] = [523.25, 659.25, 783.99, 1046.5]
        let step = 0.11
        return render(duration: 1.1) { t, _ in
            var out: Float = 0
            for (i, f) in notes.enumerated() {
                let start = Double(i) * step
                guard t >= start else { continue }
                let lt = t - start
                let decay = i == notes.count - 1 ? 2.5 : 9.0
                out += Float(exp(-lt * decay)) * (sine(lt * f) + 0.3 * sine(lt * f * 2))
            }
            return 0.22 * out
        }
    }

    static func failure() -> AVAudioPCMBuffer? {
        let notes: [Double] = [392.0, 329.63, 261.63]
        let step = 0.18
        return render(duration: 1.0) { t, _ in
            var out: Float = 0
            for (i, f) in notes.enumerated() {
                let start = Double(i) * step
                guard t >= start else { continue }
                let lt = t - start
                out += Float(exp(-lt * 4)) * sine(lt * f)
            }
            return 0.2 * out
        }
    }

    static func menu() -> AVAudioPCMBuffer? {
        render(duration: 0.07) { t, _ in
            0.25 * sine(t * 1250) * Float(exp(-t * 60))
        }
    }

    /// Seamless 6-second ambient drone: all frequencies complete whole cycles.
    static func ambience() -> AVAudioPCMBuffer? {
        let d = 6.0
        return render(duration: d) { t, _ in
            let lfo = Float(0.5 + 0.5 * sin(2 * .pi * t / d))
            let lfo2 = Float(0.5 + 0.5 * sin(2 * .pi * 2 * t / d + 1))
            let a = sine(t * 55) * 0.5
            let b = sine(t * 82.5) * 0.3 * lfo
            let c = sine(t * 220) * 0.06 * lfo2
            return 0.12 * (a + b + c)
        }
    }
}
