# Security

TypeVoice runs entirely on the Mac: no accounts, no servers of ours, and the only network
requests are a one-time model download from Hugging Face and the purchase check with
RevenueCat. The threat model is therefore mostly local: the sandbox, the Accessibility
permission (a global event tap that acts only on the trigger key), and the clipboard
round-trip used to paste text.

If you find a problem, email the address in `Sources/TypeVoice/Support/Brand.swift`
rather than opening a public issue, and give us a few days to fix it before you write
about it. We'll credit you if you'd like.
