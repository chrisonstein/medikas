import SwiftUI
import MapKit

// Praktijk zoeken op naam via Apple Kaarten: suggesties onder het naamveld,
// en bij kiezen worden naam, adres, postcode en plaats ingevuld (daarna gewoon te wijzigen).

/// Een gevonden adres, opgesplitst in de velden van een praktijk.
struct FoundAddress {
    var name: String?
    var address: String
    var postalCode: String
    var city: String
}

@MainActor
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        // Nederland als voorkeursgebied
        completer.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 52.2, longitude: 5.3),
                                              span: MKCoordinateSpan(latitudeDelta: 3.6, longitudeDelta: 3.6))
    }

    func search(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.count < 3 { clear(); return }
        completer.queryFragment = q
    }

    func clear() {
        completer.cancel()
        results = []
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = Array(completer.results.prefix(6))
        Task { @MainActor in self.results = found }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    /// Haalt de volledige adresgegevens op voor een gekozen suggestie.
    static func resolve(_ completion: MKLocalSearchCompletion) async -> FoundAddress? {
        guard let item = try? await MKLocalSearch(request: .init(completion: completion)).start().mapItems.first
        else { return nil }
        let p = item.placemark
        let street = [p.thoroughfare, p.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        return FoundAddress(
            name: item.pointOfInterestCategory != nil || !completion.subtitle.isEmpty ? item.name : nil,
            address: street,
            postalCode: formatPostcode(p.postalCode ?? ""),
            city: p.locality ?? "")
    }

    /// "1234AB" → "1234 AB"; andere formaten blijven zoals ze zijn.
    static func formatPostcode(_ s: String) -> String {
        let t = s.replacingOccurrences(of: " ", with: "").uppercased()
        guard t.range(of: #"^\d{4}[A-Z]{2}$"#, options: .regularExpression) != nil else { return s }
        return "\(t.prefix(4)) \(t.suffix(2))"
    }
}

/// Naamveld voor een praktijk met adressuggesties uit Apple Kaarten.
/// ↑/↓ = door de suggesties, ↩ = kiezen, Esc = sluiten.
struct PracticeNameField: View {
    @Binding var client: Client
    var autofocus = false

    @StateObject private var search = PlaceSearch()
    @Local private var highlighted = 0
    @Local private var userTyped = false      // alleen zoeken na eigen invoer, niet bij openen
    @Local private var resolving = false
    @FocusState private var focused: Bool

    private var showList: Bool { focused && userTyped && !search.results.isEmpty }

    var body: some View {
        HStack(spacing: 7) {
            TextField(client.address.isEmpty ? "Naam van de praktijk — typ om het adres op te zoeken" : "Naam van de praktijk",
                      text: $client.name)
                .labelsHidden()
                .textFieldStyle(.plain)
                .focused($focused)
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.return) {
                    guard showList else { return .ignored }
                    pick(search.results[min(highlighted, search.results.count - 1)])
                    return .handled
                }
                .onExitCommand { search.clear(); userTyped = false }
            if resolving {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary).font(.callout)
                    .help("Typ de naam: MediKas zoekt het adres op in Apple Kaarten")
                    .accessibilityHidden(true)
            }
        }
        .modifier(FieldSurface(focused: focused))
        // Zwevende keuzelijst over de velden eronder (de omliggende views zetten zIndex hoger)
        .overlay(alignment: .top) {
            if showList {
                suggestions
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: 36)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: showList)
        .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
        .onChange(of: client.name) { _, new in
            guard focused else { return }
            userTyped = true
            highlighted = 0
            search.search(new)
        }
        .onChange(of: focused) { _, f in if !f { userTyped = false } }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(search.results.enumerated()), id: \.offset) { i, r in
                Button { pick(r) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: r.subtitle.isEmpty ? "mappin" : "building.2")
                            .foregroundStyle(.secondary).frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.title).lineLimit(1)
                            if !r.subtitle.isEmpty {
                                Text(r.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(i == highlighted ? accent.opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { highlighted = i } }
            }
            Text("Suggesties uit Apple Kaarten · je kunt alles daarna aanpassen")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 8).padding(.top, 4)
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard showList else { return .ignored }
        highlighted = max(0, min(search.results.count - 1, highlighted + delta))
        return .handled
    }

    private func pick(_ completion: MKLocalSearchCompletion) {
        search.clear()
        userTyped = false
        resolving = true
        Task {
            defer { resolving = false }
            guard let found = await PlaceSearch.resolve(completion) else { return }
            if let name = found.name, !name.isEmpty { client.name = name }
            if !found.address.isEmpty { client.address = found.address }
            if !found.postalCode.isEmpty { client.postalCode = found.postalCode }
            if !found.city.isEmpty { client.city = found.city }
        }
    }
}
