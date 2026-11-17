import SwiftUI

/// Instellingen → Huisstijl: opmaak, logo, kleuren, lettertypen en patroon van de factuur, met live voorbeeld.
struct BrandSettingsTab: View {
    @EnvironmentObject var store: Store

    private var style: Binding<InvoiceStyle> { $store.data.settings.style }

    var body: some View {
        HStack(spacing: 0) {
            Form {
                templateSection
                logoSection
                colorSection
                fontSection
                patternSection
            }
            .formStyle(.grouped)
            .frame(width: 470)

            Divider()

            InvoicePreview()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Opmaak

    private var templateSection: some View {
        Section("Opmaak") {
            Toggle("Titel in hoofdletters (FACTUUR)", isOn: style.titleUppercase)
            Toggle("Lijnen met kleurverloop", isOn: style.gradientLines)
                .help("Verloop van de hoofdkleur naar de tweede kleur, boven het totaal en de voettekst")
        }
    }

    // MARK: Logo

    private var logoSection: some View {
        Section {
            HStack {
                if let logo = store.logo {
                    Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 50, alignment: .leading)
                } else {
                    Text("Geen logo: de bedrijfsnaam wordt als kop gebruikt.").foregroundStyle(.secondary)
                }
                Spacer()
                Button(store.logo == nil ? "Kies logo…" : "Wijzig…") { store.chooseLogo() }
                if store.logo != nil { Button("Verwijder") { store.removeLogo() } }
            }
            if store.logo != nil {
                LabeledContent("Hoogte op de factuur") {
                    HStack {
                        Slider(value: style.logoHeight, in: 28...90).frame(width: 160)
                        Text("\(Int(store.data.settings.style.logoHeight)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
            }
        } header: {
            Text("Logo")
        } footer: {
            Text("Lege randen rond het logo worden automatisch weggesneden, zodat de hoogte klopt. Een heel breed logo wordt maximaal 300 pt breed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Kleuren

    private var colorSection: some View {
        Section {
            ColorRow(title: "Tekst", hint: "Koppen en lopende tekst", hex: style.textHex)
            ColorRow(title: "Hoofdkleur", hint: "Titels, tabelkoppen, accenten", hex: style.primaryHex)
            ColorRow(title: "Tweede kleur", hint: "Einde van het kleurverloop", hex: style.secondaryHex)
            ColorRow(title: "Vlakken", hint: "Tabelkop en betaalvak (heel licht)", hex: style.surfaceHex)
            HStack {
                Button("Neem kleuren over uit logo") { store.colorsFromLogo() }
                    .disabled(store.logo == nil)
                Spacer()
                Button("Standaardkleuren") {
                    let d = InvoiceStyle()
                    store.undoable("Standaardkleuren") {
                        store.data.settings.style.textHex = d.textHex
                        store.data.settings.style.primaryHex = d.primaryHex
                        store.data.settings.style.secondaryHex = d.secondaryHex
                        store.data.settings.style.surfaceHex = d.surfaceHex
                    }
                }
                .buttonStyle(.link)
            }
        } header: {
            Text("Kleuren")
        } footer: {
            Text("Vul de hexcodes uit je huisstijlhandboek in (bijv. 8E5CFF), kies met de kleurkiezer, of neem ze over uit je logo.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Lettertypen

    private var fontOptions: [String] { store.customFontFamilies + BrandFonts.builtIn }

    private var fontSection: some View {
        Section {
            fontPicker("Koppen", selection: style.headingFont)
            fontPicker("Tekst", selection: style.bodyFont)
            HStack {
                Button("Lettertype toevoegen…") { store.addFonts() }
                Spacer()
                if !store.customFontFamilies.isEmpty {
                    Menu("Verwijder") {
                        ForEach(store.customFontFamilies, id: \.self) { f in
                            Button(f) { store.removeFontFamily(f) }
                        }
                    }
                    .fixedSize()
                }
            }
        } header: {
            Text("Lettertypen")
        } footer: {
            Text("Eigen lettertypen (.ttf/.otf) worden in je gegevensmap bewaard, zodat ze ook op een andere Mac werken. Inter is gratis te downloaden via rsms.me/inter.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func fontPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("Systeem (SF Pro)").tag("")
            if !store.customFontFamilies.isEmpty {
                Section("Toegevoegd") {
                    ForEach(store.customFontFamilies, id: \.self) { f in Text(f).font(.custom(f, size: 13)).tag(f) }
                }
            }
            Section("macOS") {
                ForEach(BrandFonts.builtIn, id: \.self) { f in Text(f).font(.custom(f, size: 13)).tag(f) }
            }
        }
    }

    // MARK: Patroon

    private var patternSection: some View {
        Section {
            Picker("Patroon onderaan", selection: style.pattern) {
                ForEach(InvoiceStyle.Pattern.allCases) { Text($0.label).tag($0) }
            }
            if store.data.settings.style.pattern == .afbeelding {
                HStack {
                    if let p = store.patternImage {
                        Image(nsImage: p).resizable().interpolation(.high).scaledToFit().frame(height: 28)
                    } else {
                        Text("Nog geen afbeelding gekozen").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.patternImage == nil ? "Kies afbeelding…" : "Wijzig…") { store.choosePattern() }
                    if store.patternImage != nil { Button("Verwijder") { store.removePattern() } }
                }
            }
            if store.data.settings.style.pattern != .geen {
                LabeledContent("Dekking") {
                    HStack {
                        Slider(value: style.patternOpacity, in: 0.05...0.6).frame(width: 160)
                        Text("\(Int(store.data.settings.style.patternOpacity * 100))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Hoogte") {
                    HStack {
                        Slider(value: style.patternHeight, in: 18...70).frame(width: 160)
                        Text("\(Int(store.data.settings.style.patternHeight)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
            }
        } header: {
            Text("Patroon")
        } footer: {
            Text("Een rand van herhaalde beeldmerken onderaan de pagina, zoals op briefpapier. Komt nooit onder de tekst. Gebruik bij voorkeur alleen het beeldmerk (zonder naam) met een transparante achtergrond.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Kleur kiezen met kleurkiezer én hexcode.
struct ColorRow: View {
    let title: String
    let hint: String
    @Binding var hex: String
    @Local private var text = ""

    init(title: String, hint: String, hex: Binding<String>) {
        self.title = title; self.hint = hint; _hex = hex
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                TextField("Hex", text: $text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(width: 90)
                    .onSubmit { apply() }
                    .onChange(of: text) { _, new in if Color(hex: new) != nil, new.count >= 6 { apply() } }
                ColorPicker(title, selection: Binding(
                    get: { Color(hex: hex) ?? .black },
                    set: { hex = $0.hex; text = "#" + hex }), supportsOpacity: false)
                    .labelsHidden()
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { text = "#" + hex }
        .onChange(of: hex) { _, new in if Color(hex: text)?.hex != new { text = "#" + new } }
    }

    private func apply() {
        guard let c = Color(hex: text) else { return }
        let h = c.hex
        if h != hex { hex = h }
    }
}

/// Live voorbeeld van de eerste pagina, met de laatste echte factuur of voorbeeldgegevens.
struct InvoicePreview: View {
    @EnvironmentObject var store: Store

    private var sample: Invoice {
        if let latest = store.data.invoices.filter({ !$0.lines.isEmpty && !$0.isCredit }).max(by: { $0.date < $1.date }) {
            return latest
        }
        var inv = Invoice()
        inv.number = store.nextInvoiceNumber(for: Date())
        inv.billTo.name = "Voorbeeldpraktijk"
        inv.billTo.address = "Voorbeeldstraat 1"
        inv.billTo.postalCode = "1234 AB"; inv.billTo.city = "Voorbeeldplaats"
        inv.kmRate = store.data.settings.defaultKmRate
        inv.reference = "Voorbeeld"
        inv.lines = (0..<3).map { i in
            var l = WorkLine()
            l.date = Date().startOfDay.adding(days: i - 5)
            l.description = store.data.settings.defaultLineDescription.isEmpty ? "Waarneming" : store.data.settings.defaultLineDescription
            l.hours = 8; l.hourlyRate = store.data.settings.defaultHourlyRate > 0 ? store.data.settings.defaultHourlyRate : 100
            l.commuteKm = 30; l.visitKm = Decimal(i * 6)
            return l
        }
        return inv
    }

    var body: some View {
        let inv = sample
        let pages = InvoicePDF.pages(for: inv, settings: store.data.settings, brand: store.brand)
        VStack(spacing: 10) {
            HStack {
                Text("Voorbeeld").font(.headline)
                Text(store.data.invoices.isEmpty ? "met voorbeeldgegevens" : "factuur \(inv.number)").foregroundStyle(.secondary)
                Spacer()
                Button("Open als PDF") { InvoicePDF.preview(inv, store: store) }
            }
            GeometryReader { geo in
                let scale = min(geo.size.width / 595.28, geo.size.height / 841.89)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                            page
                                .scaleEffect(scale, anchor: .topLeading)
                                .frame(width: 595.28 * scale, height: 841.89 * scale, alignment: .topLeading)
                                .background(Rectangle().fill(.white).shadow(color: .black.opacity(0.18), radius: 8, y: 2))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(18)
        .background(Color.canvas)
    }
}
