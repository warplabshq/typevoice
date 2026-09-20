# Contributing

Thanks for looking. TypeVoice is small on purpose, so the bar for a change is "a person
dictating notices the difference": a phrase that comes out wrong, an app it can't type into,
a pause that should have been a paragraph.

- **Bugs:** open an issue with the sentence you said, what came out, and what you expected.
  If it's about insertion, say which app. Nothing you dictate is ever sent to us, so the
  example has to come from you.
- **Changes:** keep the tone of the code around you (comments explain why, not what), run
  `make app` and try it, and describe the before/after in the pull request.
- **Text pipeline:** `build/TypeVoice.app/Contents/MacOS/TypeVoice --test text` runs the
  rule-based cleanup against its examples; add a line there when you fix one.

## License of contributions

By opening a pull request you agree that your contribution is licensed under the
[GPL v3](LICENSE), and that Priyam Ventures may also include it in the signed builds it
distributes under the [TypeVoice license agreement](https://typevoice.ai/eula). That second
part is what lets the official build stay a normal Mac app download while the source stays
free. Sign off your commits (`git commit -s`) to say you have the right to contribute the
code.

The TypeVoice name and icon are trademarks and stay out of forks; see the README.
