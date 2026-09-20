# TypeVoice

Local dictation for Mac. Hold a key, talk, release: clean, punctuated text lands at your
cursor in any app. Everything runs on the Mac — no account, no server, no telemetry — and
the code is here so you don't have to take our word for it.

**[typevoice.ai](https://typevoice.ai)** · free for seven days, then one purchase, no subscription.

## Open source, and paid

The source is under the [GNU GPL v3](LICENSE). Read it, build it, change it, keep the
changes under the same license. What we sell at typevoice.ai is the signed, notarized build:
it installs in one drag, updates itself, comes with support, and pays for the work. If you
build it yourself the License tab will tell you the checkout isn't configured, and
everything else works; we'd still be glad if you bought a key.

The name **TypeVoice** and the icon are trademarks of Priyam Ventures and are not covered by
the GPL. A fork needs its own name and icon, so that nobody mistakes it for the build we
stand behind.

## How it works

- **Speech:** NVIDIA Parakeet TDT 0.6B v2 on the Neural Engine, via [FluidAudio](https://github.com/FluidInference/FluidAudio).
  Downloaded once (about 450 MB) on first launch. English, every accent.
- **Cleanup:** fillers, stutters, numbers, lists and paragraphs by rule; then Apple's on-device
  model when Apple Intelligence is available, under a hard 1.2 s deadline that never blocks
  insertion.
- **Insertion:** through the Accessibility API when the focused field allows it (the words
  before the cursor decide spacing and capitals, and the clipboard is never touched);
  otherwise a paste into the frontmost app, with the clipboard restored right after.
- **UI:** a pill that appears while you hold the key on the screen you're typing on, shows the
  sentence, and retreats. Menu bar only; the main window has Summary (time saved, history),
  Dictionary, Style, Settings, License and Privacy.
- **Triggers:** hold a key, a chord (⌥⌘), or a key combo; double-tap keeps listening; or
  tap to start and tap to stop.
- **Voice notes (opt-in):** Settings › Indicator › Offer the audio after each dictation
  keeps a small AAC file per dictation; drag the chip on the pill, or a Summary row, into
  any chat.
- **Licensing:** a seven-day trial, then a license key from [Dodo Payments](https://dodopayments.com)
  (the merchant of record). The app talks to Dodo's public license endpoints only to
  activate, deactivate, or re-check a key (weekly, with a 30-day offline grace period).
- **Updates:** [Sparkle](https://sparkle-project.org), checking an appcast on the website once
  a day. Updates are EdDSA-signed, on top of Developer ID signing and notarization.

## Build

macOS 26 or later on Apple silicon, Xcode 27.

```bash
make run          # release build → build/TypeVoice.app, then launches it
make debug        # same, debug config
open Package.swift   # if you prefer Xcode
TYPEVOICE_DEBUG=1 build/TypeVoice.app/Contents/MacOS/TypeVoice | Tools/latency.sh
build/TypeVoice.app/Contents/MacOS/TypeVoice --test clip.wav   # run the text pipeline on a file
build/TypeVoice.app/Contents/MacOS/TypeVoice --test vocab      # dictionary matcher self-test
```

There is nothing secret in the tree. The checkout links and prices live in
`Sources/TypeVoice/Support/Brand.swift`; the update feed and its public key in
`Packaging/Info.plist`. A fork should replace those (or blank them: the License tab then says
the checkout isn't configured and the updater stays off), along with the name and icon.

### Signing during development

`make` signs ad-hoc with a stable, identifier-based designated requirement, so macOS keeps
the Accessibility and Microphone grants across rebuilds. Ad-hoc builds skip the hardened
runtime (its library validation refuses the embedded Sparkle framework); release builds have
it. If Accessibility ever looks on but TypeVoice doesn't react: System Settings › Privacy &
Security › Accessibility, flip TypeVoice off and on, then relaunch.

Data lives in `~/Library/Application Support/TypeVoice` (history, dictionary, recordings)
and `~/Library/Application Support/FluidAudio` (the model). A Mac that ran the earlier
sandboxed builds has its data moved out of the container on first launch.

## Releasing (how we ship the official build)

Direct distribution needs three things from an Apple Developer account and one from Dodo.
Each is set up once; `docs/HANDBOOK.md` has the longer version.

1. **Developer ID Application certificate** — Xcode › Settings › Accounts › Manage
   Certificates › + › Developer ID Application. `make release` picks it up from the keychain.
2. **Notarization credentials** — an App Store Connect API key, stored once:

   ```bash
   xcrun notarytool store-credentials TypeVoice --key AuthKey_ID.p8 --key-id ID --issuer UUID
   ```
3. **Sparkle keys** — `make keys` prints a public key; paste it into `SUPublicEDKey` in
   `Packaging/Info.plist`. The private key stays in your login keychain; export a backup with
   `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private.key` and keep it
   somewhere safe. Losing it means existing installs can't verify future updates.
4. **Dodo Payments** — two one-time products, each with a *License Key* entitlement (Advanced
   settings › Entitlements, no expiry): **Personal, $79, activations limit 2** (a desk Mac and a
   laptop) and **Team, $299, activations limit 10** (five people, two Macs each, one shared
   key). Put the personal checkout link into `Brand.checkoutURL` and the price into
   `Brand.price`; the team link goes into the site's `SITE.teamCheckoutURL`. Set both products'
   return URL to the site's `/thanks`, which hands the key to the app through
   `typevoice://activate?key=…`. Country prices are Localized Pricing rules on the products
   (`by_country`); the site's `/geo` and the app's License tab read the same table.

Then, per version: bump `CFBundleShortVersionString` and `CFBundleVersion` in
`Packaging/Info.plist`, write the entry at the top of `CHANGELOG.md` (it becomes the release
notes Sparkle shows, and the site's changelog page repeats it), and

```bash
make release
```

which builds, signs with Developer ID, notarizes and staples, and writes
`dist/TypeVoice-<version>.zip` (what Sparkle downloads), `dist/TypeVoice.dmg` (the site's
Download button), the release notes and `dist/appcast.xml`. Then

```bash
make publish
```

creates the GitHub release `v<version>` in `warplabshq/typevoice-releases` with both files,
copies the appcast into the site and deploys it. The site's Download button links to
`releases/latest/download/TypeVoice.dmg`, so it always serves the newest release.

To try a purchase against Dodo's test mode: use the test-mode checkout link and
`defaults write com.priyamventures.typevoice dodoTest -bool YES`.

## Website and legal pages

The landing page, Support, Privacy Policy, Terms and the license agreement live in their
own repository, `typevoice-site` (locally `../TypeVoiceSite`), together with `appcast.xml`
and the thank-you page. Everything brand-specific is in its `site.js`. It deploys to
Cloudflare Pages; a fork puts its own host into `Brand.website` in
`Sources/TypeVoice/Support/Brand.swift` and into `SUFeedURL` in `Packaging/Info.plist`.

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Security
problems: [SECURITY.md](SECURITY.md).

## Layout

```
Sources/TypeVoice/
  App/      entry point, AppState, DictationController (the pipeline)
  Capture/  Fn/shortcut monitor, microphone → 16 kHz, FFT band analysis for the waveform
  Engine/   Transcriber protocol, Parakeet implementation
  Text/     deterministic Cleaner, SmartCleaner (Foundation Models)
  Insert/   Accessibility insertion with paste fallback
  HUD/      the glass pill: window, controller, voice-reactive waveform, type-on text
  Store/    history (SQLite), dictionary, recordings, paths
  UI/       main window (summary, dictionary, style, settings, license, privacy), onboarding, menu bar
  Support/  prefs, licensing (Dodo), updater (Sparkle), permissions, migration, logging
Packaging/  Info.plist, entitlements, icon
Tools/      icon.swift, latency.sh, wer.py
```

Rebranding: the display name comes from `CFBundleDisplayName` in `Packaging/Info.plist`
(`Brand.name` in code); the bundle ID lives in `Packaging/Info.plist`, the Makefile's signing
requirement and `Support/Migration.swift`; the icon is rendered by `make icon`.
