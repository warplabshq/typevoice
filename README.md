# Murmur

Hold 🌐, talk, release. Clean text lands at your cursor. Everything runs on this Mac.

- **Speech:** NVIDIA Parakeet TDT 0.6B v2 on the Neural Engine (via FluidAudio).
- **Cleanup:** Apple's on-device model, with a hard 1.2 s deadline. Never blocks insertion.
- **UI:** a Liquid Glass pill that appears at the bottom of the screen you're typing on while you
  hold the key, shows the sentence as it's typed, and vanishes. Nothing is on screen otherwise.
- **App:** menu bar only. The main window has Summary (time saved, history), Dictionary
  (your spellings, e.g. VidAI), Style, Settings, License and Privacy. No telemetry, no accounts.
- **Triggers:** hold to talk (double-tap keeps listening) or tap to start / tap to stop.
  Settings › Microphone picks the input and has a level test.
- **Voice notes (opt-in):** Settings › Voice notes › Keep recordings saves each dictation as a
  small AAC file too; drag the chip after speaking, or a Summary row, into any chat.
- **Rebrand:** the display name comes from `CFBundleDisplayName` in `Packaging/Info.plist`
  (`Brand.name` in code); the bundle ID lives in `project.yml`, `Packaging/Info.plist` and
  the Makefile's signing requirement; the icon is rendered by `Tools/icon.swift`.

## Build

```bash
make run          # release build → build/Murmur.app, then launches it
make debug        # same, debug config
MURMUR_DEBUG=1 build/Murmur.app/Contents/MacOS/Murmur | Tools/latency.sh
build/Murmur.app/Contents/MacOS/Murmur --test clip.wav   # run the text pipeline on a file
build/Murmur.app/Contents/MacOS/Murmur --test vocab      # dictionary matcher self-test
```

Requires macOS 26+, Xcode 26+ (Swift 6). First launch downloads ~600 MB of CoreML models
and compiles them for this Mac; that happens once.

### Signing

`make` signs ad-hoc with a stable, identifier-based designated requirement, so macOS keeps the
Accessibility and Microphone grants across rebuilds. If Accessibility ever looks on but Murmur
doesn't react: System Settings › Privacy & Security › Accessibility, flip Murmur off and on,
then relaunch.

## App Store

Murmur is built for the Mac App Store: sandboxed, hardened runtime, purchases through
StoreKit via RevenueCat. Text is inserted by pasting into the frontmost app (the sandbox rules
out the Accessibility API), which needs the Accessibility permission for the key tap and the
synthetic ⌘V, plus the Microphone permission.

### One-time setup (your side)

1. **App Store Connect:** create the app (bundle ID `com.priyam.murmur`, or change it in
   `project.yml` and `Packaging/Info.plist`). Category Productivity.
2. **In-app purchase:** create the products (e.g. a non-consumable "Murmur Pro", or a
   subscription with a 3-day free trial if you prefer StoreKit-enforced trials). Complete the
   Paid Apps agreement and tax/banking in App Store Connect.
3. **RevenueCat:** new project → add the macOS app → enter the App Store Connect
   In-App Purchase key (or shared secret) → create the entitlement **`pro`** and attach the
   products → create an offering with those packages. Copy the **public SDK key** (`appl_…`)
   into `Licensing.apiKey` in `Sources/Murmur/Support/Licensing.swift`.
4. **Signing:** put your Team ID in `project.yml` (`DEVELOPMENT_TEAM`) and
   `Packaging/ExportOptions.plist` (`teamID`). Xcode with your Apple ID signed in handles the
   provisioning automatically.
5. **Review notes:** say that Murmur is a dictation utility that needs Accessibility to notice
   the hold-to-talk key and to paste the recognised text into the frontmost app, and that all
   speech recognition runs on-device. Mention that the speech model (~450 MB) downloads on
   first launch. Provide a demo video: reviewers can't hold Fn through a screenshot.
6. **Privacy nutrition label:** "Data Not Collected". Nothing leaves the Mac except purchase
   validation.

### Shipping a build

```bash
make project     # regenerate Murmur.xcodeproj from project.yml (XcodeGen)
make archive     # archive + upload to App Store Connect
```

Or open `Murmur.xcodeproj` in Xcode → Product › Archive → Distribute App. Bump
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` for each build.
TestFlight for Mac works for beta testers.

### Local development

`make run` still produces a sandboxed, ad-hoc-signed app for day-to-day use. Its data lives
in `~/Library/Containers/com.priyam.murmur/Data/Library/Application Support/Murmur`.

## Layout

```
Sources/Murmur/
  App/      entry point, AppState, DictationController (the pipeline)
  Capture/  Fn/shortcut monitor, microphone → 16 kHz, FFT band analysis for the waveform
  Engine/   Transcriber protocol, Parakeet implementation
  Text/     deterministic Cleaner, SmartCleaner (Foundation Models)
  Insert/   Accessibility insertion with paste fallback
  HUD/      the glass pill: window, controller, voice-reactive waveform, type-on text
  Store/    history and dictionary (plain JSON in ~/Library/Application Support/Murmur)
  UI/       main window (history, dictionary, style, settings, privacy), onboarding, menu bar
Tools/      latency.sh, wer.py
```
