import SwiftUI
import AppKit

// MARK: - Weergave-instellingen (per Mac)

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var label: String { switch self { case .system: "Automatisch"; case .light: "Licht"; case .dark: "Donker" } }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case zorggroen, blauw, salie, lavendel, grafiet, systeem
    var id: Self { self }

    var label: String {
        switch self {
        case .zorggroen: "Zorggroen"
        case .blauw: "Rustig blauw"
        case .salie: "Salie"
        case .lavendel: "Lavendel"
        case .grafiet: "Grafiet"
        case .systeem: "Systeem"
        }
    }

    /// Licht- en donkervariant: in donker iets lichter, zodat het contrast klopt.
    var color: Color {
        func dyn(_ l: (CGFloat, CGFloat, CGFloat), _ d: (CGFloat, CGFloat, CGFloat)) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let c = dark ? d : l
                return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
            })
        }
        switch self {
        case .zorggroen: return dyn((0.10, 0.45, 0.47), (0.33, 0.70, 0.70))
        case .blauw: return dyn((0.36, 0.50, 0.84), (0.54, 0.66, 0.96))
        case .salie: return dyn((0.33, 0.52, 0.41), (0.52, 0.73, 0.60))
        case .lavendel: return dyn((0.49, 0.42, 0.78), (0.66, 0.60, 0.94))
        case .grafiet: return dyn((0.27, 0.29, 0.33), (0.80, 0.82, 0.86))
        case .systeem: return Color(nsColor: .controlAccentColor)
        }
    }
}

@MainActor
final class Theme: ObservableObject {
    static let shared = Theme()

    @Published var appearance: AppearanceMode { didSet { save(); apply() } }
    @Published var accentChoice: AccentChoice { didSet { save() } }

    private init() {
        let d = UserDefaults.standard
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        accentChoice = AccentChoice(rawValue: d.string(forKey: "accent") ?? "") ?? .zorggroen
        d.removeObject(forKey: "surface")   // oude instelling (Liquid Glass) opruimen
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(appearance.rawValue, forKey: "appearance")
        d.set(accentChoice.rawValue, forKey: "accent")
    }

    /// Zet licht/donker voor de hele app, ook voor meldingen en panelen.
    func apply() {
        NSApp.appearance = appearance.nsAppearance
    }
}

/// Accentkleur van de app (volgt de instelling).
@MainActor var accent: Color { Theme.shared.accentChoice.color }

/// Vaste huisstijlkleur op de factuur, zodat facturen er altijd hetzelfde uitzien.
let invoiceAccent = Color(red: 0.10, green: 0.45, blue: 0.47)

// MARK: - Kleuren van het canvas en de kaarten

extension Color {
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    /// Rustige, licht koele achtergrond waar de kaarten op liggen.
    static let canvas = dynamic(light: NSColor(srgbRed: 0.945, green: 0.949, blue: 0.957, alpha: 1),
                                dark: NSColor(srgbRed: 0.105, green: 0.108, blue: 0.118, alpha: 1))
    static let cardFill = dynamic(light: .white,
                                  dark: NSColor(srgbRed: 0.165, green: 0.168, blue: 0.180, alpha: 1))
    /// Zachte vulling voor velden en rijen binnen een kaart.
    static let well = dynamic(light: NSColor(srgbRed: 0.955, green: 0.958, blue: 0.965, alpha: 1),
                              dark: NSColor(white: 1, alpha: 0.06))
}

// MARK: - Canvas

/// Achtergrond van een scherm: één rustige, effen kleur (geen verloop; strak en goed leesbaar).
struct CanvasBackground: View {
    var body: some View {
        Color.canvas.ignoresSafeArea()
    }
}

// MARK: - Kaart

struct CardModifier: ViewModifier {
    @ObservedObject var theme = Theme.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var padding: CGFloat = 20
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let padded = content.padding(padding).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // ‘Meer contrast’ (Toegankelijkheid): duidelijke rand om elke kaart
        let border = contrast == .increased ? Color.primary.opacity(0.45) : Color.primary.opacity(scheme == .dark ? 0.07 : 0.05)
        padded
            .background(Color.cardFill, in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: contrast == .increased ? 1 : 0.5))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.035), radius: 12, y: 3)
    }
}

extension View {
    func card(padding: CGFloat = 20, radius: CGFloat = 22) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }

    /// Schermachtergrond voor bento-schermen.
    func canvas() -> some View { background(CanvasBackground()) }
}

/// Kaartkop: icoon in een zacht vlak, titel en optioneel iets rechts (bv. een menu).
struct CardHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconWell(icon: icon).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.title3.weight(.semibold)).tracking(-0.2)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct IconWell: View {
    let icon: String
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(.primary.opacity(0.8))
            .frame(width: size, height: size)
            .background(Color.well, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Groot getal-tegel zoals in een bento grid: icoon linksboven, getal, label met status.
struct MetricTile: View {
    let icon: String
    let value: String
    let label: String
    var status: String? = nil
    var statusColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.primary.opacity(0.75))
            Spacer(minLength: 18)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .tracking(-0.5)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.55)
                .contentTransition(.numericText())
            HStack(spacing: 4) {
                Text(label).foregroundStyle(.secondary)
                if let status { Text(status).foregroundStyle(statusColor).fontWeight(.medium) }
            }
            .font(.callout)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.trimmingCharacters(in: CharacterSet(charactersIn: ":· ")))
        .accessibilityValue([value, status].compactMap { $0 }.joined(separator: ", "))
    }
}

/// Keuzechips (zoals een scope bar): één actief, rustig vormgegeven.
struct ChipPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .foregroundStyle(selected ? Color(nsColor: .windowBackgroundColor) : .primary)
                        .background {
                            Capsule().fill(selected ? Color.primary.opacity(0.85) : Color.clear)
                            Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.12), lineWidth: 0.5)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Dunne voortgangs-/verhoudingsbalk.
struct CapsuleBar: View {
    let fraction: Double
    var color: Color = accent
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.well)
                Capsule().fill(LinearGradient(colors: [color.opacity(0.55), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Paginakop

/// Kop van een pagina: titel en ondertitel links, acties rechts op dezelfde regel.
/// (Het venster heeft geen titelbalk; dit is de enige titel, dus geen dubbele titels.)
struct PageHeader<Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var actions: () -> Actions

    init(_ title: String, subtitle: String? = nil, @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title; self.subtitle = subtitle; self.actions = actions
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.7)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { actions() }
                .controlSize(.large)
        }
        .padding(.bottom, 4)
    }
}

extension PageHeader where Actions == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// Compacte cijfertegel (voor beknopte overzichten): icoon + label, getal eronder.
struct CompactMetric: View {
    let icon: String
    let label: String
    let value: String
    var detail: String? = nil
    var detailColor: Color = .secondary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconWell(icon: icon, size: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.callout).foregroundStyle(.secondary)
                Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let detail { Text(detail).font(.caption).foregroundStyle(detailColor).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 16, radius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue([value, detail].compactMap { $0 }.joined(separator: ", "))
    }
}

// MARK: - Tabellen

/// Klein PDF-label (macOS heeft geen PDF-symbool); gebruikt achter factuurnummers die de PDF openen.
struct PDFBadge: View {
    var body: some View {
        Text("PDF")
            .font(.system(size: 8.5, weight: .heavy))
            .tracking(0.3)
            .foregroundStyle(.white)
            .padding(.horizontal, 3.5).padding(.vertical, 1.5)
            .background(Color(red: 0.84, green: 0.20, blue: 0.17), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension View {
    /// Dunne scheidingslijn onder een tabelrij (systeemkleur, volgt licht/donker en ‘Meer contrast’).
    func rowSeparator(inset: CGFloat = 12) -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .padding(.horizontal, inset)
                .accessibilityHidden(true)
        }
    }
}

/// Zet bij een native SwiftUI-tabel horizontale rasterlijnen aan (i.p.v. afwisselende rijkleuren),
/// zodat alle tabellen in de app dezelfde scheidingslijnen hebben.
struct TableGridLines: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { Self.apply(from: v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(from: nsView) }
    }
    private static func apply(from view: NSView) {
        // Zoek de dichtstbijzijnde NSTableView in dezelfde container
        var container: NSView? = view.superview
        for _ in 0..<6 {
            if let c = container, let table = findTable(in: c) {
                table.gridStyleMask = [.solidHorizontalGridLineMask]
                table.gridColor = .separatorColor
                table.usesAlternatingRowBackgroundColors = false
                return
            }
            container = container?.superview
        }
    }
    private static func findTable(in view: NSView) -> NSTableView? {
        if let t = view as? NSTableView { return t }
        for s in view.subviews { if let t = findTable(in: s) { return t } }
        return nil
    }
}
