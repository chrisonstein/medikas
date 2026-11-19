import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Demo.runIfRequested()
            Theme.shared.apply()
            DockIcon.shared.start()
            _ = AppUpdater.shared   // start de dagelijkse updatecontrole
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MediKasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup("MediKas") {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, nl)
                .environment(\.calendar, nlCalendar)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1380, height: 840)
        // Geen titelbalk: elke pagina heeft zijn eigen kop met acties. De scheidingslijn naast de
        // zijbalk loopt dan vanzelf over de volle hoogte (zoals Muziek en Notities).
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()   // Weergave → Toon/verberg zijbalk (⌃⌘S)
            CommandGroup(after: .textEditing) {
                Button("Zoek") { NotificationCenter.default.post(name: .focusSearch, object: nil) }
                    .keyboardShortcut("f")
            }
            CommandGroup(after: .appInfo) {
                Button("Zoek naar updates…") { AppUpdater.shared.checkForUpdates() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Nieuwe factuur") { store.startNewInvoice() }
                    .keyboardShortcut("n")
                Button("Nieuwe praktijk") {
                    let id = store.addClient().id
                    store.sidebar = .praktijken
                    DispatchQueue.main.async { store.selectedClientID = id }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .importExport) {
                Button("Importeer bestaande factuur…") {
                    store.startImport(for: store.sidebar == .praktijken ? store.client(store.selectedClientID) : nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Button("Maak back-up") { store.backupNow() }.disabled(store.backupDestination == nil)
                Button("Bewaar back-up als…") { store.saveBackupAs() }
                Button("Zet back-up terug…") { store.importBackup() }
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { i, item in
                    Button(item.rawValue) { store.sidebar = item }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
                Divider()
            }
        }

        // Standaard macOS-instellingenvenster (⌘,)
        Settings {
            SettingsView()
                .environmentObject(store)
                .environment(\.locale, nl)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var theme = Theme.shared
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if let reason = store.unavailableReason {
                FolderUnavailableView(reason: reason)
            } else {
                main
            }
        }
        .overlay(alignment: .bottom) { NoticeView() }
        // Testmodus: alle tekst onleesbaar maken (om met echte gegevens te testen zonder ze te zien)
        .redacted(reason: ProcessInfo.processInfo.environment["MEDIKAS_REDACT"] != nil ? .placeholder : [])
        // Knoppen, schakelaars en links gebruiken de accentkleur van het systeem (Apple-conventie)
        // Nieuwe accentkleur: views opnieuw opbouwen zodat alles de nieuwe kleur pakt
        .id(theme.accentChoice)
        .onAppear { store.undoManager = undoManager }
        // Naar ‘Praktijken’ gaan vanaf een andere pagina = altijd het overzicht
        .onChange(of: store.sidebar) { old, new in
            if new == .praktijken && old != .praktijken { store.selectedClientID = nil }
        }
        .onChange(of: undoManager) { _, um in store.undoManager = um }
    }

    private var overdueCount: Int { store.sentInvoices.filter { $0.status() == .overdue }.count }

    private var main: some View {
        NavigationSplitView {
            List(selection: $store.sidebar) {
                Section("Administratie") {
                    row(.overzicht)
                    row(.facturen, badge: overdueCount)
                    row(.betalingen)
                }
                Section("Relaties") { row(.praktijken) }
                Section("Inzicht") { row(.statistieken) }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            let page = store.sidebar ?? .overzicht
            Group {
            if store.isLoadingData {
                // Laadtoestand in de vorm van de pagina (nooit een lege toestand tonen tijdens het laden)
                LoadingState(layout: page == .facturen || page == .betalingen ? .table : (page == .praktijken ? .form : .dashboard))
                    .navigationTitle(page.rawValue)
            } else {
                switch page {
                case .overzicht: DashboardView()
                case .facturen: InvoicesView()
                case .betalingen: PaymentsView()
                case .praktijken: ClientsView()
                case .statistieken: StatsView()
                }
            }
            }
            // Inhoud mag nooit breder worden dan de ruimte naast de zijbalk (anders schuift de zijbalk weg)
            .frame(minWidth: 0, maxWidth: .infinity)
        }
        .background(WindowConfigurator().frame(width: 0, height: 0).accessibilityHidden(true))
        .sheet(item: $store.editingInvoice) { invoice in
            InvoiceEditorView(draft: invoice, isNew: !store.isSaved(invoice))
        }
        .sheet(item: $store.paymentInvoice) { invoice in
            PaymentSheet(invoice: invoice)
        }
    }

    /// De tag moet de buitenste modifier zijn, anders kan de lijst de rij niet selecteren
    /// (een .badge ná .tag maakte ‘Facturen’ onklikbaar).
    private func row(_ item: SidebarItem, badge: Int = 0) -> some View {
        Label(item.rawValue, systemImage: item.icon)
            .badge(badge)
            .tag(item)
    }
}

/// Bedrijfsnaam en opslaglocatie onderin de zijbalk; klik opent de instellingen.
struct SidebarFooter: View {
    @EnvironmentObject var store: Store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button { openSettings() } label: {
            HStack(spacing: 10) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(invoiceAccent.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.data.settings.displayName)
                        .font(.callout.weight(.semibold)).lineLimit(1)
                    Label(store.folderKind.name, systemImage: store.folderKind.icon)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Gegevens staan in \(store.folder.path). Klik voor instellingen.")
        .accessibilityLabel("\(store.data.settings.displayName), gegevens in \(store.folderKind.name)")
        .accessibilityHint("Opent de instellingen")
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

/// Niet-modale bevestiging onderin het venster (verdwijnt vanzelf).
struct NoticeView: View {
    @EnvironmentObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let notice = store.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .modifier(FloatingSurface())
                    .padding(.bottom, 20)
                    .onTapGesture { store.notice = nil }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 1), value: store.notice)
    }
}

// MARK: - Gedeelde kleine views

struct StatusBadge: View {
    let status: InvoiceStatus
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status.color).frame(width: 6, height: 6)
            Text(status.rawValue)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(status.color.opacity(0.1), in: Capsule())
        .foregroundStyle(status.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(status.rawValue)")
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var color: Color = .primary
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                if let icon { Image(systemName: icon).foregroundStyle(color == .primary ? accent : color) }
            }
            .font(.subheadline).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
    }
}

struct YearPicker: View {
    @EnvironmentObject var store: Store
    @Binding var year: Int?
    var allowAll = true

    var body: some View {
        Picker("Jaar", selection: $year) {
            if allowAll { Text("Alle jaren").tag(Int?.none) }
            ForEach(store.years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
        }
        .fixedSize()
    }
}

struct FolderUnavailableView: View {
    @EnvironmentObject var store: Store
    let reason: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 48)).foregroundStyle(.orange)
            Text("Gegevensmap niet bereikbaar").font(.title2.weight(.semibold))
            Text(reason).multilineTextAlignment(.center).foregroundStyle(.secondary).textSelection(.enabled)
                .frame(maxWidth: 520)
            Text("Er wordt niets opgeslagen totdat de map weer bereikbaar is.").font(.callout)
            HStack {
                Button("Opnieuw proberen") { store.load() }.keyboardShortcut(.defaultAction)
                Button("Andere map kiezen…") { store.chooseFolder() }
                Button("Map op deze Mac gebruiken") { store.useDefaultFolder() }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Zwevende melding boven de inhoud: effen en goed leesbaar.
struct FloatingSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.cardFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

/// Venster zonder titelbalk. Verslepen kan via de (onzichtbare) strook bovenin, net als in Muziek/Notities.
/// Bewust níet ‘versleepbaar via achtergrond’: dat kan klikken in lijsten verstoren.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isMovableByWindowBackground = false
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}


/// Dock-icoon volgt de iconenstijl van macOS (Systeeminstellingen → Weergave → Stijl van iconen en widgets):
/// - Standaard: het lichte icoon uit de bundel
/// - Donker: het donkere MediKas-icoon
/// - Helder / Getint: niets overschrijven, zodat macOS zelf de heldere of getinte versie maakt
/// (Zonder Xcode-assetcatalogus kan het icoon zelf geen varianten bevatten; daarom regelt de app dit zolang hij draait.)
@MainActor
final class DockIcon: NSObject {
    static let shared = DockIcon()
    private lazy var dark: NSImage? = Bundle.main.url(forResource: "AppIconDark", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    private var lastTheme: String?

    func start() {
        update()
        // macOS meldt wijzigingen in uiterlijk; bij twijfel ook controleren als de app actief wordt
        for name in ["AppleInterfaceThemeChangedNotification", "AppleIconAppearanceThemeChangedNotification", "AppleColorPreferencesChangedNotification"] {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(changed), name: Notification.Name(name), object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSApplication.didBecomeActiveNotification, object: nil)
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { DockIcon.shared.update() }
        }
    }

    @objc private func changed() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { DockIcon.shared.update() }
    }

    /// Huidige iconenstijl, bv. "RegularDark", "ClearLight", "TintedDark"; nil = Standaard.
    static var theme: String? {
        UserDefaults.standard.string(forKey: "AppleIconAppearanceTheme")   // komt uit het globale domein
    }

    func update() {
        let theme = Self.theme ?? ""
        guard theme != lastTheme else { return }
        lastTheme = theme
        let t = theme.lowercased()
        let useDark = t.contains("dark") && !t.contains("clear") && !t.contains("tint")
        NSApp.applicationIconImage = useDark ? dark : nil   // nil = icoon uit de bundel; macOS past Helder/Getint zelf toe
    }
}
