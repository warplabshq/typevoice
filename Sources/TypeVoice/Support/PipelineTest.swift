import AVFoundation
import FluidAudio
import Foundation

/// `TypeVoice --test file.wav [file2.wav …]`: runs the text pipeline on audio files
/// and prints each stage. Exits when done. Used by Tools/wer.py.
enum PipelineTest {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--test"), i + 1 < args.count else { return false }
        let files = Array(args[(i + 1)...])
        if files.first == "vocab" {
            vocabSelfTest(); exit(0)
        }
        if files.first == "structure" {
            for c in ["Here's the plan. Number one, ship the build. Number two, write the changelog. Number three, post it.",
                      "Things to buy, bullet milk, bullet eggs, bullet point bread.",
                      "Thanks for the update. New paragraph. I'll review it tomorrow, new line, Priyam.",
                      "The number one priority is speed.",
                      "Step one open settings, step two, pick a shortcut.",
                      "Grocery list: milk, eggs, bread and butter.",
                      "Grocery list, milk, two kilos of tomatoes, onions, coriander, and paneer.",
                      "Bullet. Milk. Bullet, eggs. Bullet bread.",
                      "Shopping list bullet milk, eggs, bread, and some butter.",
                      "Call Sam, Rohan, and Priya about the launch.",
                      "I like coffee, books and rain.",
                      "First, we ship the build. Second, we write the changelog. Third, we post it and go home.",
                      "First of all, thanks for coming. It means a lot.",
                      "Things I need from you: the invoice, the signed contract, and the timeline.",
                      "Packing list, passport, charger, headphones, a jacket.",
                      // From real dictations that stayed flat.
                      "Hey, so I want three things to save today. So first lights, second camera and third glasses.",
                      "Hey, add these things to my list. Eggs, basket, bear, some Jack Daniels, sugar, and that's all.",
                      "Two things: first the lights and second the camera. Thanks.",
                      "The first thing is speed, the second thing is privacy, and the third thing is price.",
                      "Can you get these things? Milk, eggs, and bread. I'll be home late.",
                      // Must stay as they are.
                      "When I'm talking about three items, it should always be in a bullet point, you know.",
                      "I hate bullet points in emails.",
                      "At first I was unsure, but the second time it worked.",
                      "First of all, thanks. Second, the build is green.",
                      "I need three things done before Friday and I'm not sure we'll make it.",
                      "I invited three people, Sam, Rohan and Priya, to the launch.",
                      "Let me tell you some things, the launch went well, the numbers are up and the team is happy.",
                      "Quick update on the launch.\n\nThings to buy: cake, candles and balloons.\n\nSee you at six."] {
                print("\(c)\n  →\n\(Structure.commands(c).split(separator: "\n", omittingEmptySubsequences: false).map { "    |" + $0 }.joined(separator: "\n"))")
            }
            exit(0)
        }
        if files.first == "packs" {
            // Heard → expected, with every word marked uncertain (0.5) unless suffixed with a bang (confident).
            // Pack terms come from the built-in packs; a term missing there fails loudly.
            let cases: [(String, String)] = [
                ("rip grep", "ripgrep"), ("neo vim", "Neovim"), ("tail scale", "Tailscale"), ("supa base", "Supabase"),
                ("ver sell", "Vercel"), ("ray cast", "Raycast"), ("ff mpeg", "ffmpeg"), ("tera form", "terraform"), ("compose io", "Composio"), ("kube cuttle", "kubectl"),
                ("the meeting!", "the meeting!"), ("ripped", "ripped"), ("really", "really"), ("sell it", "sell it"),
            ]
            Packs.Index.warm(ids: Packs.all().map(\.id))   // every pack, without touching the preference
            while Packs.Index.current == nil { Thread.sleep(forTimeInterval: 0.05) }
            print("index: \(Packs.Index.current!.count) terms")
            var failures = 0
            for (heard, expected) in cases {
                let words = heard.split(separator: " ").map { w -> Structure.Word in
                    let confident = w.hasSuffix("!")
                    return Structure.Word(text: String(w), gapBefore: 0, confidence: confident ? 0.99 : 0.5)
                }
                let got = Packs.correct(words).map(\.text).joined(separator: " ")
                let ok = got == expected
                if !ok { failures += 1 }
                print("\(ok ? "ok " : "FAIL") \(heard) → \(got)\(ok ? "" : "   (wanted \(expected))")")
            }
            // Cost on a long dictation with a few doubtful words.
            let long = Array(repeating: "the quick brown fox jumps over the lazy dog near the river bank today", count: 6).joined(separator: " ")
            var many = long.split(separator: " ").enumerated().map { Structure.Word(text: String($0.element), gapBefore: 0, confidence: $0.offset % 9 == 0 ? 0.4 : 0.98) }
            let t0 = ContinuousClock.now
            for _ in 0..<20 { many = Packs.correct(many) }
            print("packs.correct on \(many.count) words: \(String(format: "%.2f", Double((ContinuousClock.now - t0) / .milliseconds(1)) / 20)) ms")
            print(failures == 0 ? "all good" : "\(failures) failed")
            exit(failures == 0 ? 0 : 1)
        }
        if files.first == "spoken" {
            let cases: [(String, String)] = [
                ("go to typevoice dot ai", "go to typevoice.ai"),
                ("it's on logs dot so", "it's on logs.so"),
                ("send it to jane at example dot com", "send it to jane@example.com"),
                ("the docs are at typevoice dot ai slash support", "the docs are at typevoice.ai/support"),
                ("we ship to bbc dot co dot uk", "we ship to bbc.co.uk"),
                ("Typevoice. Ai is live", "Typevoice.ai is live"),
                ("Check the logs. So we should ship.", "Check the logs. So we should ship."),
                ("It is hosted on Cloudflare. It works.", "It is hosted on Cloudflare. It works."),
                ("Try Composio. Dev tools are great.", "Try Composio. Dev tools are great."), ("it lives on logs. So.", "it lives on logs.so."), ("Get it at typevoice. Ai today", "Get it at typevoice.ai today"),
                ("I was at home. So was she.", "I was at home. So was she."),
            ]
            var failures = 0
            for (input, expected) in cases {
                let got = Spoken.apply(input)
                let ok = got == expected; if !ok { failures += 1 }
                print("\(ok ? "ok " : "FAIL") \(input) → \(got)\(ok ? "" : "   (wanted \(expected))")")
            }
            print(failures == 0 ? "all good" : "\(failures) failed")
            exit(failures == 0 ? 0 : 1)
        }
        if files.first == "itn" {
            let n = TextNormalizer.shared
            for c in ["the launch is in twenty twenty four", "I was born in nineteen ninety nine", "we need twenty four hours",
                      "call me at two thirty pm", "it costs five dollars and fifty cents", "chapter twenty two, page one hundred and five",
                      "send it to jane at example dot com", "one two three four five", "I have two cats and one dog",
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
                let transcript = try await transcriber.transcribe(samples)
                var raw = transcript.text
                if ProcessInfo.processInfo.environment["TYPEVOICE_TOKENS"] == "1" {
                    for t in transcript.tokens { print(String(format: "  %6.2f-%6.2f  %@", t.start, t.end, t.token)) }
                }
                if !transcript.tokens.isEmpty {
                    var words = Structure.words(text: raw, tokens: transcript.tokens)
                    if !Prefs.packs.isEmpty { words = Packs.correct(words) }
                    raw = Prefs.pauseParagraphs ? Structure.paragraphs(words, pause: 1.0) : words.map(\.text).joined(separator: " ")
                }
                let asrMs = Int((ContinuousClock.now - t1).ms)
                var cleaned = Cleaner.clean(raw)
                if Prefs.voiceCommands { cleaned = Structure.commands(cleaned) }
                if Prefs.numbersAsDigits { cleaned = Numbers.apply(cleaned) }
                cleaned = Spoken.apply(cleaned)
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
        let terms = ["VidAI", "Priyam", "Wispr Flow", "Kubernetes", "Timenite", "Logs.so"]
        let cases = [
            "I was talking to the team at vid AI about the export flow.",
            "Send it to pre-um and the video AI folks, and cc Wisper flow.",
            "we deployed to cuber netties last night, timenight is up.",
            "Vidai looks good. Video looks good too. AI is fine.",
            "Priya said hi.",
            "Check logs. So and tell me what you see.",
            "Open logs dot so in the browser.",
        ]
        for c in cases { print("\(c)\n  → \(Vocabulary.apply(terms, to: c))") }
    }

    static func load16k(_ url: URL) throws -> [Float] {
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
