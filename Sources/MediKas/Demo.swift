import SwiftUI
import Foundation
import AppKit

/// `MediKas --demo-pdf <pad> [regels]` maakt een voorbeeldfactuur met verzonnen gegevens (om de opmaak te testen).
enum Demo {
    @MainActor static func runIfRequested() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--selftest-storage"), i + 1 < args.count { selfTestStorage(URL(fileURLWithPath: args[i + 1])) }
        if let i = args.firstIndex(of: "--selftest-backup"), i + 1 < args.count { selfTestBackup(URL(fileURLWithPath: args[i + 1])) }
        if args.contains("--selftest-clients") { selfTestClients() }
        if let i = args.firstIndex(of: "--render-previews"), i + 1 < args.count { renderPreviews(to: URL(fileURLWithPath: args[i + 1])) }
        if let i = args.firstIndex(of: "--snapshot-window"), i + 1 < args.count { snapshotWindow(to: URL(fileURLWithPath: args[i + 1])) }
        if args.contains("--selftest-clicks") { selfTestClicks() }
        if args.contains("--selftest-keyboard") { selfTestKeyboard() }
        if args.contains("--selftest-filters") { selfTestFilters() }
        if args.contains("--dump-views") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard let w = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 }),
                      let root = w.contentView?.superview else { exit(1) }
                print("venster: \(w.frame.size) stijl fullSizeContentView=\(w.styleMask.contains(.fullSizeContentView)) toolbarStyle=\(w.toolbarStyle.rawValue) titlebarSeparator=\(w.titlebarSeparatorStyle.rawValue)")
                func walk(_ v: NSView, _ depth: Int) {
                    let name = String(describing: type(of: v))
                    let f = v.convert(v.bounds, to: nil)
                    if depth < 9 && (name.contains("Split") || name.contains("Titlebar") || name.contains("Toolbar") || name.contains("Divider") || name.contains("Separator") || name.contains("Effect")) {
                        var extra = ""
                        if let sv = v as? NSSplitView { extra = " divider=\(sv.dividerStyle.rawValue) thickness=\(sv.dividerThickness) vertical=\(sv.isVertical)" }
                        print(String(repeating: "  ", count: depth) + "\(name) x=\(Int(f.minX)) y=\(Int(f.minY)) w=\(Int(f.width)) h=\(Int(f.height))\(extra)")
                    }
                    for c in v.subviews { walk(c, depth + 1) }
                }
                walk(root, 0)
                exit(0)
            }
        }
        if let i = args.firstIndex(of: "--selftest-correction"), i + 1 < args.count { selfTestCorrection(pdfDir: args[i + 1]) }
        guard let i = args.firstIndex(of: "--demo-pdf"), i + 1 < args.count else { return }
        let count = (i + 2 < args.count ? Int(args[i + 2]) : nil) ?? 12

        var s = BusinessSettings()
        s.ownerName = "Dr. Voorbeeld"
        s.address = "Voorbeeldstraat 1"
        s.postalCode = "1234 AB"
        s.city = "Ergens"
        s.email = "info@voorbeeld.nl"
        s.kvk = "12345678"
        s.agb = "01012345"
        s.iban = "NL00 BANK 0123 4567 89"
        s.defaultHourlyRate = 95

        var c = Client()
        c.name = "Huisartsenpraktijk De Linde"
        c.contactPerson = "Praktijkmanager"
        c.address = "Lindelaan 10"
        c.postalCode = "5678 CD"
        c.city = "Dorp"

        var inv = Invoice()
        inv.number = "2026-007"
        inv.billTo = c
        inv.kmRate = Decimal(string: "0.23")!
        inv.isSent = true
        var day = nlCalendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        for n in 0..<count {
            while nlCalendar.isDateInWeekend(day) { day = day.adding(days: 1) }
            var l = WorkLine()
            l.date = day
            l.description = n % 5 == 4 ? "Avonddienst huisartsenpost" : "Waarneming spreekuur"
            l.hours = n % 3 == 0 ? Decimal(string: "8.5")! : 8
            l.hourlyRate = n % 5 == 4 ? 110 : 95
            l.commuteKm = 42
            l.visitKm = Decimal(n % 4 * 7)
            inv.lines.append(l)
            day = day.adding(days: 1)
        }
        inv.date = day
        inv.dueDate = day.adding(days: 30)

        if let data = InvoicePDF.data(for: inv, settings: s, logo: nil) {
            try? data.write(to: URL(fileURLWithPath: args[i + 1]))
            print("PDF geschreven: \(args[i + 1]) — totaal \(inv.total.euro)")
        }
        exit(0)
    }

    /// Verzonnen testgegevens (alleen met --seed-demo in een lege map).
    static func sampleData() -> AppData {
        var d = AppData()
        d.settings.ownerName = "Dr. Voorbeeld"
        d.settings.iban = "NL00 BANK 0123 4567 89"
        d.settings.defaultHourlyRate = 95
        let names = ["Huisartsenpraktijk De Linde", "Gezondheidscentrum Noord", "Praktijk Aan de Dijk"]
        d.clients = names.enumerated().map { i, n in
            var c = Client(); c.name = n; c.city = ["Dorp", "Stad", "Polder"][i]; c.commuteKm = Decimal([42, 18, 64][i]); return c
        }
        var number = 0
        for monthOffset in 0..<14 {
            let start = nlCalendar.date(byAdding: .month, value: monthOffset - 13, to: nlCalendar.date(from: DateComponents(year: Date().year, month: Date().month, day: 1))!)!
            let client = d.clients[monthOffset % 3]
            var inv = Invoice()
            inv.clientID = client.id; inv.billTo = client; inv.kmRate = Decimal(string: "0.23")!
            var day = start
            for n in 0..<(6 + monthOffset % 7) {
                while nlCalendar.isDateInWeekend(day) { day = day.adding(days: 1) }
                var l = WorkLine(); l.date = day; l.hours = n % 3 == 0 ? 9 : 8; l.hourlyRate = 95
                l.commuteKm = client.commuteKm; l.visitKm = Decimal(n % 4 * 6)
                inv.lines.append(l); day = day.adding(days: 2)
            }
            number = start.month == 1 ? 1 : number + 1
            inv.number = "\(start.year)-" + String(format: "%03d", number)
            inv.date = nlCalendar.date(byAdding: .month, value: 1, to: start)!.adding(days: 1)
            inv.dueDate = inv.date.adding(days: 30)
            inv.isSent = monthOffset < 13
            if monthOffset < 11 { inv.payments = [Payment(date: inv.date.adding(days: 12 + monthOffset % 9), amount: inv.total)] }
            if monthOffset == 11 { inv.payments = [Payment(date: inv.date.adding(days: 10), amount: 500, note: "Deelbetaling")] }
            d.invoices.append(inv)
        }
        return d
    }

    /// Test van verhuizen + archiveren (gebruik met MEDIKAS_DATA_DIR naar een lege testmap).
    @MainActor static func selfTestStorage(_ target: URL) {
        let fm = FileManager.default
        let store = Store(loadAsync: false)
        store.data = sampleData()
        store.saveNow()
        store.archiveMissing()
        let archived = store.data.invoices.filter { store.archivedURL($0) != nil }.count
        print("gearchiveerd: \(archived) van \(store.data.invoices.filter(\.isSent).count) verstuurd")
        if let inv = store.data.invoices.first(where: \.isSent) {
            store.delete(inv)
            let moved = (try? fm.contentsOfDirectory(atPath: store.archiveFolder.appendingPathComponent("Verwijderd").path)) ?? []
            print("na verwijderen in Verwijderd: \(moved)")
        }
        let count = store.data.invoices.count
        store.changeFolder(to: target)
        print("nieuwe map: \(store.folder.path), facturen: \(store.data.invoices.count) (verwacht \(count)), onbereikbaar: \(store.unavailableReason ?? "nee")")
        let pdfs = fm.enumerator(atPath: target.appendingPathComponent("Facturen").path)?.allObjects.compactMap { $0 as? String }.filter { $0.hasSuffix(".pdf") } ?? []
        print("PDF's in nieuwe map: \(pdfs.count), backups: \((try? fm.contentsOfDirectory(atPath: target.appendingPathComponent("Backups").path))?.count ?? 0)")
        UserDefaults.standard.removeObject(forKey: "dataFolderPath")
        exit(0)
    }

    /// Test van zip-back-up en opruimen (gebruik met MEDIKAS_DATA_DIR naar een lege testmap).
    @MainActor static func selfTestBackup(_ dest: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let store = Store(loadAsync: false)
        store.data = sampleData()
        store.saveNow()
        store.archiveMissing()
        let zip = dest.appendingPathComponent("MediKas-backup-2026-11-16-1200.zip")
        do { try Store.zip(store.folder, to: zip) } catch { print("zip mislukt: \(error)"); exit(1) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); p.arguments = ["-l", zip.path]
        try? p.run(); p.waitUntilExit()
        // Opruimen: 60 dagelijkse nep-back-ups over 3 maanden
        for d in 0..<60 {
            let date = nlCalendar.date(byAdding: .day, value: -d, to: Date())!
            fm.createFile(atPath: dest.appendingPathComponent("MediKas-backup-\(Fmt.file.string(from: date))-0900.zip").path, contents: Data())
        }
        Store.pruneZips(in: dest)
        let left = ((try? fm.contentsOfDirectory(atPath: dest.path)) ?? []).filter { $0.hasSuffix(".zip") }.sorted()
        print("na opruimen: \(left.count) zips; oudste: \(left.first ?? "-")")
        exit(0)
    }

    /// Test van praktijk verwijderen (gebruik met MEDIKAS_DATA_DIR naar een lege testmap).
    @MainActor static func selfTestClients() {
        setvbuf(stdout, nil, _IONBF, 0)
        let store = Store(loadAsync: false)
        store.data = sampleData()
        store.data.settings.defaultHourlyRate = 97
        let undo = UndoManager(); undo.groupsByEvent = false
        store.undoManager = undo

        func describe(_ r: Store.ClientRemoval) -> String {
            switch r { case .delete: "verwijderen"; case .deleteWithConcepts(let n): "verwijderen + \(n) concept(en)"; case .archiveOnly(let n): "alleen archiveren (\(n) verstuurd)" }
        }
        // 1. Verkeerd toegevoegd, geen facturen
        undo.beginUndoGrouping()
        let fresh = store.addClient()
        undo.endUndoGrouping()
        print("nieuw: uurtarief \(fresh.hourlyRate) (verwacht 97), km \(fresh.kmRate) → \(describe(store.removal(for: fresh)))")
        undo.beginUndoGrouping(); store.deleteClient(fresh); undo.endUndoGrouping()
        print("  na verwijderen nog aanwezig: \(store.client(fresh.id) != nil)")
        undo.undo()
        print("  na ⌘Z terug: \(store.client(fresh.id) != nil)")

        // 2. Alleen een concept
        var concept = store.makeInvoice(for: fresh); concept.isSent = false
        store.data.invoices.append(concept)
        print("met concept → \(describe(store.removal(for: fresh)))")
        undo.beginUndoGrouping(); store.deleteClient(fresh); undo.endUndoGrouping()
        print("  praktijk weg: \(store.client(fresh.id) == nil), concept weg: \(!store.data.invoices.contains { $0.id == concept.id })")

        // 3. Met verstuurde facturen
        let used = store.data.clients[0]
        print("met facturen → \(describe(store.removal(for: used)))")
        undo.beginUndoGrouping(); store.deleteClient(used); undo.endUndoGrouping()
        print("  nog aanwezig: \(store.client(used.id) != nil), gearchiveerd: \(store.client(used.id)?.archived == true), facturen intact: \(store.invoiceCount(for: used))")
        exit(0)
    }

    /// Rendert schermen buiten beeld naar PNG (om het ontwerp te controleren zonder schermopname).
    @MainActor static func renderPreviews(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Store(loadAsync: false)
        store.data = sampleData()
        store.data.settings.ownerName = "Dr. Voorbeeld"
        let theme = Theme.shared
        let original = theme.accentChoice
        func shot<V: View>(_ name: String, _ view: V, size: CGSize, dark: Bool) {
            let host = NSHostingView(rootView: view.environmentObject(store).environment(\.locale, nl))
            host.frame = CGRect(origin: .zero, size: size)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.appearance = host.appearance
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
        }
        let big = CGSize(width: 1180, height: 1000)
        shot("overzicht-licht", DashboardView(), size: big, dark: false)
        shot("overzicht-donker", DashboardView(), size: big, dark: true)
        shot("statistieken-licht", StatsView(), size: CGSize(width: 1180, height: 1500), dark: false)
        shot("editor-licht", InvoiceEditorView(draft: store.data.invoices[3], isNew: false), size: CGSize(width: 1080, height: 1500), dark: false)
        shot("instellingen-weergave", AppearanceSettingsTab(), size: CGSize(width: 660, height: 640), dark: false)
        store.data.invoices[2].memo = "Herinnering gestuurd op 3 december"
        shot("facturen-licht", InvoicesView(), size: CGSize(width: 1180, height: 900), dark: false)
        shot("betalingen-licht", PaymentsView(), size: CGSize(width: 1180, height: 1000), dark: false)
        shot("praktijken-overzicht", ClientsOverview(), size: CGSize(width: 1100, height: 600), dark: false)
        shot("praktijk-licht", ClientPage(clientID: store.data.clients[0].id), size: CGSize(width: 1100, height: 1500), dark: false)
        shot("editor-donker", InvoiceEditorView(draft: store.data.invoices[3], isNew: false), size: CGSize(width: 1080, height: 900), dark: true)
        shot("correctie-venster", CorrectionSheet(invoice: store.data.invoices[3]) { _ in }, size: CGSize(width: 540, height: 560), dark: false)
        if let open = store.data.invoices.first(where: { $0.status() == .open }) {
            store.correct(open, reissue: true)
            shot("editor-gecrediteerd", InvoiceEditorView(draft: store.invoice(open.id)!, isNew: false), size: CGSize(width: 1080, height: 700), dark: false)
        }
        theme.accentChoice = .blauw
        shot("overzicht-blauw", DashboardView(), size: big, dark: false)
        theme.accentChoice = original
        print("klaar: \(dir.path)")
        exit(0)
    }

    /// Legt het échte app-venster vast per onderdeel (in het eigen proces, geen schermopname nodig).
    @MainActor static func snapshotWindow(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let items = SidebarItem.allCases
        func capture(_ index: Int) {
            guard index < items.count else {
                // Extra: een praktijkpagina
                Store.current?.sidebar = .praktijken
                DispatchQueue.main.async { Store.current?.selectedClientID = Store.current?.activeClients.first?.id }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 }),
                       let view = window.contentView?.superview ?? window.contentView,
                       let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("venster-Praktijk.png"))
                    }
                    print("klaar"); exit(0)
                }
                return
            }
            Store.current?.sidebar = items[index]
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.frame.width > 600 })?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 600 }),
                   // Hele venster incl. titelbalk en werkbalk
                   let view = window.contentView?.superview ?? window.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: dir.appendingPathComponent("venster-\(items[index].rawValue).png"))
                }
                capture(index + 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { capture(0) }
    }

    /// Stuurt echte muisklikken naar het eigen venster (Facturen) en controleert de reactie.
    @MainActor static func selfTestClicks() {
        setvbuf(stdout, nil, _IONBF, 0)
        func click(_ window: NSWindow, x: CGFloat, yFromTop: CGFloat) {
            let h = window.contentView?.bounds.height ?? 0
            let p = NSPoint(x: x, y: h - yFromTop)
            func event(_ type: NSEvent.EventType) -> NSEvent? {
                NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            }
            // Muis-omhoog vooraf in de wachtrij: lijsten volgen de muis tot die loslaat.
            if let up = event(.leftMouseUp) { NSApp.postEvent(up, atStart: false) }
            if let down = event(.leftMouseDown) { window.sendEvent(down) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let store = Store.current,
                  let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 }) else { print("geen venster"); exit(1) }
            store.sidebar = .overzicht
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            print("TEST: venster actief: \(window.isKeyWindow), app actief: \(NSApp.isActive)")
            // Controle: klik in de zijbalk op "Betalingen", daarna op "Facturen"
            click(window, x: 60, yFromTop: 128)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            print("TEST: klik op zijbalk Betalingen → pagina: \(store.sidebar?.rawValue ?? "-")")
            click(window, x: 60, yFromTop: 100)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("TEST: klik op zijbalk Facturen → pagina: \(store.sidebar?.rawValue ?? "-")")
            if let dir = ProcessInfo.processInfo.environment["MEDIKAS_TEST_SHOT"], let view = window.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/na-zijbalkklik.png"))
            }
            if store.sidebar != .facturen { store.sidebar = .facturen }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                // Eerste rij: datumkolom (opent factuur)
                click(window, x: 520, yFromTop: 262)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    print("TEST: klik op rij → editor open: \(store.editingInvoice != nil) (\(store.editingInvoice?.number ?? "-"))")
                    store.editingInvoice = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        // Factuurnummer (opent PDF)
                        click(window, x: 268, yFromTop: 262)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            print("TEST: klaar")
                            exit(0)
                        }
                    }
                }
            }
            }
            }
            }
        }
    }

    /// Test van corrigeren: creditfactuur + nieuwe factuur, koppelingen, statussen, cijfers, verwijderen, versies.
    @MainActor static func selfTestCorrection(pdfDir: String) {
        setvbuf(stdout, nil, _IONBF, 0)
        let store = Store(loadAsync: false)
        store.data = sampleData()
        store.saveNow()
        store.archiveMissing()
        guard let original = store.data.invoices.first(where: { $0.status() == .open }) else { print("geen open factuur"); exit(1) }
        let year = original.date.year
        let before = Analytics.periods(store.sentInvoices, grouping: .jaar, basis: .factuurdatum, year: nil)
            .first { $0.key.year == year }?.invoiced ?? 0

        guard let replacement = store.correct(original, reissue: true) else { print("correct mislukt"); exit(1) }
        let o = store.invoice(original.id)!
        let credit = store.invoice(o.creditedByID)!
        print("origineel \(o.number): status=\(o.status().rawValue) openstaand=\(o.outstanding.euro)")
        print("credit \(credit.number): kind=\(credit.kind.rawValue) totaal=\(credit.total.euro) (verwacht -\(original.total.euro)) crediteert=\(store.invoice(credit.creditsInvoiceID)?.number ?? "-")")
        print("nieuw \(replacement.number): vervangt=\(store.invoice(replacement.replacesInvoiceID)?.number ?? "-") totaal=\(replacement.total.euro)")
        print("koppeling origineel: \(store.linkSummary(o) ?? "-")")

        // Versturen → cijfers: origineel + credit vallen weg, nieuw telt
        store.markSent(credit.id); store.markSent(replacement.id)
        let after = Analytics.periods(store.sentInvoices, grouping: .jaar, basis: .factuurdatum, year: nil)
        let total = after.sum(\.invoiced)
        let beforeAll = before
        print("omzet jaar \(year) vóór: \(beforeAll.euro); na (alle jaren, credit+nieuw in \(Date().year)): totaal \(total.euro)")
        print("credit status na versturen: \(store.invoice(credit.id)!.status().rawValue), PDF: \(store.archivedURL(store.invoice(credit.id)!)?.lastPathComponent ?? "-")")

        // PDF's om te bekijken
        if let d = InvoicePDF.data(for: store.invoice(credit.id)!, store: store) { try? d.write(to: URL(fileURLWithPath: pdfDir + "/credit.pdf")) }
        if let d = InvoicePDF.data(for: store.invoice(replacement.id)!, store: store) { try? d.write(to: URL(fileURLWithPath: pdfDir + "/vervangend.pdf")) }

        // Toch bewerken van een verstuurde factuur → eerdere versie bewaard
        var edited = store.invoice(replacement.id)!
        edited.lines[0].hours += 1
        store.save(edited)
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: store.archiveFolder.appendingPathComponent("Eerdere versies").path)) ?? []
        print("eerdere versies: \(versions.count), aangepast na verzending: \(store.invoice(replacement.id)!.editedAfterSending.count)x")
        // Alleen een betaling → geen nieuwe versie
        store.addPayment(Payment(amount: 10), to: replacement.id)
        var withPayment = store.invoice(replacement.id)!; withPayment.memo = "test"
        store.save(withPayment)
        let versions2 = (try? FileManager.default.contentsOfDirectory(atPath: store.archiveFolder.appendingPathComponent("Eerdere versies").path)) ?? []
        print("na betaling+opmerking nog steeds \(versions2.count) versie(s)")

        // Creditfactuur verwijderen → koppeling weg
        store.delete(store.invoice(credit.id)!)
        print("na verwijderen credit: origineel gecrediteerd=\(store.invoice(original.id)!.isCredited) status=\(store.invoice(original.id)!.status().rawValue)")
        exit(0)
    }

    /// Toetsenbordtest in de factuur-editor: ⌘D, focus op de nieuwe regel, Tab en Return.
    @MainActor static func selfTestKeyboard() {
        setvbuf(stdout, nil, _IONBF, 0)
        func key(_ chars: String, code: UInt16, flags: NSEvent.ModifierFlags = []) {
            guard let w = NSApp.keyWindow else { print("TEST: geen actief venster"); return }
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: w.windowNumber, context: nil, characters: chars,
                                            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
                    if type == .keyDown, flags.contains(.command) { _ = NSApp.mainMenu?.performKeyEquivalent(with: e); if !(w.performKeyEquivalent(with: e)) { w.sendEvent(e) } }
                    else { w.sendEvent(e) }
                }
            }
        }
        func focusDescription() -> String {
            guard let r = NSApp.keyWindow?.firstResponder else { return "geen" }
            if let tv = r as? NSTextView, tv.isFieldEditor { return "tekstveld" }
            return String(describing: type(of: r))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let store = Store.current else { exit(1) }
            store.startNewInvoice(for: store.activeClients.first)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let editorLines = { (store.editingInvoice != nil) }
                print("TEST: editor open: \(editorLines()), venster: \(NSApp.keyWindow?.title ?? "-")")
                // ⌘D = werkdag toevoegen
                key("d", code: 2, flags: .command)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("TEST: na ⌘D focus in: \(focusDescription())")
                    // Tab naar tarief, woon-werk, visites; dan Return
                    key("\t", code: 48); key("\t", code: 48); key("\t", code: 48)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        key("\r", code: 36)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            print("TEST: na Tab×3 + Return focus in: \(focusDescription())")
                            if let w = NSApp.keyWindow, let view = w.contentView,
                               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds),
                               let dir = ProcessInfo.processInfo.environment["MEDIKAS_TEST_SHOT"] {
                                view.cacheDisplay(in: view.bounds, to: rep)
                                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/toetsenbord.png"))
                            }
                            print("TEST: klaar")
                            exit(0)
                        }
                    }
                }
            }
        }
    }

    /// Test van de factuurfilters.
    @MainActor static func selfTestFilters() {
        let data = sampleData()
        let inv = data.invoices
        func count(_ f: InvoiceFilter) -> Int { inv.filter(f.matches).count }
        let y = Date().year
        var f = InvoiceFilter(year: nil)
        print("alle: \(count(f)) (totaal \(inv.count))")
        f.year = y; print("jaar \(y): \(count(f)) (verwacht \(inv.filter { $0.date.year == y }.count))")
        f.month = 3; print("maart \(y): \(count(f)) (verwacht \(inv.filter { $0.date.year == y && $0.date.month == 3 }.count))")
        f.month = nil; f.clientID = data.clients[0].id
        print("jaar + opdrachtgever: \(count(f)) (verwacht \(inv.filter { $0.date.year == y && $0.clientID == data.clients[0].id }.count))")
        f = InvoiceFilter(year: y, month: 1)
        f.from = nlCalendar.date(from: DateComponents(year: y, month: 4, day: 1)); f.to = nlCalendar.date(from: DateComponents(year: y, month: 6, day: 30))
        print("bereik K2 (gaat vóór maand jan): \(count(f)) (verwacht \(inv.filter { $0.date >= f.from! && $0.date <= f.to! }.count))")
        f = InvoiceFilter(year: nil, status: .betaald)
        print("status betaald: \(count(f)) (verwacht \(inv.filter { $0.status() == .paid }.count))")
        f = InvoiceFilter(year: nil, search: inv[2].number)
        print("zoeken op \(inv[2].number): \(count(f)) (verwacht 1)")
        print("periodText: '\(InvoiceFilter(year: y, month: 3).periodText)', '\(InvoiceFilter(year: nil).periodText)'")
        exit(0)
    }
}
