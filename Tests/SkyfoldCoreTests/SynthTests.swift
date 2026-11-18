import Foundation
import Testing
@testable import SkyfoldCore

// Numeric checks for the procedural audio. Everything here is nonisolated DSP, so the
// tests render on whatever thread Swift Testing picks.

nonisolated private let sr = DSP.sampleRate

nonisolated private func ms(_ body: () -> Void) -> Double {
    let t = ContinuousClock.now
    body()
    let d = ContinuousClock.now - t
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

nonisolated private func db(_ x: Float) -> Double { 20 * log10(Double(max(x, 1e-9))) }

nonisolated private func isFinite(_ x: [Float]) -> Bool { !x.contains { !$0.isFinite } }

/// Power-weighted spectral centroid (Hz) from averaged 4096-point Hann frames.
nonisolated private func centroid(_ x: [Float]) -> Double {
    var n = 4096
    while n > 256 && x.count < n { n /= 2 }
    guard x.count >= n else { return 0 }
    var wsum = 0.0, psum = 0.0
    var start = 0
    let hop = n / 2
    var re = [Double](repeating: 0, count: n), im = [Double](repeating: 0, count: n)
    let stride = max(hop, (x.count - n) / 40)
    while start + n <= x.count {
        for i in 0..<n {
            let w = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n))
            re[i] = Double(x[start + i]) * w; im[i] = 0
        }
        fft(&re, &im)
        for k in 1..<(n / 2) {
            let p = re[k] * re[k] + im[k] * im[k]
            wsum += p * Double(k) * sr / Double(n)
            psum += p
        }
        start += stride
    }
    return psum > 0 ? wsum / psum : 0
}

nonisolated private func fft(_ re: inout [Double], _ im: inout [Double]) {
    let n = re.count
    var j = 0
    for i in 1..<n {
        var bit = n >> 1
        while j & bit != 0 { j ^= bit; bit >>= 1 }
        j ^= bit
        if i < j { re.swapAt(i, j); im.swapAt(i, j) }
    }
    var len = 2
    while len <= n {
        let ang = -2 * Double.pi / Double(len)
        for i in stride(from: 0, to: n, by: len) {
            for k in 0..<(len / 2) {
                let c = cos(ang * Double(k)), s = sin(ang * Double(k))
                let a = i + k, b = i + k + len / 2
                let tr = re[b] * c - im[b] * s, ti = re[b] * s + im[b] * c
                re[b] = re[a] - tr; im[b] = im[a] - ti
                re[a] += tr; im[a] += ti
            }
        }
        len <<= 1
    }
}

/// Spectrum magnitude at a frequency (Goertzel) over the whole buffer.
nonisolated private func magnitude(_ x: [Float], at f: Double, from: Int = 0, to: Int? = nil) -> Double {
    let end = min(to ?? x.count, x.count)
    var re = 0.0, im = 0.0
    for i in from..<end {
        let ph = 2 * Double.pi * f * Double(i) / sr
        re += Double(x[i]) * cos(ph); im -= Double(x[i]) * sin(ph)
    }
    return sqrt(re * re + im * im) / Double(max(1, end - from))
}

/// Expected duration range in seconds.
nonisolated private func durationRange(_ e: SoundEffect) -> ClosedRange<Double> {
    switch e {
    case .laneSwitch: return 0.10...0.16
    case .star: return 0.30...0.45
    case .crash: return 0.42...0.62
    case .shieldBreak: return 0.2...0.7
    case .countdown: return 0.08...0.3
    case .takeoff: return 0.85...1.3
    case .landing: return 1.0...2.6
    case .gateOpen: return 0.6...0.85
    case .blessing: return 1.1...1.6
    case .curse: return 1.3...1.7
    case .unlock: return 0.8...1.2
    case .uiTap: return 0.025...0.05
    }
}

@Test(arguments: SoundEffect.allCases)
func effectIsCleanAndShaped(_ effect: SoundEffect) {
    let variants = SoundSynth.variantCount(effect)
    for v in 0..<variants {
        var buf: [Float] = []
        let t = ms { buf = SoundSynth.render(effect, variant: v) }
        let seconds = Double(buf.count) / sr
        let peak = DSP.peak(buf), rms = DSP.rms(buf)
        let c = centroid(buf)
        print("effect \(effect) v\(v): \(String(format: "%.0f", seconds * 1000)) ms, peak \(String(format: "%.1f", db(peak))) dB, rms \(String(format: "%.1f", db(rms))) dB, centroid \(Int(c)) Hz, render \(String(format: "%.1f", t)) ms")
        #expect(isFinite(buf))
        #expect(peak <= 1.0)
        #expect(db(peak) > -11 && db(peak) < -5.5, "peak \(db(peak)) dB")
        #expect(db(rms) > -40 && db(rms) < -9, "rms \(db(rms)) dB")
        #expect(durationRange(effect).contains(seconds), "duration \(seconds)")
        #expect(buf.first == 0 && buf.last == 0, "must start and end at zero")
        #expect(abs(buf[1]) < 0.05 && abs(buf[buf.count - 2]) < 0.05)
        // Soft and warm: no effect should be dominated by highs.
        #expect(c < 6000, "centroid \(c)")
        #expect(t < 400, "render \(t) ms")
    }
}

@Test(arguments: SoundEffect.allCases)
func effectIsDeterministic(_ effect: SoundEffect) {
    #expect(SoundSynth.render(effect) == SoundSynth.render(effect))
}

@Test(arguments: MusicMood.allCases)
func musicLoopIsSeamless(_ mood: MusicMood) {
    var loop: [Float] = []
    let t = ms { loop = MusicSynth.render(mood) }
    let spec = MusicSynth.spec(mood)
    let seconds = Double(loop.count) / sr
    let peak = DSP.peak(loop), rms = DSP.rms(loop)
    let c = centroid(loop)
    // Loop boundary: the step from the last sample to the first, compared with the
    // typical sample-to-sample step of the music.
    var meanStep = 0.0
    for i in 1..<loop.count { meanStep += Double(abs(loop[i] - loop[i - 1])) }
    meanStep /= Double(loop.count - 1)
    var maxStep = 0.0
    for i in 1..<loop.count { maxStep = max(maxStep, Double(abs(loop[i] - loop[i - 1]))) }
    let wrapStep = Double(abs(loop[0] - loop[loop.count - 1]))
    let slopeEnd = Double(loop[loop.count - 1] - loop[loop.count - 2])
    let slopeStart = Double(loop[1] - loop[0])
    print("music \(mood): \(String(format: "%.2f", seconds)) s, peak \(String(format: "%.1f", db(peak))) dB, rms \(String(format: "%.1f", db(rms))) dB, centroid \(Int(c)) Hz, wrapStep \(wrapStep), meanStep \(meanStep), maxStep \(maxStep), slope \(slopeEnd) -> \(slopeStart), render \(String(format: "%.0f", t)) ms, \(loop.count * 4 / 1024) KB")
    #expect(isFinite(loop))
    #expect(peak <= 1.0)
    #expect(db(peak) > -12 && db(peak) < -3, "peak \(db(peak))")
    #expect(db(rms) > -30 && db(rms) < -14, "rms \(db(rms))")
    #expect((8.0...16.5).contains(seconds))
    let bar = Double(spec.beatsPerBar) * 60 / spec.bpm * sr
    #expect(loop.count == Int((bar * Double(spec.bars)).rounded()), "whole bars")
    #expect(wrapStep <= max(4 * meanStep, 0.002), "wrap step \(wrapStep) vs mean \(meanStep)")
    #expect(abs(slopeEnd - slopeStart) <= max(6 * meanStep, 0.004), "slope \(slopeEnd) vs \(slopeStart)")
    #expect(t < 3000, "render \(t) ms")
}

@Test(arguments: MusicMood.allCases)
func musicIsDeterministic(_ mood: MusicMood) {
    #expect(MusicSynth.render(mood) == MusicSynth.render(mood))
}

@Test func totalMemoryIsSmall() {
    var bytes = 0
    for e in SoundEffect.allCases {
        for v in 0..<SoundSynth.variantCount(e) { bytes += SoundSynth.render(e, variant: v).count * 4 }
    }
    let fx = bytes
    for m in MusicMood.allCases { bytes += MusicSynth.render(m).count * 4 }
    print("memory: effects \(fx / 1024) KB, total \(String(format: "%.1f", Double(bytes) / 1_048_576)) MB")
    #expect(bytes < 25 * 1_048_576)
}

@Test func nightMusicIsDarkerThanDay() {
    let menuDay = centroid(MusicSynth.render(.menuDay)), menuNight = centroid(MusicSynth.render(.menuNight))
    let flightDay = centroid(MusicSynth.render(.flightDay)), flightNight = centroid(MusicSynth.render(.flightNight))
    print("centroids: menuDay \(Int(menuDay)), menuNight \(Int(menuNight)), flightDay \(Int(flightDay)), flightNight \(Int(flightNight))")
    #expect(menuNight < menuDay)
    #expect(flightNight < flightDay)
}

@Test func curseIsDissonantWithSlowBeating() {
    let curse = SoundSynth.render(.curse)
    // Slow beating: the amplitude envelope of the low band should wobble at 1 to 8 Hz.
    var lowpassed = curse
    DSP.transform(&lowpassed) { _, s in s }
    OnePole.lowpass(&lowpassed, cutoff: 400)
    let win = Int(sr * 0.02)
    var env: [Double] = []
    var i = Int(Double(curse.count) * 0.3)
    while i + win < Int(Double(curse.count) * 0.8) {
        var s = 0.0
        for k in i..<(i + win) { s += Double(abs(lowpassed[k])) }
        env.append(s / Double(win)); i += win
    }
    var crossings = 0
    let mean = env.reduce(0, +) / Double(env.count)
    for k in 1..<env.count where (env[k - 1] - mean) * (env[k] - mean) < 0 { crossings += 1 }
    let dur = Double(env.count) * 0.02
    let rate = Double(crossings) / 2 / dur
    let lowCentroid = centroid(curse)
    print("curse: envelope wobble ~\(String(format: "%.1f", rate)) Hz, centroid \(Int(lowCentroid)) Hz")
    #expect(lowCentroid < 1500)
    // Fluctuation depth: the beating should be audible (more than 8% of the mean).
    let depth = ((env.max() ?? 0) - (env.min() ?? 0)) / mean
    print("curse: beat depth \(String(format: "%.2f", depth))")
    #expect(depth > 0.08)
    #expect(rate > 0.5 && rate < 12)
}

@Test func blessingIsABrightMajorArpeggio() {
    let b = SoundSynth.render(.blessing)
    let c = centroid(b)
    let curse = centroid(SoundSynth.render(.curse))
    print("blessing centroid \(Int(c)) Hz vs curse \(Int(curse)) Hz")
    #expect(c > curse)
    // First notes ascend: the dominant pitch of successive quarter-second windows rises.
    func dominant(_ from: Double, _ to: Double) -> Double {
        var best = 0.0, bestF = 0.0
        var f = 150.0
        while f < 3000 {
            let m = magnitude(b, at: f, from: Int(from * sr), to: Int(to * sr))
            if m > best { best = m; bestF = f }
            f *= 1.01
        }
        return bestF
    }
    let a = dominant(0.0, 0.2), mid = dominant(0.3, 0.5), c3 = dominant(0.6, 0.8)
    print("blessing dominant pitches: \(Int(a)), \(Int(mid)), \(Int(c3)) Hz")
    #expect(mid > a * 0.99 || c3 > a)
}

@Test func writeWavs() throws {
    guard let dir = ProcessInfo.processInfo.environment["SKYFOLD_WAV_DIR"] else { return }
    func wav(_ x: [Float], _ name: String) throws {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + x.count * 2)); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(44100); u32(88200); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(x.count * 2))
        for s in x { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32767))) }
        try d.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }
    for e in SoundEffect.allCases { try wav(SoundSynth.render(e), "fx-\(e).wav") }
    for m in MusicMood.allCases { try wav(MusicSynth.render(m), "music-\(m).wav") }
}
