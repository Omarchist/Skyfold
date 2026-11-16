import Foundation

// Procedural sound for Skyfold. Everything in this file is pure, deterministic DSP
// on plain `[Float]` arrays: no AVFoundation, no shared mutable state, no actor
// hops. Every declaration is `nonisolated` (the target defaults to MainActor), so
// AudioEngine can call it from a detached background task.
//
// Output: mono Float32 at `DSP.sampleRate`, peaks around -6 dBFS, every buffer
// starts and ends at exactly 0 (short raised-cosine fades), and music loops are
// rendered circularly so the last sample flows into the first.
//
// Performance note: per-sample loops go through `DSP.generate/transform/accumulate`
// or a `while` over a raw pointer. In unoptimized Debug builds `for i in 0..<n` and
// Array subscripts cost ~100 ns each, which made a music loop take 10-25 s to render;
// the pointer loops keep Debug within a few seconds and Release within ~100 ms.

// MARK: - Basics

nonisolated enum DSP {
    static let sampleRate: Double = 44_100

    @inline(__always)
    static func samples(_ seconds: Double) -> Int {
        max(1, Int((seconds * sampleRate).rounded()))
    }

    @inline(__always)
    static func hz(_ midi: Double) -> Double {
        440 * pow(2, (midi - 69) / 12)
    }

    @inline(__always)
    static func hz(_ midi: Int) -> Double { hz(Double(midi)) }

    static func dbToGain(_ db: Float) -> Float { pow(10, db / 20) }

    /// Raised-cosine ramp: 0 at x<=0, 1 at x>=1, smooth in between.
    @inline(__always)
    static func smooth(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        return 0.5 - 0.5 * cos(Double.pi * x)
    }

    // MARK: Fast loops

    /// A new buffer of `n` samples, `body(i)` for each index.
    static func generate(_ n: Int, _ body: (Int) -> Float) -> [Float] {
        guard n > 0 else { return [] }
        return [Float](unsafeUninitializedCapacity: n) { buffer, initialized in
            let p = buffer.baseAddress!
            var i = 0
            while i < n {
                p[i] = body(i)
                i += 1
            }
            initialized = n
        }
    }

    /// `x[i] = body(i, x[i])` in place.
    static func transform(_ x: inout [Float], _ body: (Int, Float) -> Float) {
        let n = x.count
        guard n > 0 else { return }
        x.withUnsafeMutableBufferPointer { b in
            let p = b.baseAddress!
            var i = 0
            while i < n {
                p[i] = body(i, p[i])
                i += 1
            }
        }
    }

    /// `x[offset + i] += body(i)` for `i` in `0..<count`, clipped to the buffer.
    static func accumulate(_ x: inout [Float], at offset: Int, count: Int, _ body: (Int) -> Float) {
        let n = x.count
        let end = min(count, n - offset)
        guard offset >= 0, end > 0 else { return }
        x.withUnsafeMutableBufferPointer { b in
            let p = b.baseAddress! + offset
            var i = 0
            while i < end {
                p[i] += body(i)
                i += 1
            }
        }
    }

    /// `dst[i + offset] += src[i] * gain`, clipped to `dst` bounds.
    static func mix(_ src: [Float], into dst: inout [Float], at offset: Int, gain: Float = 1) {
        let start = max(0, -offset)
        let end = min(src.count, dst.count - offset)
        guard start < end else { return }
        dst.withUnsafeMutableBufferPointer { d in
            src.withUnsafeBufferPointer { s in
                let dp = d.baseAddress! + offset, sp = s.baseAddress!
                var i = start
                while i < end {
                    dp[i] += sp[i] * gain
                    i += 1
                }
            }
        }
    }

    static func peak(_ x: [Float]) -> Float {
        x.withUnsafeBufferPointer { b in
            guard let p = b.baseAddress else { return 0 }
            var m: Float = 0
            var i = 0
            while i < b.count {
                let v = abs(p[i])
                if v > m { m = v }
                i += 1
            }
            return m
        }
    }

    static func rms(_ x: [Float]) -> Float {
        x.withUnsafeBufferPointer { b in
            guard let p = b.baseAddress, b.count > 0 else { return 0 }
            var acc: Double = 0
            var i = 0
            while i < b.count {
                acc += Double(p[i]) * Double(p[i])
                i += 1
            }
            return Float((acc / Double(b.count)).squareRoot())
        }
    }

    static func scale(_ x: inout [Float], by g: Float) {
        transform(&x) { _, v in v * g }
    }

    /// Replaces NaN/inf with 0 and scales so the peak equals `target`.
    static func normalize(_ x: inout [Float], peak target: Float) {
        transform(&x) { _, v in v.isFinite ? v : 0 }
        let p = peak(x)
        guard p > 1e-9 else { return }
        scale(&x, by: target / p)
    }

    /// Raised-cosine fades so the first and last samples are exactly 0.
    static func fadeEdges(_ x: inout [Float], fadeIn: Double, fadeOut: Double) {
        let n = x.count
        guard n > 2 else {
            transform(&x) { _, _ in 0 }
            return
        }
        let fi = min(n / 2, max(1, samples(fadeIn)))
        let fo = min(n / 2, max(1, samples(fadeOut)))
        let tail = n - fo
        transform(&x) { i, v in
            var g = 1.0
            if i < fi { g = smooth(Double(i) / Double(fi)) }
            if i >= tail { g *= smooth(Double(n - 1 - i) / Double(fo)) }
            return g == 1 ? v : v * Float(g)
        }
    }

    /// Final step for every one-shot effect: clean edges, then peak-normalize.
    static func finish(_ x: inout [Float], peakDB: Float, fadeIn: Double = 0.001, fadeOut: Double = 0.02) {
        fadeEdges(&x, fadeIn: fadeIn, fadeOut: fadeOut)
        normalize(&x, peak: dbToGain(peakDB))
    }

    /// Runs a stateful per-sample processor over `input` twice and keeps the second pass,
    /// so the processor's state at the start equals its state at the end: the output is
    /// seamless when played as a loop (tails from the end wrap into the start).
    static func circular(_ input: [Float], _ step: (Int, Float) -> Float) -> [Float] {
        let n = input.count
        guard n > 0 else { return [] }
        return input.withUnsafeBufferPointer { src in
            let s = src.baseAddress!
            var i = 0
            while i < n {
                _ = step(i, s[i])
                i += 1
            }
            return generate(n) { j in step(j, s[j]) }
        }
    }
}

/// SplitMix64: tiny, fast, seedable. All "randomness" in the audio is deterministic.
nonisolated struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed ^ 0x5DEE_CE66_D1CE_4E5B }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    /// Uniform in [-1, 1).
    mutating func bipolar() -> Float { Float(unit() * 2 - 1) }

    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }

    mutating func int(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }

    /// `n` samples of white noise in [-1, 1).
    mutating func noise(_ n: Int) -> [Float] {
        var copy = self
        let out = DSP.generate(n) { _ in copy.bipolar() }
        self = copy
        return out
    }
}

// MARK: - Filters and effects

/// One-pole lowpass (6 dB/oct). `highpass` is the complementary output.
nonisolated struct OnePole {
    private var z: Float = 0
    private var a: Float

    init(cutoff: Double) { a = OnePole.coefficient(cutoff) }

    static func coefficient(_ cutoff: Double) -> Float {
        let fc = min(max(cutoff, 1), DSP.sampleRate * 0.49)
        return Float(1 - exp(-2 * Double.pi * fc / DSP.sampleRate))
    }

    @inline(__always)
    mutating func lowpass(_ x: Float) -> Float {
        z += a * (x - z)
        return z
    }

    @inline(__always)
    mutating func highpass(_ x: Float) -> Float { x - lowpass(x) }

    /// Lowpasses a whole buffer in place.
    static func lowpass(_ x: inout [Float], cutoff: Double) {
        var f = OnePole(cutoff: cutoff)
        DSP.transform(&x) { _, v in f.lowpass(v) }
    }
}

/// Topology-preserving state-variable filter (Cytomic/Simper). Stable under fast
/// cutoff modulation, which the sweeps rely on.
nonisolated struct SVF {
    nonisolated struct Output {
        var low: Float
        /// Bandpass normalized to unity gain at the center frequency.
        var band: Float
        var high: Float
    }

    private var ic1: Float = 0
    private var ic2: Float = 0
    private var a1: Float = 0
    private var a2: Float = 0
    private var a3: Float = 0
    private var k: Float = 1

    init(cutoff: Double, q: Double) { set(cutoff: cutoff, q: q) }

    mutating func set(cutoff: Double, q: Double) {
        let fc = min(max(cutoff, 10), DSP.sampleRate * 0.45)
        let g = tan(Double.pi * fc / DSP.sampleRate)
        let kk = 1 / max(q, 0.05)
        let d = 1 / (1 + g * (g + kk))
        a1 = Float(d)
        a2 = Float(g * d)
        a3 = Float(g * g * d)
        k = Float(kk)
    }

    @inline(__always)
    mutating func process(_ x: Float) -> Output {
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return Output(low: v2, band: k * v1, high: x - k * v1 - v2)
    }
}

/// Feedback delay with a lowpass in the loop, so repeats get darker ("distant").
/// Returns only the wet signal. Keeps its state between calls.
nonisolated struct Echo {
    private var buffer: [Float]
    private var index = 0
    private var dampState: Float = 0
    private let dampCoefficient: Float
    private let feedback: Float

    init(delaySamples: Int, feedback: Float, cutoff: Double) {
        buffer = [Float](repeating: 0, count: max(1, delaySamples))
        self.feedback = feedback
        dampCoefficient = OnePole.coefficient(cutoff)
    }

    mutating func process(_ input: [Float]) -> [Float] {
        let n = input.count
        guard n > 0 else { return [] }
        var out = [Float](repeating: 0, count: n)
        var idx = index, z = dampState
        let a = dampCoefficient, fb = feedback
        buffer.withUnsafeMutableBufferPointer { bb in
            input.withUnsafeBufferPointer { ib in
                out.withUnsafeMutableBufferPointer { ob in
                    let b = bb.baseAddress!, src = ib.baseAddress!, dst = ob.baseAddress!
                    let len = bb.count
                    var i = 0
                    while i < n {
                        let y = b[idx]
                        z += a * (y - z)
                        b[idx] = src[i] + z * fb
                        dst[i] = y
                        idx += 1
                        if idx == len { idx = 0 }
                        i += 1
                    }
                }
            }
        }
        index = idx
        dampState = z
        return out
    }
}

/// Small mono Schroeder/Freeverb-style reverb: 6 damped combs into 4 allpasses.
/// Returns only the wet signal (roughly unity RMS gain on noise) and keeps its
/// state between calls, so calling it twice on a loop gives a circular tail.
nonisolated struct Reverb {
    private var combs: [[Float]]
    private var combIndex: [Int]
    private var combStore: [Float]
    private var allpasses: [[Float]]
    private var allpassIndex: [Int]
    private let feedback: Float
    private let damp: Float
    private let inputGain: Float

    /// - Parameters:
    ///   - size: 0...1, longer tail as it grows (comb feedback 0.70...0.95).
    ///   - damping: 0...1, darker tail as it grows.
    init(size: Float, damping: Float) {
        combs = [1116, 1188, 1277, 1356, 1491, 1617].map { [Float](repeating: 0, count: $0) }
        allpasses = [556, 441, 341, 225].map { [Float](repeating: 0, count: $0) }
        combIndex = Array(repeating: 0, count: combs.count)
        combStore = Array(repeating: 0, count: combs.count)
        allpassIndex = Array(repeating: 0, count: allpasses.count)
        let s = min(max(size, 0), 1)
        feedback = 0.70 + 0.25 * s
        damp = min(max(damping, 0), 0.95)
        // Keep the wet level roughly independent of the tail length.
        inputGain = 0.22 * (1 - feedback * feedback).squareRoot() / 0.714
    }

    mutating func process(_ input: [Float]) -> [Float] {
        let n = input.count
        guard n > 0 else { return [] }
        var out = [Float](repeating: 0, count: n)
        let fb = feedback, d = damp, d1 = 1 - damp, g = inputGain
        input.withUnsafeBufferPointer { ib in
            out.withUnsafeMutableBufferPointer { ob in
                let src = ib.baseAddress!, dst = ob.baseAddress!
                // Combs in parallel (one pass per comb is cache- and Debug-friendly).
                for c in 0..<combs.count {
                    var idx = combIndex[c], store = combStore[c]
                    combs[c].withUnsafeMutableBufferPointer { cb in
                        let b = cb.baseAddress!
                        let len = cb.count
                        var i = 0
                        while i < n {
                            let y = b[idx]
                            store = y * d1 + store * d
                            b[idx] = src[i] * g + store * fb
                            dst[i] += y
                            idx += 1
                            if idx == len { idx = 0 }
                            i += 1
                        }
                    }
                    combIndex[c] = idx
                    combStore[c] = store
                }
                // Allpasses in series.
                for a in 0..<allpasses.count {
                    var idx = allpassIndex[a]
                    allpasses[a].withUnsafeMutableBufferPointer { ab in
                        let b = ab.baseAddress!
                        let len = ab.count
                        var i = 0
                        while i < n {
                            let x = dst[i]
                            let bv = b[idx]
                            b[idx] = x + bv * 0.5
                            dst[i] = bv - x
                            idx += 1
                            if idx == len { idx = 0 }
                            i += 1
                        }
                    }
                    allpassIndex[a] = idx
                }
            }
        }
        return out
    }

    /// One-shot convenience: `x += wet * reverb(x)` in place.
    static func apply(_ x: inout [Float], wet: Float, size: Float, damping: Float) {
        var r = Reverb(size: size, damping: damping)
        DSP.mix(r.process(x), into: &x, at: 0, gain: wet)
    }
}

/// Band-limited single-cycle table with linear interpolation.
nonisolated struct Wavetable {
    private let table: [Float]
    private let size: Int

    init(size: Int = 2048, partials: [(harmonic: Int, amp: Double)]) {
        self.size = size
        var t = DSP.generate(size + 1) { i in
            let ph = Double(i) / Double(size)
            var v = 0.0
            for p in partials { v += p.amp * sin(2 * Double.pi * Double(p.harmonic) * ph) }
            return Float(v)
        }
        DSP.normalize(&t, peak: 1)
        t[size] = t[0]
        table = t
    }

    /// Adds `count` samples of this oscillator (times `gain`) into `dst`, advancing `phase`.
    func add(into dst: UnsafeMutablePointer<Float>, count n: Int, phase: inout Double,
             increment inc: Double, gain: Float = 1) {
        let size = self.size
        table.withUnsafeBufferPointer { tb in
            let t = tb.baseAddress!
            let scale = Double(size)
            var ph = phase
            var i = 0
            while i < n {
                let x = ph * scale
                var j = Int(x)
                if j >= size { j = size - 1 }
                let f = Float(x - Double(j))
                let a = t[j]
                dst[i] += (a + (t[j + 1] - a) * f) * gain
                ph += inc
                if ph >= 1 { ph -= 1 }
                i += 1
            }
            phase = ph
        }
    }

    /// `count` samples of this oscillator at `freq`, starting at `phase`.
    func render(freq: Double, count: Int, phase: Double = 0) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        var ph = phase
        out.withUnsafeMutableBufferPointer { b in
            add(into: b.baseAddress!, count: count, phase: &ph, increment: freq / DSP.sampleRate)
        }
        return out
    }

    /// Mellow, between a triangle and a saw: the day pads.
    static let warm = Wavetable(partials: (1...10).map { ($0, 1 / pow(Double($0), 1.6)) })
    /// Few harmonics, hollow odd emphasis: the night pads and drones.
    static let dark = Wavetable(partials: (1...6).map { ($0, ($0 % 2 == 1 ? 1.0 : 0.55) / pow(Double($0), 2.1)) })
}

// MARK: - Voices (each returns a note that starts and ends at 0)

nonisolated enum Voice {
    nonisolated struct Partial {
        var ratio: Double
        var amp: Double
        /// Multiplies the note's decay time constant for this partial.
        var decayScale: Double
    }

    /// Exponentially decaying sum of sines (sine recurrence, no per-sample `sin`).
    static func additive(freq: Double, partials: [Partial], amp: Float, decay: Double,
                         attack: Double, length: Double) -> [Float] {
        let n = DSP.samples(length)
        var out = [Float](repeating: 0, count: n)
        let sr = DSP.sampleRate
        out.withUnsafeMutableBufferPointer { ob in
            let o = ob.baseAddress!
            for p in partials {
                let f = freq * p.ratio
                guard f < sr * 0.45, p.amp > 0 else { continue }
                let tau = max(0.001, decay * p.decayScale)
                let w = 2 * Double.pi * f / sr
                let cw = cos(w), sw = sin(w)
                let r = exp(-1 / (tau * sr))
                var re = 1.0, im = 0.0
                var e = p.amp * Double(amp)
                // Stop once this partial is ~80 dB down.
                let count = min(n, Int(tau * 9.3 * sr) + 1)
                var i = 0
                while i < count {
                    o[i] += Float(im * e)
                    let nre = re * cw - im * sw
                    im = re * sw + im * cw
                    re = nre
                    e *= r
                    i += 1
                }
            }
        }
        DSP.fadeEdges(&out, fadeIn: attack, fadeOut: min(0.03, length * 0.25))
        return out
    }

    /// Soft plucked string. `brightness` 0...1.
    static func pluck(freq: Double, amp: Float, decay: Double, brightness: Double,
                      length: Double? = nil) -> [Float] {
        let tilt = 2.5 - 1.4 * brightness
        let partials = (1...7).map { k in
            Partial(ratio: Double(k), amp: pow(Double(k), -tilt),
                    decayScale: 1 / (1 + Double(k - 1) * (1.1 - 0.5 * brightness)))
        }
        return additive(freq: freq, partials: partials, amp: amp, decay: decay,
                        attack: 0.004, length: length ?? min(decay * 5, 4))
    }

    /// Vibraphone-ish chime (airport "ding-dong") with a gentle tremolo.
    static func vibes(freq: Double, amp: Float, decay: Double, tremolo: Double = 5.2) -> [Float] {
        let partials = [
            Partial(ratio: 1, amp: 1, decayScale: 1),
            Partial(ratio: 4, amp: 0.10, decayScale: 0.22),
            Partial(ratio: 2.76, amp: 0.035, decayScale: 0.3),
            Partial(ratio: 10, amp: 0.012, decayScale: 0.06),
        ]
        var out = additive(freq: freq, partials: partials, amp: amp, decay: decay,
                           attack: 0.004, length: decay * 4.5)
        let w = 2 * Double.pi * tremolo / DSP.sampleRate
        DSP.transform(&out) { i, v in v * Float(1 - 0.12 * (0.5 - 0.5 * cos(w * Double(i)))) }
        return out
    }

    /// FM bell. Non-integer `ratio` gives inharmonic (eerie) partials; `index` is the
    /// initial brightness, which decays with `indexDecay`.
    static func fmBell(freq: Double, amp: Float, decay: Double, ratio: Double, index: Double,
                       indexDecay: Double, attack: Double = 0.003, length: Double? = nil) -> [Float] {
        let len = length ?? min(decay * 5.5, 6)
        let sr = DSP.sampleRate
        let wc = 2 * Double.pi * freq / sr
        let wm = wc * ratio
        let ra = exp(-1 / (decay * sr))
        let ri = exp(-1 / (indexDecay * sr))
        var e = Double(amp)
        var idx = index
        var out = DSP.generate(DSP.samples(len)) { i in
            let t = Double(i)
            let y = sin(wc * t + idx * sin(wm * t)) * e
            e *= ra
            idx *= ri
            return Float(y)
        }
        DSP.fadeEdges(&out, fadeIn: attack, fadeOut: min(0.05, len * 0.2))
        return out
    }

    /// Glassy chime: sine carrier with a quick, soft FM shimmer plus a faint octave.
    static func glass(freq: Double, amp: Float, decay: Double, length: Double? = nil) -> [Float] {
        var out = fmBell(freq: freq, amp: amp, decay: decay, ratio: 3.5, index: 0.75,
                         indexDecay: 0.035, attack: 0.0015, length: length ?? decay * 6)
        let octave = additive(freq: freq, partials: [
            Partial(ratio: 2, amp: 0.22, decayScale: 0.6),
            Partial(ratio: 2.76, amp: 0.07, decayScale: 0.35),
        ], amp: amp, decay: decay, attack: 0.0015, length: Double(out.count) / DSP.sampleRate)
        DSP.mix(octave, into: &out, at: 0)
        return out
    }

    /// Detuned wavetable pad note: raised-cosine attack and release, two-pole lowpass.
    /// Total length is `attack + hold + release`.
    static func pad(freq: Double, amp: Float, attack: Double, hold: Double, release: Double,
                    table: Wavetable, detuneCents: Double, voices: Int, cutoff: Double,
                    rng: inout SeededRandom) -> [Float] {
        let total = attack + hold + release
        let n = DSP.samples(total)
        var out = [Float](repeating: 0, count: n)
        let v = max(1, voices)
        out.withUnsafeMutableBufferPointer { ob in
            let o = ob.baseAddress!
            for j in 0..<v {
                let spread = v == 1 ? 0 : Double(j) / Double(v - 1) * 2 - 1
                let f = freq * pow(2, spread * detuneCents / 1200)
                var phase = rng.unit()
                table.add(into: o, count: n, phase: &phase, increment: f / DSP.sampleRate)
            }
        }
        var lp1 = OnePole(cutoff: cutoff), lp2 = OnePole(cutoff: cutoff)
        let g = amp / Float(v)
        let sr = DSP.sampleRate
        let releaseStart = attack + hold
        DSP.transform(&out) { i, x in
            let t = Double(i) / sr
            let env = DSP.smooth(t / attack) * (t < releaseStart ? 1 : DSP.smooth((total - t) / release))
            return i == n - 1 ? 0 : lp2.lowpass(lp1.lowpass(x)) * g * Float(env)
        }
        return out
    }

    /// Soft kick-like pulse: a sine that drops from `from` to `to` Hz. `overtone` adds a
    /// little second and third harmonic that dies away twice as fast, so the pulse still
    /// reads on a phone speaker (which plays almost nothing below about 150 Hz).
    static func thump(from f0: Double, to f1: Double, sweep: Double, decay: Double, amp: Float,
                      overtone: Double = 0) -> [Float] {
        let sr = DSP.sampleRate
        var phase = 0.0
        var out = DSP.generate(DSP.samples(decay * 7)) { i in
            let t = Double(i) / sr
            phase += (f1 + (f0 - f1) * exp(-t / sweep)) / sr
            if phase >= 1 { phase -= 1 }
            let w = 2 * Double.pi * phase
            var s = sin(w)
            if overtone > 0 { s += overtone * exp(-t / decay) * (sin(2 * w) + 0.4 * sin(3 * w)) }
            return Float(s * DSP.smooth(t / 0.003) * exp(-t / decay)) * amp
        }
        DSP.fadeEdges(&out, fadeIn: 0.001, fadeOut: 0.02)
        return out
    }

    /// Short highpassed noise tick (a very soft shaker).
    static func tick(seed: UInt64, amp: Float, decay: Double, cutoff: Double) -> [Float] {
        var rng = SeededRandom(seed: seed)
        var f = SVF(cutoff: cutoff, q: 0.8)
        let sr = DSP.sampleRate
        var out = DSP.generate(DSP.samples(decay * 6)) { i in
            let t = Double(i) / sr
            return f.process(rng.bipolar()).high * Float(DSP.smooth(t / 0.002) * exp(-t / decay)) * amp
        }
        DSP.fadeEdges(&out, fadeIn: 0.001, fadeOut: 0.01)
        return out
    }

    /// Bandpassed noise with an exponential center sweep. `env` maps 0...1 progress to gain.
    static func noiseSweep(seed: UInt64, length: Double, from f0: Double, to f1: Double,
                           q: Double, env: (Double) -> Double) -> [Float] {
        var rng = SeededRandom(seed: seed)
        let n = DSP.samples(length)
        var f = SVF(cutoff: f0, q: q)
        return DSP.generate(n) { i in
            let p = Double(i) / Double(n)
            if i & 7 == 0 { f.set(cutoff: f0 * pow(f1 / f0, p), q: q) }
            return f.process(rng.bipolar()).band * Float(env(p))
        }
    }
}

// MARK: - Sound effects

nonisolated enum SoundSynth {
    /// Frequent sounds get a few deterministic variants so repeats don't feel robotic.
    static func variantCount(_ effect: SoundEffect) -> Int {
        switch effect {
        case .laneSwitch, .star: return 3
        case .crash: return 2
        default: return 1
        }
    }

    /// Renders one effect. Pure and thread-safe; call it off the main thread.
    static func render(_ effect: SoundEffect, variant: Int = 0) -> [Float] {
        let v = max(0, variant)
        switch effect {
        case .laneSwitch: return laneSwitch(v)
        case .star: return star(v)
        case .crash: return crash(v)
        case .shieldBreak: return shieldBreak()
        case .countdown: return countdown()
        case .takeoff: return takeoff()
        case .landing: return landing()
        case .gateOpen: return gateOpen()
        case .blessing: return blessing()
        case .curse: return curse()
        case .unlock: return unlock()
        case .uiTap: return uiTap()
        }
    }

    private static let sr = DSP.sampleRate
    private static let twoPi = 2 * Double.pi

    /// Filtered-noise whoosh, 130 ms, gentle up-sweep.
    private static func laneSwitch(_ v: Int) -> [Float] {
        let spread = [1.0, 0.9, 1.12][v % 3]
        var out = Voice.noiseSweep(seed: 0x1A5E + UInt64(v), length: 0.13,
                                   from: 480 * spread, to: 2300 * spread, q: 1.3) { p in
            p < 0.35 ? DSP.smooth(p / 0.35) : pow(1 - (p - 0.35) / 0.65, 1.8)
        }
        OnePole.lowpass(&out, cutoff: 6500)
        DSP.finish(&out, peakDB: -9, fadeIn: 0.002, fadeOut: 0.012)
        return out
    }

    /// Two-note glassy chime, a major third apart, 370 ms.
    private static func star(_ v: Int) -> [Float] {
        let pairs: [(Int, Int)] = [(84, 88), (77, 81), (79, 83)]   // C6-E6, F5-A5, G5-B5
        let (a, b) = pairs[v % pairs.count]
        var out = [Float](repeating: 0, count: DSP.samples(0.37))
        DSP.mix(Voice.glass(freq: DSP.hz(a), amp: 0.75, decay: 0.085), into: &out, at: 0)
        DSP.mix(Voice.glass(freq: DSP.hz(b), amp: 1.0, decay: 0.11), into: &out, at: DSP.samples(0.07))
        Reverb.apply(&out, wet: 0.14, size: 0.5, damping: 0.4)
        DSP.finish(&out, peakDB: -6, fadeOut: 0.07)
        return out
    }

    /// Crumpled paper (grains of filtered noise) plus a low thump, ~500 ms.
    private static func crash(_ v: Int) -> [Float] {
        let n = DSP.samples(0.55)
        var rng = SeededRandom(seed: 0xC2A5 &+ UInt64(v) &* 7919)
        var paper = [Float](repeating: 0, count: n)
        for _ in 0..<40 {
            let t0 = 0.44 * pow(rng.unit(), 1.6)
            let gn = DSP.samples(rng.range(0.005, 0.028))
            var f = SVF(cutoff: rng.range(800, 3400), q: rng.range(1.5, 3.5))
            let amp = Float(rng.range(0.35, 1.0) * exp(-t0 / 0.24))
            DSP.accumulate(&paper, at: DSP.samples(t0), count: gn) { j in
                let w = sin(Double.pi * Double(j) / Double(gn))
                return f.process(rng.bipolar()).band * amp * Float(w * w)
            }
        }
        var body = OnePole(cutoff: 1400)
        DSP.accumulate(&paper, at: 0, count: n) { i in
            let t = Double(i) / sr
            return 0.35 * body.lowpass(rng.bipolar()) * Float(exp(-t / 0.07) * DSP.smooth(t / 0.003))
        }
        OnePole.lowpass(&paper, cutoff: 4800)
        DSP.normalize(&paper, peak: 1)
        // Soft saturation evens out the grain peaks, so the crumple is dense, not spiky.
        DSP.transform(&paper) { _, v in tanh(2.5 * v) }
        OnePole.lowpass(&paper, cutoff: 3600)
        DSP.normalize(&paper, peak: 1)

        // The paper carries the sound on a phone speaker; the thump is for headphones.
        var thump = Voice.thump(from: 170, to: 64, sweep: 0.03, decay: 0.075, amp: 1, overtone: 0.45)
        DSP.normalize(&thump, peak: 1)

        var out = [Float](repeating: 0, count: n)
        DSP.mix(paper, into: &out, at: 0, gain: 1)
        DSP.mix(thump, into: &out, at: 0, gain: 0.55)
        DSP.finish(&out, peakDB: -6, fadeIn: 0.001, fadeOut: 0.04)
        return out
    }

    /// Bright pop with a short shimmer.
    private static func shieldBreak() -> [Float] {
        let n = DSP.samples(0.65)
        var rng = SeededRandom(seed: 0x5E1D)
        var click = SVF(cutoff: 3800, q: 0.9)
        var phase = 0.0
        var out = DSP.generate(n) { i in
            let t = Double(i) / sr
            phase += (650 + 1600 * exp(-t / 0.010)) / sr
            if phase >= 1 { phase -= 1 }
            let pop = sin(twoPi * phase) * DSP.smooth(t / 0.0008) * exp(-t / 0.035)
            let c = Double(click.process(rng.bipolar()).band) * exp(-t / 0.003)
            return Float(0.9 * pop + 0.35 * c)
        }
        let start = DSP.samples(0.012)
        for f in [2093.0, 2637.0, 3136.0, 3951.1, 4186.0] {
            let freq = f * (1 + rng.range(-0.004, 0.004))
            let decay = 0.18 * rng.range(0.85, 1.15)
            let rate = rng.range(16, 26)
            let ph = rng.unit()
            DSP.accumulate(&out, at: start, count: n - start) { i in
                let t = Double(i) / sr
                let trem = 1 - 0.35 * (0.5 + 0.5 * sin(twoPi * (rate * t + ph)))
                let env = DSP.smooth(t / 0.01) * exp(-t / decay)
                return Float(0.11 * sin(twoPi * freq * t) * env * trem)
            }
        }
        Reverb.apply(&out, wet: 0.3, size: 0.6, damping: 0.3)
        OnePole.lowpass(&out, cutoff: 9000)
        DSP.finish(&out, peakDB: -6, fadeIn: 0.0005, fadeOut: 0.08)
        return out
    }

    /// Soft wooden tick: three damped modes and a tiny noise click.
    private static func countdown() -> [Float] {
        var out = Voice.additive(freq: 700, partials: [
            Voice.Partial(ratio: 1, amp: 1, decayScale: 1),
            Voice.Partial(ratio: 2.43, amp: 0.32, decayScale: 0.45),
            Voice.Partial(ratio: 4.07, amp: 0.12, decayScale: 0.2),
        ], amp: 1, decay: 0.020, attack: 0.0006, length: 0.09)
        var rng = SeededRandom(seed: 0x71C)
        var lp = OnePole(cutoff: 2500)
        DSP.accumulate(&out, at: 0, count: out.count) { i in
            0.18 * lp.lowpass(rng.bipolar()) * Float(exp(-Double(i) / sr / 0.0012))
        }
        DSP.finish(&out, peakDB: -8, fadeIn: 0.0005, fadeOut: 0.015)
        return out
    }

    /// Rising airy swell, about 1 s.
    private static func takeoff() -> [Float] {
        let len = 1.08
        let swell: (Double) -> Double = { t in
            t < 0.76 ? pow(t / 0.76, 1.6) : DSP.smooth((0.97 - t) / 0.21)
        }
        var out = Voice.noiseSweep(seed: 0x7A4E, length: len, from: 280, to: 3250, q: 0.8) { p in
            swell(p * len)
        }
        OnePole.lowpass(&out, cutoff: 7000)
        DSP.normalize(&out, peak: 1)
        var phase = 0.0
        DSP.accumulate(&out, at: 0, count: out.count) { i in
            let t = Double(i) / sr
            phase += 196 * pow(2, min(t / 0.85, 1)) / sr
            if phase >= 1 { phase -= 1 }
            let w = twoPi * phase
            let tone = sin(w) + 0.25 * sin(2 * w) + 0.5 * sin(1.5 * w)
            return Float(0.18 * tone * pow(swell(t), 1.3))
        }
        Reverb.apply(&out, wet: 0.2, size: 0.65, damping: 0.4)
        DSP.finish(&out, peakDB: -6, fadeIn: 0.01, fadeOut: 0.1)
        return out
    }

    /// Descending glide, then a soft airport "ding-dong" (E5, C5).
    private static func landing() -> [Float] {
        var out = [Float](repeating: 0, count: DSP.samples(2.5))
        let hump: (Double) -> Double = { p in pow(sin(Double.pi * min(max(p, 0), 1)), 1.2) }
        var glide = Voice.noiseSweep(seed: 0x1A4D, length: 0.75, from: 1900, to: 380, q: 0.9, env: hump)
        DSP.normalize(&glide, peak: 0.55)
        var phase = 0.0
        let gn = glide.count
        DSP.accumulate(&glide, at: 0, count: gn) { i in
            let p = Double(i) / Double(gn)
            phase += 587.33 * pow(0.5, p) / sr
            if phase >= 1 { phase -= 1 }
            return Float(0.12 * sin(twoPi * phase) * hump(p))
        }
        DSP.mix(glide, into: &out, at: 0)
        DSP.mix(Voice.vibes(freq: 659.26, amp: 0.55, decay: 0.45), into: &out, at: DSP.samples(0.62))
        DSP.mix(Voice.vibes(freq: 523.25, amp: 0.55, decay: 0.55), into: &out, at: DSP.samples(1.0))
        Reverb.apply(&out, wet: 0.3, size: 0.8, damping: 0.4)
        DSP.finish(&out, peakDB: -6, fadeIn: 0.005, fadeOut: 0.2)
        return out
    }

    /// Low airy slide plus a stick-slip creak, about 700 ms.
    private static func gateOpen() -> [Float] {
        let len = 0.76
        let n = DSP.samples(len)
        let slideEnv: (Double) -> Double = { t in DSP.smooth(t / 0.12) * DSP.smooth((0.66 - t) / 0.24) }
        var slide = Voice.noiseSweep(seed: 0x6A7E, length: len, from: 220, to: 624, q: 0.7) { p in
            slideEnv(p * len)
        }
        OnePole.lowpass(&slide, cutoff: 3000)
        DSP.normalize(&slide, peak: 1)

        var rng = SeededRandom(seed: 0xC4EA)
        var r1 = SVF(cutoff: 480, q: 9), r2 = SVF(cutoff: 1080, q: 7)
        var nextImpulse = 0.08
        var creak = DSP.generate(n) { i in
            let t = Double(i) / sr
            var x: Float = 0
            if t >= nextImpulse {
                let env = DSP.smooth((t - 0.08) / 0.1) * DSP.smooth((0.56 - t) / 0.12)
                x = Float(env * rng.range(0.6, 1.0))
                let rate = (26 + 30 * min(t / 0.62, 1)) * rng.range(0.85, 1.15)
                nextImpulse = t + 1 / rate
            }
            return r1.process(x).band + 0.6 * r2.process(x).band
        }
        DSP.normalize(&creak, peak: 1)

        var out = DSP.generate(n) { i in
            let t = Double(i) / sr
            let low = 0.11 * sin(twoPi * 82 * t) * slideEnv(t)
            return 0.7 * slide[i] + 0.45 * creak[i] + Float(low)
        }
        Reverb.apply(&out, wet: 0.15, size: 0.55, damping: 0.5)
        OnePole.lowpass(&out, cutoff: 5000)
        DSP.finish(&out, peakDB: -7, fadeIn: 0.005, fadeOut: 0.09)
        return out
    }

    /// Warm, bell-like major pentatonic arpeggio (C D E G A C), about 1.2 s.
    private static func blessing() -> [Float] {
        let n = DSP.samples(1.28)
        var out = [Float](repeating: 0, count: n)
        let notes = [72, 74, 76, 79, 81, 84]
        for (i, m) in notes.enumerated() {
            let last = i == notes.count - 1
            let decay = last ? 0.5 : 0.36 + 0.03 * Double(i)
            let amp = Float(0.55 + 0.07 * Double(i))
            var bell = Voice.fmBell(freq: DSP.hz(m), amp: amp, decay: decay, ratio: 1, index: 0.7,
                                    indexDecay: 0.12, attack: 0.003, length: min(decay * 5, 1.5))
            let shimmer = Voice.additive(freq: DSP.hz(m), partials: [
                Voice.Partial(ratio: 2.76, amp: 0.06, decayScale: 0.25),
                Voice.Partial(ratio: 2, amp: 0.15, decayScale: 0.5),
            ], amp: amp, decay: decay, attack: 0.003, length: Double(bell.count) / sr)
            DSP.mix(shimmer, into: &bell, at: 0)
            DSP.mix(bell, into: &out, at: DSP.samples(0.08 * Double(i)))
        }
        let chord = [60, 64, 67].map { twoPi * DSP.hz($0) }
        DSP.accumulate(&out, at: 0, count: n) { i in
            let t = Double(i) / sr
            let env = DSP.smooth(t / 0.3) * DSP.smooth((1.18 - t) / 0.5)
            return Float(0.05 * (sin(chord[0] * t) + sin(chord[1] * t) + sin(chord[2] * t)) * env)
        }
        Reverb.apply(&out, wet: 0.3, size: 0.7, damping: 0.4)
        DSP.finish(&out, peakDB: -6, fadeIn: 0.002, fadeOut: 0.16)
        return out
    }

    /// Dissonant low swell: A against E♭ (a tritone) in two octaves, each tone beating
    /// slowly against a detuned twin, with a faint minor-second whistle on top. About 1.4 s.
    private static func curse() -> [Float] {
        let n = DSP.samples(1.5)
        let env: (Double) -> Double = { t in DSP.smooth(t / 0.75) * DSP.smooth((1.32 - t) / 0.5) }
        var rng = SeededRandom(seed: 0xC0125E)
        var tone = [Float](repeating: 0, count: n)
        // (Hz, beat rate Hz, level). The beats are slow enough to hear as a wobble, fast
        // enough to turn over a few times in 1.4 s. The upper pair carries the sound on a
        // phone speaker, which cannot play the lower one.
        let voices: [(Double, Double, Float)] = [(110, 2.6, 0.7), (155.563, 3.7, 0.8), (220, 2.1, 0.8), (311.127, 3.1, 0.7)]
        tone.withUnsafeMutableBufferPointer { b in
            for (f, beat, level) in voices {
                for freq in [f, f + beat] {
                    var ph = rng.unit()
                    Wavetable.dark.add(into: b.baseAddress!, count: n, phase: &ph,
                                       increment: freq / sr, gain: level)
                }
            }
        }
        var filter = SVF(cutoff: 450, q: 1.2)
        var out = DSP.generate(n) { i in
            let t = Double(i) / sr
            let e = env(t)
            if i & 15 == 0 { filter.set(cutoff: 450 + 1150 * e, q: 1.2) }
            let low = Double(filter.process(tone[i]).low) * 0.25
            let sub = 0.07 * sin(twoPi * 55 * t)
            let whistle = 0.025 * (sin(twoPi * 1760 * t) + sin(twoPi * 1864.66 * t)) * e
            return Float((low + sub + whistle) * e)
        }
        Reverb.apply(&out, wet: 0.32, size: 0.75, damping: 0.55)
        DSP.finish(&out, peakDB: -6, fadeIn: 0.01, fadeOut: 0.18)
        return out
    }

    /// A fast rising glass arpeggio (C E G C E) that lands on a chord, with a few
    /// scattered high pings. About 900 ms.
    private static func unlock() -> [Float] {
        var out = [Float](repeating: 0, count: DSP.samples(0.98))
        for (i, m) in [72, 76, 79, 84, 88].enumerated() {
            let note = Voice.glass(freq: DSP.hz(m), amp: Float(0.5 + 0.1 * Double(i)),
                                   decay: 0.15 + 0.03 * Double(i), length: 0.7)
            DSP.mix(note, into: &out, at: DSP.samples(0.065 * Double(i)))
        }
        for m in [84, 88, 91] {
            DSP.mix(Voice.glass(freq: DSP.hz(m), amp: 0.3, decay: 0.28, length: 0.66),
                    into: &out, at: DSP.samples(0.31))
        }
        var rng = SeededRandom(seed: 0x5BA2C)
        let sparkle = [2093.0, 2349.3, 2637.0, 3136.0, 3520.0, 4186.0]
        for _ in 0..<14 {
            let t0 = rng.range(0.16, 0.62)
            let f = sparkle[rng.int(sparkle.count)] * (1 + rng.range(-0.003, 0.003))
            let amp = Float(rng.range(0.06, 0.14) * (1 - (t0 - 0.16) / 0.7))
            let ping = Voice.additive(freq: f, partials: [Voice.Partial(ratio: 1, amp: 1, decayScale: 1)],
                                      amp: amp, decay: rng.range(0.03, 0.07), attack: 0.001, length: 0.35)
            DSP.mix(ping, into: &out, at: DSP.samples(t0))
        }
        Reverb.apply(&out, wet: 0.28, size: 0.68, damping: 0.35)
        DSP.finish(&out, peakDB: -6, fadeIn: 0.001, fadeOut: 0.14)
        return out
    }

    /// Tiny soft click, 30 ms.
    private static func uiTap() -> [Float] {
        var rng = SeededRandom(seed: 0x7A9)
        var lp = OnePole(cutoff: 3500)
        var out = DSP.generate(DSP.samples(0.03)) { i in
            let t = Double(i) / sr
            let tone = sin(twoPi * 1350 * t) * DSP.smooth(t / 0.0004) * exp(-t / 0.0045)
            let noise = Double(lp.lowpass(rng.bipolar())) * exp(-t / 0.0008)
            return Float(tone + 0.3 * noise)
        }
        DSP.finish(&out, peakDB: -10, fadeIn: 0.0003, fadeOut: 0.006)
        return out
    }
}

// MARK: - Music

/// A loop under construction. Notes are added on a beat grid and wrap around the end
/// of the loop, so a note that rings past the last bar continues at the first.
nonisolated struct LoopMix {
    let length: Int
    let samplesPerBeat: Double
    var dry: [Float]
    var echoSend: [Float]
    var reverbSend: [Float]
    /// Sources that go through the slow LFO filter (only flightNight uses it).
    var lfoBus: [Float] = []

    init(spec: MusicSynth.Spec) {
        samplesPerBeat = 60 / spec.bpm * DSP.sampleRate
        length = Int((Double(spec.beatsPerBar * spec.bars) * samplesPerBeat).rounded())
        dry = [Float](repeating: 0, count: length)
        echoSend = dry
        reverbSend = dry
    }

    var seconds: Double { Double(length) / DSP.sampleRate }

    func sampleIndex(beat: Double) -> Int {
        let i = Int((beat * samplesPerBeat).rounded()) % length
        return i < 0 ? i + length : i
    }

    mutating func add(_ note: [Float], beat: Double, dry d: Float = 1, echo e: Float = 0,
                      reverb r: Float = 0, lfo l: Float = 0) {
        let start = sampleIndex(beat: beat)
        if d != 0 { LoopMix.wrapAdd(note, into: &dry, at: start, gain: d) }
        if e != 0 { LoopMix.wrapAdd(note, into: &echoSend, at: start, gain: e) }
        if r != 0 { LoopMix.wrapAdd(note, into: &reverbSend, at: start, gain: r) }
        if l != 0 {
            if lfoBus.isEmpty { lfoBus = [Float](repeating: 0, count: length) }
            LoopMix.wrapAdd(note, into: &lfoBus, at: start, gain: l)
        }
    }

    private static func wrapAdd(_ src: [Float], into dst: inout [Float], at start: Int, gain: Float) {
        let n = dst.count, count = src.count
        guard n > 0, count > 0 else { return }
        dst.withUnsafeMutableBufferPointer { d in
            src.withUnsafeBufferPointer { s in
                let dp = d.baseAddress!, sp = s.baseAddress!
                var j = start, i = 0
                while i < count {
                    dp[j] += sp[i] * gain
                    j += 1
                    if j == n { j = 0 }
                    i += 1
                }
            }
        }
    }

    /// A continuous tone that is exactly periodic over the loop: its frequency is nudged
    /// (by at most 1/(2·loop seconds) Hz) to a whole number of cycles per loop, and its
    /// tremolo completes a whole number of cycles too.
    func drone(freq: Double, amp: Float, table: Wavetable, tremoloCycles: Int, tremoloDepth: Double,
               phase: Double) -> [Float] {
        let cycles = max(1, (freq * seconds).rounded())
        var out = table.render(freq: cycles / seconds, count: length, phase: phase)
        let w = 2 * Double.pi * Double(tremoloCycles) / Double(length)
        DSP.transform(&out) { i, v in
            v * amp * Float(1 - tremoloDepth * (0.5 + 0.5 * sin(w * Double(i))))
        }
        return out
    }

    /// Wind / room tone: bandpassed noise whose center drifts with an LFO that completes
    /// a whole number of cycles per loop. Processed circularly, so it loops seamlessly.
    func wind(seed: UInt64, center: Double, octaves: Double, cycles: Int, q: Double, amp: Float) -> [Float] {
        var rng = SeededRandom(seed: seed)
        let noise = rng.noise(length)
        var f = SVF(cutoff: center, q: q)
        let w = 2 * Double.pi * Double(cycles) / Double(length)
        return DSP.circular(noise) { i, x in
            if i & 31 == 0 { f.set(cutoff: center * pow(2, octaves * sin(w * Double(i))), q: q) }
            return f.process(x).band * amp
        }
    }

    nonisolated struct Effects {
        var echoBeats: Double
        var echoFeedback: Float
        var echoCutoff: Double
        var echoReturn: Float
        var reverbSize: Float
        var reverbDamping: Float
        var reverbReturn: Float
        /// Lowpass on the LFO bus: cutoff sweeps `lfoMin...lfoMax` over `lfoCycles` per loop.
        var lfoMin: Double = 400
        var lfoMax: Double = 2000
        var lfoCycles: Int = 2
        var lfoQ: Double = 1
        var lfoReverbSend: Float = 0.25
    }

    /// Runs the LFO filter, delay and reverb circularly, sums everything and normalizes
    /// to `rmsDB` with a -6 dBFS peak ceiling.
    func render(_ fx: Effects, rmsDB: Float) -> [Float] {
        var out = dry
        var reverbIn = reverbSend

        if !lfoBus.isEmpty {
            var f = SVF(cutoff: fx.lfoMin, q: fx.lfoQ)
            let ratio = fx.lfoMax / fx.lfoMin
            let w = 2 * Double.pi * Double(fx.lfoCycles) / Double(length)
            let filtered = DSP.circular(lfoBus) { i, x in
                if i & 31 == 0 {
                    // Closed (dark) at the loop point, open mid-cycle.
                    f.set(cutoff: fx.lfoMin * pow(ratio, 0.5 - 0.5 * cos(w * Double(i))), q: fx.lfoQ)
                }
                return f.process(x).low
            }
            DSP.mix(filtered, into: &out, at: 0)
            DSP.mix(filtered, into: &reverbIn, at: 0, gain: fx.lfoReverbSend)
        }

        var echo = Echo(delaySamples: Int((fx.echoBeats * samplesPerBeat).rounded()),
                        feedback: fx.echoFeedback, cutoff: fx.echoCutoff)
        _ = echo.process(echoSend)
        let echoed = echo.process(echoSend)
        DSP.mix(echoed, into: &out, at: 0, gain: fx.echoReturn)
        DSP.mix(echoed, into: &reverbIn, at: 0, gain: fx.echoReturn * 0.6)

        var reverb = Reverb(size: fx.reverbSize, damping: fx.reverbDamping)
        _ = reverb.process(reverbIn)
        DSP.mix(reverb.process(reverbIn), into: &out, at: 0, gain: fx.reverbReturn)

        DSP.transform(&out) { _, v in v.isFinite ? v : 0 }
        let rms = DSP.rms(out), pk = DSP.peak(out)
        if rms > 1e-9, pk > 1e-9 {
            DSP.scale(&out, by: min(DSP.dbToGain(rmsDB) / rms, DSP.dbToGain(-6) / pk))
        }
        return out
    }
}

nonisolated enum MusicSynth {
    nonisolated struct Spec {
        var bpm: Double
        var beatsPerBar: Int
        var bars: Int
    }

    /// Tempos are chosen so a beat is a whole number of samples at 44.1 kHz
    /// (44100·60 is divisible by 60, 70, 80 and 100), so the loop ends exactly on a bar.
    static func spec(_ mood: MusicMood) -> Spec {
        switch mood {
        case .menuDay: return Spec(bpm: 80, beatsPerBar: 4, bars: 4)      // 12.0 s
        case .menuNight: return Spec(bpm: 70, beatsPerBar: 4, bars: 4)    // 13.7 s
        case .flightDay: return Spec(bpm: 100, beatsPerBar: 4, bars: 6)   // 14.4 s
        case .flightNight: return Spec(bpm: 100, beatsPerBar: 4, bars: 6) // 14.4 s
        case .airport: return Spec(bpm: 60, beatsPerBar: 4, bars: 4)      // 16.0 s
        }
    }

    /// Renders one seamless loop. Pure and thread-safe; call it off the main thread.
    static func render(_ mood: MusicMood) -> [Float] {
        switch mood {
        case .menuDay: return menuDay()
        case .menuNight: return menuNight()
        case .flightDay: return flightDay()
        case .flightNight: return flightNight()
        case .airport: return airport()
        }
    }

    // MARK: menuDay: F major, 80 BPM, warm pad + slow pentatonic pluck melody

    private static func menuDay() -> [Float] {
        let spec = spec(.menuDay)
        var mix = LoopMix(spec: spec)
        var rng = SeededRandom(seed: 0xDA1)
        let beat = 60 / spec.bpm
        // Fmaj7 | Dm7 | B♭maj7 | Cadd9
        let chords = [[53, 57, 60, 64], [50, 53, 57, 60], [46, 50, 53, 57], [48, 55, 62, 64]]
        for (bar, chord) in chords.enumerated() {
            let b = Double(bar * 4)
            for m in chord {
                let p = Voice.pad(freq: DSP.hz(m), amp: 0.10, attack: 0.9, hold: 4 * beat - 0.9,
                                  release: 1.6, table: .warm, detuneCents: 6, voices: 3,
                                  cutoff: 2200, rng: &rng)
                mix.add(p, beat: b - 0.15, dry: 0.8, reverb: 0.35)
            }
            let bass = Voice.pluck(freq: DSP.hz(chord[0] - 12), amp: 0.22, decay: 0.9, brightness: 0.1,
                                   length: 3.2)
            mix.add(bass, beat: b, dry: 1, reverb: 0.1)
        }
        // F major pentatonic (F G A C D), sparse and slow.
        let melody: [(Double, Int)] = [
            (0, 69), (1, 72), (2, 77), (3.5, 74),
            (4.5, 72), (5.5, 69), (6, 74), (7, 72),
            (8, 74), (9, 77), (10.5, 79), (11, 77),
            (12, 72), (13.5, 74), (14, 69), (15, 67),
        ]
        for (b, m) in melody {
            let vel = Float(0.85 + 0.15 * rng.unit())
            let note = Voice.pluck(freq: DSP.hz(m), amp: 0.32 * vel, decay: 0.55, brightness: 0.45)
            mix.add(note, beat: b + 0.012 * Double(rng.bipolar()), dry: 1, echo: 0.35, reverb: 0.3)
        }
        return mix.render(.init(echoBeats: 1.5, echoFeedback: 0.32, echoCutoff: 2800, echoReturn: 0.6,
                                reverbSize: 0.8, reverbDamping: 0.35, reverbReturn: 0.8), rmsDB: -20)
    }

    // MARK: menuNight: D minor / whole-tone, 70 BPM, dark detuned pad, sparse bells

    private static func menuNight() -> [Float] {
        let spec = spec(.menuNight)
        var mix = LoopMix(spec: spec)
        var rng = SeededRandom(seed: 0x4E1647)
        let beat = 60 / spec.bpm
        // Dm(add9) for two bars, then B♭ with an E on top (the tritone makes it uneasy).
        let chords = [[50, 53, 57, 64], [46, 53, 57, 64]]
        for (half, chord) in chords.enumerated() {
            for m in chord {
                let p = Voice.pad(freq: DSP.hz(m), amp: 0.11, attack: 2.2, hold: 8 * beat - 2.2,
                                  release: 2.8, table: .dark, detuneCents: 14, voices: 3,
                                  cutoff: 900, rng: &rng)
                mix.add(p, beat: Double(half * 8) - 0.4, dry: 0.7, reverb: 0.5)
            }
        }
        mix.add(mix.drone(freq: DSP.hz(38), amp: 0.07, table: .dark, tremoloCycles: 2, tremoloDepth: 0.35,
                          phase: 0), beat: 0, dry: 1, reverb: 0.2)
        mix.add(mix.drone(freq: DSP.hz(45) * 1.003, amp: 0.035, table: .dark, tremoloCycles: 3,
                          tremoloDepth: 0.5, phase: 0.37), beat: 0, dry: 1, reverb: 0.2)
        mix.add(mix.wind(seed: 0x817D, center: 420, octaves: 0.8, cycles: 1, q: 1.4, amp: 0.05),
                beat: 0, dry: 1, reverb: 0.4)
        // Sparse bells: whole-tone from D plus the minor third and fifth.
        let pool = [74, 76, 78, 80, 82, 84, 77, 81]
        var last = -1
        for base in [1.0, 3.5, 6.0, 9.0, 11.5, 14.0] {
            var m = pool[rng.int(pool.count)]
            while m == last { m = pool[rng.int(pool.count)] }
            last = m
            let at = base + (rng.unit() < 0.5 ? 0 : 0.5)
            let bell = Voice.fmBell(freq: DSP.hz(m), amp: Float(rng.range(0.13, 0.19)), decay: 1.6,
                                    ratio: 1.41, index: 1.6, indexDecay: 0.5)
            mix.add(bell, beat: at, dry: 0.35, echo: 0.5, reverb: 0.6)
        }
        return mix.render(.init(echoBeats: 1.5, echoFeedback: 0.42, echoCutoff: 1800, echoReturn: 0.7,
                                reverbSize: 0.9, reverbDamping: 0.5, reverbReturn: 0.9), rmsDB: -22)
    }

    // MARK: flightDay: C major, 100 BPM, pluck arpeggio + soft pulse

    private static func flightDay() -> [Float] {
        let spec = spec(.flightDay)
        var mix = LoopMix(spec: spec)
        var rng = SeededRandom(seed: 0xF1D4)
        let beat = 60 / spec.bpm
        // C | G/B | Am | F | C | G
        let chords = [[60, 64, 67], [59, 62, 67], [57, 60, 64], [53, 57, 60], [60, 64, 67], [55, 59, 62]]
        let bass = [48, 47, 45, 41, 48, 43]
        let patterns = [[0, 1, 2, 3, 4, 3, 2, 1], [0, 2, 1, 3, 2, 4, 3, 5], [0, 1, 2, 4, 3, 2, 1, 2]]
        for (bar, chord) in chords.enumerated() {
            let b0 = Double(bar * 4)
            for m in chord {
                let p = Voice.pad(freq: DSP.hz(m), amp: 0.055, attack: 0.25, hold: 4 * beat - 0.25,
                                  release: 0.6, table: .warm, detuneCents: 7, voices: 3,
                                  cutoff: 2600, rng: &rng)
                mix.add(p, beat: b0, dry: 0.6, reverb: 0.3)
            }
            // The arpeggio sits an octave above the pad, which is what makes this mood
            // brighter than the menu. The top three tones are played a little softer.
            let tones = chord.map { $0 + 12 } + chord.map { $0 + 24 }
            let pattern = patterns[bar == 5 ? 1 : rng.int(patterns.count)]
            for (step, idx) in pattern.enumerated() {
                let accent: Double = step == 0 ? 0.30 : (step % 2 == 0 ? 0.24 : 0.2)
                let amp = (accent + 0.03 * rng.unit()) * (idx >= 3 ? 0.75 : 1)
                let note = Voice.pluck(freq: DSP.hz(tones[idx]), amp: Float(amp),
                                       decay: 0.35, brightness: idx >= 3 ? 0.45 : 0.6)
                mix.add(note, beat: b0 + 0.5 * Double(step), dry: 1, echo: 0.25, reverb: 0.18)
            }
            for (k, at) in [0.0, 2.0].enumerated() {
                let m = k == 0 ? bass[bar] : bass[bar] + (bar % 2 == 0 ? 7 : 0)
                let note = Voice.pluck(freq: DSP.hz(m), amp: 0.27, decay: 0.6, brightness: 0.35, length: 1.4)
                mix.add(note, beat: b0 + at, dry: 1, reverb: 0.08)
            }
            for q in 0..<4 {
                let pulse = Voice.thump(from: 120, to: 55, sweep: 0.03, decay: 0.07,
                                        amp: q % 2 == 0 ? 0.2 : 0.15, overtone: 0.4)
                mix.add(pulse, beat: b0 + Double(q), dry: 1)
                let shaker = Voice.tick(seed: UInt64(bar * 4 + q), amp: q % 2 == 1 ? 0.08 : 0.055,
                                        decay: 0.012, cutoff: 5000)
                mix.add(shaker, beat: b0 + Double(q) + 0.5, dry: 1, reverb: 0.2)
            }
        }
        return mix.render(.init(echoBeats: 0.75, echoFeedback: 0.28, echoCutoff: 3500, echoReturn: 0.6,
                                reverbSize: 0.72, reverbDamping: 0.4, reverbReturn: 0.7), rmsDB: -19)
    }

    // MARK: flightNight: A minor, 100 BPM, low drone, LFO filter, distant echoing bells

    private static func flightNight() -> [Float] {
        let spec = spec(.flightNight)
        var mix = LoopMix(spec: spec)
        var rng = SeededRandom(seed: 0xF1A7)
        let beat = 60 / spec.bpm
        // Am | F | Dm | E | Am | B♭ (the Neapolitan B♭ leans back into Am, eerily)
        let chords = [[57, 60, 64], [53, 57, 60], [50, 53, 57], [52, 56, 59], [57, 60, 64], [50, 53, 58]]
        let patterns = [[0, 1, 2, 3, 2, 1, 2, 4], [0, 2, 1, 2, 3, 2, 1, 2], [0, 1, 2, 1, 3, 2, 4, 2]]
        // The A2 drone is the one a phone speaker can play; A1 underneath is for headphones.
        mix.add(mix.drone(freq: DSP.hz(33), amp: 0.05, table: .dark, tremoloCycles: 3, tremoloDepth: 0.2,
                          phase: 0), beat: 0, dry: 0, lfo: 1)
        mix.add(mix.drone(freq: DSP.hz(45) * 1.002, amp: 0.07, table: .dark, tremoloCycles: 2,
                          tremoloDepth: 0.4, phase: 0.21), beat: 0, dry: 0, lfo: 1)
        mix.add(mix.wind(seed: 0x9E1, center: 600, octaves: 0.7, cycles: 1, q: 1.6, amp: 0.035),
                beat: 0, dry: 1, reverb: 0.3)
        for (bar, chord) in chords.enumerated() {
            let b0 = Double(bar * 4)
            for m in chord {
                let p = Voice.pad(freq: DSP.hz(m - 12), amp: 0.07, attack: 0.6, hold: 4 * beat - 0.6,
                                  release: 1.0, table: .dark, detuneCents: 10, voices: 3,
                                  cutoff: 1400, rng: &rng)
                mix.add(p, beat: b0, dry: 0, lfo: 1)
            }
            let tones = chord + chord.map { $0 + 12 }
            let pattern = patterns[rng.int(patterns.count)]
            for (step, idx) in pattern.enumerated() where step == 0 || rng.unit() > 0.18 {
                let amp = Float((step == 0 ? 0.27 : 0.2) + 0.03 * rng.unit())
                let note = Voice.pluck(freq: DSP.hz(tones[idx]), amp: amp, decay: 0.4, brightness: 0.3)
                mix.add(note, beat: b0 + 0.5 * Double(step), dry: 0, echo: 0.12, lfo: 1)
            }
            for q in 0..<4 {
                let pulse = Voice.thump(from: 100, to: 50, sweep: 0.04, decay: 0.09,
                                        amp: q == 0 ? 0.2 : 0.15, overtone: 0.35)
                mix.add(pulse, beat: b0 + Double(q), dry: 1)
            }
        }
        // Distant bells: mostly echo and reverb, very little dry signal.
        let pool = [69, 72, 75, 76, 81]
        for base in [2.0, 7.0, 11.5, 16.0, 20.5] {
            let m = pool[rng.int(pool.count)]
            let bell = Voice.fmBell(freq: DSP.hz(m), amp: Float(rng.range(0.09, 0.12)), decay: 1.4,
                                    ratio: 1.41, index: 1.2, indexDecay: 0.4)
            mix.add(bell, beat: base + (rng.unit() < 0.5 ? 0 : 0.5), dry: 0.15, echo: 0.6, reverb: 0.55)
        }
        return mix.render(.init(echoBeats: 0.75, echoFeedback: 0.55, echoCutoff: 1500, echoReturn: 0.8,
                                reverbSize: 0.88, reverbDamping: 0.55, reverbReturn: 0.85,
                                lfoMin: 320, lfoMax: 1900, lfoCycles: 2, lfoQ: 1.1, lfoReverbSend: 0.25),
                          rmsDB: -20)
    }

    // MARK: airport: ambient terminal pad, room tone, an occasional chime

    private static func airport() -> [Float] {
        let spec = spec(.airport)
        var mix = LoopMix(spec: spec)
        var rng = SeededRandom(seed: 0xA1270)
        let beat = 60 / spec.bpm
        // Cmaj9 for two bars, Fmaj9 for two bars.
        let chords = [[48, 55, 59, 62, 64], [41, 57, 60, 64, 67]]
        for (half, chord) in chords.enumerated() {
            for m in chord {
                let p = Voice.pad(freq: DSP.hz(m), amp: 0.08, attack: 2.5, hold: 8 * beat - 2.5,
                                  release: 3.0, table: .warm, detuneCents: 5, voices: 3,
                                  cutoff: 1600, rng: &rng)
                mix.add(p, beat: Double(half * 8) - 0.5, dry: 0.6, reverb: 0.5)
            }
        }
        mix.add(mix.wind(seed: 0xA1, center: 380, octaves: 0.4, cycles: 1, q: 0.6, amp: 0.035),
                beat: 0, dry: 1, reverb: 0.2)
        // The terminal chime: C5, E5, G5.
        for (i, m) in [72, 76, 79].enumerated() {
            mix.add(Voice.vibes(freq: DSP.hz(m), amp: 0.18, decay: 1.2), beat: 9 + 0.55 * Double(i),
                    dry: 0.6, reverb: 0.5)
        }
        mix.add(Voice.fmBell(freq: DSP.hz(88), amp: 0.05, decay: 1.2, ratio: 3.5, index: 0.4, indexDecay: 0.1),
                beat: 2.5, dry: 0.5, echo: 0.4, reverb: 0.6)
        mix.add(Voice.fmBell(freq: DSP.hz(86), amp: 0.045, decay: 1.2, ratio: 3.5, index: 0.4, indexDecay: 0.1),
                beat: 13, dry: 0.5, echo: 0.4, reverb: 0.6)
        return mix.render(.init(echoBeats: 1.5, echoFeedback: 0.35, echoCutoff: 2500, echoReturn: 0.5,
                                reverbSize: 0.88, reverbDamping: 0.45, reverbReturn: 0.9), rmsDB: -23)
    }
}
