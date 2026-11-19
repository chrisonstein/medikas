import Foundation
import SwiftUI

// Alle modellen decoderen "toegeeflijk": ontbrekende velden krijgen hun standaardwaarde,
// zodat oude databestanden blijven werken als er later velden bijkomen.
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

// MARK: - Bedrijfsgegevens

struct BusinessSettings: Codable, Equatable {
    var practiceName = ""
    var tradeName = ""
    var ownerName = ""
    var title = ""
    var address = ""
    var postalCode = ""
    var city = ""
    var phone = ""
    var email = ""
    var website = ""
    var kvk = ""
    var agb = ""
    var big = ""
    var vatNumber = ""
    var iban = ""
    var bic = ""
    var accountHolder = ""

    var defaultHourlyRate: Decimal = 0
    var defaultKmRate: Decimal = Decimal(string: "0.23")!
    var paymentTermDays = 30
    var invoicePrefix = ""
    var defaultLineDescription = ""
    var vatText = "Vrijgesteld van btw o.g.v. art. 11 lid 1 sub g Wet OB 1968."
    var paymentText = "Gelieve het totaalbedrag binnen {TERMIJN} dagen over te maken op {IBAN} t.n.v. {NAAM}, onder vermelding van factuurnummer {FACTUUR}."
    var closingText = ""
    /// Bewaar automatisch een PDF van elke verstuurde factuur in de gegevensmap.
    var archivePDFs = true
    /// Archief per jaar én per maand indelen (Facturen/2026/03 maart/).
    var archiveByMonth = false
    /// Huisstijl van de factuur (sjabloon, kleuren, lettertypen, patroon).
    var style = InvoiceStyle()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BusinessSettings()
        practiceName = c.value(.practiceName, d.practiceName)
        tradeName = c.value(.tradeName, d.tradeName)
        ownerName = c.value(.ownerName, d.ownerName)
        title = c.value(.title, d.title)
        address = c.value(.address, d.address)
        postalCode = c.value(.postalCode, d.postalCode)
        city = c.value(.city, d.city)
        phone = c.value(.phone, d.phone)
        email = c.value(.email, d.email)
        website = c.value(.website, d.website)
        kvk = c.value(.kvk, d.kvk)
        agb = c.value(.agb, d.agb)
        big = c.value(.big, d.big)
        vatNumber = c.value(.vatNumber, d.vatNumber)
        iban = c.value(.iban, d.iban)
        bic = c.value(.bic, d.bic)
        accountHolder = c.value(.accountHolder, d.accountHolder)
        defaultHourlyRate = c.value(.defaultHourlyRate, d.defaultHourlyRate)
        defaultKmRate = c.value(.defaultKmRate, d.defaultKmRate)
        paymentTermDays = c.value(.paymentTermDays, d.paymentTermDays)
        invoicePrefix = c.value(.invoicePrefix, d.invoicePrefix)
        defaultLineDescription = c.value(.defaultLineDescription, d.defaultLineDescription)
        vatText = c.value(.vatText, d.vatText)
        paymentText = c.value(.paymentText, d.paymentText)
        closingText = c.value(.closingText, d.closingText)
        archivePDFs = c.value(.archivePDFs, d.archivePDFs)
        archiveByMonth = c.value(.archiveByMonth, d.archiveByMonth)
        style = c.value(.style, d.style)
    }

    var isIncomplete: Bool { practiceName.isEmpty || ownerName.isEmpty || iban.isEmpty || defaultHourlyRate == 0 }
    var holder: String { accountHolder.isEmpty ? (ownerName.isEmpty ? practiceName : ownerName) : accountHolder }
    /// Naam voor kopjes: handelsnaam, anders bedrijfsnaam, anders de app-naam.
    var displayName: String { !tradeName.isEmpty ? tradeName : (!practiceName.isEmpty ? practiceName : "MediKas") }
}

// MARK: - Praktijk (klant)

struct Client: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var contactPerson = ""
    var address = ""
    var postalCode = ""
    var city = ""
    var email = ""
    /// 0 = standaard uurtarief uit instellingen
    var hourlyRate: Decimal = 0
    /// 0 = standaard km-tarief uit instellingen
    var kmRate: Decimal = 0
    /// Woon-werk kilometers per werkdag (retour)
    var commuteKm: Decimal = 0
    var notes = ""
    var archived = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Client()
        id = c.value(.id, UUID())
        name = c.value(.name, d.name)
        contactPerson = c.value(.contactPerson, d.contactPerson)
        address = c.value(.address, d.address)
        postalCode = c.value(.postalCode, d.postalCode)
        city = c.value(.city, d.city)
        email = c.value(.email, d.email)
        hourlyRate = c.value(.hourlyRate, d.hourlyRate)
        kmRate = c.value(.kmRate, d.kmRate)
        commuteKm = c.value(.commuteKm, d.commuteKm)
        notes = c.value(.notes, d.notes)
        archived = c.value(.archived, d.archived)
    }

    var displayName: String { name.isEmpty ? "Naamloze praktijk" : name }
}

// MARK: - Factuurregel (één werkdag)

struct WorkLine: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date().startOfDay
    var description = ""
    var hours: Decimal = 0
    var hourlyRate: Decimal = 0
    var commuteKm: Decimal = 0
    var visitKm: Decimal = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WorkLine()
        id = c.value(.id, UUID())
        date = c.value(.date, d.date)
        description = c.value(.description, d.description)
        hours = c.value(.hours, d.hours)
        hourlyRate = c.value(.hourlyRate, d.hourlyRate)
        commuteKm = c.value(.commuteKm, d.commuteKm)
        visitKm = c.value(.visitKm, d.visitKm)
    }

    var totalKm: Decimal { commuteKm + visitKm }
    var hoursAmount: Decimal { (hours * hourlyRate).rounded() }
}

// MARK: - Betaling

struct Payment: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date().startOfDay
    var amount: Decimal = 0
    var note = ""

    init(date: Date = Date().startOfDay, amount: Decimal = 0, note: String = "") {
        self.date = date; self.amount = amount; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        date = c.value(.date, Date())
        amount = c.value(.amount, 0)
        note = c.value(.note, "")
    }
}

// MARK: - Factuur

enum InvoiceStatus: String, CaseIterable, Identifiable {
    case concept = "Concept"
    case open = "Open"
    case partial = "Deels betaald"
    case overdue = "Te laat"
    case paid = "Betaald"
    case credited = "Gecrediteerd"
    case creditNote = "Creditfactuur"
    var id: Self { self }

    var color: Color {
        switch self {
        case .concept: .gray
        case .open: .blue
        case .partial: .orange
        case .overdue: .red
        case .paid: .green
        case .credited: .secondary
        case .creditNote: .purple
        }
    }
}

enum InvoiceKind: String, Codable {
    case normal, credit
}

struct Invoice: Identifiable, Codable, Hashable {
    var id = UUID()
    var number = ""
    var clientID: UUID?
    /// Kopie van de praktijkgegevens op het moment van opslaan (zodat oude facturen niet veranderen).
    var billTo = Client()
    var date = Date().startOfDay
    var dueDate = Date().startOfDay.adding(days: 30)
    var kmRate: Decimal = 0
    var lines: [WorkLine] = []
    var payments: [Payment] = []
    /// Tekst óp de factuur.
    var notes = ""
    /// Interne opmerking (alleen in het overzicht, niet op de factuur).
    var memo = ""
    /// Kenmerk op de factuur (optioneel, bv. ordernummer of referentie van de praktijk).
    var reference = ""
    var isSent = false
    var sentDate: Date?

    // Correcties (creditfactuur + nieuwe factuur), aan elkaar gekoppeld
    var kind: InvoiceKind = .normal
    /// Creditfactuur: welke factuur wordt gecrediteerd.
    var creditsInvoiceID: UUID?
    /// Nieuwe factuur: welke factuur wordt vervangen.
    var replacesInvoiceID: UUID?
    /// Oorspronkelijke factuur: door welke creditfactuur gecrediteerd.
    var creditedByID: UUID?
    /// Oorspronkelijke factuur: door welke nieuwe factuur vervangen.
    var replacedByID: UUID?
    /// Nummer en datum van de gerelateerde factuur (voor op de PDF).
    var relatedNumber = ""
    var relatedDate: Date?
    /// Momenten waarop een al verstuurde factuur toch is aangepast.
    var editedAfterSending: [Date] = []

    /// Pad van de gearchiveerde PDF, relatief aan de gegevensmap (bv. "Facturen/2026/Factuur 2026-001 - ….pdf").
    var archivedFile: String?

    /// Buiten MediKas gemaakt en geïmporteerd. De originele PDF staat in het archief;
    /// MediKas maakt voor deze factuur nooit zelf een PDF.
    var isImported = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Invoice()
        id = c.value(.id, UUID())
        number = c.value(.number, d.number)
        clientID = c.value(.clientID, d.clientID)
        billTo = c.value(.billTo, d.billTo)
        date = c.value(.date, d.date)
        dueDate = c.value(.dueDate, d.dueDate)
        kmRate = c.value(.kmRate, d.kmRate)
        lines = c.value(.lines, d.lines)
        payments = c.value(.payments, d.payments)
        notes = c.value(.notes, d.notes)
        memo = c.value(.memo, d.memo)
        reference = c.value(.reference, d.reference)
        isSent = c.value(.isSent, d.isSent)
        sentDate = c.value(.sentDate, d.sentDate)
        kind = c.value(.kind, d.kind)
        creditsInvoiceID = c.value(.creditsInvoiceID, d.creditsInvoiceID)
        replacesInvoiceID = c.value(.replacesInvoiceID, d.replacesInvoiceID)
        creditedByID = c.value(.creditedByID, d.creditedByID)
        replacedByID = c.value(.replacedByID, d.replacedByID)
        relatedNumber = c.value(.relatedNumber, d.relatedNumber)
        relatedDate = c.value(.relatedDate, d.relatedDate)
        editedAfterSending = c.value(.editedAfterSending, d.editedAfterSending)
        archivedFile = c.value(.archivedFile, d.archivedFile)
        isImported = c.value(.isImported, d.isImported)
    }

    var sortedLines: [WorkLine] { lines.sorted { $0.date < $1.date } }
    var hours: Decimal { lines.sum(\.hours) }
    var hoursAmount: Decimal { lines.sum(\.hoursAmount) }
    var commuteKm: Decimal { lines.sum(\.commuteKm) }
    var visitKm: Decimal { lines.sum(\.visitKm) }
    var totalKm: Decimal { lines.sum(\.totalKm) }
    /// Som van de afgeronde bedragen per regel (zo telt de reiskostentabel op de PDF precies op).
    var kmAmount: Decimal { lines.sum { ($0.totalKm * kmRate).rounded() } }
    var total: Decimal { hoursAmount + kmAmount }
    var paid: Decimal { payments.sum(\.amount) }
    var isCredit: Bool { kind == .credit }
    var isCredited: Bool { creditedByID != nil }
    /// Creditfacturen en gecrediteerde facturen hoeven niet (meer) betaald te worden.
    var outstanding: Decimal { isCredit || isCredited ? 0 : max(0, total - paid) }
    /// Titel op de PDF.
    var documentTitle: String { isCredit ? "Creditfactuur" : "Factuur" }
    var lastPaymentDate: Date? { payments.map(\.date).max() }
    /// Datum waarop de factuur volledig betaald is (nil als nog niet).
    var paidDate: Date? { total > 0 && outstanding <= 0 ? lastPaymentDate : nil }

    var periodText: String {
        let dates = lines.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return "" }
        if first.month == last.month && first.year == last.year {
            return Fmt.monthYear.string(from: first)
        }
        return "\(first.short) t/m \(last.short)"
    }

    func status(asOf now: Date = Date()) -> InvoiceStatus {
        if !isSent { return .concept }
        if isCredit { return .creditNote }
        if isCredited { return .credited }
        if total > 0 && outstanding <= 0 { return .paid }
        if dueDate.startOfDay < now.startOfDay { return .overdue }
        if paid > 0 { return .partial }
        return .open
    }
}

// MARK: - Alles samen

struct AppData: Codable {
    var version = 1
    var settings = BusinessSettings()
    var clients: [Client] = []
    var invoices: [Invoice] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.value(.version, 1)
        settings = c.value(.settings, BusinessSettings())
        clients = try c.decodeIfPresent([Client].self, forKey: .clients) ?? []
        invoices = try c.decodeIfPresent([Invoice].self, forKey: .invoices) ?? []
    }
}
