# Contributing

Thanks for looking. TypeVoice is small on purpose; the bar for a change is "would this make
someone say *this is too good*", not "more".

## Building

macOS 26 or later on Apple silicon, Xcode 27.

```bash
make app      # release build into build/TypeVoice.app, ad-hoc signed and sandboxed
make run      # build and launch
make project  # generate the Xcode project (XcodeGen) if you prefer Xcode
```

The first `make` creates `Sources/TypeVoice/Support/Secrets.swift` from
`Secrets.example.swift`. It holds the RevenueCat key and is git-ignored; the placeholder
value builds fine, the License tab just says purchases aren't configured.

The first launch downloads the speech model (about 450 MB) into the app's sandbox
container. Permissions (Microphone, Accessibility) are per bundle identifier, so a build
with a different identifier asks again.

## Ground rules

- Nothing leaves the Mac. No analytics, no crash reporters, no network calls beyond the
  model download and the purchase check. A change that adds a network call needs a very
  good reason and an update to the privacy policy.
- No sounds, no haptics. It's macOS.
- Keep the pill quiet. Motion is calm, monochrome by default.
- Match the surrounding code: comment density, naming, and the way it reads.

## Pull requests

Describe what changed for the person using it, not just what changed in the code. If it
touches the pipeline (`Text/`), run the self-tests:

```bash
build/TypeVoice.app/Contents/MacOS/TypeVoice --test itn
build/TypeVoice.app/Contents/MacOS/TypeVoice --test structure
build/TypeVoice.app/Contents/MacOS/TypeVoice --test vocab
```
