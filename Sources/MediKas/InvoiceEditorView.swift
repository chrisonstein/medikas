import SwiftUI

struct InvoiceEditorView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Local var draft: Invoice
    let isNew: Bool

    @Local private var newPayment = Payment()
    @Local private var confirmDelete = false
    @Local private var confirmDiscard = false
    @Local private var original: Invoice?
    @Local private var unlocked = false
    @Local private var showUnlockAlert = false
    @Local private var showCorrection = false
    /// Net toegevoegde werkdag: krijgt meteen de focus (uren).
    @Local private var newLineID: UUID?

    init(draft: Invoice, isNew: Bool) {
        _draft = Local(wrappedValue: draft)
        self.isNew = isNew
    }

    private var client: Client? { store.client(draft.clientID) }

    private var showPayments: Bool { (!isNew || draft.isSent || !draft.payments.isEmpty) && !draft.isCredit }

    /// Een verstuurde factuur is vergrendeld tot je bewust ‘Toch bewerken’ kiest.
    private var wasSent: Bool { store.invoice(draft.id)?.isSent == true }
    private var locked: Bool { wasSent && !unlocked }
    private var hasLinks: Bool {
        draft.creditsInvoiceID != nil || draft.replacesInvoiceID != nil || draft.creditedByID != nil || draft.replacedByID != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleBar
                    lockBanner
                    if hasLinks { linksCard }
                    // Rij 1: gegevens + totaal
                    HStack(alignment: .top, spacing: 16) {
                        detailsCard.disabled(locked).frame(maxWidth: .infinity)
                        summaryCard.frame(width: 320)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    // Rij 2: werkdagen over de volle breedte (ruimte voor alle kolommen)
                    linesCard.disabled(locked)
                    // Rij 3: opmerkingen + betalingen
                    HStack(alignment: .top, spacing: 16) {
                        notesCard.frame(maxWidth: .infinity)
                        if showPayments { paymentsCard.frame(width: 320) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
            footer
        }
        .background(CanvasBackground())
        .frame(minWidth: 1000, idealWidth: 1080, minHeight: 680, idealHeight: 800)
        .onAppear { if original == nil { original = draft } }
        .confirmationDialog("Factuur \(draft.number) verwijderen?", isPresented: $confirmDelete) {
            Button("Verwijderen", role: .destructive) { store.delete(draft); dismiss() }
        } message: {
            Text(draft.isSent ? "De gearchiveerde PDF blijft bewaard in Facturen/Verwijderd." : "Je kunt dit ongedaan maken met ⌘Z.")
        }
        .alert("Een verstuurde factuur bewerken?", isPresented: $showUnlockAlert) {
            Button("Corrigeer met creditfactuur…") { showCorrection = true }
            Button("Toch bewerken", role: .destructive) {
                withAnimation(.spring(response: 0.3, dampingFraction: 1)) { unlocked = true }
            }
            Button("Annuleer", role: .cancel) {}
        } message: {
            Text("""
            Factuur \(draft.number) is al naar \(draft.billTo.displayName) gestuurd. De praktijk heeft hem in haar administratie verwerkt, en jij moet hem 7 jaar ongewijzigd bewaren (fiscale bewaarplicht). Als je hem nu aanpast, kloppen jouw administratie en die van de praktijk niet meer met elkaar.

            De gebruikelijke manier: maak een creditfactuur die de oude factuur ongedaan maakt, en stuur daarna een nieuwe, correcte factuur. Alles blijft dan herleidbaar en aan elkaar gekoppeld.

            Bewerk je toch, dan wordt de oude PDF bewaard als eerdere versie.
            """)
        }
        .sheet(isPresented: $showCorrection) {
            CorrectionSheet(invoice: draft) { reissue in
                showCorrection = false
                guard let open = store.correct(draft, reissue: reissue) else { return }
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.edit(store.invoice(open.id) ?? open) }
            }
        }
        .confirmationDialog("Wijzigingen weggooien?", isPresented: $confirmDiscard) {
            Button("Weggooien", role: .destructive) { dismiss() }
            Button("Bewaren") { save(close: true) }
        }
    }

    // MARK: Vergrendeling en koppelingen

    @ViewBuilder private var lockBanner: some View {
        if draft.isCredit && wasSent {
            Callout(icon: "lock.fill", tint: .purple, title: "Verstuurde creditfactuur",
                    text: "Deze creditfactuur is verstuurd en kan niet meer worden aangepast.")
        } else if locked {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "lock.fill").font(.title2).foregroundStyle(accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.isCredited ? "Gecrediteerde factuur" : "Verstuurd en vergrendeld").font(.headline)
                    Text(draft.isCredited
                         ? "Deze factuur is gecrediteerd en telt niet meer mee. Je kunt hem alleen nog bekijken."
                         : "Deze factuur is naar de praktijk gestuurd. Betalingen en je interne opmerking kun je gewoon bijwerken; de factuur zelf niet.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !draft.isCredited {
                    Button("Toch bewerken…") { showUnlockAlert = true }
                    Button("Corrigeren…") { showCorrection = true }.buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(accent.opacity(0.2), lineWidth: 0.5))
        } else if wasSent && unlocked {
            Callout(icon: "exclamationmark.triangle.fill", tint: .orange, title: "Je bewerkt een verstuurde factuur",
                    text: "Bij bewaren wordt de oude PDF bewaard in Facturen/Eerdere versies en wordt vastgelegd dat de factuur na verzending is aangepast.")
        }
        if !draft.editedAfterSending.isEmpty {
            Label("Na verzending aangepast op \(draft.editedAfterSending.map { $0.long }.joined(separator: ", "))", systemImage: "clock.arrow.circlepath")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(icon: "link", title: "Gekoppelde facturen", subtitle: "Correctie van een verstuurde factuur")
            if let id = draft.creditsInvoiceID { linkRow("Crediteert", id) }
            if let id = draft.replacesInvoiceID { linkRow("Vervangt", id) }
            if let id = draft.creditedByID { linkRow("Gecrediteerd met", id) }
            if let id = draft.replacedByID { linkRow("Vervangen door", id) }
        }
        .card()
    }

    private func linkRow(_ label: String, _ id: UUID) -> some View {
        let other = store.invoice(id)
        return HStack(spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            if let other {
                Button {
                    if draft != original { store.alert = "Bewaar of annuleer eerst je wijzigingen."; return }
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.edit(other) }
                } label: {
                    HStack(spacing: 8) {
                        Text("\(other.documentTitle) \(other.number)").fontWeight(.medium).foregroundStyle(accent)
                        Text(other.date.long).foregroundStyle(.secondary)
                        Spacer()
                        Text(other.total.euro).monospacedDigit()
                        StatusBadge(status: other.status())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(other.documentTitle.lowercased()) \(other.number)")
            } else {
                Text("verwijderd").foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color.well.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Kop

    private var titleBar: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isNew ? (draft.isCredit ? "Nieuwe creditfactuur" : "Nieuwe factuur") : "\(draft.documentTitle) \(draft.number)")
                    .font(.system(size: 28, weight: .semibold)).tracking(-0.6)
                HStack(spacing: 8) {
                    StatusBadge(status: draft.status())
                    if draft.clientID != nil {
                        Text(draft.billTo.displayName).foregroundStyle(.secondary)
                    }
                    if !draft.periodText.isEmpty {
                        Text("· \(draft.periodText)").foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
            Spacer()
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeader(icon: "cross.case", title: "Praktijk en data")
            Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    LabeledField(label: "Opdrachtgever") {
                        MenuField(placeholder: "Kies een praktijk…",
                                  selection: Binding(get: { draft.clientID }, set: selectClient),
                                  options: (store.activeClients + archivedSelected).map { (UUID?.some($0.id), $0.displayName) },
                                  icon: "cross.case")
                    }
                    .gridCellColumns(2)
                    LabeledField(label: "Factuurnummer",
                                 hint: store.isDuplicateNumber(draft.number, id: draft.id) ? "Dit nummer bestaat al" : nil) {
                        InputField("2026-001", text: $draft.number, icon: "number",
                                   invalid: store.isDuplicateNumber(draft.number, id: draft.id) || draft.number.isEmpty)
                    }
                }
                GridRow {
                    LabeledField(label: "Factuurdatum") {
                        DateField(date: Binding(get: { draft.date }, set: { newDate in
                            let oldDefaultDue = draft.date.adding(days: store.data.settings.paymentTermDays)
                            if draft.dueDate.startOfDay == oldDefaultDue.startOfDay {
                                draft.dueDate = newDate.adding(days: store.data.settings.paymentTermDays)
                            }
                            if isNew && newDate.year != draft.date.year {
                                draft.number = store.nextInvoiceNumber(for: newDate, excluding: draft.id)
                            }
                            draft.date = newDate.startOfDay
                        }))
                    }
                    LabeledField(label: "Vervaldatum",
                                 hint: "\(nlCalendar.dateComponents([.day], from: draft.date, to: draft.dueDate).day ?? 0) dagen na factuurdatum") {
                        DateField(date: $draft.dueDate)
                    }
                    LabeledField(label: "Status") {
                        ToggleRow(title: "Verstuurd", isOn: Binding(get: { draft.isSent }, set: {
                            draft.isSent = $0
                            draft.sentDate = $0 ? (draft.sentDate ?? Date().startOfDay) : nil
                        }))
                        .help("Concepten tellen niet mee in de cijfers. Bij PDF bewaren of mailen wordt een factuur automatisch op 'verstuurd' gezet.")
                    }
                }
            }
        }
        .card()
    }

    private var archivedSelected: [Client] {
        guard let c = client, c.archived else { return [] }
        return [c]
    }

    private func selectClient(_ id: UUID?) {
        draft.clientID = id
        guard let c = store.client(id) else { return }
        draft.billTo = c
        draft.kmRate = store.kmRate(for: c)
        // Werk regels bij die nog leeg zijn
        for i in draft.lines.indices where draft.lines[i].hours == 0 {
            draft.lines[i].hourlyRate = store.hourlyRate(for: c)
            draft.lines[i].commuteKm = c.commuteKm
        }
    }

    // MARK: Werkdagen

    enum W {
        static let date: CGFloat = 150, hours: CGFloat = 76, rate: CGFloat = 92, km: CGFloat = 92, total: CGFloat = 96
    }

    private var linesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "calendar.badge.clock", title: "Werkdagen",
                       subtitle: draft.lines.isEmpty ? nil : "\(draft.lines.count) dag\(draft.lines.count == 1 ? "" : "en") · \(draft.hours.fmt()) uur · \(draft.totalKm.fmt(0)) km") {
                if draft.lines.count > 1 {
                    Button("Sorteer op datum") { withAnimation { draft.lines.sort { $0.date < $1.date } } }
                        .buttonStyle(.link)
                }
            }

            if draft.lines.isEmpty {
                EmptyState(icon: "calendar.badge.plus", title: "Nog geen werkdagen",
                           message: "Voeg de dagen toe waarop je hebt gewerkt, met uren en kilometers.", compact: true)
            } else {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Datum").frame(width: W.date, alignment: .leading)
                        Text("Omschrijving").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Uren").frame(width: W.hours, alignment: .trailing)
                        Text("Uurtarief").frame(width: W.rate, alignment: .trailing)
                        Text("Woon-werk").frame(width: W.km, alignment: .trailing)
                        Text("Visites").frame(width: W.km, alignment: .trailing)
                        Text("Bedrag").frame(width: W.total, alignment: .trailing)
                        Color.clear.frame(width: 18)
                    }
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8)

                    // Binding op id (niet op positie): een regel verwijderen terwijl een veld nog actief is mag niet crashen
                    ForEach(draft.lines) { line in
                        WorkLineRow(line: lineBinding(line), kmRate: draft.kmRate,
                                    autofocus: line.id == newLineID,
                                    isLast: line.id == draft.lines.last?.id,
                                    onReturnInLastField: { addLine() }) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
                                draft.lines.removeAll { $0.id == line.id }
                            }
                        }
                    }
                }
            }

            // Nieuwe werkdag komt onder de regels; daarom staat de knop ook hier.
            HStack(spacing: 12) {
                Button { addLine() } label: {
                    Label("Werkdag toevoegen", systemImage: "plus.circle.fill").labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("d", modifiers: .command)
                .help("Volgende werkdag toevoegen met dezelfde tarieven en woon-werk km (⌘D)")
                Text("⌘D, of Return in het laatste veld").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Totalen rekenen direct mee").font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func lineBinding(_ line: WorkLine) -> Binding<WorkLine> {
        Binding(
            get: { draft.lines.first { $0.id == line.id } ?? line },
            set: { new in if let i = draft.lines.firstIndex(where: { $0.id == line.id }) { draft.lines[i] = new } })
    }

    private func addLine() {
        var line = WorkLine()
        if let last = draft.lines.max(by: { $0.date < $1.date }) {
            line.description = last.description
            line.hourlyRate = last.hourlyRate
            line.commuteKm = last.commuteKm
            line.hours = last.hours
            var next = last.date.adding(days: 1)
            while nlCalendar.isDateInWeekend(next) { next = next.adding(days: 1) }
            line.date = next
        } else {
            line.description = store.data.settings.defaultLineDescription
            line.hourlyRate = store.hourlyRate(for: client)
            line.commuteKm = client?.commuteKm ?? 0
        }
        newLineID = line.id
        withAnimation(.spring(response: 0.3, dampingFraction: 1)) { draft.lines.append(line) }   // altijd onderaan
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "text.alignleft", title: "Opmerkingen")
            LabeledField(label: "Op de factuur", hint: "Komt boven de betaalinstructie") {
                InputField("Bijvoorbeeld: waarneming tijdens vakantie van de vaste huisarts", text: $draft.notes, axis: .vertical)
            }
            .disabled(locked)
            LabeledField(label: "Interne opmerking", hint: "Alleen zichtbaar in het overzicht, niet op de factuur") {
                InputField("Bijvoorbeeld: herinnering gestuurd", text: $draft.memo, icon: "lock")
            }
        }
        .card()
    }

    // MARK: Totaal

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "eurosign", title: "Totaal")
            Text(draft.total.euro)
                .font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-0.8)
                .monospacedDigit()
                .foregroundStyle(accent)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.35, dampingFraction: 1), value: draft.total)
            VStack(spacing: 10) {
                summaryRow("Werkzaamheden", "\(draft.hours.fmt()) uur", draft.hoursAmount.euro)
                summaryRow("Reiskosten", "\(draft.commuteKm.fmt(0)) woon-werk + \(draft.visitKm.fmt(0)) visites km", draft.kmAmount.euro)
            }
            Divider()
            LabeledField(label: "Km-vergoeding") {
                NumberField(value: $draft.kmRate, prefix: "€", suffix: "per km", digits: 3)
            }
            .disabled(locked)
            Text("Te betalen vóór \(draft.dueDate.long)").font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private func summaryRow(_ title: String, _ detail: String, _ amount: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amount).monospacedDigit()
        }
    }

    // MARK: Betalingen

    private var paymentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(icon: "arrow.down.circle", title: "Betalingen")
            CapsuleBar(fraction: draft.total > 0 ? (draft.paid / draft.total).double : 0, color: .green, height: 6)
            HStack {
                Text("Betaald \(draft.paid.euro)")
                Spacer()
                Text("Open \(draft.outstanding.euro)").foregroundStyle(draft.outstanding > 0 ? accent : .secondary)
            }
            .font(.caption).monospacedDigit()

            ForEach(draft.payments.sorted { $0.date < $1.date }) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.amount.euro).monospacedDigit().fontWeight(.medium)
                        Text([p.date.long, p.note].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { draft.payments.removeAll { $0.id == p.id } } label: {
                        Image(systemName: "trash").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless).help("Betaling verwijderen")
                }
                .padding(8)
                .background(Color.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if draft.outstanding > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nieuwe betaling").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    DateField(date: $newPayment.date)
                    NumberField(value: $newPayment.amount, prefix: "€", placeholder: draft.outstanding.fmt(2))
                    InputField("Notitie (optioneel)", text: $newPayment.note)
                    HStack {
                        Button("Volledig betaald") {
                            draft.payments.append(Payment(amount: draft.outstanding, note: "Volledig betaald"))
                            if !draft.isSent { draft.isSent = true; draft.sentDate = draft.date }
                        }
                        Spacer()
                        Button("Toevoegen") {
                            guard newPayment.amount > 0 else { return }
                            var p = newPayment; p.date = p.date.startOfDay
                            withAnimation(.spring(response: 0.3, dampingFraction: 1)) { draft.payments.append(p) }
                            if !draft.isSent { draft.isSent = true; draft.sentDate = draft.date }
                            newPayment = Payment()
                        }
                        .disabled(newPayment.amount <= 0)
                    }
                    .controlSize(.small)
                }
            }
        }
        .card()
    }

    // MARK: Onderbalk

    private var footer: some View {
        HStack {
            if !isNew {
                Button("Verwijderen…", role: .destructive) { confirmDelete = true }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.orange)
            }
            Spacer()
            Group {
                Button { withSaved { InvoicePDF.preview($0, store: store) } } label: { Label("Voorbeeld", systemImage: "eye") }
                    .help("Bewaar en open de PDF in Voorvertoning")
                Button { withSaved { InvoicePDF.export($0, store: store) } } label: { Label("Bewaar PDF…", systemImage: "arrow.down.doc") }
                Button { withSaved { InvoicePDF.mail($0, store: store) } } label: { Label("Mail…", systemImage: "envelope") }
            }
            .disabled(problem != nil)
            Divider().frame(height: 20)
            Button("Annuleren") {
                if draft != original { confirmDiscard = true } else { dismiss() }
            }
            .keyboardShortcut(.cancelAction)
            Button("Bewaar") { save(close: true) }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(problem != nil)
        }
        .padding(14)
        .background(.bar)
    }

    private var problem: String? {
        if draft.clientID == nil { return "Kies eerst een praktijk." }
        if draft.number.trimmingCharacters(in: .whitespaces).isEmpty { return "Vul een factuurnummer in." }
        if store.isDuplicateNumber(draft.number, id: draft.id) { return "Factuurnummer \(draft.number) bestaat al." }
        return nil
    }

    /// Legt lopende invoer vast, bewaart, en geeft de opgeslagen factuur terug.
    private func withSaved(_ action: @escaping (Invoice) -> Void) {
        commitEditing()
        DispatchQueue.main.async {
            if let problem { store.alert = problem; return }
            store.save(draft)
            original = draft
            if let saved = store.data.invoices.first(where: { $0.id == draft.id }) {
                action(saved)
                // PDF/mail kan de status op 'verstuurd' zetten
                if let updated = store.data.invoices.first(where: { $0.id == draft.id }) {
                    draft.isSent = updated.isSent; draft.sentDate = updated.sentDate
                    draft.billTo = updated.billTo
                    original = draft
                }
            }
        }
    }

    private func save(close: Bool) {
        withSaved { _ in if close { dismiss() } }
    }
}

/// Eén werkdag in de editor: rustige rij met velden die direct meerekenen.
/// Volledig met het toetsenbord in te vullen (Tab tussen velden, Return in het laatste veld = nieuwe werkdag).
struct WorkLineRow: View {
    @Binding var line: WorkLine
    let kmRate: Decimal
    var autofocus = false
    var isLast = false
    var onReturnInLastField: () -> Void = {}
    let onDelete: () -> Void
    @Local private var hovering = false

    typealias W = InvoiceEditorView.W

    init(line: Binding<WorkLine>, kmRate: Decimal, autofocus: Bool = false, isLast: Bool = false,
         onReturnInLastField: @escaping () -> Void = {}, onDelete: @escaping () -> Void) {
        _line = line; self.kmRate = kmRate; self.autofocus = autofocus; self.isLast = isLast
        self.onReturnInLastField = onReturnInLastField; self.onDelete = onDelete
    }

    var body: some View {
        let day = Fmt.weekday.string(from: line.date)
        HStack(spacing: 8) {
            DateField(date: $line.date, style: .short).frame(width: W.date)
                .accessibilityLabel("Datum werkdag")
            InputField("Omschrijving", text: $line.description)
                .accessibilityLabel("Omschrijving, \(day)")
            NumberField(value: $line.hours, suffix: "u", autofocus: autofocus)
                .frame(width: W.hours)
                .accessibilityLabel("Uren, \(day)")
            NumberField(value: $line.hourlyRate, prefix: "€").frame(width: W.rate)
                .accessibilityLabel("Uurtarief, \(day)")
            NumberField(value: $line.commuteKm, suffix: "km", digits: 1).frame(width: W.km)
                .accessibilityLabel("Woon-werk kilometers, \(day)")
            NumberField(value: $line.visitKm, suffix: "km", digits: 1,
                        onSubmit: { if isLast { onReturnInLastField() } })
                .frame(width: W.km)
                .accessibilityLabel("Visite kilometers, \(day)")
            Text((line.hoursAmount + (line.totalKm * kmRate).rounded()).euro)
                .monospacedDigit().fontWeight(.medium)
                .contentTransition(.numericText())
                .frame(width: W.total, alignment: .trailing)
                .help("Werk \(line.hoursAmount.euro) + reiskosten \((line.totalKm * kmRate).rounded().euro)")
                .accessibilityLabel("Bedrag \(day)")
                .accessibilityValue((line.hoursAmount + (line.totalKm * kmRate).rounded()).euro)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0.35)
            .help("Werkdag verwijderen")
            .accessibilityLabel("Werkdag \(day) verwijderen")
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(hovering ? Color.well.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Corrigeren

/// Kiezen hoe je een verstuurde factuur corrigeert, met uitleg over de gebruikelijke werkwijze.
struct CorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let invoice: Invoice
    let onChoose: (_ reissue: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.uturn.backward.circle.fill").font(.system(size: 30)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Factuur \(invoice.number) corrigeren").font(.title2.weight(.semibold))
                    Text(invoice.billTo.displayName + " · " + invoice.total.euro).foregroundStyle(.secondary)
                }
            }
            Text("Een verstuurde factuur pas je niet aan. Je maakt hem ongedaan met een creditfactuur: dezelfde regels met min-bedragen, met een eigen nummer en een verwijzing naar de oude factuur. Zo kloppen jouw administratie en die van de praktijk, en blijft alles 7 jaar herleidbaar.")
                .fixedSize(horizontal: false, vertical: true)

            option(icon: "doc.on.doc", title: "Crediteren en opnieuw factureren", badge: "Meest gebruikt",
                   text: "Er komen twee concepten: creditfactuur (−\(invoice.total.euro)) en een nieuwe factuur met dezelfde werkdagen. Die nieuwe factuur pas je aan en verstuur je samen met de creditfactuur.") {
                onChoose(true)
            }
            option(icon: "xmark.circle", title: "Alleen crediteren", badge: nil,
                   text: "Voor een factuur die er niet had mogen zijn, bijvoorbeeld dubbel verstuurd of naar de verkeerde praktijk. Er komt alleen een creditfactuur.") {
                onChoose(false)
            }

            Text("De oude factuur blijft bewaard en krijgt de status ‘Gecrediteerd’. De drie facturen zijn aan elkaar gekoppeld en staan bij de praktijk. Is er al betaald? Verreken dat bedrag met de nieuwe factuur.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Annuleer", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    private func option(icon: String, title: String, badge: String?, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge).font(.caption.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 2)
                                .background(accent.opacity(0.12), in: Capsule()).foregroundStyle(accent)
                        }
                    }
                    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
