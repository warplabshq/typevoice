# Murmur

Hold 🌐, talk, release. Clean text lands at your cursor. Everything runs on this Mac.

- **Speech:** NVIDIA Parakeet TDT 0.6B v2 on the Neural Engine (via FluidAudio).
- **Cleanup:** Apple's on-device model, with a hard 1.2 s deadline. Never blocks insertion.
- **UI:** a Liquid Glass pill that appears at the bottom of the screen you're typing on while you
  hold the key, shows the sentence as it's typed, and vanishes. Nothing is on screen otherwise.
- **App:** menu bar only. The main window has History, Dictionary (your spellings, e.g. VidAI),
  Style (casing, punctuation, tone), Settings and Privacy. No telemetry, no accounts.

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

### Signing (do this once)

macOS ties the Accessibility grant to the app's code signature. An ad-hoc signature
changes on every build, so the grant silently stops applying after each rebuild.
Give the build a stable identity once and the problem goes away:

1. Open **Keychain Access** → menu **Keychain Access › Certificate Assistant › Create a Certificate…**
2. Name: `Murmur Dev` · Identity Type: Self Signed Root · Certificate Type: **Code Signing** → Create.
3. `make run` now picks it up automatically (or pass `SIGN_ID="Murmur Dev"`).

If you'd rather use your Apple ID: Xcode › Settings › Accounts › add it › Manage Certificates › **+ Apple Development**. `make` prefers that automatically.

If Accessibility ever looks on but Murmur doesn't react: System Settings › Privacy & Security › Accessibility, flip Murmur off and on, then relaunch.

## Trial and licensing

Three-day trial from first launch (the date is kept in defaults and in a hidden marker file in
the data folder). After that, dictation pauses and the License tab offers a Dodo Payments
checkout plus a key field. Activation calls Dodo's public `/licenses/activate` once, then
`/licenses/validate` about weekly with a 30-day offline grace period.

To go live: create the product in Dodo with **license keys enabled** (activation limit 1–2),
then replace `Licensing.checkoutURL` in `Sources/Murmur/Support/Licensing.swift` with the
hosted checkout link. `defaults write com.priyam.murmur dodoTest -bool true` points the app at
Dodo's test host.

## Updates

Sparkle 2 is embedded. It checks `SUFeedURL` (Info.plist) daily and shows the standard
"Check for Updates…" flow. The EdDSA public key is in Info.plist; the private key lives in the
login keychain of the Mac that generated it (this one).

Publishing a version:

1. Bump `CFBundleShortVersionString` / `CFBundleVersion` in `Packaging/Info.plist`.
2. `make release` → `dist/Murmur-<version>.zip` and `dist/appcast.xml` (signed).
3. Upload both to the host named in `SUFeedURL` (GitHub Releases works; point the feed at the
   raw appcast URL). Replace the `REPLACE-ME` feed URL in Info.plist once you have it.

For real distribution you also need an Apple Developer ID certificate and notarization,
otherwise Gatekeeper blocks the download on other Macs. `make SIGN_ID="Developer ID Application: …"`
picks it up; notarize the zip with `xcrun notarytool submit` before running `generate_appcast`.

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
