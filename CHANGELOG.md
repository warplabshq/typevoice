# Changelog

The top entry is what Sparkle shows before an update installs (`make notes` turns it into
`dist/TypeVoice-<version>.html`; `make release` runs that for you). Keep entries in the
user's words: what changed for the person dictating, not which file moved.

## 1.0.10 — 22 September 2026

- Web addresses, spoken: "typevoice dot ai", "logs dot so", "jane at example dot com", "slash
  support" come out as typevoice.ai, logs.so, jane@example.com, typevoice.ai/support. When the
  model hears "dot" as a full stop ("logs. So"), that's repaired too, wherever it can't be a
  real sentence.
- Import a list… now explains the file format before asking for the file.

## 1.0.9 — 22 September 2026

- Word packs. The Dictionary tab now carries lists of spellings the model has no way to know:
  Developer tools (3,600 names from Homebrew, PyPI and Wikidata, plus our own picks) and
  Internet slang (hand-picked). A pack only steps in where the model was unsure of a word,
  your own Dictionary always wins, and Import a list… takes any text file, one term per line.
  Files inside the app; nothing is fetched.

## 1.0.8 — 21 September 2026

- Microphones, sorted out. The Mac's own mic is now the default even when AirPods or another
  Bluetooth headset is connected: it hears you better, starts instantly, and doesn't drop the
  music on your headset to headset quality while you talk. Pick a headset under Settings ›
  Microphone if you need to whisper. A mic that changes or disappears mid-sentence no longer
  kills dictation until the next launch; the sentence finishes with what was heard.
- Insertion can't be held hostage by a busy app: Accessibility questions time out in 0.3 s and
  paste takes over.
- Summary: one Export button (the save panel picks the format), and Clear History moved from
  the toolbar to the end of the list. A tidier Dictionary row and Privacy page.

## 1.0.7 — 21 September 2026

- Fixes a crash when choosing an item in the menu bar menu.

## 1.0.6 — 21 September 2026

- Apple Intelligence bug fixes. Smart cleanup is now off by default; turn it on under Style
  if you want the model's edits and don't mind a moment more per dictation.

## 1.0.5 — 20 September 2026

- After an update installs, the window comes back where it was instead of the app quietly
  relaunching in the menu bar.
- The menu bar glyph eases between states. Listening lifts the bars a little rather than
  swapping in a different, fatter icon.
- Settings › About says Changelog, like the site.

## 1.0.4 — 20 September 2026

- Style › Sign-off: a fixed note on the end of every dictation, for places where spelling
  gets judged — a coding assistant, a ticket queue. Off by default; the text is yours to change.
- License: with a personal key, the team key is one click away and this Mac can switch to it;
  the tab knows which kind of key it holds; the key is re-checked while the app stays running.

## 1.0.3 — 20 September 2026

- TypeVoice is open source: the code is on GitHub under the GPL v3, linked from the Privacy
  tab, Settings › About and the Help menu. Nothing about the app changed; now you can check.

## 1.0.2 — 20 September 2026

- The License tab shows the price for your country, where there is one: a flag, the local
  figure on the Buy buttons, and what the checkout will add for tax.

## 1.0.1 — 20 September 2026

- Everything about how the text reads now lives under Style: numbers as digits, paragraphs from
  pauses, spoken commands, filler and stutter cleanup, and Smart cleanup with its Apple
  Intelligence status. Settings keeps the trigger, microphone, indicator and updates.
- Settings has an About section: the version, Check for Updates, the automatic-check switch and
  "What's new". Check for Updates is also in the app menu and the menu bar menu.
- Links from the app open the site's clean addresses.

## 1.0.0 — 20 September 2026

The first release.

- Hold a key, talk, let go: the words are typed into whatever app you're in, through
  Accessibility, with paste as the fallback.
- English speech recognition on the Neural Engine (NVIDIA Parakeet), fully offline after a
  one-time model download. Nothing you say leaves the Mac.
- Cleanup by rule: fillers, stutters, numbers, spoken commands ("new line", "bullet",
  "number one"), natural lists ("grocery list: milk, eggs, bread"), paragraphs from pauses.
  Apple Intelligence tidies further on Macs that have it.
- A personal Dictionary for names and product terms, matched by how they sound.
- Summary: every dictation, searchable and exportable, with the time it saved you.
- Optional voice notes: drag the audio of any dictation into iMessage, WhatsApp or Slack.
- Trigger your way: the Globe key, a chord like ⌥⌘, a combination, tap-to-toggle,
  double-tap to keep listening hands-free; Esc cancels; a stop button if anything takes long.
- Seven-day free trial, then one purchase. Updates in place.
