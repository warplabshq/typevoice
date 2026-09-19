import Foundation

/// One-time move out of the App Sandbox container. Builds up to 0.1.0 ran sandboxed, so
/// their history, dictionary, recordings and preferences live under
/// ~/Library/Containers/<bundle id>/Data. The first launch of a direct build brings them
/// home; afterwards the container is left alone (macOS owns it) and nothing runs again.
enum Migration {
    private static let bundleID = "com.priyamventures.typevoice"
    private static var container: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleID)/Data", isDirectory: true)
    }

    private static var done = false

    /// Runs both moves once per launch. Called from `Paths.support`, which every store touches
    /// before reading anything, and again (harmlessly) from `Prefs.registerDefaults`.
    static func run(supportFolder dest: URL, appName: String) {
        guard !done else { return }
        done = true
        preferences()
        supportFolder(to: dest, appName: appName)
    }

    /// Moves the container's Application Support/<app> folder to `dest` if `dest` has no
    /// data of its own yet. Called before the destination is created, so a plain rename does
    /// the whole job (creation dates, and with them the trial start, survive a rename).
    private static func supportFolder(to dest: URL, appName: String) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: dest.appendingPathComponent("history.sqlite").path) else { return }
        let src = container.appendingPathComponent("Library/Application Support/\(appName)", isDirectory: true)
        guard fm.fileExists(atPath: src.appendingPathComponent("history.sqlite").path) else { return }
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }   // empty dir from an aborted run
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: src, to: dest)
            Log.app.info("migrated data from the sandbox container")
        } catch {
            Log.app.error("container migration failed: \(error.localizedDescription)")
        }
    }

    /// Copies the sandboxed preferences into the normal domain, once, if this domain is
    /// still empty. Runs before `registerDefaults`, so reads that follow see the old values.
    private static func preferences() {
        let d = UserDefaults.standard
        guard d.object(forKey: Prefs.Key.hasOnboarded) == nil else { return }
        let plist = container.appendingPathComponent("Library/Preferences/\(bundleID).plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        for (k, v) in dict where d.object(forKey: k) == nil { d.set(v, forKey: k) }
        Log.app.info("migrated \(dict.count) preferences from the sandbox container")
    }
}
