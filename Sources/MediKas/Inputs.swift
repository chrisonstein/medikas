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

struct DateField: View {
    @Binding var date: Date
    var style: Style = .long
    @Local private var open = false
    @FocusState private var focused: Bool

    enum Style { case long, short }

    init(date: Binding<Date>, style: Style = .long) { _date = date; self.style = style }

    var body: some View {
        HStack(spacing: 4) {
            // Echt invoerveld: dag, maand en jaar typen; Tab of pijltjes om te wisselen
            DatePicker("Datum", selection: Binding(get: { date }, set: { date = $0.startOfDay }),
                       displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
                .environment(\.locale, nl)          // altijd dd-mm-jjjj
                .environment(\.calendar, nlCalendar)
                .focused($focused)
            Spacer(minLength: 0)
            Button { open.toggle() } label: {
                Image(systemName: "calendar").foregroundStyle(.secondary)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Kies in de kalender")
            .accessibilityLabel("Kalender openen")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(spacing: 10) {
                    DatePicker("", selection: Binding(get: { date }, set: { date = $0.startOfDay }), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    HStack {
                        Button("Vandaag") { date = Date().startOfDay }
                        Spacer()
                        Button("Klaar") { open = false }.keyboardShortcut(.defaultAction)
                    }
                    .controlSize(.small)
                }
                .padding(14)
                .environment(\.locale, nl)
            }
        }
        .padding(.leading, -4)
        .modifier(FieldSurface(focused: focused || open))
        .help(date.long)
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
