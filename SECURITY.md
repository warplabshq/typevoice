# Security

TypeVoice runs entirely on the Mac: no accounts, no servers of ours, and the only network
requests are a one-time model download from Hugging Face, the Sparkle update check against
our own appcast (EdDSA-signed updates over HTTPS), and license activation and re-checks
with Dodo Payments. The threat model is therefore mostly local: the Accessibility
permission (a global event tap that acts only on the trigger key, and text insertion into
the focused field), and the clipboard round-trip used when pasting is the fallback.

If you find a problem, email mail@warplabs.co and give us a few days to fix it before you
write about it. We'll credit you if you'd like.
