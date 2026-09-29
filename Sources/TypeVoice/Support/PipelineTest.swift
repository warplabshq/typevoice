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
        if files.first == "dict" {
            // This Mac's own Dictionary against phrases the way the model tends to hear them.
            // `--test dict "some sentence" …` checks your own; without arguments, the built-in set.
            let terms = JSONFile.load([String].self, from: Paths.dictionary) ?? []
            let given = Array(files.dropFirst())
            let cases = given.isEmpty ? ["We should use Warp Labs for this.", "Everyone knows about Whisperflow.", "We copied Whisper Plow and made Type Voice.",
                                         "and type voice does that", "Mass send to VDI customers.", "Their name is saved as vid AI in loops.",
                                         "Check uploads on Bidai.", "No response from Hicksfield.", "Should I use Higgs field?",
                                         "Gobind told me about R2.", "Harsh Gobind said hi.", "Tube magic is active.", "Use Alfred for this.",
                                         "It's already done.", "The idea is good.", "I have a video. I like it."] : given
            _ = English.isWord("warm")   // the word list loads once at launch in the app
            let t0 = ContinuousClock.now
            for c in cases { print("\(c)\n  → \(Vocabulary.apply(terms, to: c))") }
            print(String(format: "%d terms, %.2f ms per sentence", terms.count, Double((ContinuousClock.now - t0) / .microseconds(1)) / 1000 / Double(cases.count)))
            exit(0)
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
        if files.first == "grammar" {
            let cases: [(String, String)] = [
                // Questions said flat.
                ("Can you send me the file.", "Can you send me the file?"),
                ("Is the button still gonna be there after I buy it.", "Is the button still gonna be there after I buy it?"),
                ("Are you saying they can be stacked.", "Are you saying they can be stacked?"),
                ("Should I make it sound cool.", "Should I make it sound cool?"),
                ("Do you have access to loops.", "Do you have access to loops?"),
                ("What is left for us to ship this.", "What is left for us to ship this?"),
                ("How about we make it free.", "How about we make it free?"),
                ("Why did the build fail.", "Why did the build fail?"),
                ("What time is it.", "What time is it?"),
                ("How long does it take.", "How long does it take?"),
                ("Who wants coffee.", "Who wants coffee?"),
                ("Did that work.", "Did that work?"),
                ("Has anyone tried it.", "Has anyone tried it?"),
                ("We ship Friday, right.", "We ship Friday, right?"),
                ("So, can you check the logs.", "So, can you check the logs?"),
                ("Hey Alfred, what do you know about me.", "Hey Alfred, what do you know about me?"),
                ("Okay and what about the other one.", "Okay and what about the other one?"),
                ("Any update on the invoice.", "Any update on the invoice?"),
                ("What if we do a mass send.", "What if we do a mass send?"),
                ("I fixed it. Can you test it now", "I fixed it. Can you test it now?"),
                ("Is it ready.\nShip it.", "Is it ready?\nShip it."),
                ("Can we meet at 9 a.m. tomorrow.", "Can we meet at 9 a.m. tomorrow?"),
                // Orders and statements keep their full stop.
                ("Do a UI audit, especially UX.", "Do a UI audit, especially UX."),
                ("Do it.", "Do it."), ("Do this in parallel as well.", "Do this in parallel as well."),
                ("Don't show this in the changelog please.", "Don't show this in the changelog please."),
                ("Don't have to touch the code base.", "Don't have to touch the code base."),
                ("Do keep in mind that it broke.", "Do keep in mind that it broke."),
                ("What you say should be offline.", "What you say should be offline."),
                ("What's new can just be called changelog.", "What's new can just be called changelog."),
                ("When OpenClaw had come out, everyone built a wrapper.", "When OpenClaw had come out, everyone built a wrapper."),
                ("Why did we create a new bucket is what I don't understand.", "Why did we create a new bucket is what I don't understand."),
                ("What is up, so I was thinking about something.", "What is up, so I was thinking about something."),
                ("Have a good day.", "Have a good day."), ("Can't wait to see it.", "Can't wait to see it."),
                ("Will Smith said hi.", "Will Smith said hi."), ("May the best one win.", "May the best one win."),
                ("I wonder if it works.", "I wonder if it works."), ("Let me know if you can come.", "Let me know if you can come."),
                ("What a day.", "What a day."), ("What matters is speed.", "What matters is speed."),
                ("Did that already.", "Did that already."), ("Was thinking we could ship.", "Was thinking we could ship."),
                ("How it works is simple.", "How it works is simple."), ("Wow, that's great!", "Wow, that's great!"),
                ("Check typevoice.ai and tell me.", "Check typevoice.ai and tell me."),
                // Hyphens: before what they describe, and a few always.
                ("It's a one time purchase.", "It's a one-time purchase."), ("We met one time, very simple.", "We met one time, very simple."),
                ("We need real time updates.", "We need real-time updates."), ("It syncs in real time.", "It syncs in real time."),
                ("It's an open source app.", "It's an open-source app."), ("The app is open source.", "The app is open source."),
                ("Think long term.", "Think long term."), ("Our long term plan is simple.", "Our long-term plan is simple."),
                ("Start a 7 day trial.", "Start a 7-day trial."), ("It took 7 days.", "It took 7 days."), ("Book a 30 minute call.", "Book a 30-minute call."),
                ("I'll follow up tomorrow.", "I'll follow up tomorrow."), ("Send a follow up email.", "Send a follow-up email."),
                ("Do a product mock up of this.", "Do a product mock-up of this."), ("It's self hosted.", "It's self-hosted."),
                ("He's my co founder.", "He's my co-founder."), ("The wifi is down.", "The Wi-Fi is down."), ("Is the doc up to date?", "Is the doc up to date?"),
                ("We keep up to date docs.", "We keep up-to-date docs."), ("It's end to end encrypted.", "It's end-to-end encrypted."),
                ("A 3 step setup.", "A 3-step setup."), ("You must have access.", "You must have access."), ("It is a must have feature.", "It is a must-have feature."), ("Start with one page actually.", "Start with one page actually."), ("Do something high quality here.", "Do something high quality here."), ("I work on the front end.", "I work on the front end."), ("We need a front end developer.", "We need a front-end developer."),
                // Capitals.
                ("i think i'm done.", "I think I'm done."), ("it works. then we ship.", "It works. Then we ship."),
                ("see you at 9 a.m. tomorrow.", "See you at 9 a.m. tomorrow."), ("that is, i.e. the second one.", "That is, i.e. the second one."),
            ]
            var failures = 0
            let t0 = ContinuousClock.now
            for (input, expected) in cases {
                let got = Cleaner.capitalizeFirst(Grammar.apply(input, style: Style()))
                let ok = got == expected; if !ok { failures += 1 }
                print("\(ok ? "ok " : "FAIL") \(input.replacingOccurrences(of: "\n", with: "⏎")) → \(got.replacingOccurrences(of: "\n", with: "⏎"))\(ok ? "" : "   (wanted \(expected))")")
            }
            print(String(format: "%.3f ms per sentence", Double((ContinuousClock.now - t0) / .microseconds(1)) / 1000 / Double(cases.count)))
            print(failures == 0 ? "all good" : "\(failures) failed")
            exit(failures == 0 ? 0 : 1)
        }
        if files.first == "fillers", files.dropFirst().first == "log" {
            // Every raw dictation in this Mac's log, before/after the filler pass only.
            let logURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/TypeVoice/typevoice.log")
            let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            var n = 0, changed = 0
            for line in log.split(separator: "\n") {
                guard let r = line.range(of: #"\] raw\([\d.]+s\): "#, options: .regularExpression) else { continue }
                let raw = String(line[r.upperBound...]); n += 1
                let before = Cleaner.clean(raw, style: Style(removeFillers: false)), after = Cleaner.clean(raw, style: Style())
                let baseline = Cleaner.clean(raw, style: Style(removeFillers: false)).replacingOccurrences(of: #"(?i)(?<![\w'])(?:u+m+|u+h+|uhm+|h+m+|er+m*|ah+|eh+)(?![\w'])[,.]?\s*"#, with: "", options: .regularExpression)
                if after != baseline && after != before.replacingOccurrences(of: "  ", with: " ") { changed += 1; print("WAS: \(baseline)\nNOW: \(after)\n") }
            }
            print("\(n) dictations, \(changed) changed by the filler pass")
            exit(0)
        }
        if files.first == "fillers" {
            let cases: [(String, String)] = [
                ("Alright, so accordingly I'm waiting for you know I'm waiting for a relevant schedule today.", "Alright, so accordingly I'm waiting for a relevant schedule today."),
                ("Some people feel the stock footage is simply not simply not that accurate.", "Some people feel the stock footage is simply not that accurate."),
                ("And obviously we can use re we can use recent.", "And obviously we can use recent."),
                ("I had this chat which I mis mistakenly archived.", "I had this chat which I mistakenly archived."),
                ("It kind of you know it kind of makes me feel more stuck.", "It kind of makes me feel more stuck."),
                ("Maybe we should just be a white background thing, I don't know.", "Maybe we should just be a white background thing."),
                ("A lot of visual stuff, animations, I don't know, a lot of tasteful stuff.", "A lot of visual stuff, animations, a lot of tasteful stuff."),
                ("We should tell the user that they can, you know, put out the cross button.", "We should tell the user that they can put out the cross button."),
                ("Anyway, let's ship it. I mean, it's fine.", "let's ship it. it's fine."),
                ("Also like maybe short form can be more consistent.", "Also maybe short form can be more consistent."),
                ("That's done, anyways.", "That's done."),
                // Meaning stays.
                ("Do you know the answer?", "Do you know the answer?"), ("If you know the way, lead.", "If you know the way, lead."),
                ("What I mean is simple.", "What I mean is simple."), ("I like it a lot.", "I like it a lot."),
                ("You know what, let's go.", "You know what, let's go."), ("I don't know the answer.", "I don't know the answer."),
                ("It looks like a bird.", "It looks like a bird."), ("very very good", "very very good"), ("no no no", "no no no"),
                ("Things you know are true.", "Things you know are true."), ("People that you know the most.", "People that you know the most."),
                ("I'll re read it.", "I'll re read it."), ("I want it as soon as possible, and I know I don't.", "I want it as soon as possible, and I know I don't."),
                ("Inside the app the license page should show.", "Inside the app the license page should show."), ("I know you know my plans.", "I know you know my plans."),
                ("Be fully safe, as safe as possible.", "Be fully safe, as safe as possible."), ("What you sh what you say matters.", "What you say matters."),
                ("Ship one point zero point one live.", "Ship one point zero point one live."), ("Use emails plus SEO plus Reddit.", "Use emails plus SEO plus Reddit."),
                ("Our revenue t revenue grew.", "Our revenue grew."), ("maybe FAQ, maybe docs", "maybe FAQ, maybe docs"), ("I have to host a server, mini server somewhere.", "I have to host a server, mini server somewhere."), ("old numbers and bad sch schedule", "old numbers and bad schedule"), ("From your o older audits.", "From your older audits."), ("Check my last few trans the transcriptions.", "Check my last few the transcriptions."), ("I bought a trans am car.", "I bought a trans am car."), ("Go with plan B backup.", "Go with plan B backup."), ("I have a apple.", "I have a apple."), ("Go to today's list.", "Go to today's list."), ("We ship. We ship fast.", "We ship. We ship fast."),
            ]
            _ = English.isWord("warm")
            var failures = 0
            let t0 = ContinuousClock.now
            for (input, expected) in cases {
                let got = Disfluency.apply(input)
                let ok = got == expected; if !ok { failures += 1 }
                print("\(ok ? "ok " : "FAIL") \(input) → \(got)\(ok ? "" : "   (wanted \(expected))")")
            }
            print(String(format: "%.3f ms per sentence", Double((ContinuousClock.now - t0) / .microseconds(1)) / 1000 / Double(cases.count)))
            print(failures == 0 ? "all good" : "\(failures) failed")
            exit(failures == 0 ? 0 : 1)
        }
        if files.first == "micchange" {
            // Record 3 s; at 1.5 s the audio setup "changes" (engine stops). Capture must continue.
            let r = AudioRecorder()
            var interrupted = false
            r.onInterrupted = { interrupted = true }
            do { try r.start() } catch { print("start failed"); exit(1) }
            Thread.sleep(forTimeInterval: 1.5)
            r.simulateConfigurationChange()
            Thread.sleep(forTimeInterval: 1.5)
            let rec = r.stop()
            print(String(format: "recorded %.2f s (wanted ≈3), interrupted: %@", rec.seconds, interrupted ? "yes" : "no"))
            exit(rec.seconds > 2.5 && !interrupted ? 0 : 1)
        }
        if files.first == "micidle", let secs = files.dropFirst().first.flatMap(Double.init) {
            // Prewarm, wait like an idle Mac, then open the mic and say how long each step took.
            let r = AudioRecorder()
            r.prewarm(); print("prewarmed; waiting \(Int(secs)) s"); fflush(stdout)
            Thread.sleep(forTimeInterval: secs)
            let t0 = ContinuousClock.now
            do { try r.start() } catch { print("start failed: \(error.localizedDescription)"); exit(1) }
            print(String(format: "after %.0f s idle: mic opened in %.0f ms", secs, Double((ContinuousClock.now - t0) / .microseconds(1)) / 1000)); fflush(stdout)
            _ = r.stop(); exit(0)
        }
        if files.first == "mic" {
            // Two seconds from the microphone through AudioRecorder (TYPEVOICE_FORCE_QUEUE=1 for
            // the input-only fallback). Prints what came back.
            let r = AudioRecorder()
            let tw = ContinuousClock.now
            r.prewarm()
            print(String(format: "prewarm %.0f ms (off the key press)", Double((ContinuousClock.now - tw) / .microseconds(1)) / 1000))
            let t0 = ContinuousClock.now
            do { try r.start() } catch { print("start failed: \(error.localizedDescription)"); exit(1) }
            print(String(format: "mic opened in %.0f ms", Double((ContinuousClock.now - t0) / .microseconds(1)) / 1000))
            Thread.sleep(forTimeInterval: 2.0)
            let rec = r.stop()
            print(String(format: "recorded %.2f s, %d samples, peak %.4f", rec.seconds, rec.samples.count, rec.peak))
            // A second dictation, the way the app does it: prewarm after the session, then start.
            Thread.sleep(forTimeInterval: 0.5)
            r.prewarm(); Thread.sleep(forTimeInterval: 1.0)
            let t2 = ContinuousClock.now
            do { try r.start() } catch { print("second start failed: \(error.localizedDescription)"); exit(1) }
            print(String(format: "second session: mic opened in %.0f ms", Double((ContinuousClock.now - t2) / .microseconds(1)) / 1000))
            Thread.sleep(forTimeInterval: 1.0)
            let rec2 = r.stop()
            print(String(format: "recorded %.2f s, peak %.4f", rec2.seconds, rec2.peak))
            exit(rec.samples.count > 16_000 ? 0 : 1)
        }
        if files.first == "replay" {
            // Every dictation in this Mac's log (raw text + which words the model doubted), run
            // through today's text pipeline, printed where the result differs from the raw.
            // Reads the log at runtime; nothing personal lives in the repo.
            Packs.Index.warm()
            while Packs.Index.current == nil { Thread.sleep(forTimeInterval: 0.05) }
            let terms = JSONFile.load([String].self, from: Paths.dictionary) ?? []
            let logURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/TypeVoice/typevoice.log")
            let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            var raw: String?, changed = 0, total = 0
            for line in log.split(separator: "\n") {
                if let r = line.range(of: #"\] raw\([\d.]+s\): "#, options: .regularExpression) { raw = String(line[r.upperBound...]); continue }
                guard let text = raw, let r = line.range(of: "] doubtful: ") ?? line.range(of: "] focused ") else { continue }
                var doubt: [String: Float] = [:]
                if line.contains("] doubtful: ") {
                    for d in line[r.upperBound...].split(separator: " ") {
                        if let o = d.lastIndex(of: "("), let v = Float(d[d.index(after: o)...].dropLast()) { doubt[String(d[..<o])] = v }
                    }
                }
                raw = nil; total += 1
                var words = text.split(separator: " ").map { Structure.Word(text: String($0), gapBefore: 0, confidence: doubt[String($0)] ?? 0.99) }
                if !Prefs.packs.isEmpty { words = Packs.correct(words, dictionary: terms) }
                var out = Cleaner.clean(words.map(\.text).joined(separator: " "))
                if Prefs.voiceCommands { out = Structure.commands(out) }
                if Prefs.numbersAsDigits { out = Numbers.apply(out) }
                out = Spoken.apply(out)
                out = Vocabulary.apply(terms, to: out)
                out = Grammar.apply(out, style: .current)
                if out.replacingOccurrences(of: "\n", with: " ") != text { changed += 1; print("RAW: \(text)\nNOW: \(out.replacingOccurrences(of: "\n", with: " ⏎ "))\n") }
            }
            print("\(total) dictations, \(changed) changed")
            exit(0)
        }
        if files.first == "packs" {
            // Heard → expected, with every word marked uncertain (0.5) unless suffixed with a bang (confident).
            // Pack terms come from the built-in packs; a term missing there fails loudly.
            let cases: [(String, String)] = [
                ("rip grep", "ripgrep"), ("neo vim", "Neovim"), ("tail scale", "Tailscale"), ("supa base", "Supabase"),
                ("ver sell", "Vercel"), ("ray cast", "Raycast"), ("ff mpeg", "ffmpeg"), ("tera form", "terraform"), ("compose io", "Composio"), ("kube cuttle", "kubectl"),
                ("the meeting!", "the meeting!"), ("ripped", "ripped"), ("really", "really"), ("sell it", "sell it"),
                // Heard right already: a household name, a pack term, a possessive, your own Dictionary.
                ("through Reddit,", "through Reddit,"), ("Reddit.", "Reddit."), ("Neovide", "Neovide"), ("Reddit's", "Reddit's"),
                ("Priyam", "Priyam"),
                // Real words that merely sound like a pack term stay as they were said.
                ("Games.", "Games."), ("g games", "g games"), ("cat", "cat"), ("cat.", "cat."), ("just", "just"),
                ("time,", "time,"), ("think.", "think."), ("native", "native"), ("way. And", "way. And"),
                ("dodo payments.", "Dodo Payments."), ("Cloudfair", "Cloudflare"),
                ("model.com", "model.com"), ("modal.com.", "modal.com."), ("Mac mini", "Mac mini"), ("hyperframes,", "hyperframes,"), ("vinsic", "vinsic"), ("kinda", "kinda"), ("anytime", "anytime"), ("codecs", "codecs"), ("Cloudflare pages.", "Cloudflare pages."), ("late-night", "late-night"),
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
                let got = Packs.correct(words, dictionary: ["Priyam"]).map(\.text).joined(separator: " ")
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
                // From real dictations that came out joined.
                ("I don't know. So, what now?", "I don't know. So, what now?"),
                ("whatever you want. It's fine.", "whatever you want. It's fine."),
                ("just be chill about it. One time, very simple", "just be chill about it. One time, very simple"),
                ("we love games. So, pick one.", "we love games. So, pick one."),
                ("Check typevoice.com today", "Check typevoice.com today"),
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
                      "the year two thousand and twenty", "twenty percent off", "about a thousand words", "it's the third time", "I need it by the fifth of March", "we have three options", "It took two and a half hours", "Version two point five is out", "My number is nine eight seven six five four three two one zero", "Meet at half past two", "There were a hundred people", "one video of Matt. And I think two is plenty", "Testing one three.", "Testing one two three.", "First, we ship. Second, we post.", "It is the first time and the second try.", "Can you 1st off tell me", "March first is the launch", "the second of May", "call me at two thirty pm", "one oh five", "we have twenty first century problems"] {
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
                cleaned = Grammar.apply(cleaned, style: .current)
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
