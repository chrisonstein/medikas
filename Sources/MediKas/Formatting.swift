import Foundation
import SwiftUI

let nl = Locale(identifier: "nl_NL")

let nlCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.locale = nl
    c.firstWeekday = 2
    c.timeZone = .current
    return c
}()


enum Fmt {
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = nl
        f.calendar = nlCalendar
        f.dateFormat = format
        return f
    }
    static let short = make("dd-MM-yyyy")
    static let long = make("d MMMM yyyy")
    static let weekday = make("EEE d MMM")
    static let month = make("MMMM")
    static let monthShort = make("MMM")
    static let monthYear = make("MMMM yyyy")
    static let file = make("yyyy-MM-dd")
}

extension Date {
    var short: String { Fmt.short.string(from: self) }
    var long: String { Fmt.long.string(from: self) }
    var year: Int { nlCalendar.component(.year, from: self) }
    var month: Int { nlCalendar.component(.month, from: self) }
    var quarter: Int { (month - 1) / 3 + 1 }
    var startOfDay: Date { nlCalendar.startOfDay(for: self) }
    func adding(days: Int) -> Date { nlCalendar.date(byAdding: .day, value: days, to: self) ?? self }
}

extension Decimal {
    var euro: String { formatted(.currency(code: "EUR").locale(nl)) }
    var double: Double { NSDecimalNumber(decimal: self).doubleValue }

    func rounded(_ scale: Int = 2) -> Decimal {
        var value = self, result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }

    /// Getal in Nederlandse notatie, bv. 32,5
    func fmt(_ maxDigits: Int = 2) -> String {
        formatted(.number.precision(.fractionLength(0...maxDigits)).locale(nl))
    }
}

extension Sequence {
    func sum(_ value: (Element) -> Decimal) -> Decimal { reduce(0) { $0 + value($1) } }
}

/// Invoerveld voor getallen met Nederlandse komma-notatie.
struct DecimalField: View {
    var title: String = ""
    @Binding var value: Decimal
    var digits: Int = 2

    var body: some View {
        TextField(title, value: $value,
                  format: .number.precision(.fractionLength(0...digits)).locale(nl))
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
    }
}

/// Zorgt dat een veld dat nog focus heeft zijn waarde vastlegt (vóór opslaan).
@MainActor func commitEditing() {
    NSApp.keyWindow?.makeFirstResponder(nil)
}

// MARK: - @Local: vervanger voor @State
// In de huidige SDK is @State een macro waarvoor volledige Xcode nodig is.
// Deze wrapper doet hetzelfde met @StateObject, zodat de app met alleen de Command Line Tools bouwt.

final class LocalBox<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}

@propertyWrapper
struct Local<T>: DynamicProperty {
    @StateObject private var box: LocalBox<T>

    init(wrappedValue: @autoclosure @escaping () -> T) {
        _box = StateObject(wrappedValue: LocalBox(wrappedValue()))
    }

    var wrappedValue: T {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<T> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
}

extension DateFormatter {
    static let versionStamp: DateFormatter = {
        let f = DateFormatter(); f.locale = nl; f.dateFormat = "yyyy-MM-dd HH.mm"; return f
    }()
}
