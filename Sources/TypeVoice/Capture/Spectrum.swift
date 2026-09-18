import Accelerate
import Foundation

/// Turns raw microphone samples into a handful of log-spaced band energies,
/// normalised so the bars stay lively at any mic gain. ~86 updates/s, trivial CPU.
final class Spectrum {
    let bands: Int
    private let n = 1024
    private let log2n: vDSP_Length = 10
    private let setup: FFTSetup
    private var ring: [Float]
    private var ringPos = 0
    private var window: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var mags: [Float]
    private var edges: [Int] = []
    private var ceiling: [Float]      // slow-adapting per-band max (AGC)
    private var smoothed: [Float]
    private let sampleRate: Double

    init(bands: Int = 10, sampleRate: Double) {
        self.bands = bands
        self.sampleRate = sampleRate
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        ring = [Float](repeating: 0, count: n)
        window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        real = [Float](repeating: 0, count: n / 2)
        imag = [Float](repeating: 0, count: n / 2)
        mags = [Float](repeating: 0, count: n / 2)
        ceiling = [Float](repeating: 1e-3, count: bands)
        smoothed = [Float](repeating: 0, count: bands)
        // Log-spaced band edges from 90 Hz to 7 kHz, where voice lives.
        let lo = 90.0, hi = min(7000.0, sampleRate / 2 - 1)
        let binHz = sampleRate / Double(n)
        edges = (0...bands).map { i in
            let f = lo * pow(hi / lo, Double(i) / Double(bands))
            return max(1, min(n / 2 - 1, Int(f / binHz)))
        }
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Feed a buffer; returns band energies 0…1 (already smoothed), or nil if not enough data yet.
    func analyze(_ samples: UnsafePointer<Float>, count: Int, gate: Float) -> [Float] {
        // Append to ring.
        for i in 0..<count { ring[ringPos] = samples[i]; ringPos = (ringPos + 1) % n }

        // Windowed copy in time order.
        var frame = [Float](repeating: 0, count: n)
        for i in 0..<n { frame[i] = ring[(ringPos + i) % n] }
        vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(n))

        // Real FFT (packed).
        real.withUnsafeMutableBufferPointer { r in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: im.baseAddress!)
                frame.withUnsafeBufferPointer { f in
                    f.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { c in
                        vDSP_ctoz(c, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
            }
        }

        var out = [Float](repeating: 0, count: bands)
        for b in 0..<bands {
            let a = edges[b], z = max(edges[b + 1], a + 1)
            var sum: Float = 0
            for k in a..<z { sum += mags[k] }
            let mag = (sum / Float(z - a)).squareRoot()
            // Adaptive ceiling: rises instantly, decays slowly, floor keeps silence flat.
            ceiling[b] = max(mag, ceiling[b] * 0.995, 2e-3)
            var v = mag / ceiling[b]                      // 0…1 relative to recent loudness
            v = pow(v, 0.8) * gate                        // gate by overall level so silence is calm
            // Fast attack, slower release.
            smoothed[b] = v > smoothed[b] ? smoothed[b] + (v - smoothed[b]) * 0.5 : smoothed[b] * 0.8
            out[b] = smoothed[b]
        }
        return out
    }
}
