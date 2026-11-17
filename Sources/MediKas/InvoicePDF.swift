import SwiftUI
import AppKit
import UniformTypeIdentifiers

// A4 in punten
private let pageW: CGFloat = 595.28
private let pageH: CGFloat = 841.89
private let margin: CGFloat = 42
private let rowH: CGFloat = 19
private let ink = Color(white: 0.12)
private let soft = Color(white: 0.42)
private let rule = Color(white: 0.82)

// Kolombreedtes (totaal = pageW - 2*margin ≈ 511)
private enum Work {   // Werkzaamheden
    static let date: CGFloat = 80, desc: CGFloat = 191, hours: CGFloat = 60, rate: CGFloat = 80, amount: CGFloat = 100
}
private enum Travel { // Reiskosten
    static let date: CGFloat = 80, commute: CGFloat = 100, visit: CGFloat = 100, total: CGFloat = 100, amount: CGFloat = 131
}

/// Eén blok op de factuur; de paginering verdeelt deze over pagina's.
enum PDFItem: Hashable {
    case sectionTitle(String)
    case workHeader, work(WorkLine, Int), workTotal
    case travelHeader, travel(WorkLine, Int), travelTotal
    case gap

    var height: CGFloat {
        switch self {
        case .sectionTitle: 24
        case .workHeader, .travelHeader: 22
        case .work, .travel: rowH
        case .workTotal, .travelTotal: 22
        case .gap: 18
        }
    }

    static func items(for invoice: Invoice) -> [PDFItem] {
        let lines = invoice.sortedLines
        var items: [PDFItem] = [.sectionTitle("Werkzaamheden"), .workHeader]
        items += lines.enumerated().map { .work($1, $0) }
        items.append(.workTotal)
        let travel = lines.filter { $0.totalKm != 0 }   // ook negatief (creditfactuur)
        if !travel.isEmpty {
            items += [.gap, .sectionTitle("Reiskosten"), .travelHeader]
            items += travel.enumerated().map { .travel($1, $0) }
            items.append(.travelTotal)
        }
        return items
    }
}

struct InvoicePage: View {
    let invoice: Invoice
    let settings: BusinessSettings
    let brand: Brand
    let items: [PDFItem]
    let pageNumber: Int
    let pageCount: Int
    /// Alleen een deel tekenen (om de hoogte te meten voor de paginering).
    var part: Part? = nil

    enum Part { case firstHeader, nextHeader, closing, footer }

    private var isFirst: Bool { pageNumber == 1 }
    private var isLast: Bool { pageNumber == pageCount }
    private var ink: Color { brand.text }
    private var soft: Color { brand.soft }
    private var rule: Color { brand.rule }
    private var accent: Color { brand.primary }
    private var modern: Bool { brand.isModern }

    var body: some View {
        if let part { measuringBody(part) } else { pageBody }
    }

    @ViewBuilder private func measuringBody(_ part: Part) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch part {
            case .firstHeader: header; addressBlock; title
            case .nextHeader: continuationHeader
            case .closing: if modern { modernTotals; modernClosing } else { totals; closing }
            case .footer: footer
            }
        }
        .frame(width: pageW - 2 * margin, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .font(brand.body(9.5))
    }

    private var pageBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFirst { header; addressBlock; title } else { continuationHeader }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in itemView(item) }
            if isLast {
                if modern { modernTotals; modernClosing } else { totals; closing }
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, margin)
        .padding(.top, margin)
        .padding(.bottom, brand.patternTile == nil ? 26 : brand.patternSpace + 8)
        .frame(width: pageW, height: pageH, alignment: .topLeading)
        .background(Color.white)
        .overlay(alignment: .bottom) { patternStrip }
        .foregroundStyle(ink)
        .font(brand.body(9.5))
        .environment(\.colorScheme, .light)
    }

    // MARK: Klassieke kop

    private var header: some View {
        HStack(alignment: .top) {
            logoOrName
            Spacer()
            VStack(alignment: .trailing, spacing: 1.5) {
                if !settings.ownerName.isEmpty { Text(settings.ownerName).fontWeight(.semibold) }
                if !settings.title.isEmpty { Text(settings.title).foregroundStyle(soft) }
                if !settings.address.isEmpty { Text(settings.address) }
                if !(settings.postalCode + settings.city).isEmpty {
                    Text([settings.postalCode, settings.city].filter { !$0.isEmpty }.joined(separator: "  "))
                }
                if !settings.phone.isEmpty { Text(settings.phone) }
                if !settings.email.isEmpty { Text(settings.email) }
                if !settings.website.isEmpty { Text(settings.website) }
            }
            .font(brand.body(9))
        }
        .padding(.bottom, 26)
    }

    @ViewBuilder private var logoOrName: some View {
        if let logo = brand.logo {
            Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
                .frame(maxWidth: 240, maxHeight: CGFloat(brand.style.logoHeight), alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(settings.displayName).font(brand.heading(19, .bold)).foregroundStyle(accent)
                if !settings.tradeName.isEmpty && settings.practiceName != settings.tradeName && !settings.practiceName.isEmpty {
                    Text(settings.practiceName).font(brand.body(10)).foregroundStyle(soft)
                }
            }
        }
    }

    private var billToBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(invoice.billTo.displayName).font(brand.heading(11, .semibold))
            if !invoice.billTo.contactPerson.isEmpty { Text("t.a.v. \(invoice.billTo.contactPerson)") }
            if !invoice.billTo.address.isEmpty { Text(invoice.billTo.address) }
            if !(invoice.billTo.postalCode + invoice.billTo.city).isEmpty {
                Text([invoice.billTo.postalCode, invoice.billTo.city].filter { !$0.isEmpty }.joined(separator: "  "))
            }
        }
    }

    @ViewBuilder private var metaRows: some View {
        meta(invoice.isCredit ? "Creditnummer" : "Factuurnummer", invoice.number, bold: true)
        meta(modern ? "\(invoice.isCredit ? "Credit" : "Factuur")datum" : "Datum", modern ? invoice.date.short : invoice.date.long)
        if !invoice.isCredit { meta("Vervaldatum", modern ? invoice.dueDate.short : invoice.dueDate.long) }
        if !invoice.reference.isEmpty { meta("Kenmerk", invoice.reference, bold: modern) }
        if !invoice.relatedNumber.isEmpty {
            meta(invoice.isCredit ? "Crediteert factuur" : "Vervangt factuur",
                 invoice.relatedNumber + (invoice.relatedDate.map { " van \(modern ? $0.short : $0.long)" } ?? ""), bold: true)
        }
        if !invoice.periodText.isEmpty { meta("Periode", invoice.periodText) }
    }

    private var addressBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FACTUUR AAN").font(brand.body(7.5, .semibold)).kerning(0.8).foregroundStyle(soft).padding(.bottom, 2)
                billToBlock
            }
            Spacer()
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) { metaRows }
        }
        .padding(.bottom, 20)
    }

    private var title: some View {
        Text(titleText).font(brand.heading(22, .bold)).foregroundStyle(modern ? ink : accent)
            .padding(.bottom, 12)
    }

    private var titleText: String { brand.style.titleUppercase ? invoice.documentTitle.uppercased() : invoice.documentTitle }

    private func meta(_ label: String, _ value: String, bold: Bool = false) -> some View {
        GridRow {
            Text(label).foregroundStyle(soft)
            Text(value).fontWeight(bold ? .semibold : .regular)
                .gridColumnAlignment(modern ? .trailing : .leading)
        }
    }

    private var continuationHeader: some View {
        HStack {
            if let logo = brand.logo {
                Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
                    .frame(maxWidth: 140, maxHeight: 24, alignment: .leading)
            } else {
                Text(settings.displayName).font(brand.heading(12, .bold)).foregroundStyle(accent)
            }
            Spacer()
            Text("\(invoice.documentTitle) \(invoice.number) — vervolg").foregroundStyle(soft)
        }
        .padding(.bottom, 18)
    }

    // MARK: Tabellen

    private var kmRateText: String {
        invoice.kmRate.formatted(.currency(code: "EUR").precision(.fractionLength(2...3)).locale(nl))
    }

    @ViewBuilder private func itemView(_ item: PDFItem) -> some View {
        switch item {
        case .sectionTitle(let title):
            Group {
                if modern {
                    Text(title.uppercased()).font(brand.body(8, .semibold)).kerning(1.4).foregroundStyle(ink)
                } else {
                    Text(title).font(brand.heading(11, .semibold)).foregroundStyle(accent)
                }
            }
            .frame(height: 24, alignment: .bottomLeading)
        case .gap:
            Color.clear.frame(height: 18)

        case .workHeader:
            headerRow {
                cell(label("Datum"), Work.date, .leading); cell(label("Omschrijving"), Work.desc, .leading)
                cell(label("Uren"), Work.hours); cell(label("Uurtarief"), Work.rate); cell(label("Bedrag"), Work.amount)
            }
        case .work(let line, let i):
            row(i) {
                cell(line.date.short, Work.date, .leading)
                cell(line.description, Work.desc, .leading)
                cell(line.hours.fmt(), Work.hours)
                cell(line.hourlyRate.euro, Work.rate)
                cell(line.hoursAmount.euro, Work.amount)
            }
        case .workTotal:
            totalRow {
                cell("Subtotaal", Work.date + Work.desc, .leading)
                cell(invoice.hours.fmt(), Work.hours); cell("", Work.rate)
                cell(invoice.hoursAmount.euro, Work.amount)
            }

        case .travelHeader:
            headerRow {
                cell(label("Datum"), Travel.date, .leading); cell(label("Woon-werk km"), Travel.commute)
                cell(label("Visites km"), Travel.visit); cell(label("Totaal km"), Travel.total)
                cell(label("Bedrag (\(kmRateText)/km)", keepCase: true), Travel.amount)
            }
        case .travel(let line, let i):
            row(i) {
                cell(line.date.short, Travel.date, .leading)
                cell(line.commuteKm == 0 ? "–" : line.commuteKm.fmt(1), Travel.commute)
                cell(line.visitKm == 0 ? "–" : line.visitKm.fmt(1), Travel.visit)
                cell(line.totalKm.fmt(1), Travel.total)
                cell((line.totalKm * invoice.kmRate).rounded().euro, Travel.amount)
            }
        case .travelTotal:
            totalRow {
                cell("Subtotaal", Travel.date, .leading)
                cell(invoice.commuteKm.fmt(1), Travel.commute)
                cell(invoice.visitKm.fmt(1), Travel.visit)
                cell(invoice.totalKm.fmt(1), Travel.total)
                cell(invoice.kmAmount.euro, Travel.amount)
            }
        }
    }

    private func label(_ s: String, keepCase: Bool = false) -> String { modern && !keepCase ? s.uppercased() : s }

    @ViewBuilder private func headerRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if modern {
            HStack(spacing: 0, content: content)
                .font(brand.body(7.5, .semibold)).kerning(1)
                .foregroundStyle(accent)
                .frame(height: 22)
                .background(brand.surface, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            HStack(spacing: 0, content: content)
                .font(brand.body(8, .semibold))
                .foregroundStyle(.white)
                .frame(height: 22)
                .background(accent)
        }
    }

    @ViewBuilder private func row<C: View>(_ i: Int, @ViewBuilder _ content: () -> C) -> some View {
        if modern {
            HStack(spacing: 0, content: content)
                .frame(height: rowH)
                .overlay(alignment: .bottom) { Rectangle().fill(rule).frame(height: 0.6) }
        } else {
            HStack(spacing: 0, content: content)
                .frame(height: rowH)
                .background(i.isMultiple(of: 2) ? Color.clear : brand.surface.opacity(0.6))
        }
    }

    private func totalRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 0, content: content)
            .fontWeight(.semibold)
            .frame(height: 22)
            .overlay(alignment: .top) { Rectangle().fill(modern ? Color.clear : rule).frame(height: 0.7) }
            .monospacedDigit()
    }

    private func cell(_ text: String, _ width: CGFloat, _ align: Alignment = .trailing) -> some View {
        Text(text).lineLimit(1).truncationMode(.tail)
            .padding(.horizontal, modern ? 6 : 4)
            .frame(width: width, alignment: align)
            .monospacedDigit()
    }

    // MARK: Totalen

    private var totals: some View {
        HStack {
            Spacer()
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 5) {
                subtotalRows
                GridRow { Rectangle().fill(ink).frame(height: 0.8).gridCellColumns(2) }
                GridRow {
                    Text(invoice.isCredit ? "Totaal creditbedrag" : "Totaal te betalen").font(brand.heading(11.5, .bold))
                    Text(invoice.total.euro).font(brand.heading(11.5, .bold)).foregroundStyle(accent)
                }
                vatRow
            }
            .frame(width: 300)
            .monospacedDigit()
        }
        .padding(.top, 18)
    }

    @ViewBuilder private var subtotalRows: some View {
        GridRow {
            Text("Werkzaamheden (\(invoice.hours.fmt()) uur)").gridColumnAlignment(.leading)
            Text(invoice.hoursAmount.euro)
        }
        if invoice.totalKm != 0 {
            GridRow {
                Text("Reiskosten (\(invoice.totalKm.fmt(1)) km × \(kmRateText))")
                Text(invoice.kmAmount.euro)
            }
        }
    }

    @ViewBuilder private var vatRow: some View {
        if !settings.vatText.isEmpty {
            GridRow {
                Text(settings.vatText).font(brand.body(7.5)).italic().foregroundStyle(soft)
                    .gridCellColumns(2).gridCellAnchor(.trailing)
            }
        }
    }

    private var modernTotals: some View {
        HStack {
            Spacer()
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
                subtotalRows.foregroundStyle(soft)
                GridRow {
                    Rectangle().fill(brand.line).frame(height: 2).gridCellColumns(2).padding(.top, 6)
                }
                GridRow {
                    Text(invoice.isCredit ? "Totaal creditbedrag" : "Totaal").font(brand.heading(12, .semibold))
                    Text(invoice.total.euro).font(brand.heading(12, .semibold))
                }
                vatRow
            }
            .frame(width: 260)
            .monospacedDigit()
        }
        .padding(.top, 20)
    }

    private var closing: some View {
        VStack(alignment: .leading, spacing: 8) {
            relatedText
            if !invoice.notes.isEmpty { Text(invoice.notes) }
            if !invoice.isCredit { Text(paymentSentence) }
            if !settings.closingText.isEmpty { Text(settings.closingText) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 26)
    }

    @ViewBuilder private var relatedText: some View {
        if invoice.isCredit {
            Text("Deze creditfactuur crediteert factuur \(invoice.relatedNumber)\(invoice.relatedDate.map { " van \($0.long)" } ?? "") volledig. U hoeft niets te betalen; een eventueel al betaald bedrag wordt verrekend of teruggestort.")
        } else if !invoice.relatedNumber.isEmpty {
            Text("Deze factuur vervangt factuur \(invoice.relatedNumber)\(invoice.relatedDate.map { " van \($0.long)" } ?? ""), die met een creditfactuur is gecrediteerd.")
        }
    }

    private var modernClosing: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                relatedText
                if !invoice.notes.isEmpty { Text(invoice.notes) }
                if !settings.closingText.isEmpty { Text(settings.closingText) }
            }
            .fixedSize(horizontal: false, vertical: true)
            // Betaalvak
            VStack(alignment: .leading, spacing: 6) {
                Text(invoice.isCredit ? "U hoeft voor deze creditfactuur niets te betalen." : paymentSentence)
                    .font(brand.body(9.5, .medium))
                let ids = [settings.iban.isEmpty ? nil : "IBAN \(settings.iban)\(settings.bic.isEmpty ? "" : " · BIC \(settings.bic)")"].compactMap { $0 }
                if !ids.isEmpty { Text(ids.joined(separator: " · ")).foregroundStyle(soft) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(brand.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.top, 24)
    }

    private var paymentSentence: String {
        settings.paymentText
            .replacingOccurrences(of: "{TERMIJN}", with: "\(settings.paymentTermDays)")
            .replacingOccurrences(of: "{IBAN}", with: settings.iban.isEmpty ? "ons rekeningnummer" : settings.iban)
            .replacingOccurrences(of: "{NAAM}", with: settings.holder)
            .replacingOccurrences(of: "{FACTUUR}", with: invoice.number)
            .replacingOccurrences(of: "{BEDRAG}", with: invoice.total.euro)
            .replacingOccurrences(of: "{VERVALDATUM}", with: invoice.dueDate.long)
    }

    // MARK: Voet

    private var footer: some View {
        VStack(alignment: .leading, spacing: modern ? 7 : 4) {
            Rectangle().fill(modern ? AnyShapeStyle(brand.line) : AnyShapeStyle(rule)).frame(height: modern ? 2 : 0.7)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if modern {
                        Text(registrationItems.joined(separator: " · "))
                    } else {
                        Text(([settings.practiceName] + registrationItems).filter { !$0.isEmpty }.joined(separator: "   ·   "))
                    }
                }
                Spacer()
                if pageCount > 1 { Text("Pagina \(pageNumber) van \(pageCount)") }
            }
            .font(brand.body(7.5))
            .foregroundStyle(soft)
        }
    }

    private var registrationItems: [String] {
        var items: [String] = []
        if !settings.kvk.isEmpty { items.append("KvK \(settings.kvk)") }
        if !settings.agb.isEmpty { items.append("AGB \(settings.agb)") }
        if !settings.big.isEmpty { items.append("BIG \(settings.big)") }
        if !settings.vatNumber.isEmpty { items.append("Btw-id \(settings.vatNumber)") }
        if !settings.iban.isEmpty && !modern { items.append("IBAN \(settings.iban)\(settings.bic.isEmpty ? "" : " (\(settings.bic))")") }
        return items
    }

    // MARK: Patroon onderaan (nooit onder tekst)

    @ViewBuilder private var patternStrip: some View {
        if let tile = brand.patternTile {
            let h = CGFloat(brand.style.patternHeight)
            Canvas { ctx, size in
                let ratio = tile.size.height > 0 ? tile.size.width / tile.size.height : 1
                let th = h * 0.55
                let tw = th * ratio
                let gap = tw * 0.55
                guard let resolved = ctx.resolveSymbol(id: 0) else { return }
                ctx.opacity = brand.style.patternOpacity
                // Twee rijen, versprongen; de onderste loopt van de pagina af
                for (row, y) in [(0, size.height - h), (1, size.height - h + th * 0.95)].map({ ($0.0, $0.1) }) {
                    var x: CGFloat = row == 0 ? -tw / 2 : 0
                    while x < size.width {
                        ctx.draw(resolved, in: CGRect(x: x, y: y, width: tw, height: th))
                        x += tw + gap
                    }
                }
            } symbols: {
                Image(nsImage: tile).resizable().interpolation(.high).tag(0)
            }
            .frame(width: pageW, height: h)
            .clipped()
            .allowsHitTesting(false)
        }
    }
}

// MARK: - PDF maken, bewaren en mailen

@MainActor
enum InvoicePDF {
    /// Gemeten hoogtes van de vaste delen van een pagina.
    struct Layout { var firstCap: CGFloat; var nextCap: CGFloat; var closing: CGFloat }

    /// Meet kop, slot en voet van deze factuur in deze huisstijl.
    static func measure(_ invoice: Invoice, settings: BusinessSettings, brand: Brand) -> Layout {
        func h(_ part: InvoicePage.Part) -> CGFloat {
            let view = InvoicePage(invoice: invoice, settings: settings, brand: brand, items: [], pageNumber: 1, pageCount: 2, part: part)
            return NSHostingView(rootView: view).fittingSize.height
        }
        let fixed = pageH - margin - (brand.patternTile == nil ? 26 : brand.patternSpace + 8) - h(.footer) - 12   // 12 pt veiligheidsmarge
        return Layout(firstCap: fixed - h(.firstHeader), nextCap: fixed - h(.nextHeader), closing: h(.closing))
    }

    /// Verdeelt de blokken over pagina's op basis van hoogte. Een tabel die doorloopt krijgt
    /// op de volgende pagina opnieuw zijn kop; de laatste pagina heeft ruimte voor totalen en betaalvak.
    static func paginate(_ items: [PDFItem], layout: Layout) -> [[PDFItem]] {
        var pages: [[PDFItem]] = [[]]
        var used: CGFloat = 0
        func cap() -> CGFloat { pages.count == 1 ? layout.firstCap : layout.nextCap }

        for item in items {
            var needed = item.height
            // Een sectietitel niet los onderaan een pagina: houd hem bij kop + eerste regel.
            if case .sectionTitle = item { needed += 22 + rowH }
            if used + needed > cap() && !(pages.last ?? []).isEmpty {
                pages.append([]); used = 0
                if case .gap = item { continue }
                switch item {
                case .work, .workTotal: pages[pages.count - 1].append(.workHeader); used += 22
                case .travel, .travelTotal: pages[pages.count - 1].append(.travelHeader); used += 22
                default: break
                }
            }
            pages[pages.count - 1].append(item)
            used += item.height
        }
        if used + layout.closing > cap() { pages.append([]) }
        return pages
    }

    static func pages(for invoice: Invoice, settings: BusinessSettings, brand: Brand) -> [InvoicePage] {
        let chunks = paginate(PDFItem.items(for: invoice), layout: measure(invoice, settings: settings, brand: brand))
        return chunks.enumerated().map { i, items in
            InvoicePage(invoice: invoice, settings: settings, brand: brand,
                        items: items, pageNumber: i + 1, pageCount: chunks.count)
        }
    }

    static func data(for invoice: Invoice, store: Store) -> Data? {
        data(for: invoice, settings: store.data.settings, brand: store.brand)
    }

    static func data(for invoice: Invoice, settings: BusinessSettings, logo: NSImage?) -> Data? {
        data(for: invoice, settings: settings, brand: Brand(style: settings.style, logo: logo, patternImage: nil))
    }

    static func data(for invoice: Invoice, settings: BusinessSettings, brand: Brand) -> Data? {
        let out = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let consumer = CGDataConsumer(data: out as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, [
                kCGPDFContextTitle: "Factuur \(invoice.number)",
                kCGPDFContextAuthor: settings.practiceName,
                kCGPDFContextCreator: "MediKas",
              ] as CFDictionary) else { return nil }
        for page in pages(for: invoice, settings: settings, brand: brand) {
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(width: pageW, height: pageH)
            renderer.render { _, draw in
                ctx.beginPDFPage(nil)
                draw(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return out as Data
    }

    static func fileName(_ invoice: Invoice) -> String {
        let client = invoice.billTo.displayName.replacingOccurrences(of: "/", with: "-")
        return "\(invoice.documentTitle) \(invoice.number) - \(client).pdf"
    }

    private static func writeTemp(_ invoice: Invoice, store: Store) -> URL? {
        guard let data = data(for: invoice, store: store) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MediKas", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName(invoice))
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    /// Opent de PDF in Voorvertoning zonder iets te bewaren.
    static func preview(_ invoice: Invoice, store: Store) {
        guard let url = writeTemp(invoice, store: store) else { return }
        NSWorkspace.shared.open(url)
    }

    static func export(_ invoice: Invoice, store: Store) {
        guard let data = data(for: invoice, store: store) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName(invoice)
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            store.markSent(invoice.id)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            store.alert = "PDF bewaren mislukt: \(error.localizedDescription)"
        }
    }

    static func mail(_ invoice: Invoice, store: Store) {
        guard let url = writeTemp(invoice, store: store),
              let service = NSSharingService(named: .composeEmail) else { return }
        // Bij een vervangende factuur hoort de creditfactuur van de oude factuur er ook bij
        let original = store.invoice(invoice.replacesInvoiceID)
        let credit = store.invoice(original?.creditedByID)
        let creditURL = credit.flatMap { writeTemp($0, store: store) }
        let s = store.data.settings
        if !invoice.billTo.email.isEmpty { service.recipients = [invoice.billTo.email] }
        service.subject = "Factuur \(invoice.number) – \(s.displayName)"
        let greeting = invoice.billTo.contactPerson.isEmpty ? "Beste collega's," : "Beste \(invoice.billTo.contactPerson),"
        let intro: String
        if invoice.isCredit {
            service.subject = "Creditfactuur \(invoice.number) – \(s.displayName)"
            intro = "Hierbij stuur ik creditfactuur \(invoice.number), waarmee factuur \(invoice.relatedNumber) volledig wordt gecrediteerd. U hoeft hiervoor niets te betalen."
        } else if let original, let credit, creditURL != nil {
            intro = "Factuur \(original.number) bevatte een fout. Daarom stuur ik creditfactuur \(credit.number), die factuur \(original.number) ongedaan maakt, en de gecorrigeerde factuur \(invoice.number). Het totaalbedrag van de nieuwe factuur is \(invoice.total.euro), te voldoen vóór \(invoice.dueDate.long). Excuses voor het ongemak."
        } else {
            intro = "Hierbij stuur ik de factuur \(invoice.number) voor de waarneming\(invoice.periodText.isEmpty ? "" : " (\(invoice.periodText))"). Het totaalbedrag is \(invoice.total.euro), te voldoen vóór \(invoice.dueDate.long)."
        }
        let body = """
        \(greeting)

        \(intro)

        Met vriendelijke groet,

        \(s.ownerName.isEmpty ? s.practiceName : s.ownerName)
        \(s.tradeName.isEmpty ? "" : s.tradeName)
        """
        service.perform(withItems: [body] + [creditURL, url].compactMap { $0 })
        if let credit, creditURL != nil { store.markSent(credit.id) }
        store.markSent(invoice.id)
    }
}
