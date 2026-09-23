# TypeVoice developer handbook

Everything a developer (or a future Claude session) needs to run, ship and support TypeVoice.
Written 2026-09-20 at the end of the launch setup; keep it current when any of it changes.

## 1. What it is

Local push-to-talk dictation for macOS 26 on Apple silicon. Hold a key, talk, release; the words
are typed into the frontmost app. Speech recognition is NVIDIA Parakeet TDT 0.6B v2 on the
Neural Engine via the FluidAudio package (English only, ~450 MB model downloaded on first launch
into `~/Library/Application Support/FluidAudio`). Cleanup is rule-based (`Sources/TypeVoice/Text/`),
with Apple Intelligence's on-device model on top when the Mac has it. No accounts, no telemetry,
no server of ours. Sold directly for $79 (personal, two Macs) or $299 (team key, five people),
seven-day trial, Dodo Payments as merchant of record, Sparkle for updates. Closed source.

Owner: Priyam Raj, Priyam Ventures / Warplabs. Support: mail@warplabs.co. Site: https://typevoice.ai.

## 2. Repositories and hosting

| What | Where | Notes |
|---|---|---|
| App source (private) | github.com/warplabshq/typevoice | local `~/Desktop/Projects/TypeVoice`, branch `main` |
| Website | github.com/warplabshq/typevoice-site | local `~/Desktop/Projects/TypeVoiceSite`; deployed by `make deploy` to Cloudflare Pages project `typevoice` (account Priyam Ventures) → https://typevoice.pages.dev and https://typevoice.ai |
| Source (public, GPL v3) | github.com/warplabshq/typevoice | the name and icon are trademarks; official builds also ship under the EULA |
| Downloads + release notes (public) | github.com/warplabshq/typevoice-releases | only release assets; the site's Download button and the Sparkle appcast point here |
| Old forms product (unrelated) | github.com/warplabshq/typevoice-forms | the previous "TypeVoice" (Next.js on Railway) — retired; its Railway service should be deleted |

Cloudflare: the `typevoice.ai` zone is in the same account. `wrangler` is logged in via OAuth
(`npx wrangler whoami`); it can deploy Pages but cannot edit DNS — DNS needs an API token with
*Zone › DNS › Edit* on that zone (keychain item `typevoice-cf-dns`, account `cloudflare`).

## 3. Build and run (development)

```bash
make run          # release build → build/TypeVoice.app, ad-hoc signed, then launches it
make debug        # same, debug configuration
make app          # build only
open Package.swift   # Xcode, if wanted
```

Ad-hoc dev builds carry an identifier-based designated requirement so Accessibility/Microphone
grants survive rebuilds, and skip the hardened runtime (its library validation refuses the ad-hoc
Sparkle framework). Never `pkill` and relaunch the app while the user may be dictating: check
the last line of `~/Library/Logs/TypeVoice/typevoice.log` — a `listening →` without a following
`inserted`/`cancelled` means a dictation is in flight.

Self-tests (headless, no GUI):

```bash
build/TypeVoice.app/Contents/MacOS/TypeVoice --test itn        # numbers
build/TypeVoice.app/Contents/MacOS/TypeVoice --test structure  # lists, commands
build/TypeVoice.app/Contents/MacOS/TypeVoice --test vocab      # dictionary matcher
build/TypeVoice.app/Contents/MacOS/TypeVoice --test clip.wav   # full pipeline on audio (16 kHz wav; afconvert -f WAVE -d LEI16@16000 -c 1 in.m4a out.wav)
TYPEVOICE_DEBUG=1 build/TypeVoice.app/Contents/MacOS/TypeVoice | Tools/latency.sh
```

Debug hooks in the running app (all via a distributed notification; the app must have
`debugLog` on: `defaults write ~/Library/Preferences/com.priyamventures.typevoice debugLog -bool YES`):

```bash
# helper: swift Tools/… or the one-liner below posts "typevoice.debug.showTab"
post() { TAB="$1" swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("typevoice.debug.showTab"), object: ProcessInfo.processInfo.environment["TAB"]!, userInfo: nil, deliverImmediately: true)'; }
# (swift -e does not pass "--" arguments through, hence the environment variable)
# Screenshot the main window: WID=$(swift -e 'import CoreGraphics; for w in CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]] where (w["kCGWindowOwnerName"] as? String) == "TypeVoice" { if ((w["kCGWindowBounds"] as? [String: Any])?["Height"] as? Double ?? 0) > 200 { print(w["kCGWindowNumber"]!); break } }'); screencapture -x -l $WID out.png
post history | dictionary | style | settings | license | privacy   # open a main-window tab
post onboarding | cheatsheet
post hud:listening | hud:locked | hud:processing | hud:done | hud:audio | hud:copy | hud:copied | hud:error | hud:notheard | hud:silent | hud:idle
post appearance:light | appearance:dark | appearance:system
post dictate:/path/to/clip.wav     # run a full session from a file (types into the frontmost app!)
```

(On the owner's Mac the old sandbox container still exists, so `defaults write <domain>` lands in
the container and the app never sees it; the `~/Library/Preferences/<domain>` path form works
everywhere. Fresh installs have no container.)

Other defaults: `dodoTest` (Bool) points licensing and the Buy buttons at Dodo's test mode and
returns to `http://localhost:8787/thanks.html`; `NSRequiresAquaSystemAppearance` is not used.
The site's local preview: `make preview` in the site repo (port 8787).

## 4. Where things live on a user's Mac

- Data: `~/Library/Application Support/TypeVoice/` — `history.sqlite` (FTS5), `dictionary.json`,
  `Recordings/*.m4a` (only with "Offer the audio after each dictation" on; pruned by the retention
  setting), `.first` (trial start marker; its creation date is the trial clock).
- Model: `~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2` (443 MB).
- Preferences: `com.priyamventures.typevoice` (`defaults read` it). Licence key, activation id and
  last validation date are in there (`licenseKey`, `licenseInstance`, `licenseValidated`).
- Log: `~/Library/Logs/TypeVoice/typevoice.log` (only with `debugLog`).
- Drag cache: `~/Library/Caches/TypeVoice/Drag/` (hard links with friendly names).
- Migration: builds ≤ 0.1.0 were sandboxed; `Support/Migration.swift` moves data out of
  `~/Library/Containers/com.priyamventures.typevoice` on first launch of a direct build.

## 5. Licensing (Dodo Payments)

How it works, end to end:

1. Buyer pays on Dodo's hosted checkout (price adapts to their billing country: PPP is on for both
   products; Dodo's default country table applies unless changed under Settings › Business).
2. Dodo generates a license key from the product's *License Key entitlement* and emails it with the
   receipt and our activation message. It also redirects to `https://typevoice.ai/thanks.html?license_key=…`;
   that page offers `typevoice://activate?key=…`, which lands the key in the app.
3. The app calls `POST https://live.dodopayments.com/licenses/activate {license_key, name}`
   (name = the Mac's name) and stores the returned activation id. Errors: 404 wrong key,
   403 inactive/expired, 422 activation limit reached.
4. Weekly `POST /licenses/validate {license_key, license_key_instance_id}`; 30-day offline grace;
   `POST /licenses/deactivate` frees the seat ("Deactivate this Mac" in the License tab).
   Code: `Sources/TypeVoice/Support/Licensing.swift`, UI: `UI/LicenseView.swift`.

Dodo objects (business `<business id>`):

| | Live | Test |
|---|---|---|
| Brand "TypeVoice" (icon logo, statement descriptor `DODOPAY_TYPEVOICE`, url typevoice.ai, support mail@warplabs.co) | `<brand id>` | `<brand id>` |
| Product TypeVoice, $79, entitlement activations 2 | `pdt_0NnyeIUl5lH6A5vMnNQl0` | `pdt_0Nnye4FRV4gyNve43FkdY` |
| Product TypeVoice Team, $299, entitlement activations 10 | `pdt_0NnyeIYh7eg5s2udMzUGZ` | `pdt_0Nnye4HFHXLRKq4WkVJXG` |

Checkout links: `https://checkout.dodopayments.com/buy/<product id>?redirect_url=<thanks page>`
(test: `test.checkout.dodopayments.com`). They are built in `Brand.swift` (app) and `site.js`
(site). Test card: 4242 4242 4242 4242, any future date, any CVC.

API access without ever seeing the key: `~/bin/dodoapi test|live METHOD /path ['json']` reads
the key from the keychain (`typevoice-dodo-test` / `typevoice-dodo-live`, account `dodo`).
Gotchas learned: entitlements attach as `{"entitlements":[{"entitlement_id":…}]}`; product images
are `PUT /products/{id}/images` → presigned S3 PUT (same key each time, CDN may cache the old one
for a while); brand logos need `PUT /brands/{id}/images` **and then** `PATCH /brands/{id}
{"image_id":…}`; PPP percentages and Adaptive Currency are dashboard-only.

Dashboard-only, done by the owner: business verification and payouts, PPP percentages, refunds.

Support playbook:
- *Lost key* → Dodo dashboard › Customers/Licenses, resend, or `dodoapi live GET /licenses`.
- *Moving to a new Mac* → Deactivate this Mac on the old one; if the old Mac is gone, deactivate
  the instance from the dashboard (or `POST /licenses/deactivate`).
- *Refund* → issue in Dodo (14-day policy on the site); the key is revoked and the app notices at
  its next weekly check (or Re-check).
- *"Price is different from the site"* → PPP by billing country; see the support FAQ.

## 6. Releasing

One-time setup (owner):
1. Developer ID Application certificate: Xcode › Settings › Accounts › Manage Certificates › +.
2. Notarization credentials: an App Store Connect API key (Users and Access › Integrations › Team
   Keys; role Developer is enough), stored once with
   `xcrun notarytool store-credentials TypeVoice --key AuthKey_<ID>.p8 --key-id <ID> --issuer <UUID>`.
   The `.p8` then belongs in the password manager, not in Downloads. Team ID J3QE43KTMT.
3. Sparkle keys: `make keys` → paste the public key into `SUPublicEDKey` in `Packaging/Info.plist`;
   back up the private key (`.build/artifacts/sparkle/Sparkle/bin/generate_keys -x file`). Losing it
   means shipped copies can't take updates.
4. `gh auth login` (done on the owner's Mac; org warplabshq).
5. `python3 -m pip install --user dmgbuild` — `make dmg` lays the image out from `Packaging/dmg.py`
   (app left, Applications right, arrow between) over `Packaging/dmg-background{,@2x}.png`, which
   `swift Tools/dmgbg.swift Packaging/dmg-background` redraws. Icon centres live in both files.

Per release:
1. Top entry in `CHANGELOG.md` (user's words); bump `CFBundleShortVersionString` and
   `CFBundleVersion` in `Packaging/Info.plist`; commit.
2. `make release` → signs with Developer ID, notarizes (2–10 min), staples, writes
   `dist/TypeVoice-<v>.zip` (Sparkle), `dist/TypeVoice.dmg` (downloads), `dist/TypeVoice-<v>.html`
   (notes) and `dist/appcast.xml`. The appcast is generated from `dist/updates/` (zip + notes only;
   `generate_appcast` refuses a zip and a dmg of the same version side by side) with the notes
   embedded, so no per-version page is needed on the site.
3. `make publish` → GitHub release `v<v>` in warplabshq/typevoice-releases with both files, copies
   the appcast into the site repo and deploys the site. Commit the site repo afterwards.
4. Update `changelog.html` on the site (mirror the CHANGELOG entry), then `git tag -a v<v>` in
   this repo so the source of every shipped build is findable.
5. `make release` also files the build's dSYM under `dist/symbols/` (keep that folder; it is
   git-ignored). A crash report names the binary UUID; `dwarfdump --uuid` on the dSYM must match,
   then `atos -o dist/symbols/TypeVoice-<v>.dSYM/Contents/Resources/DWARF/TypeVoice -l <load
   address> <frame address>` gives the function. Without the dSYM a report only shows framework
   frames, as the 1.0.6 menu crash did.
6. Sanity: download the DMG from the release page, `spctl -a -vv -t exec` on the app inside
   (expect "Notarized Developer ID"), and open the appcast URL. The `make app` build only copies
   resource bundles of packages still in `Package.swift`; a stale `.build` cannot leak others.

Installed copies check `https://typevoice.ai/appcast.xml` daily (`SUFeedURL`), show the notes and
install in place. Updates are verified by Apple notarization + the Sparkle EdDSA signature.

## 7. Site

Static HTML/CSS/JS; everything brand-specific in `site.js` (`SITE`): price, refund days, Mac limit,
team price/seats, checkout links, download link, domain, email. Pages: index, support, privacy,
terms, eula, changelog, thanks (Dodo return page, `noindex`), plus `appcast.xml`, `robots.txt`,
`sitemap.xml`, a `404.html`, `_headers` (HSTS, caching, `no-cache` on the appcast) and one Pages
Function, `functions/geo.js`: it answers `/geo` with the fixed price for the visitor's country
(from Cloudflare's country header) and `site.js` rewrites the price lines to "₹2,499 in 🇮🇳 India".
Its `PRICES` table mirrors the Dodo Localized Pricing rules (`pricing_mode: by_country`, PPP off,
rules on all four products via `/products/{id}/localized-prices`): IN ₹2,499 / ₹9,499 (+GST),
PK/BD/EG/NG $24 / $89. Everyone else pays $79 / $299 converted at checkout. Change a rule → change
the table. `?c=NG` previews another country. Visitors from those countries see it as a quiet
special offer: a flag pill ("🇮🇳 A special price for you"), the local price, the list price struck
through — no country name.
Short checkout links (Dodo, live): **dodo.pe/typevoice** and **dodo.pe/typevoice-team**, created
with `POST /products/{id}/short_links` and the `/thanks` return URL baked in.
Umami (self-hosted) is scoped to typevoice.ai, drops query strings, and counts `download`, `buy`,
`buy-team`, `activate` and `regional-price` events. `make deploy` publishes via wrangler direct upload. Legal copy states: 7-day trial,
$79 / 2 Macs, team 5 × 2 Macs, 14-day refund, PPP, jurisdiction India, Dodo as merchant of record,
closed source with third-party notices.

## 7a. Word packs

`Text/Packs.swift`: lists of spellings the model mangles, matched by sound like the Dictionary
(`Vocabulary`), but only on spans whose every piece scored below `Packs.confidenceGate` (0.85,
from Parakeet's per-token `token_prob`), and only with a closer match (≥ 0.85) when the heard
words are real English (`/usr/share/dict/words`) — "sell it" must never become "sqlite". The
index buckets terms by first phonetic letter + length; a long dictation costs ~0.5 ms.
Packs are text files in `Sources/TypeVoice/Resources/Packs/` (a SwiftPM resource bundle),
built by `python3 Tools/packs/build.py [dev|slang|all]` from Homebrew analytics, top-PyPI,
Wikidata (software classes, 5+ sitelinks) and the hand-picked `Tools/packs/core-*.txt`.
Wiktionary's slang categories were evaluated and rejected: even minus its offensive categories
they skew to slurs and dog whistles. Imported lists live in `~/Library/Application Support/
TypeVoice/Packs/`. `--test packs` runs the heard → expected cases and prints the cost.
A span spelled exactly like a known name is never replaced (`Index.known`: every term of every
pack, enabled or not, plus `Packs/known.txt`, the household names `build.py` keeps out of the
packs; the person's Dictionary is passed in by the caller). This is what stopped "Reddit" →
"Rediff" (0.80 similarity, confidence 0.46): the model had spelled it right.
A single real English word is never replaced by a pack ("games" stays games, whatever sounds
like it); a span never crosses punctuation; real words only join into a term when the spelling
also matches (≥ 0.75), and an exact spelling only gets its capitals back. Dictionary: shortest
span first, and a term with a dot only meets a heard address whose two halves line up.
`--test replay` runs every dictation in this Mac's log through today's pipeline and prints what
changed (reads the log at runtime; nothing personal in the repo). Run it after any rule change.
The `doubtful:` debug log line lists each dictation's low-confidence words, for tuning the gate.
Next step (Dictionary v2): decode-time boosting — re-export the v2 joint CoreML model with
top-K logits and port sherpa-onnx's Aho-Corasick hotword boost into FluidAudio's decoder.

## 7b. Lists from speech

`Text/Structure.swift`, after `Cleaner.clean` (fillers gone) and before `Numbers`. Four ways a
list forms, each needing more than one hit so "number one priority" stays prose:
spoken markers ("bullet", "number two", "step three"; ≥ 2, or one "bullet" followed by a
comma series); ordinals at sentence starts (≥ 3); an in-order ordinal run anywhere in the
sentence ("so first lights, second camera and third glasses"; ≥ 3, or ≥ 2 after a count cue
like "two things"); and natural series, where the lead-in before a colon, a sentence end or a
comma announces a list ("my list", "three things") and ≥ 3 short items follow. Every marker
swallows its connector ("and third" → "3."), "bullet" is ignored as a noun ("in a bullet
point", "bullet points"), closers like "and that's all" / "etc" are dropped, and a sentence
said after the list goes below it. Ordinals give numbers, plain series give dashes. `tidy`
does capitals, colons and periods. `--test structure` prints every case; the last block is
real dictations that used to stay flat, then sentences that must never become lists.

## 8. Brand

One waveform (`Sources/TypeVoice/UI/BrandWave.swift`): eight bars, gap 0.82× bar width, tallest
bar 8.35× bar width. Icon (`make icon` from `Tools/icon.swift`), menu bar glyph, sidebar tile,
Summary card, live waveform at rest, site diagram all use it. Asset set: `swift Tools/brand.swift
build/AppIcon.iconset Brand Brand/out` (icons, lockups, wordmarks, product tile, banner; see
`Brand/README.md`). Serif is Instrument Serif (OFL). Never use the Apple logo on buttons.

## 9. Credentials and where they are

| Secret | Where |
|---|---|
| Dodo API keys | macOS keychain: `typevoice-dodo-test`, `typevoice-dodo-live` (account `dodo`) |
| Cloudflare wrangler OAuth | `~/Library/Preferences/.wrangler/config/default.toml` |
| Cloudflare DNS token | keychain `typevoice-cf-dns` (account `cloudflare`) |
| GitHub | `gh auth` keyring, user priyam-raj (admin on warplabshq) |
| Notarization | keychain profile `TypeVoice` (notarytool) |
| Sparkle private key | login keychain (created by `make keys`); back it up |

Nothing secret is in either repository.

## 10. Decisions log

- 2026-09-18 renamed Murmur → TypeVoice; bundle id `com.priyamventures.typevoice`.
- 2026-09-20 direct sales instead of the App Store (sandbox removed; Accessibility insertion
  back; RevenueCat out — it has no Dodo integration; Dodo license keys; Sparkle).
- 2026-09-20 trial 3 → 7 days; personal key 2 Macs; team key 5 × 2 Macs at $299; PPP first, then
  replaced by fixed Localized Pricing for IN/PK/BD/EG/NG only (PPP defaults also discounted the UK, DE, JP…);
  14-day refund; downloads on a public releases repo; site on Cloudflare Pages.
- 2026-09-21 microphone policy: the built-in mic by default (`InputDevices.resolve`), the system
  default only when chosen ("Whatever the Mac is using"), a device UID otherwise with fallback to
  built-in. Reason: a Bluetooth headset switching to its HFP profile changed the input format
  under a running engine; `installTap` with a stale format throws an Objective-C exception no
  Swift `catch` sees, and dictation silently died until relaunch. The tap now uses `format: nil`,
  the converter follows the buffers' real format, and `AVAudioEngineConfigurationChange` resets
  the engine (and finishes a running session with what was heard).
- 2026-09-21 the menu bar item moved from SwiftUI MenuBarExtra to AppKit (`UI/StatusItem.swift`)
  after a user's 1.0.6 crash in a menu action callback SwiftUI had already released; the menu is
  rebuilt on every open and every item is owned for the app's lifetime.
- 2026-09-20 open source (GPL v3) later the same day, for trust; revenue from the signed build,
  updates and support. Trademarks on the name and icon keep forks distinguishable.
- Name collision noted: a third-party iPhone "TypeVoice: AI Voice Keyboard" exists at
  typevoice.app (App Store id 6769261600). Owner chose to keep the name; domain is typevoice.ai.
- Parakeet stays the engine: Apple's SpeechTranscriber measured equal on the owner's voice and
  2–3× slower in batch; a seam-gap repair pass in FluidAudio was turned off (−300 ms, no text change).

## 11. Open work

- Shipped: 1.0.0, 1.0.1 (Style owns the text options; Settings › About), 1.0.2 (License tab shows
  the country price via `/geo`) — all on 20 September 2026. 1.0.0 (build 100) — notarized, stapled, on the releases repo,
  appcast live, site on typevoice.ai (root + www, Cloudflare proxied, HSTS). Source tagged `v1.0.0`.
- Not yet done by hand: a test-mode purchase (`defaults write ~/Library/Preferences/com.priyamventures.typevoice dodoTest
  -bool YES`, site served locally on :8787) to see a key arrive and activate; a clean-Mac run
  (download → open → onboard → trial → activate → update check). Dodo issues keys through the
  License Key entitlement on `payment.succeeded` and appends `license_key=` to the return URL.
- Cloudflare: add a Redirect Rule "www → root" in the dashboard (Rules › Redirect Rules; the
  Pages `_redirects` file cannot redirect by host, so `site.js` does it in JS meanwhile). The
  stale `_railway-verify` TXT record can go once the Railway service is deleted.
- Delete the Railway service of the old product.
- Parked (usage limit): the dictation-quality implementation on the `quality` branch/worktree
  (`../TypeVoice-quality`: TextPipeline scaffold + `--test text` runner; modules cleaner, numbers,
  structure, spoken formats, vocabulary v2, audio capture, smart-cleanup gate — proposals in the
  session scratchpad) and the UX-audit synthesis (raw findings from 8 auditors).
- Later: newsletter only if wanted (privacy policy promises no list today); larger team sizes;
  App Intents (needs an Xcode build; URLs `typevoice://start|stop|toggle|cancel` exist).
