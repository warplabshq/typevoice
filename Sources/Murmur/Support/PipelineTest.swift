import AVFoundation
import FluidAudio
import Foundation

/// `Murmur --test file.wav [file2.wav …]`: runs the text pipeline on audio files
/// and prints each stage. Exits when done. Used by Tools/wer.py.
enum PipelineTest {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--test"), i + 1 < args.count else { return false }
        let files = Array(args[(i + 1)...])
        if files.first == "vocab" {
            vocabSelfTest(); exit(0)
        }
        if files.first == "itn" {
            let n = TextNormalizer.shared
            for c in ["the launch is in twenty twenty four", "I was born in nineteen ninety nine", "we need twenty four hours",
                      "call me at two thirty pm", "it costs five dollars and fifty cents", "chapter twenty two, page one hundred and five",
                      "send it to priyam at gmail dot com", "one two three four five", "I have two cats and one dog",
                      "the year two thousand and twenty", "twenty percent off", "about a thousand words", "it's the third time", "I need it by the fifth of March", "we have three options", "It took two and a half hours", "Version two point five is out", "My number is nine eight seven six five four three two one zero", "Meet at half past two", "There were a hundred people"] {
                print("\(c)\n  → \(Numbers.apply(c))")
            }
            exit(0)
        }
        Task.detached {
            let code = await run(files: files)
            exit(code)
        }
        return true
    }

    private static func run(files: [String]) async -> Int32 {
        let transcriber = ParakeetTranscriber()
        let smart = await MainActor.run { SmartCleaner() }
        let t0 = ContinuousClock.now
        do {
            try await transcriber.warm { _ in }
        } catch {
            print("warm failed: \(error)"); return 2
        }
        print("warm: \(Int((ContinuousClock.now - t0).ms)) ms")
        await MainActor.run { smart.prewarm() }
        let reason = await MainActor.run { smart.unavailableReason }
        print("smart cleaner: \(reason ?? "available")")

        for f in files {
            do {
                let samples = try load16k(URL(fileURLWithPath: f))
                let t1 = ContinuousClock.now
                let raw = try await transcriber.transcribe(samples)
                let asrMs = Int((ContinuousClock.now - t1).ms)
                var cleaned = Cleaner.clean(raw)
                if Prefs.numbersAsDigits { cleaned = Numbers.apply(cleaned) }
                let t2 = ContinuousClock.now
                let smartOut = await smart.clean(cleaned)
                let smartMs = Int((ContinuousClock.now - t2).ms)
                print("file:   \(f) (\(String(format: "%.1f", Double(samples.count) / 16000))s)")
                print("raw:    \(raw)   [\(asrMs) ms]")
                print("clean:  \(cleaned)")
                print("smart:  \(smartOut ?? "<nil>")   [\(smartMs) ms]")
                print("Transcription: \(smartOut ?? cleaned)")
            } catch {
                print("file:   \(f)\nerror:  \(error)")
            }
        }
        return 0
    }

    private static func vocabSelfTest() {
        let terms = ["VidAI", "Priyam", "Wispr Flow", "Kubernetes", "Timenite"]
        let cases = [
            "I was talking to the team at vid AI about the export flow.",
            "Send it to pre-um and the video AI folks, and cc Wisper flow.",
            "we deployed to cuber netties last night, timenight is up.",
            "Vidai looks good. Video looks good too. AI is fine.",
            "Priya said hi.",
        ]
        for c in cases { print("\(c)\n  → \(Vocabulary.apply(terms, to: c))") }
    }

    private static func load16k(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let conv = AVAudioConverter(from: file.processingFormat, to: out)!
        let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inBuf)
        let cap = AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 64
        let outBuf = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: cap)!
        var done = false
        var err: NSError?
        _ = conv.convert(to: outBuf, error: &err) { _, status in
            if done { status.pointee = .endOfStream; return nil }
            done = true; status.pointee = .haveData; return inBuf
        }
        if let err { throw err }
        return Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength)))
    }
}
