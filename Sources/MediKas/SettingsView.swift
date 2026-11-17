import SwiftUI

/// Standaard macOS-instellingenvenster (⌘,) met tabbladen.
struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsTab().frame(width: 660, height: 640)
                .tabItem { Label("Weergave", systemImage: "paintpalette") }
            BusinessSettingsTab().frame(width: 660, height: 640)
                .tabItem { Label("Bedrijf", systemImage: "person.crop.rectangle") }
            InvoicingSettingsTab().frame(width: 660, height: 640)
                .tabItem { Label("Facturatie", systemImage: "doc.text") }
            BrandSettingsTab().frame(width: 1060, height: 780)
                .tabItem { Label("Huisstijl", systemImage: "swatchpalette") }
            StorageSettingsTab().frame(width: 660, height: 640)
                .tabItem { Label("Opslag", systemImage: "externaldrive.badge.icloud") }
            UpdatesSettingsTab().frame(width: 660, height: 640)
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
    }
}

struct BusinessSettingsTab: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let s = $store.data.settings
        Form {
            Section("Bedrijf") {
                TextField("Bedrijfsnaam", text: s.practiceName, prompt: Text("zoals bij de KvK"))
                TextField("Handelsnaam (groot op factuur)", text: s.tradeName, prompt: Text("optioneel"))
                TextField("Je naam", text: s.ownerName, prompt: Text("zoals op de factuur"))
                TextField("Functie", text: s.title)
                TextField("Adres", text: s.address)
                TextField("Postcode", text: s.postalCode)
                TextField("Plaats", text: s.city)
                TextField("Telefoon", text: s.phone)
                TextField("E-mail", text: s.email)
                TextField("Website", text: s.website)
            }
            Section {
                HStack {
                    if let logo = store.logo {
                        Image(nsImage: logo).resizable().scaledToFit().frame(maxWidth: 180, maxHeight: 60)
                    } else {
                        Text("Geen logo — de handelsnaam wordt als kop gebruikt.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Kies logo…") { store.chooseLogo() }
                    if store.logo != nil { Button("Verwijder") { store.removeLogo() } }
                }
            } header: { Text("Logo") }

            Section("Registratie") {
                TextField("KvK-nummer", text: s.kvk)
                TextField("AGB-code", text: s.agb, prompt: Text("optioneel"))
                TextField("BIG-nummer", text: s.big)
                TextField("Btw-identificatienummer", text: s.vatNumber, prompt: Text("optioneel"))
            }
            Section("Bank") {
                TextField("IBAN", text: s.iban)
                TextField("BIC", text: s.bic, prompt: Text("optioneel"))
                TextField("Ten name van", text: s.accountHolder, prompt: Text(store.data.settings.holder))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.visible)
    }
}

struct InvoicingSettingsTab: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let s = $store.data.settings
        Form {
            Section {
                LabeledContent("Standaard uurtarief") { NumberField(value: s.defaultHourlyRate, prefix: "€", suffix: "per uur").frame(width: 170) }
                LabeledContent("Standaard km-vergoeding") { NumberField(value: s.defaultKmRate, prefix: "€", suffix: "per km", digits: 3).frame(width: 170) }
                Stepper("Betaaltermijn: \(store.data.settings.paymentTermDays) dagen", value: s.paymentTermDays, in: 0...90, step: 7)
                TextField("Voorvoegsel factuurnummer", text: s.invoicePrefix, prompt: Text("bijv. ASH-"))
                LabeledContent("Volgend factuurnummer") { Text(store.nextInvoiceNumber(for: Date())).monospacedDigit() }
                TextField("Standaard omschrijving regel", text: s.defaultLineDescription, prompt: Text("bijv. Waarneming"))
            } header: {
                Text("Facturatie")
            } footer: {
                Text("Nieuwe praktijken krijgen deze tarieven automatisch. Per praktijk kun je ze daarna aanpassen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                TextField("Btw-tekst", text: s.vatText, axis: .vertical).lineLimit(1...3)
                TextField("Betaalinstructie", text: s.paymentText, axis: .vertical).lineLimit(2...5)
                TextField("Afsluiting", text: s.closingText, axis: .vertical).lineLimit(1...3)
            } header: {
                Text("Teksten op de factuur")
            } footer: {
                Text("In de betaalinstructie kun je gebruiken: {TERMIJN}, {IBAN}, {NAAM}, {FACTUUR}, {BEDRAG}, {VERVALDATUM}. Huisartsenzorg (ook waarneming) is meestal vrijgesteld van btw — check dit bij twijfel met je boekhouder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.visible)
    }
}

struct StorageSettingsTab: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let s = $store.data.settings
        Form {
            Section {
                LabeledContent {
                    Button("Toon in Finder") { NSWorkspace.shared.open(store.folder) }
                } label: {
                    Label(store.folderKind.name, systemImage: store.folderKind.icon)
                    Text(store.folder.path).font(.caption).textSelection(.enabled)
                }
                HStack {
                    Button { store.useICloudDrive() } label: { Label("iCloud Drive", systemImage: "icloud") }
                        .disabled(store.folderKind.name == "iCloud Drive")
                    ForEach(Store.googleDriveRoots, id: \.self) { root in
                        Button { store.changeFolder(to: root.appendingPathComponent("MediKas", isDirectory: true)) } label: {
                            Label(Store.googleDriveRoots.count > 1 ? "Google Drive (\(root.deletingLastPathComponent().lastPathComponent.replacingOccurrences(of: "GoogleDrive-", with: "")))" : "Google Drive",
                                  systemImage: "externaldrive.badge.icloud")
                        }
                    }
                    Button("Andere map…") { store.chooseFolder() }
                    Spacer()
                    if !store.isDefaultFolder { Button("Terug naar deze Mac") { store.useDefaultFolder() } }
                }
            } header: {
                Text("Opslaglocatie")
            } footer: {
                Text("""
                Gegevens, back-ups en het factuurarchief staan samen in deze map. Met iCloud Drive of Google Drive heb je automatisch een kopie in de cloud en kun je erbij vanaf elke Mac. Bij het wisselen worden de bestaande gegevens meegekopieerd; de oude map blijft staan.
                Let op: gebruik MediKas op één Mac tegelijk. Bij Google Drive kun je de map het beste op ‘offline beschikbaar’ zetten.
                """)
                .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Bewaar automatisch een PDF van elke verstuurde factuur", isOn: s.archivePDFs)
                Toggle("Per maand indelen", isOn: Binding(get: { store.data.settings.archiveByMonth },
                                                          set: { store.setArchiveByMonth($0) }))
                    .help("Bijv. Facturen/2026/03 maart/. Bestaande PDF’s worden meeverplaatst.")
                HStack {
                    Button("Open factuurarchief") { store.openArchive() }
                    Button("Ontbrekende PDF’s archiveren") { store.archiveMissing() }
                    Spacer()
                }
            } header: {
                Text("Factuurarchief (bewaarplicht 7 jaar)")
            } footer: {
                Text("Elke verstuurde factuur wordt als PDF bewaard in Facturen/<jaar>/ (of per maand: Facturen/<jaar>/<nn maand>/) in de gegevensmap, precies zoals hij is verstuurd. De factuurdatum bepaalt de map. Verwijderde facturen gaan naar Facturen/Verwijderd; die PDF’s blijven dus bewaard.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    HStack {
                        Button(store.backupDestination == nil ? "Kies locatie…" : "Wijzig…") { store.chooseBackupDestination() }
                        if store.backupDestination != nil {
                            Button("Uitzetten") { store.backupDestination = nil }
                        }
                    }
                } label: {
                    if let dest = store.backupDestination {
                        Label(store.backupDestinationReachable ? "Extra back-uplocatie" : "Extra back-uplocatie (niet bereikbaar)",
                              systemImage: store.backupDestinationReachable ? "externaldrive.fill.badge.checkmark" : "externaldrive.badge.xmark")
                        Text(dest.path).font(.caption).textSelection(.enabled)
                    } else {
                        Label("Geen extra back-uplocatie", systemImage: "externaldrive.badge.questionmark")
                        Text("Aanbevolen: een externe schijf, NAS of een tweede cloudmap").font(.caption)
                    }
                }
                LabeledContent("Laatste back-up") {
                    if store.isBackingUp {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(store.lastBackupDate.map { "\($0.long), \($0.formatted(date: .omitted, time: .shortened))" } ?? "nog nooit")
                    }
                }
                if let problem = store.lastBackupProblem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("Nu back-up maken") { store.backupNow() }
                        .disabled(store.backupDestination == nil || store.isBackingUp)
                    Button("Back-up opslaan als…") { store.saveBackupAs() }.disabled(store.isBackingUp)
                    Button("Back-up terugzetten…") { store.importBackup() }
                    Spacer()
                    if let dest = store.backupDestination, store.backupDestinationReachable {
                        Button("Open") { NSWorkspace.shared.open(dest) }
                    }
                }
            } header: {
                Text("Back-ups")
            } footer: {
                Text("""
                Een back-up is een zip met álles: gegevens, logo en alle factuur-PDF’s. Die gaat elke dag automatisch naar de extra back-uplocatie, zodra MediKas open is en de locatie bereikbaar is. De laatste 30 blijven bewaard, plus één per maand voor altijd.
                Daarnaast staat in de gegevensmap zelf elke dag een kopie van de gegevens (map Backups).
                Het veiligst: gegevens in iCloud Drive én back-ups naar een externe schijf. Gaat er dan iets mis in de cloud, dan heb je nog een eigen kopie.
                """)
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.visible)
    }
}


// MARK: - Weergave

struct AppearanceSettingsTab: View {
    @ObservedObject private var theme = Theme.shared

    var body: some View {
        Form {
            Section("Uiterlijk") {
                HStack(spacing: 22) {
                    ForEach(AppearanceMode.allCases) { mode in
                        AppearanceTile(mode: mode, selected: theme.appearance == mode) { theme.appearance = mode }
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            Section {
                HStack(spacing: 14) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button { theme.accentChoice = choice } label: {
                            Circle()
                                .fill(choice == .systeem
                                      ? AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
                                      : AnyShapeStyle(choice.color.gradient))
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                                .overlay {
                                    if theme.accentChoice == choice { Circle().fill(.white).frame(width: 7, height: 7) }
                                }
                                .padding(3)
                                .overlay {
                                    if theme.accentChoice == choice {
                                        Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(choice.label)
                        .accessibilityLabel(choice.label)
                    }
                    Spacer()
                    Text(theme.accentChoice.label).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Accentkleur")
            } footer: {
                Text("Voor knoppen, grafieken en markeringen in de app. De factuur zelf houdt altijd dezelfde huisstijlkleur.")
                    .font(.caption).foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
    }

}

/// Mini-venster als voorbeeld, zoals in Systeeminstellingen → Weergave.
struct AppearanceTile: View {
    let mode: AppearanceMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    switch mode {
                    case .light: window(dark: false)
                    case .dark: window(dark: true)
                    case .system:
                        window(dark: false)
                            .overlay(window(dark: true).mask(HStack(spacing: 0) { Color.clear; Color.black }))
                    }
                }
                .frame(width: 96, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? accent : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 0.5))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                Text(mode.label).font(.callout).fontWeight(selected ? .semibold : .regular)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func window(dark: Bool) -> some View {
        let bg = dark ? Color(white: 0.12) : Color(white: 0.94)
        let card = dark ? Color(white: 0.22) : .white
        let side = dark ? Color(white: 0.17) : Color(white: 0.88)
        return HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(side).frame(width: 22)
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(card)
                    RoundedRectangle(cornerRadius: 3).fill(card)
                }
                RoundedRectangle(cornerRadius: 3).fill(card).overlay(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach([0.4, 0.7, 0.5, 0.9], id: \.self) { h in
                            RoundedRectangle(cornerRadius: 1.5).fill(accent.opacity(0.8)).frame(width: 5, height: 18 * h)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .padding(5)
        .background(bg)
    }
}

// MARK: - Updates

struct UpdatesSettingsTab: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Versie", value: updater.version)
                Toggle("Dagelijks automatisch naar updates zoeken", isOn: $updater.automaticallyChecks)
                Toggle("Updates automatisch downloaden en installeren", isOn: $updater.automaticallyDownloads)
                    .disabled(!updater.automaticallyChecks)
                LabeledContent("Laatst gecontroleerd") {
                    Text(updater.lastCheck.map { "\($0.long), \($0.formatted(date: .omitted, time: .shortened))" } ?? "nog niet")
                }
                HStack {
                    Spacer()
                    Button("Zoek nu naar updates") { updater.checkForUpdates() }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Nieuwe versies komen van github.com/chrisonstein/medikas. Updates zijn digitaal ondertekend; je gegevens worden er niet door aangeraakt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
