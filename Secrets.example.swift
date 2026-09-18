// Copy this file to Sources/TypeVoice/Support/Secrets.swift and fill it in. Secrets.swift is git-ignored;
// `make` creates it from this template when it is missing, so a fresh checkout builds.
//
// The RevenueCat key here is the app's *public* SDK key (it ships inside the binary anyway),
// but keeping it out of the repository means forks start from a clean slate.
enum Secrets {
    static let revenueCatAPIKey = "appl_REPLACE-ME"
}
