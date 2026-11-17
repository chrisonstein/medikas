import SwiftUI

/// Filter voor factuurlijsten (facturenoverzicht én facturen op een praktijkpagina).
/// Datums gaan over de factuurdatum.
struct InvoiceFilter: Equatable {
    var year: Int? = Date().year
    var month: Int? = nil              // 1-12, alleen met een jaar
    var from: Date? = nil              // eigen datumbereik (gaat vóór jaar/maand)
    var to: Date? = nil
    var clientID: UUID? = nil
    var status: StatusFilter = .alle
    var search = ""

    var hasRange: Bool { from != nil || to != nil }

    /// Alles behalve de status (zodat de statuschips hun aantallen kunnen tonen).
    func matchesExceptStatus(_ inv: Invoice) -> Bool {
        if hasRange {
            if let from, inv.date < from.startOfDay { return false }
            if let to, inv.date > to.startOfDay { return false }
        } else {
            if let year, inv.date.year != year { return false }
            if let month, inv.date.month != month { return false }
        }
        if let clientID, inv.clientID != clientID { return false }
        if !search.isEmpty {
            let hit = inv.number.localizedCaseInsensitiveContains(search)
                || inv.billTo.displayName.localizedCaseInsensitiveContains(search)
                || inv.memo.localizedCaseInsensitiveContains(search)
                || inv.notes.localizedCaseInsensitiveContains(search)
            if !hit { return false }
        }
        return true
    }

    func matches(_ inv: Invoice) -> Bool { matchesExceptStatus(inv) && status.matches(inv) }

    /// Wijkt af van de standaard (voor ‘Wis filters’).
    func isActive(comparedTo base: InvoiceFilter) -> Bool { self != base }

    /// Korte omschrijving van de periode, bv. "maart 2026" of "1 jan – 31 mrt 2026".
    var periodText: String {
        if hasRange {
            let f = from.map { Fmt.short.string(from: $0) } ?? "…"
            let t = to.map { Fmt.short.string(from: $0) } ?? "…"
            return "\(f) – \(t)"
        }
        guard let year else { return "Alle jaren" }
        if let month, let d = nlCalendar.date(from: DateComponents(year: year, month: month, day: 1)) {
            return Fmt.monthYear.string(from: d)
        }
        return String(year)
    }
}

/// Filterbalk boven een factuurtabel: status, jaar, maand, (opdrachtgever), datumbereik, zoeken.
struct InvoiceFilterBar: View {
    @EnvironmentObject var store: Store
    @Binding var filter: InvoiceFilter
    /// Facturen waarop gefilterd wordt (voor aantallen en beschikbare jaren).
    let source: [Invoice]
    var showClient = true
    var defaultFilter = InvoiceFilter()
    var searchWidth: CGFloat = 240

    @Local private var showRange = false
    @Local private var rangeFrom = Date().startOfDay
    @Local private var rangeTo = Date().startOfDay

    init(filter: Binding<InvoiceFilter>, source: [Invoice], showClient: Bool = true,
         defaultFilter: InvoiceFilter = InvoiceFilter(), searchWidth: CGFloat = 240) {
        _filter = filter; self.source = source; self.showClient = showClient
        self.defaultFilter = defaultFilter; self.searchWidth = searchWidth
    }

    private var years: [Int] {
        var set = Set(source.map(\.date.year)); set.insert(Date().year)
        return set.sorted(by: >)
    }

    private var clients: [Client] {
        let ids = Set(source.compactMap(\.clientID))
        return store.data.clients.filter { ids.contains($0.id) || !$0.archived }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        let base = source.filter(filter.matchesExceptStatus)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ChipPicker(options: StatusFilter.allCases, selection: $filter.status) { s in
                    let n = base.filter(s.matches).count
                    return s == .alle ? "Alle \(n)" : "\(s.rawValue) \(n)"
                }
                Spacer(minLength: 8)
                SearchField("Zoeken", text: $filter.search, width: searchWidth)
                    .help("Zoek op factuurnummer, praktijk of opmerking (⌘F)")
            }

            HStack(spacing: 8) {
                // Jaar
                Picker("Jaar", selection: Binding(get: { filter.year }, set: { filter.year = $0; if $0 == nil { filter.month = nil } })) {
                    Text("Alle jaren").tag(Int?.none)
                    Divider()
                    ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                }
                .labelsHidden().fixedSize()
                .disabled(filter.hasRange)
                .help("Jaar (factuurdatum)")

                // Maand
                Picker("Maand", selection: $filter.month) {
                    Text("Alle maanden").tag(Int?.none)
                    Divider()
                    ForEach(1...12, id: \.self) { m in
                        Text(Fmt.month.string(from: nlCalendar.date(from: DateComponents(year: 2026, month: m, day: 1))!).capitalizedFirst)
                            .tag(Int?.some(m))
                    }
                }
                .labelsHidden().fixedSize()
                .disabled(filter.year == nil || filter.hasRange)
                .help(filter.year == nil ? "Kies eerst een jaar" : "Maand (factuurdatum)")

                // Opdrachtgever
                if showClient {
                    Picker("Opdrachtgever", selection: $filter.clientID) {
                        Text("Alle opdrachtgevers").tag(UUID?.none)
                        Divider()
                        ForEach(clients) { Text($0.displayName).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden().fixedSize()
                    .help("Opdrachtgever")
                }

                // Eigen datumbereik
                Button {
                    rangeFrom = filter.from ?? nlCalendar.date(from: DateComponents(year: filter.year ?? Date().year, month: filter.month ?? 1, day: 1)) ?? Date()
                    rangeTo = filter.to ?? Date().startOfDay
                    showRange = true
                } label: {
                    Label(filter.hasRange ? filter.periodText : "Van – tot…", systemImage: "calendar")
                        .labelStyle(.titleAndIcon)
                }
                .help("Filter op een eigen periode, bijvoorbeeld een kwartaal")
                .popover(isPresented: $showRange, arrowEdge: .bottom) { rangePopover }

                if filter.hasRange {
                    Button { filter.from = nil; filter.to = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help("Datumbereik wissen").accessibilityLabel("Datumbereik wissen")
                }

                Spacer(minLength: 8)

                if filter.isActive(comparedTo: defaultFilter) {
                    Text("\(base.filter(filter.status.matches).count) van \(source.count)")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    Button("Wis filters") {
                        withAnimation(.easeOut(duration: 0.15)) { filter = defaultFilter }
                    }
                    .buttonStyle(.link)
                }
            }
            .controlSize(.regular)
        }
    }

    private var rangePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Eigen periode").font(.headline)
            HStack(spacing: 10) {
                LabeledField(label: "Van") { DateField(date: $rangeFrom) }.frame(width: 190)
                LabeledField(label: "Tot en met") { DateField(date: $rangeTo) }.frame(width: 190)
            }
            // Snelkeuzes
            HStack(spacing: 6) {
                ForEach(1...4, id: \.self) { q in
                    Button("K\(q)") { setQuarter(q) }.controlSize(.small)
                }
                Button("Dit jaar") {
                    let y = filter.year ?? Date().year
                    rangeFrom = nlCalendar.date(from: DateComponents(year: y, month: 1, day: 1))!
                    rangeTo = nlCalendar.date(from: DateComponents(year: y, month: 12, day: 31))!
                }
                .controlSize(.small)
            }
            HStack {
                if filter.hasRange {
                    Button("Wis") { filter.from = nil; filter.to = nil; showRange = false }
                }
                Spacer()
                Button("Annuleer") { showRange = false }.keyboardShortcut(.cancelAction)
                Button("Toepassen") {
                    filter.from = min(rangeFrom, rangeTo)
                    filter.to = max(rangeFrom, rangeTo)
                    showRange = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    private func setQuarter(_ q: Int) {
        let y = filter.year ?? Date().year
        rangeFrom = nlCalendar.date(from: DateComponents(year: y, month: (q - 1) * 3 + 1, day: 1))!
        let nextStart = nlCalendar.date(from: DateComponents(year: y, month: q * 3 + 1, day: 1)) ?? rangeFrom
        rangeTo = nextStart.adding(days: -1)
    }
}
