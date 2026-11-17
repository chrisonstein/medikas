import SwiftUI

// Moderne invoervelden: rustig vlak, accentrand bij focus, eenheden in het veld,
// en getallen die direct meerekenen terwijl je typt.

/// Het vlak waarin een veld staat (gedeeld door alle invoervelden).
struct FieldSurface: ViewModifier {
    var focused: Bool
    var invalid: Bool = false
    var height: CGFloat = 32

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        content
            .padding(.horizontal, 10)
            .frame(minHeight: height)
            .background(Color.well, in: shape)
            .overlay(shape.strokeBorder(invalid ? Color.orange : (focused ? accent : Color.primary.opacity(0.06)),
                                        lineWidth: focused || invalid ? 1.5 : 0.5))
            .shadow(color: focused ? accent.opacity(0.18) : .clear, radius: 4)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// Label boven een veld, met optionele hulptekst eronder.
struct LabeledField<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content()
            if let hint { Text(hint).font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tekst

struct InputField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var axis: Axis = .horizontal
    var invalid = false
    var autofocus = false
    @FocusState private var focused: Bool

    init(_ placeholder: String, text: Binding<String>, icon: String? = nil, axis: Axis = .horizontal,
         invalid: Bool = false, autofocus: Bool = false) {
        self.placeholder = placeholder; _text = text; self.icon = icon; self.axis = axis
        self.invalid = invalid; self.autofocus = autofocus
    }

    var body: some View {
        HStack(spacing: 7) {
            if let icon { Image(systemName: icon).foregroundStyle(.secondary).font(.callout) }
            TextField(placeholder, text: $text, axis: axis)
                .labelsHidden()
                .textFieldStyle(.plain)
                .lineLimit(axis == .vertical ? 2...6 : 1...1)
                .focused($focused)
                .padding(.vertical, axis == .vertical ? 8 : 0)
        }
        .modifier(FieldSurface(focused: focused, invalid: invalid))
        .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
    }
}

// MARK: - Getal (live, met eenheden)

struct NumberField: View {
    @Binding var value: Decimal
    var prefix: String? = nil
    var suffix: String? = nil
    var digits: Int = 2
    var placeholder = "0"
    var compact = false
    var autofocus = false
    var onSubmit: (() -> Void)? = nil

    @Local private var text = ""
    @FocusState private var focused: Bool

    init(value: Binding<Decimal>, prefix: String? = nil, suffix: String? = nil, digits: Int = 2,
         placeholder: String = "0", compact: Bool = false, autofocus: Bool = false, onSubmit: (() -> Void)? = nil) {
        _value = value; self.prefix = prefix; self.suffix = suffix; self.digits = digits
        self.placeholder = placeholder; self.compact = compact; self.autofocus = autofocus; self.onSubmit = onSubmit
    }

    var body: some View {
        HStack(spacing: 4) {
            if let prefix { Text(prefix).foregroundStyle(.secondary).accessibilityHidden(true) }
            TextField(placeholder, text: $text)
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focused)
                .onSubmit { onSubmit?() }
            if let suffix { Text(suffix).foregroundStyle(.secondary).font(.callout).accessibilityHidden(true) }
        }
        .modifier(FieldSurface(focused: focused, invalid: !text.isEmpty && NumberField.parse(text) == nil,
                               height: compact ? 28 : 32))
        .onAppear {
            text = format(value)
            if autofocus { DispatchQueue.main.async { focused = true } }
        }
        .onChange(of: text) { _, new in
            // Direct meerekenen tijdens het typen
            if let v = NumberField.parse(new), v != value { value = v }
            if new.isEmpty, value != 0 { value = 0 }
        }
        .onChange(of: value) { _, new in
            if !focused, NumberField.parse(text) != new { text = format(new) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { text = format(value) }   // netjes opmaken na verlaten
        }
    }

    private func format(_ v: Decimal) -> String { v == 0 ? "" : v.fmt(digits) }

    /// "1.234,5" en "0.23" worden allebei goed gelezen.
    static func parse(_ s: String) -> Decimal? {
        var t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        if t.isEmpty { return 0 }
        if t.contains(",") { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        guard t.range(of: #"^-?\d*\.?\d*$"#, options: .regularExpression) != nil, t != ".", t != "-" else { return nil }
        return Decimal(string: t, locale: Locale(identifier: "en_US_POSIX"))
    }
}

// MARK: - Datum (typen met het toetsenbord, of kiezen in een kalender)

/// Datumveld in dezelfde stijl als de andere velden. Typen als 01-10-2026 (ook 1-10-26, 1/10/2026 of 01102026),
/// ↑/↓ = dag verder/terug (⇧ = week), kalenderknop voor kiezen met de muis.
struct DateField: View {
    @Binding var date: Date
    var style: Style = .long
    @Local private var open = false
    @Local private var text = ""
    @FocusState private var focused: Bool

    enum Style { case long, short }

    init(date: Binding<Date>, style: Style = .long) { _date = date; self.style = style }

    private var invalid: Bool { !text.isEmpty && DateField.parse(text) == nil }

    var body: some View {
        HStack(spacing: 4) {
            TextField("dd-mm-jjjj", text: $text)
                .labelsHidden()
                .textFieldStyle(.plain)
                .monospacedDigit()
                .focused($focused)
                .onSubmit { commit() }
                .onKeyPress(.upArrow, phases: .down) { press in step(press.modifiers.contains(.shift) ? 7 : 1); return .handled }
                .onKeyPress(.downArrow, phases: .down) { press in step(press.modifiers.contains(.shift) ? -7 : -1); return .handled }
                .accessibilityValue(date.long)
            Button { open.toggle() } label: {
                Image(systemName: "calendar").foregroundStyle(.secondary)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Kies in de kalender")
            .accessibilityLabel("Kalender openen")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(spacing: 10) {
                    DatePicker("", selection: Binding(get: { date }, set: { set($0) }), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    HStack {
                        Button("Vandaag") { set(Date()) }
                        Spacer()
                        Button("Klaar") { open = false }.keyboardShortcut(.defaultAction)
                    }
                    .controlSize(.small)
                }
                .padding(14)
                .environment(\.locale, nl)
                .environment(\.calendar, nlCalendar)
            }
        }
        .modifier(FieldSurface(focused: focused || open, invalid: invalid))
        .help(date.long)
        .onAppear { text = Fmt.short.string(from: date) }
        .onChange(of: date) { _, new in if !focused || DateField.parse(text) != new.startOfDay { text = Fmt.short.string(from: new) } }
        .onChange(of: text) { _, new in
            // Direct overnemen zodra het een volledige, geldige datum is
            if let d = DateField.parse(new), d != date.startOfDay { date = d }
        }
        .onChange(of: focused) { _, f in if !f { commit() } }
    }

    private func set(_ d: Date) {
        date = d.startOfDay
        text = Fmt.short.string(from: date)
    }

    private func step(_ days: Int) { set(date.adding(days: days)) }

    private func commit() {
        if let d = DateField.parse(text) { set(d) } else { text = Fmt.short.string(from: date) }
    }

    /// Leest d-m-jjjj, d/m/jj, d.m.jjjj en 8 of 6 cijfers zonder scheiding. Twee cijfers voor het jaar = 20xx.
    static func parse(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        var parts = s.split(whereSeparator: { "-/. ".contains($0) }).map(String.init)
        if parts.count == 1, let only = parts.first, only.allSatisfy(\.isNumber) {
            if only.count == 8 { parts = [String(only.prefix(2)), String(only.dropFirst(2).prefix(2)), String(only.suffix(4))] }
            else if only.count == 6 { parts = [String(only.prefix(2)), String(only.dropFirst(2).prefix(2)), String(only.suffix(2))] }
        }
        guard parts.count == 3, let d = Int(parts[0]), let m = Int(parts[1]), var y = Int(parts[2]),
              parts[2].count == 2 || parts[2].count == 4 else { return nil }
        if parts[2].count == 2 { y += 2000 }
        guard (1...12).contains(m), (1...31).contains(d), (1990...2100).contains(y),
              let date = nlCalendar.date(from: DateComponents(year: y, month: m, day: d)),
              nlCalendar.component(.day, from: date) == d else { return nil }   // bv. 31-02 bestaat niet
        return date.startOfDay
    }
}

// MARK: - Keuze (standaard keuzemenu van macOS, bereikbaar met het toetsenbord)

struct MenuField<Value: Hashable>: View {
    let placeholder: String
    @Binding var selection: Value
    let options: [(Value, String)]
    var icon: String? = nil

    var body: some View {
        Picker(placeholder, selection: $selection) {
            if !options.contains(where: { $0.0 == selection }) {
                Text(placeholder).tag(selection)
            }
            ForEach(options, id: \.0) { option in
                Text(option.1).tag(option.0)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlSize(.large)
        .accessibilityLabel(placeholder)
    }
}

// MARK: - Schakelaar-rij

struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background(Color.well, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Werkbalkknoppen

/// Hoofdactie in de werkbalk: icoon + tekst, in de accentkleur van het systeem.
struct PrimaryToolbarButton: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
    }
}

/// Gewone werkbalkactie met icoon + tekst.
struct ToolbarTextButton: View {
    let title: String
    let icon: String
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).labelStyle(.titleAndIcon)
        }
        .help(help ?? title)
    }
}

// MARK: - Zoekveld (in context, boven een tabel)

extension Notification.Name {
    /// ⌘F: zet de focus in het zoekveld van de huidige pagina.
    static let focusSearch = Notification.Name("MediKasFocusSearch")
}

struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var width: CGFloat? = 260
    @FocusState private var focused: Bool

    init(_ prompt: String, text: Binding<String>, width: CGFloat? = 260) {
        self.prompt = prompt; _text = text; self.width = width
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { text = ""; focused = false }   // Esc wist de zoekopdracht
                .accessibilityLabel("Zoeken")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Wis zoekopdracht")
                .accessibilityLabel("Wis zoekopdracht")
            }
        }
        .modifier(FieldSurface(focused: focused, height: 30))
        .frame(width: width)
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in focused = true }
    }
}
