import SwiftUI
import Charts

enum ChartMetric: String, CaseIterable, Identifiable {
    case omzet = "Omzet", ontvangen = "Ontvangen", uren = "Uren", km = "Kilometers"
    var id: Self { self }

    var usesWorkDate: Bool { self == .uren || self == .km }

    func value(_ r: PeriodRow) -> Double {
        switch self {
        case .omzet: r.invoiced.double
        case .ontvangen: r.received.double
        case .uren: r.hours.double
        case .km: r.km.double
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .omzet, .ontvangen: Decimal(v).rounded(0).euro.replacingOccurrences(of: ",00", with: "")
        case .uren: "\(Decimal(v).fmt(1)) uur"
        case .km: "\(Decimal(v).fmt(0)) km"
        }
    }

    func axis(_ v: Double) -> String {
        switch self {
        case .omzet, .ontvangen: v >= 1000 ? "€ \(Decimal(v / 1000).fmt(1))k" : "€ \(Int(v))"
        case .uren, .km: Decimal(v).fmt(0)
        }
    }
}

/// Staafgrafiek in een kaart: rustige grijze staven, de actieve periode in de accentkleur
/// met een ballon erboven. Met de muis bekijk je andere periodes.
struct PeriodChartCard<Trailing: View>: View {
    let title: String
    let icon: String
    /// Regels per metriek (omzet op factuurdatum, uren/km op werkdatum).
    let rows: (ChartMetric) -> [PeriodRow]
    let highlightKey: PeriodKey?
    @Binding var metric: ChartMetric
    @ViewBuilder var trailing: () -> Trailing

    @Local private var hovered: String?
    @Environment(\.colorScheme) private var scheme

    init(title: String, icon: String, rows: @escaping (ChartMetric) -> [PeriodRow], highlightKey: PeriodKey?,
         metric: Binding<ChartMetric>, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title; self.icon = icon; self.rows = rows; self.highlightKey = highlightKey
        _metric = metric; self.trailing = trailing
    }

    var body: some View {
        let data = rows(metric)
        // Actief: onder de muis, anders de huidige periode (als die al cijfers heeft), anders de laatste met cijfers.
        let highlighted = hovered ?? data.first { $0.key == highlightKey && metric.value($0) > 0 }?.shortLabel
            ?? data.last { metric.value($0) > 0 }?.shortLabel

        VStack(alignment: .leading, spacing: 16) {
            CardHeader(icon: icon, title: title, trailing: trailing)
            ChipPicker(options: ChartMetric.allCases, selection: $metric) { $0.rawValue }

            Chart(data) { r in
                let v = metric.value(r)
                let active = r.shortLabel == highlighted
                BarMark(x: .value("Periode", r.shortLabel), y: .value(metric.rawValue, v), width: .ratio(0.58))
                    .cornerRadius(8)
                    .accessibilityLabel(r.label)
                    .accessibilityValue(metric.format(v))
                    .foregroundStyle(active
                        ? AnyShapeStyle(LinearGradient(colors: [accent, accent.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.primary.opacity(scheme == .dark ? 0.14 : 0.075)))
                    .annotation(position: .top, alignment: .center, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        if active && v > 0 {
                            VStack(spacing: 1) {
                                Text(r.label).font(.caption2).opacity(0.75)
                                Text(metric.format(v)).font(.caption.weight(.semibold)).monospacedDigit()
                            }
                            // Omgekeerd contrast: donker op licht, licht op donker
                            .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(scheme == .dark ? Color(white: 0.92) : Color(white: 0.16),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
            }
            .chartXSelection(value: $hovered)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(Color.secondary.opacity(0.35))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(metric.axis(d)) } }
                }
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(.caption) }
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .frame(minHeight: 210)
            .animation(.spring(response: 0.35, dampingFraction: 1), value: metric)
        }
        .card()
    }
}

/// Rond "avatar"-vlak met initialen (voor praktijken).
struct Initials: View {
    let name: String
    var size: CGFloat = 34

    var body: some View {
        let letters = name.split(separator: " ")
            .filter { !["huisartsenpraktijk", "praktijk", "gezondheidscentrum", "de", "het", "van", "aan"].contains($0.lowercased()) }
            .prefix(2).compactMap(\.first).map(String.init).joined()
        Text(letters.isEmpty ? "•" : letters.uppercased())
            .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)
            .frame(width: size, height: size)
            .background(accent.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}
