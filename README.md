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
