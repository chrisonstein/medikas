import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openSettings) private var openSettings
    @Local private var metric: ChartMetric = .omzet

    private var year: Int { Date().year }
    private var sent: [Invoice] { store.sentInvoices }
    private var byInvoiceDate: [PeriodRow] { Analytics.periods(sent, grouping: .maand, basis: .factuurdatum, year: year) }
    private var byWorkDate: [PeriodRow] { Analytics.periods(sent, grouping: .maand, basis: .werkdatum, year: year) }
    private var openInvoices: [Invoice] { sent.filter { $0.outstanding > 0 }.sorted { $0.dueDate < $1.dueDate } }
    private var overdue: [Invoice] { openInvoices.filter { $0.status() == .overdue } }
    private var concepts: [Invoice] { store.data.invoices.filter { !$0.isSent }.sorted { $0.date > $1.date } }

    var body: some View {
        let invoiceRows = byInvoiceDate
        let workRows = byWorkDate
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(greeting, subtitle: "\(Date().long.capitalizedFirst) · je praktijk in één oogopslag") {
                    PrimaryToolbarButton(title: "Nieuwe factuur", icon: "plus", shortcut: "⌘N") { store.startNewInvoice() }
                }
                .padding(.bottom, 8)

                // Bij een lege administratie staat dit al als stap 1 in ‘Aan de slag’
                if store.data.settings.isIncomplete && !store.data.invoices.isEmpty {
                    Callout(icon: "person.crop.rectangle", tint: accent,
                            title: "Vul je bedrijfsgegevens in",
                            text: "Naam, adres, KvK, IBAN en je standaard uurtarief komen op elke factuur.",
                            action: ("Instellingen…", { openSettings() }))
                }
                if let warning = store.safetyWarning {
                    Callout(icon: "exclamationmark.shield", tint: .orange,
                            title: "Maak je gegevens veilig", text: warning,
                            action: ("Instellingen…", { openSettings() }))
                }

                if store.data.invoices.isEmpty {
                    gettingStarted
                } else {
                // Rij 1: vier tegels + grafiek
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            MetricTile(icon: "doc.text", value: invoiceRows.sum(\.invoiced).euro,
                                       label: "Gefactureerd", status: String(year), statusColor: .secondary)
                            MetricTile(icon: "arrow.down.circle", value: invoiceRows.sum(\.received).euro,
                                       label: "Ontvangen", status: String(year), statusColor: .secondary)
                        }
                        HStack(spacing: 16) {
                            MetricTile(icon: "clock", value: openInvoices.sum(\.outstanding).euro,
                                       label: "Openstaand:", status: countText(openInvoices.count),
                                       statusColor: openInvoices.isEmpty ? .secondary : accent)
                            MetricTile(icon: "exclamationmark.circle", value: overdue.sum(\.outstanding).euro,
                                       label: "Te laat:", status: overdue.isEmpty ? "geen" : countText(overdue.count),
                                       statusColor: overdue.isEmpty ? .green : .red)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    PeriodChartCard(title: "Per maand", icon: "chart.bar",
                                    rows: { $0.usesWorkDate ? workRows : invoiceRows },
                                    highlightKey: PeriodKey.of(Date(), .maand), metric: $metric) {
                        Text(String(year)).font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Rij 2: te doen + deze maand
                HStack(alignment: .top, spacing: 16) {
                    todoCard.frame(maxWidth: .infinity)
                    monthCard(workRows).frame(width: 300)
                }
                .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 28).padding(.top, 6)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .canvas()
        .navigationTitle("Overzicht")
    }

    // MARK: Lege toestand: aan de slag

    private var gettingStarted: some View {
        let s1 = !store.data.settings.isIncomplete
        let s2 = !store.activeClients.isEmpty
        return VStack(alignment: .leading, spacing: 18) {
            EmptyState(icon: "sparkles", title: "Welkom bij MediKas",
                       message: "Hier zie je straks in één oogopslag wat je hebt gefactureerd, wat er binnen is en wat nog openstaat. In drie stappen ben je klaar voor je eerste factuur.")
                .padding(.bottom, -16)
            VStack(spacing: 10) {
                step(1, done: s1, title: "Vul je bedrijfsgegevens in",
                     detail: "Naam, adres, KvK, IBAN en je standaard uurtarief. AGB-code is optioneel.",
                     action: ("Instellingen…", { openSettings() }))
                step(2, done: s2, title: "Voeg een praktijk toe",
                     detail: "De praktijk waar je waarneemt, met adres en woon-werk km.",
                     action: ("Praktijk toevoegen", {
                         let id = store.addClient().id
                         store.sidebar = .praktijken
                         DispatchQueue.main.async { store.selectedClientID = id }
                     }))
                step(3, done: false, title: "Maak je eerste factuur",
                     detail: "Werkdagen, uren en kilometers; de PDF maakt MediKas.",
                     action: ("Nieuwe factuur", { store.startNewInvoice() }), enabled: s2)
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 12)
        .card(padding: 28)
    }

    private func step(_ n: Int, done: Bool, title: String, detail: String,
                      action: (String, () -> Void), enabled: Bool = true) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(done ? Color.green.opacity(0.15) : Color.well).frame(width: 32, height: 32)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.green)
                } else {
                    Text("\(n)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium).strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? .secondary : .primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !done {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!enabled)
            }
        }
        .padding(12)
        .background(Color.well.opacity(done ? 0.4 : 0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func countText(_ n: Int) -> String { "\(n) factu\(n == 1 ? "ur" : "ren")" }

    private var greeting: String {
        let h = nlCalendar.component(.hour, from: Date())
        let part = h < 12 ? "Goedemorgen" : h < 18 ? "Goedemiddag" : "Goedenavond"
        // Eerste naamdeel zonder titel of voorletters: "Dr. Anna Jansen" → "Anna"
        let skip: Set<String> = ["dr", "drs", "mr", "ir", "prof", "mevr", "dhr"]
        let first = store.data.settings.ownerName.split(separator: " ").map(String.init)
            .first { part in
                let bare = part.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return !skip.contains(bare) && !part.contains(".")
            } ?? ""
        return first.isEmpty ? part : "\(part), \(first)"
    }

    // MARK: Nog te doen

    private var todoCard: some View {
        let items = concepts + openInvoices
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "checklist", title: "Nog te doen",
                       subtitle: items.isEmpty ? nil : "\(concepts.count) concept\(concepts.count == 1 ? "" : "en") · \(openInvoices.count) open") {
                if items.count > 6 { Button("Toon alle") { store.sidebar = .facturen }.buttonStyle(.link) }
            }
            if items.isEmpty {
                EmptyState(icon: "checkmark.seal", title: "Alles is bij",
                           message: "Geen concepten en geen openstaande facturen.", compact: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(6).enumerated()), id: \.element.id) { i, inv in
                        if i > 0 { Divider().opacity(0.5).padding(.leading, 50) }
                        OpenInvoiceRow(invoice: inv)
                    }
                }
            }
        }
        .card()
    }

    // MARK: Deze maand

    private func monthCard(_ rows: [PeriodRow]) -> some View {
        let now = Date()
        let current = rows.first { $0.key.index == now.month }
        let earlier = rows.filter { $0.key.index < now.month && $0.hours > 0 }
        let avg = earlier.isEmpty ? 0 : earlier.sum(\.hours).double / Double(earlier.count)
        let hours = current?.hours.double ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            CardHeader(icon: "calendar", title: Fmt.month.string(from: now).capitalizedFirst, subtitle: "Deze maand")
            Spacer(minLength: 18)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Decimal(hours).fmt(1))
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).tracking(-1)
                    .monospacedDigit()
                Text("uur").font(.title3).foregroundStyle(.secondary)
            }
            Text("\(current?.days ?? 0) werkdagen · \((current?.km ?? 0).fmt(0)) km")
                .font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 18)
            if avg > 0 {
                CapsuleBar(fraction: hours / avg)
                HStack {
                    Text("Gemiddeld \(Decimal(avg).fmt(0)) uur per maand")
                    Spacer()
                    Text("\(Int((hours / avg * 100).rounded()))%").monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }
        }
        .card()
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Opvallende maar rustige melding met één duidelijke actie.
struct Callout: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String
    var action: (String, () -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let action { Button(action.0, action: action.1) }
        }
        .padding(16)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 0.5))
    }
}

struct OpenInvoiceRow: View {
    @EnvironmentObject var store: Store
    let invoice: Invoice
    @Local private var hovering = false

    init(invoice: Invoice) { self.invoice = invoice }

    var body: some View {
        HStack(spacing: 12) {
            // Klik op de rij opent de factuur
            Button { store.edit(invoice) } label: {
                HStack(spacing: 12) {
                    Initials(name: invoice.billTo.displayName)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(invoice.billTo.displayName).fontWeight(.medium).lineLimit(1)
                        Text(invoice.isSent ? "\(invoice.number) · vervalt \(invoice.dueDate.long)" : "\(invoice.number) · concept van \(invoice.date.long)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(invoice.isSent ? invoice.outstanding.euro : invoice.total.euro)
                        .monospacedDigit().fontWeight(.medium)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Factuur \(invoice.number) openen")
            ZStack(alignment: .trailing) {
                StatusBadge(status: invoice.status()).opacity(hovering ? 0 : 1)
                Group {
                    if invoice.isSent {
                        Button("Betaling…") { store.paymentInvoice = invoice }
                    } else {
                        Button("Openen") { store.edit(invoice) }
                    }
                }
                .controlSize(.small)
                .opacity(hovering ? 1 : 0)
            }
            .frame(width: 112, alignment: .trailing)
        }
        .padding(.vertical, 8).padding(.horizontal, 8)
        .background(hovering ? Color.well : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .contextMenu {
            Button("Openen…") { store.edit(invoice) }
            if invoice.isSent && invoice.outstanding > 0 {
                Button("Betaling registreren…") { store.paymentInvoice = invoice }
                Button("Markeer als volledig betaald") { store.markPaid(invoice) }
            }
        }
    }
}
