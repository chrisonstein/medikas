import AppKit
import UniformTypeIdentifiers
import Foundation

enum Grouping: String, CaseIterable, Identifiable {
    case maand = "Maand", kwartaal = "Kwartaal", jaar = "Jaar"
    var id: Self { self }
}

enum DateBasis: String, CaseIterable, Identifiable {
    case werkdatum = "Werkdatum", factuurdatum = "Factuurdatum"
    var id: Self { self }
}

struct PeriodKey: Hashable, Comparable {
    var year: Int
    var index: Int   // maand 1-12, kwartaal 1-4, of 0 voor jaar

    static func < (a: PeriodKey, b: PeriodKey) -> Bool { (a.year, a.index) < (b.year, b.index) }

    static func of(_ date: Date, _ g: Grouping) -> PeriodKey {
        switch g {
        case .maand: PeriodKey(year: date.year, index: date.month)
        case .kwartaal: PeriodKey(year: date.year, index: date.quarter)
        case .jaar: PeriodKey(year: date.year, index: 0)
        }
    }

    func label(_ g: Grouping, short: Bool = false) -> String {
        switch g {
        case .maand:
            let d = nlCalendar.date(from: DateComponents(year: year, month: index, day: 1)) ?? Date()
            return (short ? Fmt.monthShort : Fmt.month).string(from: d).capitalized
        case .kwartaal: return "K\(index) \(year)"
        case .jaar: return "\(year)"
        }
    }
}

struct PeriodRow: Identifiable {
    var key: PeriodKey
    var label = ""
    var shortLabel = ""
    var hours: Decimal = 0
    var commuteKm: Decimal = 0
    var visitKm: Decimal = 0
    var hoursAmount: Decimal = 0
    var kmAmount: Decimal = 0
    var received: Decimal = 0
    var workDays = Set<Date>()

    var id: PeriodKey { key }
    var km: Decimal { commuteKm + visitKm }
    var invoiced: Decimal { hoursAmount + kmAmount.rounded() }
    var days: Int { workDays.count }
}

struct ClientRow: Identifiable {
    var id: UUID
    var name: String
    var hours: Decimal = 0
    var km: Decimal = 0
    var invoiced: Decimal = 0
    var received: Decimal = 0
    var outstanding: Decimal = 0
    var invoices = 0
}

enum Analytics {
    /// Cijfers per periode. `year == nil` → alle jaren.
    static func periods(_ invoices: [Invoice], grouping: Grouping, basis: DateBasis, year: Int?) -> [PeriodRow] {
        var rows: [PeriodKey: PeriodRow] = [:]
        func inScope(_ d: Date) -> Bool { year == nil || d.year == year }
        func row(_ k: PeriodKey) -> PeriodRow { rows[k] ?? PeriodRow(key: k) }

        // Lege periodes tonen voor een volledig jaar
        if let year, grouping != .jaar {
            for i in 1...(grouping == .maand ? 12 : 4) { rows[PeriodKey(year: year, index: i)] = PeriodRow(key: PeriodKey(year: year, index: i)) }
        }

        for inv in invoices where inv.isSent {
            for line in inv.lines {
                let d = basis == .werkdatum ? line.date : inv.date
                guard inScope(d) else { continue }
                let k = PeriodKey.of(d, grouping)
                var r = row(k)
                r.hours += line.hours
                r.commuteKm += line.commuteKm
                r.visitKm += line.visitKm
                r.hoursAmount += line.hoursAmount
                r.kmAmount += line.totalKm * inv.kmRate
                r.workDays.insert(line.date.startOfDay)
                rows[k] = r
            }
            for p in inv.payments where inScope(p.date) {
                let k = PeriodKey.of(p.date, grouping)
                var r = row(k)
                r.received += p.amount
                rows[k] = r
            }
        }
        return rows.values.sorted { $0.key < $1.key }.map {
            var r = $0
            r.label = r.key.label(grouping)
            r.shortLabel = r.key.label(grouping, short: true)
            return r
        }
    }

    static func clients(_ invoices: [Invoice], basis: DateBasis, year: Int?) -> [ClientRow] {
        var rows: [UUID: ClientRow] = [:]
        for inv in invoices where inv.isSent {
            let key = inv.clientID ?? inv.billTo.id
            var r = rows[key] ?? ClientRow(id: key, name: inv.billTo.displayName)
            var counted = false
            for line in inv.lines {
                let d = basis == .werkdatum ? line.date : inv.date
                guard year == nil || d.year == year else { continue }
                r.hours += line.hours
                r.km += line.totalKm
                r.invoiced += line.hoursAmount + (line.totalKm * inv.kmRate).rounded()
                counted = true
            }
            for p in inv.payments where year == nil || p.date.year == year { r.received += p.amount }
            if counted {
                r.invoices += 1
                r.outstanding += inv.outstanding
            }
            rows[key] = r
        }
        return rows.values.filter { $0.invoices > 0 || $0.received > 0 }.sorted { $0.invoiced > $1.invoiced }
    }
}

// MARK: - CSV (Excel-vriendelijk: puntkomma's en komma als decimaalteken)

enum CSV {
    static func field(_ s: String) -> String {
        if s.contains(";") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    static func num(_ d: Decimal) -> String {
        d.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(nl))
    }

    static func make(_ header: [String], _ rows: [[String]]) -> String {
        ([header] + rows).map { $0.map(field).joined(separator: ";") }.joined(separator: "\r\n")
    }

    @MainActor static func save(_ text: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // BOM zodat Excel de accenten goed toont
        try? ("\u{FEFF}" + text).data(using: .utf8)?.write(to: url, options: .atomic)
    }
}

