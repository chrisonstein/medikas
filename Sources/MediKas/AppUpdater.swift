import AppKit
import Sparkle

/// Automatische updates (Sparkle). De app leest `SUFeedURL` uit Info.plist: de appcast.xml
/// van de nieuwste GitHub-release. Standaard één keer per dag; handmatig via ‘Zoek naar updates…’.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    private let controller: SPUStandardUpdaterController

    /// Tijdens zelftests en in de voorbeeldmodus geen updater starten.
    static var isDisabled: Bool {
        ProcessInfo.processInfo.environment["MEDIKAS_DATA_DIR"] != nil
            || Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") == nil
    }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: !AppUpdater.isDisabled,
                                                  updaterDelegate: nil, userDriverDelegate: nil)
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Updates zonder vragen installeren (bij de volgende keer afsluiten).
    var automaticallyDownloads: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { objectWillChange.send(); controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }

    var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// Toont Sparkle’s vensters: ‘Zoeken…’ → ‘Je hebt de nieuwste versie’ / ‘Update beschikbaar’.
    func checkForUpdates() {
        guard !AppUpdater.isDisabled else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
