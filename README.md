# TypeVoice

Local dictation for Mac. Hold a key, talk, release: clean, punctuated text lands at your
cursor in any app. Everything runs on the Mac — no account, no server, no telemetry.

Sold on the Mac App Store (free for three days, then one purchase, no subscription).
The source is here under the Apache 2.0 licence so you can see exactly what it does with
your voice, build it yourself, or improve it. See `TRADEMARKS.md` about the name and icon.

## How it works

- **Speech:** NVIDIA Parakeet TDT 0.6B v2 on the Neural Engine, via [FluidAudio](https://github.com/FluidInference/FluidAudio).
  Downloaded once (about 450 MB) on first launch. English, every accent.
- **Cleanup:** fillers, stutters, numbers, lists and paragraphs by rule; then Apple's on-device
  model when Apple Intelligence is available, under a hard 1.2 s deadline that never blocks
  insertion.
- **Insertion:** the text is pasted into the frontmost app (the sandbox forbids the
  Accessibility API for direct insertion); the clipboard is restored right after.
- **UI:** a pill that appears while you hold the key on the screen you're typing on, shows the
  sentence, and retreats. Menu bar only; the main window has Summary (time saved, history),
  Dictionary, Style, Settings, License and Privacy.
- **Triggers:** hold a key, a chord (⌥⌘), or a key combo; double-tap keeps listening; or
  tap to start and tap to stop.
- **Voice notes (opt-in):** Settings › Indicator › Offer the audio after each dictation
  keeps a small AAC file per dictation; drag the chip on the pill, or a Summary row, into
  any chat.

Layout: `Sources/TypeVoice/` — `Capture/` (hotkey tap, audio, spectrum), `Engine/`
(transcriber), `Text/` (cleaner, numbers, structure, vocabulary, smart cleanup),
`Insert/`, `HUD/` (the pill), `UI/` (main window, onboarding), `Store/` (SQLite history,
dictionary, recordings), `Support/` (prefs, licensing, logging).

Rebranding: the display name comes from `CFBundleDisplayName` in `Packaging/Info.plist`
(`Brand.name` in code); the bundle ID lives in `project.yml`, `Packaging/Info.plist` and the
Makefile's signing requirement; the icon is rendered by `Tools/icon.swift`.

## Build

macOS 26 or later on Apple silicon, Xcode 27.

```bash
make run          # release build → build/TypeVoice.app, then launches it
make debug        # same, debug config
make project      # Xcode project via XcodeGen, if you prefer Xcode
TYPEVOICE_DEBUG=1 build/TypeVoice.app/Contents/MacOS/TypeVoice | Tools/latency.sh
build/TypeVoice.app/Contents/MacOS/TypeVoice --test clip.wav   # run the text pipeline on a file
build/TypeVoice.app/Contents/MacOS/TypeVoice --test vocab      # dictionary matcher self-test
```

The first `make` creates `Sources/TypeVoice/Support/Secrets.swift` from `Secrets.example.swift`
(git-ignored; holds the RevenueCat key, placeholder is fine for building).

### Signing

`make` signs ad-hoc with a stable, identifier-based designated requirement, so macOS keeps the
Accessibility and Microphone grants across rebuilds. If Accessibility ever looks on but TypeVoice
doesn't react: System Settings › Privacy & Security › Accessibility, flip TypeVoice off and on,
then relaunch.

## App Store

TypeVoice is built for the Mac App Store: sandboxed, hardened runtime, purchases through
StoreKit via RevenueCat. Text is inserted by pasting into the frontmost app (the sandbox rules
out the Accessibility API), which needs the Accessibility permission for the key tap and the
synthetic ⌘V, plus the Microphone permission.

### One-time setup (your side)

1. **App Store Connect:** create the app (bundle ID `com.priyamventures.typevoice`, or change it in
   `project.yml` and `Packaging/Info.plist`). Category Productivity.
2. **In-app purchase:** create the products (e.g. a non-consumable "TypeVoice Pro", or a
   subscription with a 3-day free trial if you prefer StoreKit-enforced trials). Complete the
   Paid Apps agreement and tax/banking in App Store Connect.
3. **RevenueCat:** new project → add the macOS app → enter the App Store Connect
   In-App Purchase key (or shared secret) → create the entitlement **`pro`** and attach the
   products → create an offering with those packages. Copy the **public SDK key** (`appl_…`)
   into `Licensing.apiKey` in `Sources/TypeVoice/Support/Licensing.swift`.
4. **Signing:** put your Team ID in `project.yml` (`DEVELOPMENT_TEAM`) and
   `Packaging/ExportOptions.plist` (`teamID`). Xcode with your Apple ID signed in handles the
   provisioning automatically.
5. **Review notes:** say that TypeVoice is a dictation utility that needs Accessibility to notice
   the hold-to-talk key and to paste the recognised text into the frontmost app, and that all
   speech recognition runs on-device. Mention that the speech model (~450 MB) downloads on
   first launch. Provide a demo video: reviewers can't hold Fn through a screenshot.
6. **Privacy nutrition label:** "Data Not Collected". Nothing leaves the Mac except purchase
   validation.

### Website and legal pages

The landing page plus Support, Privacy Policy, Terms of Use and the EULA (with Apple's
required minimum terms) live in their own repository, `typevoice-site` (locally
`../TypeVoiceSite`). Everything brand-specific is in its `site.js`. Deploy that
repository anywhere static, then put the real host into `Brand.website` in
`Sources/TypeVoice/Support/Brand.swift` so the in-app links (Privacy tab › Legal, License tab,
Settings › Help, menu bar › Help) point at it. App Store Connect wants the Privacy Policy URL
and Support URL; the EULA can be linked or pasted.

### Shipping a build

```bash
make project     # regenerate TypeVoice.xcodeproj from project.yml (XcodeGen)
make archive     # archive + upload to App Store Connect
```

Or open `TypeVoice.xcodeproj` in Xcode → Product › Archive → Distribute App. Bump
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` for each build.
TestFlight for Mac works for beta testers.

### Local development

`make run` still produces a sandboxed, ad-hoc-signed app for day-to-day use. Its data lives
in `~/Library/Containers/com.priyamventures.typevoice/Data/Library/Application Support/TypeVoice`.

## Layout

```
Sources/TypeVoice/
  App/      entry point, AppState, DictationController (the pipeline)
  Capture/  Fn/shortcut monitor, microphone → 16 kHz, FFT band analysis for the waveform
  Engine/   Transcriber protocol, Parakeet implementation
  Text/     deterministic Cleaner, SmartCleaner (Foundation Models)
  Insert/   Accessibility insertion with paste fallback
  HUD/      the glass pill: window, controller, voice-reactive waveform, type-on text
  Store/    history and dictionary (plain JSON in ~/Library/Application Support/TypeVoice)
  UI/       main window (history, dictionary, style, settings, privacy), onboarding, menu bar
Tools/      latency.sh, wer.py
```
