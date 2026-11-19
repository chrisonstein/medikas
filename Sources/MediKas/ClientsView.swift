import SwiftUI

// MARK: - Cijfers per praktijk

struct ClientSummary {
    var invoiceCount = 0
    var invoicedThisYear: Decimal = 0
    var outstanding: Decimal = 0
    var hoursThisYear: Decimal = 0
    var lastInvoice: Date?
    var avgDaysToPay: Double?
    var paidOnTime = 0
    var paidCount = 0

    @MainActor init(client: Client, store: Store) {
        let year = Date().year
        let all = store.data.invoices.filter { $0.clientID == client.id }
        let sent = all.filter(\.isSent)
        invoiceCount = all.count
        invoicedThisYear = sent.filter { $0.date.year == year }.sum(\.total)
        outstanding = sent.sum(\.outstanding)
        hoursThisYear = sent.filter { $0.date.year == year }.sum(\.hours)
        lastInvoice = all.map(\.date).max()
        let paid = sent.filter { $0.status() == .paid }
        let days = paid.compactMap { inv in inv.lastPaymentDate.map { nlCalendar.dateComponents([.day], from: inv.date, to: $0).day ?? 0 } }
        avgDaysToPay = days.isEmpty ? nil : Double(days.reduce(0, +)) / Double(days.count)
        paidCount = paid.count
        paidOnTime = paid.filter { ($0.lastPaymentDate ?? .distantFuture) <= $0.dueDate.adding(days: 1) }.count
    }
}

// MARK: - Praktijken: overzicht → detail

struct ClientsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Group {
            if let id = store.selectedClientID, store.client(id) != nil {
                ClientPage(clientID: id)
                    .id(id)
                    .transition(.opacity)
            } else {
                ClientsOverview()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: store.selectedClientID)
        .navigationTitle("Praktijken")
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { store.clientToDelete != nil },
                                                              set: { if !$0 { store.clientToDelete = nil } }),
                            titleVisibility: .visible, presenting: store.clientToDelete) { client in
            switch store.removal(for: client) {
            case .delete:
                Button("Verwijder praktijk", role: .destructive) { store.deleteClient(client) }
            case .deleteWithConcepts(let n):
                Button("Verwijder praktijk en \(n) concept\(n == 1 ? "" : "en")", role: .destructive) { store.deleteClient(client) }
            case .archiveOnly:
                if !client.archived { Button("Archiveer praktijk") { store.setArchived(client, true) } }
            }
            Button("Annuleer", role: .cancel) {}
        } message: { client in
            switch store.removal(for: client) {
            case .delete:
                Text("Er zijn geen facturen aan deze praktijk gekoppeld. Je kunt dit ongedaan maken met ⌘Z.")
            case .deleteWithConcepts(let n):
                Text("Er \(n == 1 ? "is 1 concept" : "zijn \(n) concepten") voor deze praktijk, maar nog geen verstuurde facturen. Die worden ook verwijderd. Je kunt dit ongedaan maken met ⌘Z.")
            case .archiveOnly(let sent):
                Text("Deze praktijk heeft \(sent) verstuurde factu\(sent == 1 ? "ur" : "ren"). Die moet je 7 jaar bewaren, dus de praktijk kan niet worden verwijderd. \(client.archived ? "Hij is al gearchiveerd." : "Archiveer hem: hij verdwijnt dan uit de lijsten, maar blijft op de facturen staan.")")
            }
        }
    }

    private var dialogTitle: String {
        guard let c = store.clientToDelete else { return "" }
        if case .archiveOnly = store.removal(for: c) { return "\(c.displayName) kan niet worden verwijderd" }
        return "\(c.displayName) verwijderen?"
    }
}

// MARK: - Overzicht

private enum ClientScope: String, CaseIterable, Identifiable {
    case actief = "Actief", archief = "Archief"
    var id: Self { self }
}

private enum ClientCol {
    static let city: CGFloat = 130, count: CGFloat = 70, money: CGFloat = 120, date: CGFloat = 100
}

struct ClientsOverview: View {
    @EnvironmentObject var store: Store
    @Local private var scope: ClientScope = .actief
    @Local private var search = ""

    private var clients: [Client] {
        store.data.clients
            .filter { scope == .archief ? $0.archived : !$0.archived }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.city.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let list = clients
        let year = String(Date().year)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader("Praktijken",
                           subtitle: "\(store.activeClients.count) actief · \(store.sentInvoices.filter { $0.date.year == Date().year }.sum(\.total).euro) gefactureerd in \(year)") {
                    PrimaryToolbarButton(title: "Nieuwe praktijk", icon: "plus", shortcut: "⇧⌘N") {
                        store.selectedClientID = store.addClient().id
                    }
                }
                .padding(.bottom, 8)

                if store.data.clients.isEmpty {
                    EmptyState(icon: "cross.case", title: "Nog geen praktijken",
                               message: "Voeg de praktijken toe waar je waarneemt. Adres en tarieven worden dan automatisch op elke factuur ingevuld.",
                               primary: ("Praktijk toevoegen", { store.selectedClientID = store.addClient().id }))
                        .card()
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            ChipPicker(options: ClientScope.allCases, selection: $scope) { s in
                                let n = store.data.clients.filter { s == .archief ? $0.archived : !$0.archived }.count
                                return "\(s.rawValue) \(n)"
                            }
                            Spacer(minLength: 8)
                            SearchField("Zoeken", text: $search, width: 240)
                                .help("Zoek op naam of plaats (⌘F)")
                        }

                        if list.isEmpty {
                            if !search.isEmpty {
                                EmptyState(icon: "magnifyingglass", title: "Niets gevonden voor ‘\(search)’",
                                           message: "Zoek op naam of plaats.", primary: ("Wis zoekopdracht", { search = "" }), compact: true)
                            } else {
                                EmptyState(icon: "archivebox", title: scope == .archief ? "Geen gearchiveerde praktijken" : "Geen actieve praktijken",
                                           message: scope == .archief ? "Praktijken die je archiveert, staan hier." : "Alle praktijken zijn gearchiveerd.",
                                           compact: true)
                            }
                        } else {
                            VStack(spacing: 0) {
                                header(year)
                                ForEach(list) { c in ClientListRow(client: c) }
                            }
                        }
                    }
                    .card(padding: 18)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 28).padding(.top, 6)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .canvas()
    }

    private func header(_ year: String) -> some View {
        HStack(spacing: 12) {
            Text("Praktijk").frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            Text("Plaats").frame(width: ClientCol.city, alignment: .leading)
            Text("Facturen").frame(width: ClientCol.count, alignment: .trailing)
            Text("Gefactureerd \(year)").frame(width: ClientCol.money, alignment: .trailing)
            Text("Openstaand").frame(width: ClientCol.money, alignment: .trailing)
            Text("Laatste factuur").frame(width: ClientCol.date, alignment: .trailing)
            Color.clear.frame(width: 14)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.bottom, 8)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}

/// Eén praktijk in het overzicht; klik = naar de praktijkpagina.
struct ClientListRow: View {
    @EnvironmentObject var store: Store
    let client: Client
    @Local private var hovering = false

    init(client: Client) { self.client = client }

    var body: some View {
        let s = ClientSummary(client: client, store: store)
        Button { store.selectedClientID = client.id } label: {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Initials(name: client.displayName, size: 30)
                    Text(client.displayName).fontWeight(.medium).lineLimit(1)
                }
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                Text(client.city.isEmpty ? "—" : client.city).foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: ClientCol.city, alignment: .leading)
                Text("\(s.invoiceCount)").monospacedDigit().frame(width: ClientCol.count, alignment: .trailing)
                Text(s.invoicedThisYear.euro).monospacedDigit().frame(width: ClientCol.money, alignment: .trailing)
                Text(s.outstanding > 0 ? s.outstanding.euro : "—").monospacedDigit()
                    .foregroundStyle(s.outstanding > 0 ? accent : .secondary)
                    .frame(width: ClientCol.money, alignment: .trailing)
                Text(s.lastInvoice?.short ?? "—").monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: ClientCol.date, alignment: .trailing)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .frame(width: 14)
            }
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(hovering ? Color.well : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowSeparator()
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hovering = h } }
        .contextMenu { ClientActions(client: client) }
        .help("Open \(client.displayName)")
        .accessibilityLabel("\(client.displayName), \(client.city), \(s.invoiceCount) facturen, \(s.outstanding.euro) openstaand")
        .accessibilityHint("Opent de praktijk")
    }
}

// MARK: - Praktijkpagina

struct ClientPage: View {
    @EnvironmentObject var store: Store
    let clientID: UUID
    /// Filters voor de facturen van deze praktijk (standaard: alle jaren)
    @Local private var filter = InvoiceFilter(year: nil)
    private static let defaultFilter = InvoiceFilter(year: nil)

    init(clientID: UUID) { self.clientID = clientID }

    private var client: Binding<Client> {
        Binding(get: { store.client(clientID) ?? Client() },
                set: { new in if let i = store.data.clients.firstIndex(where: { $0.id == clientID }) { store.data.clients[i] = new } })
    }
    private var invoices: [Invoice] { store.data.invoices.filter { $0.clientID == clientID }.sorted { $0.date > $1.date } }

    var body: some View {
        let c = client.wrappedValue
        let s = ClientSummary(client: c, store: store)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Terug naar het overzicht (ook ⌘[)
                Button { store.selectedClientID = nil } label: {
                    Label("Praktijken", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.link)
                .keyboardShortcut("[", modifiers: .command)
                .help("Terug naar alle praktijken (⌘[)")

                HStack(alignment: .center, spacing: 14) {
                    Initials(name: c.displayName, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.displayName).font(.system(size: 30, weight: .semibold)).tracking(-0.7).lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                        Text([c.city, c.archived ? "gearchiveerd" : nil, s.invoiceCount == 0 ? "nog geen facturen" : "\(s.invoiceCount) facturen"]
                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        Menu {
                            ClientActions(client: c)
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 18, height: 16)
                        }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Meer acties: bestaande factuur importeren, archiveren of verwijderen")
                        .accessibilityLabel("Meer acties")
                        Button { store.startImport(for: c) } label: {
                            Label("Importeer…", systemImage: "tray.and.arrow.down").labelStyle(.titleAndIcon)
                        }
                        .help("Importeer een factuur die je buiten MediKas hebt gemaakt (PDF)")
                        PrimaryToolbarButton(title: "Nieuwe factuur", icon: "plus") { store.startNewInvoice(for: c) }
                            .disabled(c.archived)
                    }
                    .controlSize(.large)
                }
                .padding(.bottom, 8)

                if c.archived {
                    Callout(icon: "archivebox", tint: .secondary, title: "Gearchiveerd",
                            text: "Deze praktijk staat niet meer in de keuzelijsten. De facturen blijven bewaard.",
                            action: ("Zet terug", { store.setArchived(c, false) }))
                }

                // Beknopte cijfers
                HStack(spacing: 12) {
                    CompactMetric(icon: "doc.text", label: "Gefactureerd \(String(Date().year))", value: s.invoicedThisYear.euro)
                    CompactMetric(icon: "clock", label: "Openstaand", value: s.outstanding.euro,
                                  detail: s.outstanding > 0 ? nil : "alles betaald", detailColor: .green)
                    CompactMetric(icon: "stethoscope", label: "Uren \(String(Date().year))", value: s.hoursThisYear.fmt(1))
                    CompactMetric(icon: "hourglass", label: "Gem. betaaltijd",
                                  value: s.avgDaysToPay.map { "\(Decimal($0).fmt(0)) dagen" } ?? "—",
                                  detail: s.paidCount > 0 ? "\(s.paidOnTime) van \(s.paidCount) op tijd" : nil)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Gegevens | tarieven + notities
                HStack(alignment: .top, spacing: 16) {
                    detailsCard(client).frame(maxWidth: .infinity)
                    VStack(spacing: 16) {
                        ratesCard(client)
                        notesCard(client)
                    }
                    .frame(width: 340)
                }
                .fixedSize(horizontal: false, vertical: true)
                .zIndex(1)   // adressuggesties mogen over de kaarten eronder vallen

                DocumentsCard(clientID: c.id)

                invoicesCard(c)
            }
            .padding(.horizontal, 28).padding(.bottom, 28).padding(.top, 6)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .canvas()
    }

    // Gegevens
    private func detailsCard(_ client: Binding<Client>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "building.2", title: "Gegevens", subtitle: "Komen zo op de factuur")
            LabeledField(label: "Naam") {
                PracticeNameField(client: client, autofocus: client.wrappedValue.name.isEmpty)
            }
            .zIndex(1)   // keuzelijst met adressuggesties valt over de velden eronder
            HStack(alignment: .top, spacing: 12) {
                LabeledField(label: "Ter attentie van") { InputField("Contactpersoon", text: client.contactPerson, icon: "person") }
                LabeledField(label: "E-mail voor facturen") { InputField("facturen@praktijk.nl", text: client.email, icon: "envelope") }
            }
            LabeledField(label: "Adres") { InputField("Straat en huisnummer", text: client.address) }
            HStack(alignment: .top, spacing: 12) {
                LabeledField(label: "Postcode") { InputField("1234 AB", text: client.postalCode) }.frame(width: 140)
                LabeledField(label: "Plaats") { InputField("Plaats", text: client.city) }
            }
        }
        .card()
    }

    // Tarieven
    private func ratesCard(_ client: Binding<Client>) -> some View {
        let usesDefaults = client.wrappedValue.hourlyRate == store.data.settings.defaultHourlyRate
            && client.wrappedValue.kmRate == store.data.settings.defaultKmRate
        return VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "eurosign", title: "Tarieven", subtitle: "Voorgesteld op nieuwe facturen") {
                if !usesDefaults {
                    Button("Standaard") {
                        client.wrappedValue.hourlyRate = store.data.settings.defaultHourlyRate
                        client.wrappedValue.kmRate = store.data.settings.defaultKmRate
                    }
                    .buttonStyle(.link)
                    .help("Neem de standaardtarieven uit de instellingen over")
                }
            }
            LabeledField(label: "Uurtarief") { NumberField(value: client.hourlyRate, prefix: "€", suffix: "per uur") }
            LabeledField(label: "Km-vergoeding") { NumberField(value: client.kmRate, prefix: "€", suffix: "per km", digits: 3) }
            LabeledField(label: "Woon-werk per dag", hint: "Retour, wordt per werkdag ingevuld") {
                NumberField(value: client.commuteKm, suffix: "km", digits: 1)
            }
        }
        .card()
    }

    private func notesCard(_ client: Binding<Client>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "note.text", title: "Notities", subtitle: "Alleen voor jezelf")
            InputField("Bijv. afspraken, dienstrooster, parkeren…", text: client.notes, axis: .vertical)
        }
        .card()
    }

    // Facturen
    private func invoicesCard(_ c: Client) -> some View {
        let list = invoices.filter(filter.matches)
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "doc.text", title: "Facturen",
                       subtitle: invoices.isEmpty ? nil
                        : "\(list.filter(\.isSent).sum(\.total).euro) gefactureerd · \(filter.periodText.lowercased() == "alle jaren" ? "alle jaren" : filter.periodText)")
            if !invoices.isEmpty {
                InvoiceFilterBar(filter: $filter, source: invoices, showClient: false,
                                 defaultFilter: Self.defaultFilter, searchWidth: 200)
            }
            if invoices.isEmpty {
                EmptyState(icon: "doc.text", title: "Nog geen facturen",
                           message: "Facturen voor deze praktijk verschijnen hier.",
                           primary: c.archived ? nil : ("Nieuwe factuur", { store.startNewInvoice(for: c) }),
                           secondary: ("Importeer bestaande factuur…", { store.startImport(for: c) }), compact: true)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Factuur").frame(width: 124, alignment: .leading)
                        Text("Datum").frame(width: 90, alignment: .leading)
                        Text("Periode").frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                        Text("Bedrag").frame(width: 110, alignment: .trailing)
                        Text("Status").frame(width: 120, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 8)
                    .overlay(alignment: .bottom) { Divider().opacity(0.6) }
                    ForEach(list) { inv in ClientInvoiceRow(invoice: inv) }
                }
                if list.isEmpty {
                    EmptyState(icon: "line.3.horizontal.decrease.circle", title: "Geen facturen met deze filters",
                               message: "Er zijn geen facturen in \(filter.periodText)\(filter.status == .alle ? "" : " met status ‘\(filter.status.rawValue)’").",
                               primary: ("Wis filters", { filter = Self.defaultFilter }), compact: true)
                }
            }
        }
        .card(padding: 18)
    }
}

struct ClientInvoiceRow: View {
    @EnvironmentObject var store: Store
    let invoice: Invoice
    @Local private var hovering = false

    init(invoice: Invoice) { self.invoice = invoice }

    var body: some View {
        HStack(spacing: 12) {
            Button { store.openPDF(invoice) } label: {
                HStack(spacing: 4) {
                    Text(invoice.number).monospacedDigit().lineLimit(1).fixedSize()
                    PDFBadge().opacity(0.8)
                    if invoice.isImported {
                        Image(systemName: "tray.and.arrow.down").font(.caption2).foregroundStyle(.secondary)
                            .help("Geïmporteerd: buiten MediKas gemaakt")
                    }
                }
                .foregroundStyle(accent).fontWeight(.medium)
                .frame(width: 124, height: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open PDF")
            .accessibilityLabel("PDF van \(invoice.documentTitle.lowercased()) \(invoice.number)")

            Button { store.edit(invoice) } label: {
                HStack(spacing: 12) {
                    Text(invoice.date.short).monospacedDigit().frame(width: 90, alignment: .leading)
                    HStack(spacing: 6) {
                        Text(invoice.periodText).foregroundStyle(.secondary).lineLimit(1)
                        if let link = store.linkSummary(invoice) {
                            Label(link, systemImage: "link").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                    Text(invoice.total.euro).monospacedDigit().fontWeight(.medium).frame(width: 110, alignment: .trailing)
                    StatusBadge(status: invoice.status()).frame(width: 120, alignment: .leading)
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(invoice.documentTitle) \(invoice.number) openen")
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(hovering ? Color.well : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .rowSeparator()
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hovering = h } }
    }
}

/// Acties voor één praktijk (contextmenu en ‘Meer’-menu).
struct ClientActions: View {
    @EnvironmentObject var store: Store
    let client: Client

    var body: some View {
        Button("Nieuwe factuur voor deze praktijk") { store.startNewInvoice(for: client) }
            .disabled(client.archived)
        Button("Importeer bestaande factuur…") { store.startImport(for: client) }
        Divider()
        if client.archived {
            Button("Zet terug uit archief") { store.setArchived(client, false) }
        } else {
            Button("Archiveer") { store.setArchived(client, true) }
        }
        Button("Verwijder…", role: .destructive) { store.requestDelete(client) }
    }
}
