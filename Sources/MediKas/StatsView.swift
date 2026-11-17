import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var store: Store
    @Local private var year: Int? = Date().year
    @Local private var grouping: Grouping = .maand
    @Local private var basis: DateBasis = .werkdatum
    @Local private var metric: ChartMetric = .omzet
    @Local private var showDetails = true

    private var scopeYear: Int? { grouping == .jaar ? nil : year }
    private var sent: [Invoice] { store.sentInvoices }

    var body: some View {
        let rows = Analytics.periods(sent, grouping: grouping, basis: basis, year: scopeYear)
        let previous = scopeYear.map { Analytics.periods(sent, grouping: grouping, basis: basis, year: $0 - 1) }
        let clients = Analytics.clients(sent, basis: basis, year: scopeYear)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader("Statistieken", subtitle: scopeYear.map { "Per \(grouping.rawValue.lowercased()) in \(String($0)) · op \(basis.rawValue.lowercased())" }
                           ?? "Alle jaren · op \(basis.rawValue.lowercased())") {
                    if grouping != .jaar { YearPicker(year: $year, allowAll: false) }
                    Picker("Op basis van", selection: $basis) {
                        ForEach(DateBasis.allCases) { Text("Op \($0.rawValue.lowercased())").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help("Werkdatum: wanneer je werkte. Factuurdatum: wanneer gefactureerd (relevant voor je boekhouding/aangifte).")
                    Button { exportCSV(rows) } label: { Label("Exporteer", systemImage: "square.and.arrow.up") }
                        .help("Exporteer deze cijfers als CSV (Excel/Numbers)")
                }
                .padding(.bottom, 8)

                if sent.isEmpty {
                    EmptyState(icon: "chart.bar.xaxis", title: "Nog geen cijfers",
                               message: "Zodra je een factuur verstuurt, zie je hier je omzet, uren, kilometers en betaalgedrag per maand, kwartaal of jaar. Concepten tellen niet mee.",
                               primary: ("Naar facturen", { store.sidebar = .facturen }))
                        .card()
                } else if rows.allSatisfy({ $0.invoiced == 0 && $0.received == 0 && $0.hours == 0 }), let y = scopeYear {
                    EmptyState(icon: "calendar", title: "Geen cijfers in \(String(y))",
                               message: "In \(String(y)) zijn er (op \(basis.rawValue.lowercased())) nog geen verstuurde facturen of betalingen.",
                               primary: ("Toon per jaar", { grouping = .jaar }),
                               secondary: ("Huidig jaar", { year = Date().year }))
                        .card()
                } else {
                // Rij 1: kerncijfers + grafiek
                HStack(alignment: .top, spacing: 16) {
                    tiles(rows, previous: previous).frame(maxWidth: .infinity)
                    PeriodChartCard(title: "Verloop", icon: "chart.bar",
                                    rows: { _ in rows }, highlightKey: PeriodKey.of(Date(), grouping), metric: $metric) {
                        Menu {
                            Picker("Groeperen", selection: $grouping) {
                                ForEach(Grouping.allCases) { Text("Per \($0.rawValue.lowercased())").tag($0) }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            Text("Per \(grouping.rawValue.lowercased())")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Rij 2: praktijken (breed) + km en betaalgedrag (smal, gestapeld)
                HStack(alignment: .top, spacing: 16) {
                    clientsCard(clients).frame(maxWidth: .infinity)
                    VStack(spacing: 16) {
                        kmCard(rows)
                        paymentCard
                    }
                    .frame(width: 320)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Rij 3: alle cijfers
                detailsCard(rows)

                Text("Concepten tellen niet mee. ‘\(basis.rawValue)’ bepaalt in welke periode uren, km en omzet vallen; ontvangsten tellen op de betaaldatum.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 28).padding(.top, 6)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .canvas()
        .navigationTitle("Statistieken")
        .onChange(of: grouping) { _, g in if g != .jaar && year == nil { year = Date().year } }
    }

    // MARK: Tegels

    private func tiles(_ rows: [PeriodRow], previous: [PeriodRow]?) -> some View {
        let invoiced = rows.sum(\.invoiced)
        let received = rows.sum(\.received)
        let hours = rows.sum(\.hours)
        let days = rows.reduce(0) { $0 + $1.days }
        let prevInvoiced = previous?.sum(\.invoiced) ?? 0

        var change: (String, Color)? = nil
        if let year = scopeYear, prevInvoiced > 0 {
            let pct = ((invoiced - prevInvoiced) / prevInvoiced * 100).double
            change = ("\(pct >= 0 ? "+" : "−")\(Decimal(abs(pct)).fmt(0))% vs \(String(year - 1))", pct >= 0 ? .green : .orange)
        }
        let receivedPct = invoiced > 0 ? Int((received / invoiced * 100).double.rounded()) : 0

        return VStack(spacing: 16) {
            HStack(spacing: 16) {
                MetricTile(icon: "doc.text", value: invoiced.euro, label: "Gefactureerd",
                           status: change?.0, statusColor: change?.1 ?? .secondary)
                MetricTile(icon: "arrow.down.circle", value: received.euro, label: "Ontvangen:",
                           status: invoiced > 0 ? "\(receivedPct)%" : "—", statusColor: receivedPct >= 90 ? .green : accent)
            }
            HStack(spacing: 16) {
                MetricTile(icon: "clock", value: hours.fmt(1), label: "Uren ·",
                           status: "\(days) werkdagen", statusColor: .secondary)
                MetricTile(icon: "eurosign.circle", value: hours > 0 ? (invoiced / hours).rounded().euro : "—",
                           label: "Per uur", status: "incl. km", statusColor: .secondary)
            }
        }
    }

    // MARK: Praktijken

    private func clientsCard(_ clients: [ClientRow]) -> some View {
        let total = clients.sum(\.invoiced)
        return VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "cross.case", title: "Praktijken", subtitle: "\(clients.count) met omzet in deze periode")
            if clients.isEmpty {
                Text("Nog geen verstuurde facturen in deze periode.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            }
            ForEach(clients) { c in
                HStack(spacing: 12) {
                    Initials(name: c.name)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(c.name).fontWeight(.medium).lineLimit(1)
                            Spacer()
                            Text(c.invoiced.euro).monospacedDigit().fontWeight(.medium)
                        }
                        CapsuleBar(fraction: total > 0 ? (c.invoiced / total).double : 0, height: 6)
                        HStack {
                            Text("\(c.hours.fmt(1)) uur · \(c.km.fmt(0)) km · \(c.invoices) factu\(c.invoices == 1 ? "ur" : "ren")")
                            Spacer()
                            if c.outstanding > 0 {
                                Text("\(c.outstanding.euro) open").foregroundStyle(accent)
                            } else {
                                Text(total > 0 ? "\(Int(((c.invoiced / total) * 100).double.rounded()))%" : "")
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .padding(.vertical, 2)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    // MARK: Kilometers

    private func kmCard(_ rows: [PeriodRow]) -> some View {
        let commute = rows.sum(\.commuteKm).double
        let visits = rows.sum(\.visitKm).double
        let total = commute + visits
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "car", title: "Kilometers")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Decimal(total).fmt(0)).font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.6).monospacedDigit()
                Text("km").foregroundStyle(.secondary)
                Spacer()
                Text(rows.sum(\.kmAmount).rounded().euro).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { geo in
                HStack(spacing: 3) {
                    Capsule().fill(accent).frame(width: total > 0 ? max(6, (geo.size.width - 3) * commute / total) : geo.size.width / 2)
                    Capsule().fill(accent.opacity(0.3))
                }
            }
            .frame(height: 8)
            HStack {
                legend(accent, "Woon-werk", Decimal(commute).fmt(0))
                Spacer()
                legend(accent.opacity(0.3), "Visites", Decimal(visits).fmt(0))
            }
            .font(.caption)
        }
        .card()
    }

    private func legend(_ color: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    // MARK: Betaalgedrag

    private var paymentCard: some View {
        let inScope = sent.filter { scopeYear == nil || $0.date.year == scopeYear }
        let paid = inScope.filter { $0.status() == .paid }
        let days = paid.compactMap { inv in inv.lastPaymentDate.map { nlCalendar.dateComponents([.day], from: inv.date, to: $0).day ?? 0 } }
        let avg = days.isEmpty ? nil : Double(days.reduce(0, +)) / Double(days.count)
        let onTime = paid.filter { ($0.lastPaymentDate ?? .distantFuture) <= $0.dueDate.adding(days: 1) }.count
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "hourglass", title: "Betaalgedrag")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(avg.map { Decimal($0).fmt(0) } ?? "—")
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.6).monospacedDigit()
                Text("dagen gemiddeld").foregroundStyle(.secondary)
            }
            CapsuleBar(fraction: paid.isEmpty ? 0 : Double(onTime) / Double(paid.count), color: .green, height: 8)
            HStack {
                Text(paid.isEmpty ? "Nog geen betaalde facturen" : "\(onTime) van \(paid.count) op tijd betaald")
                Spacer()
                Text("termijn \(store.data.settings.paymentTermDays) d")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    // MARK: Alle cijfers

    private func detailsCard(_ rows: [PeriodRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "tablecells", title: "Alle cijfers", subtitle: "Per \(grouping.rawValue.lowercased())") {
                Button(showDetails ? "Verberg" : "Toon") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 1)) { showDetails.toggle() }
                }
                .buttonStyle(.link)
            }
            if showDetails { periodTable(rows).transition(.opacity) }
        }
        .card()
    }

    /// Echte tabel (macOS): kolomkoppen, afwisselende rijen, rechts uitgelijnde getallen, totaalregel.
    private func periodTable(_ rows: [PeriodRow]) -> some View {
        var total = PeriodRow(key: PeriodKey(year: 9999, index: 99))
        total.label = "Totaal"
        for r in rows {
            total.hours += r.hours; total.commuteKm += r.commuteKm; total.visitKm += r.visitKm
            total.hoursAmount += r.hoursAmount; total.kmAmount += r.kmAmount; total.received += r.received
            total.workDays.formUnion(r.workDays)
        }
        let all = rows + [total]
        func isTotal(_ r: PeriodRow) -> Bool { r.key == total.key }
        func cell(_ text: String, _ r: PeriodRow, color: Color = .primary) -> some View {
            Text(text)
                .monospacedDigit()
                .fontWeight(isTotal(r) ? .semibold : .regular)
                .foregroundStyle(r.invoiced == 0 && r.received == 0 && !isTotal(r) ? .secondary : color)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        return Table(all) {
            TableColumn("Periode") { r in
                Text(r.label).fontWeight(isTotal(r) ? .semibold : .regular)
                    .foregroundStyle(r.invoiced == 0 && r.received == 0 && !isTotal(r) ? .secondary : .primary)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Werkdagen") { r in cell("\(r.days)", r) }.width(min: 70, ideal: 80).alignment(.numeric)
            TableColumn("Uren") { r in cell(r.hours.fmt(), r) }.width(min: 60, ideal: 70).alignment(.numeric)
            TableColumn("Woon-werk km") { r in cell(r.commuteKm.fmt(0), r) }.width(min: 90, ideal: 100).alignment(.numeric)
            TableColumn("Visite km") { r in cell(r.visitKm.fmt(0), r) }.width(min: 70, ideal: 80).alignment(.numeric)
            TableColumn("Werkzaamheden") { r in cell(r.hoursAmount.euro, r) }.width(min: 100, ideal: 120).alignment(.numeric)
            TableColumn("Reiskosten") { r in cell(r.kmAmount.rounded().euro, r) }.width(min: 90, ideal: 100).alignment(.numeric)
            TableColumn("Gefactureerd") { r in cell(r.invoiced.euro, r) }.width(min: 100, ideal: 120).alignment(.numeric)
            TableColumn("Ontvangen") { r in cell(r.received.euro, r) }.width(min: 100, ideal: 120).alignment(.numeric)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .background(TableGridLines().frame(width: 0, height: 0))   // scheidingslijnen tussen de rijen
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .frame(height: CGFloat(all.count) * 24 + 34)
        .accessibilityLabel("Alle cijfers per \(grouping.rawValue.lowercased())")
    }

    private func exportCSV(_ rows: [PeriodRow]) {
        let text = CSV.make(["Periode", "Werkdagen", "Uren", "Woon-werk km", "Visite km", "Bedrag uren", "Km-vergoeding", "Gefactureerd", "Ontvangen"],
                            rows.map { [$0.label, "\($0.days)", CSV.num($0.hours), CSV.num($0.commuteKm), CSV.num($0.visitKm),
                                        CSV.num($0.hoursAmount), CSV.num($0.kmAmount.rounded()), CSV.num($0.invoiced), CSV.num($0.received)] })
        let scope = scopeYear.map(String.init) ?? "alle jaren"
        CSV.save(text, name: "Statistieken per \(grouping.rawValue.lowercased()) \(scope) (\(basis.rawValue.lowercased())).csv")
    }
}
