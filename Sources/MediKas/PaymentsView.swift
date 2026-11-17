import SwiftUI

struct PaymentRowItem: Identifiable {
    var id: UUID { payment.id }
    var payment: Payment
    var invoice: Invoice
}

struct PaymentsView: View {
    @EnvironmentObject var store: Store
    @Local private var year: Int? = Date().year
    @Local private var search = ""

    private var rows: [PaymentRowItem] {
        store.data.invoices.flatMap { inv in inv.payments.map { PaymentRowItem(payment: $0, invoice: inv) } }
            .filter { year == nil || $0.payment.date.year == year }
            .filter { search.isEmpty || $0.invoice.number.localizedCaseInsensitiveContains(search)
                || $0.invoice.billTo.displayName.localizedCaseInsensitiveContains(search)
                || $0.payment.note.localizedCaseInsensitiveContains(search) }
            .sorted { $0.payment.date > $1.payment.date }
    }

    private var open: [Invoice] {
        store.sentInvoices.filter { $0.outstanding > 0 }.sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        let rows = rows
        let open = open
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader("Betalingen", subtitle: "\(rows.sum(\.payment.amount).euro) ontvangen \(year.map { "in \(String($0))" } ?? "in totaal") · \(open.sum(\.outstanding).euro) openstaand") {
                    YearPicker(year: $year)
                    Button { exportCSV(rows) } label: { Label("Exporteer", systemImage: "square.and.arrow.up") }
                        .help("Exporteer de betalingen als CSV (Excel/Numbers)")
                }
                .padding(.bottom, 8)

                if store.sentInvoices.isEmpty {
                    EmptyState(icon: "eurosign.circle", title: "Nog geen betalingen",
                               message: "Zodra je facturen verstuurt, zie je hier wat nog openstaat en wat er binnen is. Een betaling registreer je met één klik.",
                               primary: ("Naar facturen", { store.sidebar = .facturen }))
                        .card()
                } else {
                // Openstaand
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(icon: "clock", title: "Openstaand",
                               subtitle: open.isEmpty ? nil : "\(open.count) factu\(open.count == 1 ? "ur" : "ren") · oudste eerst")
                    if open.isEmpty {
                        EmptyState(icon: "checkmark.seal", title: "Alles is betaald",
                                   message: "Er staan geen facturen meer open.", compact: true)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(open.enumerated()), id: \.element.id) { i, inv in
                                if i > 0 { Divider().opacity(0.5).padding(.leading, 50) }
                                OpenInvoiceRow(invoice: inv)
                            }
                        }
                    }
                }
                .card()

                // Ontvangen
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(icon: "arrow.down.circle", title: "Ontvangen", subtitle: "\(rows.count) betalingen") {
                        SearchField("Zoeken", text: $search, width: 220)
                            .help("Zoek op factuurnummer, praktijk of notitie (⌘F)")
                    }
                    if rows.isEmpty && !search.isEmpty {
                        EmptyState(icon: "magnifyingglass", title: "Niets gevonden voor ‘\(search)’",
                                   message: "Zoek op factuurnummer, praktijk of notitie.",
                                   primary: ("Wis zoekopdracht", { search = "" }), compact: true)
                    } else if rows.isEmpty {
                        EmptyState(icon: "tray", title: year.map { "Nog geen betalingen in \(String($0))" } ?? "Nog geen betalingen",
                                   message: "Registreer een betaling bij een openstaande factuur hierboven.",
                                   secondary: year == nil ? nil : ("Toon alle jaren", { year = nil }), compact: true)
                    } else {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Text("Ontvangen op").frame(width: 110, alignment: .leading)
                                Text("Factuur").frame(width: 124, alignment: .leading)
                                Text("Opdrachtgever").frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                                Text("Bedrag").frame(width: 110, alignment: .trailing)
                                Text("Notitie").frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                                Color.clear.frame(width: 20)
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.bottom, 8)
                            .overlay(alignment: .bottom) { Divider().opacity(0.6) }
                            ForEach(rows) { PaymentTableRow(item: $0) }
                        }
                    }
                }
                .card(padding: 18)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 28).padding(.top, 6)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .canvas()
        .navigationTitle("Betalingen")
    }

    private func exportCSV(_ rows: [PaymentRowItem]) {
        let text = CSV.make(["Datum", "Factuurnummer", "Opdrachtgever", "Bedrag", "Notitie"],
                            rows.map { [$0.payment.date.short, $0.invoice.number, $0.invoice.billTo.displayName, CSV.num($0.payment.amount), $0.payment.note] })
        CSV.save(text, name: "Betalingen \(year.map(String.init) ?? "alle jaren").csv")
    }
}

struct PaymentTableRow: View {
    @EnvironmentObject var store: Store
    let item: PaymentRowItem
    @Local private var hovering = false

    init(item: PaymentRowItem) { self.item = item }

    var body: some View {
        HStack(spacing: 12) {
            Text(item.payment.date.short).monospacedDigit().lineLimit(1).frame(width: 110, alignment: .leading)
            Button { store.openPDF(item.invoice) } label: {
                HStack(spacing: 4) {
                    Text(item.invoice.number).foregroundStyle(accent).fontWeight(.medium).monospacedDigit().lineLimit(1).fixedSize()
                    PDFBadge().opacity(0.8)
                }
                .frame(width: 124, height: 28, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open PDF")
            Button { store.edit(item.invoice) } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Initials(name: item.invoice.billTo.displayName, size: 24)
                        Text(item.invoice.billTo.displayName).lineLimit(1)
                    }
                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                    Text(item.payment.amount.euro).monospacedDigit().fontWeight(.medium).frame(width: 110, alignment: .trailing)
                    Text(item.payment.note).foregroundStyle(.secondary).lineLimit(1)
                        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Factuur \(item.invoice.number) openen")
            Button { store.deletePayment(item.payment.id, from: item.invoice.id) } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless).frame(width: 20)
            .opacity(hovering ? 1 : 0)
            .help("Betaling verwijderen (⌘Z maakt ongedaan)")
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(hovering ? Color.well : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .rowSeparator()
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hovering = h } }
        .contextMenu {
            Button("Factuur openen…") { store.edit(item.invoice) }
            Button("Open PDF") { store.openPDF(item.invoice) }
            Divider()
            Button("Betaling verwijderen", role: .destructive) { store.deletePayment(item.payment.id, from: item.invoice.id) }
        }
    }
}
