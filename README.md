# MediKas 🩺

Boekhouding voor zzp-artsen, zoals een waarnemend huisarts: facturen voor waarneming, betalingen bijhouden en overzichten per maand, kwartaal en jaar. Een native macOS-app (SwiftUI). Alle gegevens blijven op de Mac staan.

## Wat kan het?

- **Facturen** per praktijk, met per werkdag: datum, omschrijving, uren, uurtarief, woon-werk km en visite km. De km-vergoeding staat per factuur ingesteld. Op de PDF staan de werkzaamheden en de **reiskosten in aparte tabellen**, elk met een subtotaal.
- **Factuuroverzicht**: factuurnummer (klik om de PDF te openen), datum, opdrachtgever, bedrag, vervaldatum, betaald op, status en een interne opmerking. Je kunt sorteren op elke kolom en zoeken. Filteren kan op status (Alle, Concept, Open, Te laat, Betaald), **jaar**, **maand**, **opdrachtgever** en een **eigen periode** ("van–tot", met snelkeuzes per kwartaal). Dezelfde filters staan bij de facturen op een praktijkpagina, behalve opdrachtgever, want die is daar al gekozen. "Wis filters" zet alles terug. De opmerking is alleen voor jezelf en komt niet op de factuur.
- **Invoervelden**:
  - het label staat boven het veld
  - eenheden staan in het veld zelf (€, uur, km)
  - totalen rekenen direct mee terwijl je typt
  - datums kies je in een kalender
  - ⌘N maakt een nieuwe factuur, ⌘D voegt de volgende werkdag toe (met dezelfde tarieven en woon-werk km), ⌘S bewaart.
  - Het factuurnummer loopt automatisch op per jaar (`2026-001`, eventueel met een voorvoegsel).
- **PDF**: bekijken in Voorvertoning, bewaren of direct mailen via Mail. Een factuur die je bewaart als PDF of mailt, wordt automatisch op *verstuurd* gezet.
- **Verstuurde facturen zijn vergrendeld.**
  - Betalingen en de interne opmerking kun je gewoon bijwerken; de factuur zelf niet.
  - **Corrigeren…** maakt een creditfactuur (dezelfde regels met min-bedragen, met verwijzing naar de oude factuur) en, als je dat wilt, een nieuwe factuur om aan te passen. Alle drie zijn aan elkaar gekoppeld en staan bij de praktijk.
  - De oude factuur krijgt de status *Gecrediteerd* en telt niet meer mee. Bij het mailen van de nieuwe factuur gaat de creditfactuur automatisch mee.
  - **Toch bewerken…** kan alleen na een melding met uitleg. De oude PDF wordt dan bewaard in `Facturen/Eerdere versies`, en de app legt vast dat de factuur na verzending is aangepast.
- **Huisstijl van de factuur** (Instellingen → Huisstijl, met live voorbeeld):
  - sjabloon **Klassiek** of **Modern** (getinte tabelkop, betaalvak, lijnen met kleurverloop)
  - **logo** (PNG, PDF of SVG, scherp op papier) met instelbare hoogte
  - **kleuren** voor tekst, hoofdkleur, tweede kleur (verloop) en vlakken, via hexcode, kleurkiezer of overgenomen uit het logo
  - **lettertypen** voor koppen en tekst: die van macOS, of zelf toegevoegd (.ttf/.otf, bijv. Inter)
  - een **patroon** onderaan de pagina (herhaald beeldmerk, instelbare dekking en hoogte; nooit onder tekst)
  - logo, patroon en lettertypen staan in de map `Huisstijl/` in je gegevensmap, dus ze reizen mee naar een andere Mac
  - per factuur een optioneel **kenmerk**
- **Bestaande facturen importeren** (facturen die je buiten MediKas hebt gemaakt): via *Importeer…* op een praktijkpagina, het menu van een praktijk of Archief → *Importeer bestaande factuur…* (⇧⌘I).
  - Je kiest de originele PDF. Factuurnummer, datum, vervaldatum en totaal worden zo goed mogelijk uit de PDF gelezen; controleer ze altijd.
  - Vul de werkdagen in zoals op de factuur. Wijkt het totaal af van de PDF, dan zie je meteen het verschil.
  - De originele PDF gaat ongewijzigd naar het archief (`Facturen/<jaar>/`). MediKas maakt voor zo'n factuur nooit een eigen PDF; openen, bewaren en mailen gebruiken het origineel.
  - Een geïmporteerde factuur telt als verstuurd en loopt overal mee: statistieken, betalingen, openstaand, te laat, praktijkcijfers en de nummering (na `2025-017` stelt MediKas `2025-018` voor). In de lijsten staat een klein importicoon bij het nummer.
  - Je kunt de gegevens later gewoon corrigeren (de PDF verandert niet) of de factuur crediteren via *Corrigeren…*.
- **Betalingen** handmatig registreren (ook deelbetalingen). De status gaat dan van Open naar Deels betaald, Te laat of Betaald.
- **Praktijken**: een overzicht met per praktijk de plaats, het aantal facturen, wat dit jaar gefactureerd is, wat openstaat en de laatste factuur. Klik door naar een praktijkpagina met:
  - vier beknopte cijfers: gefactureerd, openstaand, uren en gemiddelde betaaltijd
  - de gegevens, tarieven en notities
  - alle facturen
  Terug naar het overzicht gaat met "‹ Praktijken" of ⌘[. Elke praktijk heeft eigen tarieven en vaste woon-werk km. Een nieuwe praktijk krijgt automatisch het standaard uurtarief en de standaard km-vergoeding uit de instellingen.
  - **Verwijderen** gaat via een rechtermuisklik, ⌫ of de knop onderaan. Zonder facturen: verwijderen na bevestiging (⌘Z maakt het ongedaan). Met alleen concepten: die worden meeverwijderd, en dat staat in de bevestiging. Met verstuurde facturen kan verwijderen niet (bewaarplicht); dan kun je de praktijk alleen archiveren.
- **Ongedaan maken (⌘Z)** voor verwijderen, betalingen, wijzigingen aan facturen en praktijken.
- **Statistieken** per maand, kwartaal of jaar: omzet, ontvangsten, uren, werkdagen, km, gemiddelde tarieven en een overzicht per praktijk. Te tellen op **werkdatum** of op **factuurdatum** (die laatste is handig voor de aangifte).
- **CSV-export** (Excel/Numbers) van facturen, betalingen en statistieken.
- **Opslaglocatie instelbaar**: lokaal, in iCloud Drive, in Google Drive of in een eigen map (Instellingen → Opslaglocatie). Bestaande gegevens worden meegekopieerd.
- **Factuurarchief** voor de bewaarplicht van 7 jaar: van elke verstuurde factuur wordt automatisch een PDF bewaard in `Facturen/<jaar>/`. PDF's van verwijderde facturen gaan naar `Facturen/Verwijderd/`.
- **Back-ups naar een tweede plek** (externe schijf, NAS of een andere cloudmap): elke dag automatisch een zip met álles, dus gegevens, logo en alle factuur-PDF's. Je kunt ook handmatig een back-up maken of er een terugzetten.
- **Waarschuwing op het overzicht** als de gegevens alleen op deze Mac staan, of als de laatste back-up te lang geleden is.

Concepten (facturen die nog niet verstuurd zijn) tellen niet mee in de cijfers.

## Bouwen en installeren

Je hebt alleen de Command Line Tools nodig (`xcode-select --install`), geen Xcode.

```bash
./build.sh install   # bouwt de app en zet hem in /Applications
./build.sh run       # bouwt de app en start hem vanuit ./build
```

De app is niet ondertekend door Apple. Als je hem naar een andere Mac kopieert, open je hem de eerste keer met rechtermuisklik → *Open*.

## Eerste keer

1. Open **Instellingen** (⌘, of via het MediKas-menu) en vul je naam, adres, KvK, IBAN en je standaard uur- en km-tarief in. De AGB-code is optioneel en komt alleen op de factuur als je hem invult. Kies eventueel een logo.
2. Voeg onder **Praktijken** de praktijken toe met adres, factuur-e-mail en woon-werk km (retour).
3. Maak een factuur met ⌘N.

## Installeren voor gebruikers

Download de nieuwste `MediKas-<versie>.dmg` van de [releases](https://github.com/chrisonstein/medikas/releases/latest), sleep de app naar Programma's en open hem één keer via Systeeminstellingen → Privacy en beveiliging → "Open toch" (de app is niet genotariseerd). Daarna werkt MediKas zichzelf automatisch bij.

## Releases (updates via Sparkle + GitHub Releases)

MediKas leest elke dag `SUFeedURL` uit `Support/Info.plist`: de `appcast.xml` van de nieuwste GitHub-release. Is er een nieuwere versie, dan biedt de app die met één klik aan. Zelf zoeken kan via MediKas → *Zoek naar updates…* of Instellingen → Updates.

Een nieuwe versie publiceren:

1. Verhoog `CFBundleShortVersionString` én `CFBundleVersion` in `Support/Info.plist`. Sparkle vergelijkt `CFBundleVersion`, dus die moet omhoog.
2. Optioneel: release notes in `Support/ReleaseNotes/<versie>.md` (`- ` punten). Die staan in het updatevenster en op GitHub.
3. `./release.sh`. Dat draait `package.sh` (universele build, dmg, zip en een ondertekende `dist/appcast.xml`) en maakt de GitHub-release aan.

Twee sleutels staan alleen op deze Mac. **Maak van allebei een back-up:**
- het certificaat *MediKas Local Signing* (aangemaakt met `Support/setup-signing.sh`): elke versie heeft dan dezelfde handtekening.
- de Sparkle-updatesleutel: sleutelhangeronderdeel *https://sparkle-project.org*, account *MediKas*. Exporteren doe je met `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account MediKas -x medikas-sparkle-key.txt`. Zonder deze sleutel accepteren geïnstalleerde kopieën geen nieuwe updates meer.

Voor een installatie zonder waarschuwing heb je een Apple *Developer ID*-certificaat en notarisatie nodig.

## Gegevens en opslaglocatie

Alles staat in één map. Standaard is dat `~/Library/Application Support/MediKas/`; via Instellingen → Opslaglocatie kies je iCloud Drive, Google Drive of een eigen map.

```
data.json            alle gegevens
logo.png             logo
Huisstijl/           patroon en eigen lettertypen
Backups/             dagelijkse back-ups van data.json
Facturen/2026/       PDF van elke verstuurde factuur (optioneel per maand: Facturen/2026/03 maart/)
Facturen/Verwijderd/ PDF's van verwijderde facturen
```

- Bij het wisselen van map worden de gegevens meegekopieerd. De oude map blijft staan.
- Staat er in de gekozen map al een `data.json`, dan kies je zelf: die gegevens gebruiken, of ze vervangen (er wordt eerst een kopie gemaakt).
- Is de map niet bereikbaar, bijvoorbeeld omdat Google Drive niet draait, dan toont de app een melding en slaat hij niets op.
- Is de app op een andere Mac aangepast, dan worden de gegevens opnieuw ingelezen zodra je MediKas weer naar voren haalt. Gebruik de app wel op **één Mac tegelijk**.
- Google Drive: zet de map MediKas op *offline beschikbaar*.
- De keuze van de map wordt per Mac bewaard (`defaults read io.github.chrisonstein.medikas dataFolderPath`).

## Veilig bewaren: aanbevolen opzet

1. **Gegevensmap in iCloud Drive** (of Google Drive): zo staat alles in de cloud en kun je er vanaf elke Mac bij.
2. **Extra back-uplocatie op een externe schijf** (Instellingen → Back-ups): elke dag een volledige zip. Als er in de cloud iets misgaat of per ongeluk wordt gewist, heb je nog een eigen kopie.

Wil je liever alles lokaal houden, laat de gegevensmap dan op de Mac staan en stel een back-uplocatie in. Dat mag ook een cloudmap zijn, bijvoorbeeld Google Drive.

Back-ups op de extra locatie: `MediKas-backup-JJJJ-MM-DD-UUMM.zip`. De laatste 30 blijven bewaard, plus de laatste van elke maand voor altijd. Terugzetten gaat via Instellingen → Back-ups → *Back-up terugzetten…* (zip of json). Je kunt een zip ook gewoon openen in de Finder.

De zips zijn niet versleuteld. Gebruik daarom een versleutelde back-upschijf (Schijfhulpprogramma → *APFS (versleuteld)*) en zet FileVault aan.

## Ontwerp

De app volgt de macOS-conventies en Apple's ontwerpprincipes:
- **Geen titelbalk, één titel per pagina.** Rechts naast de titel staan de acties (jaar, Exporteer, Nieuwe factuur). Zoeken zit in context, direct boven de tabel waarin je zoekt. ⌘F springt naar het zoekveld en Esc wist het. Zonder titelbalk loopt de scheidingslijn naast de zijbalk vanzelf over de volle hoogte.
- **Strak en rustig**: effen achtergrond zonder kleurverloop. Primaire knoppen gebruiken de accentkleur van het systeem; werkbalkknoppen hebben een icoon én tekst.
- **Volledig met het toetsenbord**:
  - Met Tab ga je door de velden. In datums typ je dag, maand en jaar, en de kalenderknop is optioneel.
  - ⌘D voegt een werkdag toe (onderaan, met de cursor meteen in Uren), en Return in het laatste veld doet hetzelfde. ⌘S bewaart, Esc annuleert, ⌘N maakt een nieuwe factuur en ⌘1–5 kiest een pagina.
  - Zet *Systeeminstellingen → Toetsenbord → Toetsenbordnavigatie* aan om met Tab ook knoppen en keuzemenu's te bereiken.
- **Toegankelijkheid**:
  - VoiceOver krijgt duidelijke beschrijvingen van rijen, tegels, statussen en grafiekstaven, en bevestigingen worden voorgelezen. Decoratieve elementen worden overgeslagen.
  - Bij *Meer contrast* krijgen kaarten duidelijke randen. *Verminder beweging* wordt gerespecteerd.
- **Lay-out**: de inhoud past zich aan de vensterbreedte aan. In een smal venster vallen in het factuuroverzicht "Betaald op" en "Opmerking" weg, zodat de zijbalk nooit wordt weggedrukt. De praktijkenlijst heeft een vaste breedte.
- **Standaard instellingenvenster** (⌘,) met de tabbladen Bedrijf, Facturatie en Opslag.
- **Zijbalk** gegroepeerd in Administratie, Relaties en Inzicht, met een teller voor facturen die te laat zijn. Met ⌘1 t/m ⌘5 spring je naar een onderdeel.
- **Vergevingsgezind**: bijna alles is met ⌘Z ongedaan te maken. Bevestigen hoeft alleen nog bij verstuurde facturen (vanwege de boekhouding).
- **Rustige feedback**: bevestigingen verschijnen onderin en verdwijnen vanzelf. Alleen fouten krijgen een standaard macOS-melding.
- **Fouten direct in beeld**: in de factuur-editor zie je meteen wat er ontbreekt, in plaats van een melding na het bewaren.
- **Lege toestanden** leggen uit wat je kunt doen, met één duidelijke knop.
- **Hiërarchie**: op het overzicht staan eerst de vier belangrijkste cijfers, daaronder de details.
- **Lege toestanden en laadtoestanden** op elke pagina:
  - Een lege pagina legt uit wat er komt en biedt de volgende stap. Het overzicht toont dan "Aan de slag" in drie stappen.
  - Tijdens het inlezen (bijvoorbeeld als iCloud nog downloadt) verschijnt een skelet van de pagina, en er wordt dan niets opgeslagen.
- Houdt rekening met de systeeminstellingen *Verminder beweging* en *Verminder transparantie*.
- **Bento-layout**: overzicht, statistieken en de factuur-editor bestaan uit rustige kaarten op een lichtgrijze ondergrond. Er zijn grote cijfers, en de grafieken markeren de actieve periode met een ballon (wijs met de muis voor andere periodes).
- **Weergave** (Instellingen → Weergave):
  - uiterlijk Automatisch, Licht of Donker
  - zes accentkleuren
  De factuur-PDF houdt altijd de vaste huisstijlkleur.

## Ontwikkelen

- `Sources/MediKas/`: de SwiftUI-code (modellen, opslag, schermen, PDF)
- `@Local` vervangt `@State`, omdat `@State` in de huidige SDK een macro is waarvoor volledige Xcode nodig is.
- Testen zonder echte gegevens aan te raken:
  ```bash
  MEDIKAS_DATA_DIR=/tmp/medikas-test .build/debug/MediKas --seed-demo   # app met verzonnen gegevens
  .build/debug/MediKas --demo-pdf /tmp/voorbeeld.pdf 30                      # voorbeeldfactuur met 30 regels
  MEDIKAS_DATA_DIR=/tmp/st1 .build/debug/MediKas --selftest-storage /tmp/st2  # test verhuizen + archief
  MEDIKAS_DATA_DIR=/tmp/sb1 .build/debug/MediKas --selftest-backup /tmp/sb2   # test zip-back-up + opruimen
  MEDIKAS_DATA_DIR=/tmp/sc1 .build/debug/MediKas --selftest-clients           # test praktijk verwijderen
  MEDIKAS_DATA_DIR=/tmp/sk1 .build/debug/MediKas --selftest-correction /tmp    # test creditfactuur + koppelingen
  MEDIKAS_TEST_CLICKS=1 MEDIKAS_DATA_DIR=/tmp/st1 .build/debug/MediKas --selftest-clicks  # echte muisklikken (zijbalk, rij, nummer)
  MEDIKAS_DATA_DIR=/tmp/st2 .build/debug/MediKas --selftest-keyboard          # toetsenbord in de factuur-editor
  MEDIKAS_DATA_DIR=/tmp/st3 .build/debug/MediKas --selftest-filters           # factuurfilters
  MEDIKAS_DATA_DIR=/tmp/si1 .build/debug/MediKas --selftest-import            # bestaande factuur importeren
  MEDIKAS_DATA_DIR=/tmp/sp1 .build/debug/MediKas --render-previews /tmp/shots  # schermen als PNG (buiten beeld)
  MEDIKAS_DATA_DIR=/tmp/sw1 .build/debug/MediKas --seed-demo --snapshot-window /tmp/win  # het échte venster per pagina
  MEDIKAS_TEST_SLOW_LOAD=30 …                                                    # trage opslag nabootsen (laadtoestand)
  ```
- Het icoon: `Support/AppIcon.icns` (licht, uit `Support/AppIcon-bron/icon-licht-1024.png`) en `Support/AppIconDark.png` (donker). Zonder Xcode kan macOS geen automatische licht/donker-iconen maken; daarom volgt MediKas zelf de iconenstijl van macOS zolang de app draait: Standaard = licht icoon, Donker = donker icoon, Helder/Getint = macOS past de stijl zelf toe.

## Btw

Standaard staat op de factuur: *"Vrijgesteld van btw o.g.v. art. 11 lid 1 sub g Wet OB 1968"*. Dat geldt meestal voor huisartsenzorg, ook bij waarneming. Je kunt de tekst aanpassen in Instellingen. Check het bij twijfel met je boekhouder.
