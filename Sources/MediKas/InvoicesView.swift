import SwiftUI

// MARK: - Filters en sortering

enum StatusFilter: String, CaseIterable, Identifiable {
    case alle = "Alle", concept = "Concept", open = "Open", teLaat = "Te laat", betaald = "Betaald"
    var id: Self { self }

    func matches(_ inv: Invoice) -> Bool {
        switch self {
        case .alle: true
        case .concept: inv.status() == .concept
        case .open: inv.status() == .open || inv.status() == .partial
        case .teLaat: inv.status() == .overdue
        case .betaald: inv.status() == .paid
        }
    }
}

enum InvoiceSort: String { case number, date, client, amount, due, paid, status }

// MARK: - Facturenoverzicht

struct InvoicesView: View {
    @EnvironmentObject var store: Store
    @Local private var filter = InvoiceFilter()
    @Local private var sort: InvoiceSort = .number
    @Local private var ascending = false
    @Local private var confirmDelete: Invoice?
    /// Beschikbare breedte; bij smal venster vallen minder belangrijke kolommen weg.
    @Local private var tableWidth: CGFloat = 1200
    /// Volledige tabel heeft ±1060 pt nodig; anders vallen ‘Betaald op’ en ‘Opmerking’ weg.
    private var compact: Bool { tableWidth < 1090 }

    private var rows: [Invoice] {
        let list = store.data.invoices.filter(filter.matches)
        let sorted: [Invoice]
        switch sort {
        case .number: sorted = list.sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
        case .date: sorted = list.sorted { $0.date < $1.date }
        case .client: sorted = list.sorted { $0.billTo.displayName.localizedCaseInsensitiveCompare($1.billTo.displayName) == .orderedAscending }
        case .amount: sorted = list.sorted { $0.total < $1.total }
        case .due: sorted = list.sorted { $0.dueDate < $1.dueDate }
        case .paid: sorted = list.sorted { ($0.paidDate ?? .distantFuture) < ($1.paidDate ?? .distantFuture) }
        case .status: sorted = list.sorted { $0.status().rawValue < $1.status().rawValue }
        }
        return ascending ? sorted : sorted.reversed()
    }

    var body: some View {
        let list = rows
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader("Facturen", subtitle: "\(filter.periodText.capitalizedFirst) · \(list.count) factu\(list.count == 1 ? "ur" : "ren")") {
                    Button { exportCSV(list) } label: { Label("Exporteer", systemImage: "square.and.arrow.up") }
                        .help("Exporteer deze lijst als CSV (Excel/Numbers)")
                    PrimaryToolbarButton(title: "Nieuwe factuur", icon: "plus", shortcut: "⌘N") { store.startNewInvoice() }
                }
                .padding(.bottom, 8)

                if store.data.invoices.isEmpty {
                    EmptyState(icon: "doc.text", title: "Nog geen facturen",
                               message: "Hier komen al je facturen te staan, met status, vervaldatum en wanneer ze betaald zijn. Klik op een factuurnummer om de PDF te openen.",
                               primary: store.activeClients.isEmpty ? ("Eerst een praktijk toevoegen", {
                                   let id = store.addClient().id
                                   store.sidebar = .praktijken
                                   DispatchQueue.main.async { store.selectedClientID = id }
                               }) : ("Nieuwe factuur", { store.startNewInvoice() }))
                        .card()
                } else {
                VStack(alignment: .leading, spacing: 14) {
                    // Filters en zoeken horen bij de tabel: ze staan er direct boven
                    InvoiceFilterBar(filter: $filter, source: store.data.invoices, searchWidth: compact ? 180 : 240)

                    if list.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            headerRow
                            ForEach(list) { inv in
                                InvoiceTableRow(invoice: inv, compact: compact, onDelete: { requestDelete(inv) })
                            }
                        }
                        footer(list)
                    }
                }
                .card(padding: 18)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24).padding(.top, 6)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
        }
        // Beschikbare breedte van de pagina meten (minWidth 0: niet laten oprekken door de tabel zelf)
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { tableWidth = g.size.width }
                .onChange(of: g.size.width) { _, w in tableWidth = w }
        })
        .canvas()
        .navigationTitle("Facturen")
        .confirmationDialog("Factuur \(confirmDelete?.number ?? "") verwijderen?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Verwijderen", role: .destructive) { if let c = confirmDelete { store.delete(c) }; confirmDelete = nil }
        } message: {
            Text("Deze factuur is verstuurd. De gearchiveerde PDF blijft bewaard in Facturen/Verwijderd.")
        }
    }

    private func requestDelete(_ inv: Invoice) {
        if inv.isSent { confirmDelete = inv } else { store.delete(inv) }
    }

    // MARK: Kop en voet

    private var headerRow: some View {
        HStack(spacing: 12) {
            sortHeader("Factuur", .number, width: InvoiceCol.number)
            sortHeader("Datum", .date, width: InvoiceCol.date)
            sortHeader("Opdrachtgever", .client, width: nil)
            sortHeader("Bedrag", .amount, width: InvoiceCol.amount, alignment: .trailing)
            sortHeader("Vervaldatum", .due, width: InvoiceCol.date)
            if !compact { sortHeader("Betaald op", .paid, width: InvoiceCol.date) }
            sortHeader("Status", .status, width: InvoiceCol.status)
            if !compact { Text("Opmerking").frame(minWidth: 90, maxWidth: 200, alignment: .leading) }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.bottom, 8)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }

    private func sortHeader(_ title: String, _ key: InvoiceSort, width: CGFloat?, alignment: Alignment = .leading) -> some View {
        let active = sort == key
        let button = Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
                if active { ascending.toggle() } else { sort = key; ascending = key == .client }
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(active ? 1 : 0)
            }
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sorteer op \(title.lowercased())")
        return Group {
            if let width { button.frame(width: width, alignment: alignment) }
            else { button.frame(minWidth: 110, maxWidth: .infinity, alignment: alignment) }
        }
    }

    private func footer(_ list: [Invoice]) -> some View {
        let sent = list.filter(\.isSent)
        return HStack(spacing: 20) {
            Text("\(list.count) facturen").foregroundStyle(.secondary)
            Spacer()
            summary("Totaal", sent.sum(\.total))
            summary("Ontvangen", sent.sum(\.paid))
            summary("Openstaand", sent.sum(\.outstanding), color: accent)
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.top, 4)
    }

    private func summary(_ label: String, _ value: Decimal, color: Color = .primary) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            Text(value.euro).monospacedDigit().fontWeight(.semibold).foregroundStyle(color)
        }
    }

    /// Lege lijst terwijl er wél facturen zijn: leg uit waarom en bied de weg terug.
    @ViewBuilder private var emptyState: some View {
        if !filter.search.isEmpty {
            EmptyState(icon: "magnifyingglass", title: "Niets gevonden voor ‘\(filter.search)’",
                       message: "Zoek op factuurnummer, praktijk of opmerking.",
                       primary: ("Wis zoekopdracht", { filter.search = "" }))
        } else {
            EmptyState(icon: "line.3.horizontal.decrease.circle", title: "Geen facturen met deze filters",
                       message: "Er zijn geen facturen in \(filter.periodText)\(filter.clientID.flatMap { store.client($0) }.map { " voor \($0.displayName)" } ?? "")\(filter.status == .alle ? "" : " met status ‘\(filter.status.rawValue)’").",
                       primary: ("Wis filters", { filter = InvoiceFilter() }))
        }
    }

    private func exportCSV(_ list: [Invoice]) {
        let rows = list.map { i in [
            i.number, i.date.short, i.billTo.displayName, CSV.num(i.total), i.dueDate.short,
            i.paidDate?.short ?? "", i.status().rawValue, i.memo,
            CSV.num(i.hours), CSV.num(i.hoursAmount), CSV.num(i.totalKm), CSV.num(i.kmAmount),
            CSV.num(i.paid), CSV.num(i.outstanding),
        ] }
        let text = CSV.make(["Factuurnummer", "Factuurdatum", "Opdrachtgever", "Bedrag", "Vervaldatum", "Betaald op",
                             "Status", "Opmerking", "Uren", "Bedrag uren", "Km", "Reiskosten", "Betaald", "Openstaand"], rows)
        CSV.save(text, name: "Facturen \(filter.periodText).csv")
    }
}

enum InvoiceCol {
    static let number: CGFloat = 118, date: CGFloat = 84, amount: CGFloat = 100, status: CGFloat = 104
}

// MARK: - Rij

/// Eén factuur in het overzicht. Alles is opgebouwd uit gewone knoppen (betrouwbaar klikken):
/// klik op de rij = factuur openen, klik op het nummer = PDF openen, klik op de opmerking = bewerken.
struct InvoiceTableRow: View {
    @EnvironmentObject var store: Store
    let invoice: Invoice
    var compact = false
    let onDelete: () -> Void
    @Local private var hovering = false
    @Local private var hoverNumber = false
    @Local private var editingMemo = false
    @Local private var memoDraft = ""

    init(invoice: Invoice, compact: Bool = false, onDelete: @escaping () -> Void) {
        self.invoice = invoice; self.compact = compact; self.onDelete = onDelete
    }

    var body: some View {
        let status = invoice.status()
        HStack(spacing: 12) {
            // Factuurnummer = link naar de PDF
            Button { store.openPDF(invoice) } label: {
                HStack(spacing: 4) {
                    Text(invoice.number).monospacedDigit().underline(hoverNumber).lineLimit(1).fixedSize()
                    PDFBadge().opacity(hoverNumber ? 1 : 0.8)
                }
                .foregroundStyle(accent)
                .fontWeight(.medium)
                .frame(width: InvoiceCol.number, height: 30, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoverNumber = $0 }
            .help(store.archivedURL(invoice) != nil ? "Open de gearchiveerde PDF" : "Open de PDF (voorbeeld)")
            .accessibilityLabel("PDF van \(invoice.documentTitle.lowercased()) \(invoice.number)")
            .accessibilityHint("Opent de PDF in Voorvertoning")

            // De rest van de rij opent de factuur
            Button { store.edit(invoice) } label: {
                HStack(spacing: 12) {
                    Text(invoice.date.short).monospacedDigit().frame(width: InvoiceCol.date, alignment: .leading)

                    HStack(spacing: 8) {
                        Initials(name: invoice.billTo.displayName, size: 24)
                        Text(invoice.billTo.displayName).lineLimit(1)
                    }
                    .frame(minWidth: 110, maxWidth: .infinity, alignment: .leading)

                    Text(invoice.total.euro).monospacedDigit().fontWeight(.medium)
                        .frame(width: InvoiceCol.amount, alignment: .trailing)

                    Text(invoice.isSent ? invoice.dueDate.short : "—").monospacedDigit()
                        .foregroundStyle(status == .overdue ? Color.red : (invoice.isSent ? .primary : .secondary))
                        .frame(width: InvoiceCol.date, alignment: .leading)

                    if !compact {
                        Group {
                            if let paid = invoice.paidDate {
                                Text(paid.short).monospacedDigit()
                            } else if invoice.paid > 0 {
                                Text("deels").foregroundStyle(.orange)
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: InvoiceCol.date, alignment: .leading)
                    }

                    StatusBadge(status: status).frame(width: InvoiceCol.status, alignment: .leading)
                }
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(invoice.documentTitle) \(invoice.number) openen")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(status))
            .accessibilityHint("Opent de factuur")

            if !compact { memoButton.frame(minWidth: 90, maxWidth: 200, alignment: .leading) }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Color.well : .clear))
        .rowSeparator()
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hovering = h } }
        .contextMenu { menu }
    }

    private func accessibilityText(_ status: InvoiceStatus) -> String {
        var parts = ["\(invoice.documentTitle) \(invoice.number)", invoice.billTo.displayName,
                     "datum \(invoice.date.long)", invoice.total.euro, status.rawValue]
        if invoice.isSent && !invoice.isCredit { parts.append("vervalt \(invoice.dueDate.long)") }
        if let paid = invoice.paidDate { parts.append("betaald op \(paid.long)") }
        if !invoice.memo.isEmpty { parts.append("opmerking: \(invoice.memo)") }
        if let link = store.linkSummary(invoice) { parts.append(link) }
        return parts.joined(separator: ", ")
    }

    private var memoButton: some View {
        Button { memoDraft = invoice.memo; editingMemo = true } label: {
            HStack(spacing: 6) {
                if invoice.memo.isEmpty, !hovering, let link = store.linkSummary(invoice) {
                    // Koppeling met creditfactuur / nieuwe factuur
                    Label(link, systemImage: "link").labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(invoice.memo.isEmpty ? (hovering ? "Opmerking toevoegen" : "") : invoice.memo)
                        .foregroundStyle(invoice.memo.isEmpty ? .tertiary : .secondary)
                        .lineLimit(1)
                }
                if hovering { Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(invoice.memo.isEmpty ? "Interne opmerking toevoegen (niet op de factuur)" : invoice.memo)
        .accessibilityLabel(invoice.memo.isEmpty ? "Opmerking toevoegen bij \(invoice.number)" : "Opmerking bij \(invoice.number): \(invoice.memo)")
        .popover(isPresented: $editingMemo, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Interne opmerking").font(.headline)
                Text("Alleen voor jezelf; komt niet op de factuur.").font(.caption).foregroundStyle(.secondary)
                InputField("Bijv. herinnering gestuurd op 3 december", text: $memoDraft, axis: .vertical, autofocus: true)
                    .frame(width: 300)
                HStack {
                    if !invoice.memo.isEmpty {
                        Button("Wis") { store.setMemo("", for: invoice.id); editingMemo = false }
                    }
                    Spacer()
                    Button("Annuleer") { editingMemo = false }.keyboardShortcut(.cancelAction)
                    Button("Bewaar") { store.setMemo(memoDraft, for: invoice.id); editingMemo = false }
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.small)
            }
            .padding(16)
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Openen…") { store.edit(invoice) }
        Button("Open PDF") { store.openPDF(invoice) }
        Button("Bewaar als PDF…") { InvoicePDF.export(invoice, store: store) }
        Button("Mail factuur…") { InvoicePDF.mail(invoice, store: store) }
        if let url = store.archivedURL(invoice) {
            Button("Toon in archief") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        Divider()
        Button("Betaling registreren…") { store.paymentInvoice = invoice }.disabled(invoice.outstanding <= 0)
        Button("Markeer als volledig betaald") { store.markPaid(invoice) }.disabled(invoice.outstanding <= 0)
        if !invoice.isSent { Button("Markeer als verstuurd") { store.markSent(invoice.id) } }
        Button("Opmerking…") { memoDraft = invoice.memo; editingMemo = true }
        Divider()
        if invoice.isSent && !invoice.isCredit && !invoice.isCredited {
            Button("Corrigeren met creditfactuur…") { store.edit(invoice) }
        }
        Button("Dupliceren") { store.edit(store.duplicate(invoice)) }
        Button(invoice.isSent ? "Verwijderen…" : "Verwijderen", role: .destructive, action: onDelete)
    }
}

// MARK: - Betaling registreren

struct PaymentSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let invoice: Invoice
    @Local private var date = Date().startOfDay
    @Local private var amount: Decimal = 0
    @Local private var note = ""

    init(invoice: Invoice) { self.invoice = invoice }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Initials(name: invoice.billTo.displayName, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Betaling registreren").font(.title2.weight(.semibold))
                    Text("Factuur \(invoice.number) · \(invoice.billTo.displayName)").foregroundStyle(.secondary)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Totaal").font(.caption).foregroundStyle(.secondary)
                    Text(invoice.total.euro).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Nog open").font(.caption).foregroundStyle(.secondary)
                    Text(invoice.outstanding.euro).monospacedDigit().fontWeight(.semibold).foregroundStyle(accent)
                }
            }
            .padding(12)
            .background(Color.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 12) {
                LabeledField(label: "Ontvangen op") { DateField(date: $date) }
                LabeledField(label: "Bedrag") { NumberField(value: $amount, prefix: "€") }
            }
            LabeledField(label: "Notitie", hint: "Optioneel, bijv. ‘via bank, kenmerk …’") {
                InputField("Notitie", text: $note)
            }
            HStack {
                Button("Volledig bedrag") { amount = invoice.outstanding }.buttonStyle(.link)
                Spacer()
                Button("Annuleer", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Registreer") {
                    store.addPayment(Payment(date: date.startOfDay, amount: amount, note: note), to: invoice.id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(amount <= 0)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { amount = invoice.outstanding }
    }
}
