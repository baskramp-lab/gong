# Gong — ontwikkelnotities

Gebruikers-README: [`../README.md`](../README.md). Dit bestand bevat de ontwikkel- en debugnotities (Nederlands).

Menubalk-app voor macOS die je 5 minuten vóór een Google-meeting blokkeert met een grote modal
(Join Meet / Open in Calendar / Snooze 2 min / Sluit), na zachte meldingen op 30 en 10 minuten.
Leest de geheime iCal-URL van je Google-agenda; geen OAuth.

Specs, plannen en de backlog staan lokaal in `docs/superpowers/` en `BACKLOG.md` (niet in de repo; volledige geschiedenis in het privé-archief `baskramp-lab/gong-archive`).

## Bouwen en draaien

```bash
swift test                    # unit-tests (GongCore)
scripts/build-app.sh          # maakt build/Gong.app (universal: arm64 + x86_64; vereist Xcode)
open build/Gong.app           # start de menubalk-app
build/Gong.app/Contents/MacOS/Gong --demo   # toont de blokkerende modal met een nep-meeting
build/Gong.app/Contents/MacOS/Gong --demo --multi            # plus een overlappende meeting (compacte rij)
build/Gong.app/Contents/MacOS/Gong --snapshot /tmp/m.png 1.0  # rendert de modal offscreen op 1,0 s in de cyclus
```

## Retro-modal

De modal is een 16-bit scène: een ninja in vechthouding slaat 1 s na openen (eerst even idle) en daarna elke 4 s zijwaarts op de gong
("GONG!"), precies gelijk met een gesynthetiseerd gong-geluid (geen audiobestand; `GongSynth` in GongCore).
Daaronder loopt een gesynthetiseerde chiptune-soundtrack (`SoundtrackSynth`: in-toonladder op D, 8-bit shakuhachi-lead,
koto, taiko; 32 s-loop = 8 slagen, zacht op 20 %). Staat je Mac op mute of onder 40 % volume, dan zet Gong het geluid tijdelijk
aan/omhoog (`SystemVolume`) en herstelt het je oude stand zodra de modal sluit.
Reduce Motion (Systeeminstellingen → Toegankelijkheid → Beeldscherm) houdt de ninja stil in guard; het geluid blijft.
Alle pixel-art staat als tekstrasters in `Sources/GongCore/Retro/`.

Testen: menubalk → **Demo-modal tonen** (⌘D) opent de modal met een voorbeeldmeeting (begint over 4 min); elke knop sluit hem alleen, en elke demo geeft een nieuwe kans in het spel. Een echte meeting neemt het over.

Easter egg: druk op spatie in de modal — de scène groeit uit tot de spelwereld en de ninja loopt naar het midden; dan komen de shurikens. ←/→ lopen, ↑ springen (salto), ↓ hurken (stilstaand) of sliden (tijdens lopen), spatie afweren. Er is geen terugweg: na game over blijft de wereld staan met de meeting-knoppen eronder. Eén kans per meeting, ook niet opnieuw na snoozen. 3 levens; moeilijker naarmate de meeting nadert, onmogelijk zodra hij begint. Punten: 10 per seconde overleven, +50 per weggeslagen shuriken; de klok rechtsboven telt af naar de meeting. Record in `settings.json` (`bestGameScore`). Frames per beweging: `swift run GongIconExport --game-frames /tmp/frames`.

```bash
swift run GongIconExport Resources/Assets.xcassets/AppIcon.appiconset   # app-icoon opnieuw genereren
swift run GongIconExport --frames /tmp/frames                           # scène-frames op sleutelmomenten
swift run GongIconExport --wav /tmp/gong.wav                            # het gong-geluid als WAV
swift run GongIconExport --mix /tmp/gong-mix.wav                        # soundtrack-loop (32 s) met gong op elke slag
```

Pixel-font: zet `Silkscreen-*.ttf` (OFL) in `Resources/Fonts/`; `build-app.sh` bundelt hem. Zonder font valt de modal
terug op SF Mono.

Notificaties en "Start bij inloggen" werken alleen vanuit `build/Gong.app`, niet via `swift run`.

## Instellen

Menubalk-gong (uitgegrijsd = gepauzeerd; oranje bolletje = feed verouderd, rood bolletje = fout/geen URL) → *iCal-URL instellen…* → plak het "Geheime adres in iCal-indeling" uit
Google Calendar → *Test* → *Opslaan*. De URL gaat in de Keychain (`nl.baskramp.gong`).

Instellingen: `~/Library/Application Support/Gong/settings.json` (drempels, geluid aan/uit, `includeUnaccepted`). `myEmail` mag leeg blijven: Gong haalt je adres uit de geheime iCal-URL; vul het alleen in als die URL geen adres bevat. Gong schrijft alleen het gewijzigde veld terug en laat een bestand dat niet te lezen is ongemoeid.

Menu-optie **Ook niet-geaccepteerde meetings** (standaard aan): ook uitnodigingen die je nog niet hebt geaccepteerd (of "misschien") geven een melding. Uit → alleen geaccepteerde meetings en je eigen afspraken met een videolink.

## Bekende beperkingen en dingen die je één keer moet doen

- **Meldingsicoon zit vast aan de bundle-id.** Het Berichtencentrum bewaart per bundle-id het app-icoon van het moment
  waarop je meldingen toestond. Verander je later het icoon, dan blijft de banner het oude (of geen) icoon tonen; daemon
  herstarten of `lsregister` helpt niet. Enige uitweg: een nieuwe `CFBundleIdentifier` (nu `nl.baskramp.gong.mac`) en
  opnieuw toestaan. Test met `open -n /Applications/Gong.app --args --test-notification`.
- **Meldingen alleen vanuit /Applications.** Een kopie in een andere map wordt zonder dialoog geweigerd ("not allowed").

- **Signering.** macOS accepteert alleen meldingen van een app met een echt Apple-certificaat. `scripts/build-app.sh`
  signeert automatisch met een *Apple Development*-identity als die in je Keychain staat (aanmaken: Xcode →
  Settings → Accounts → Manage Certificates → + Apple Development). Ontbreekt het tussencertificaat *WWDR G3*,
  download het dan van apple.com/certificateauthority en voeg het toe aan de login-Keychain. Zonder certificaat
  wordt ad-hoc gesigneerd: alles werkt, behalve de zachte meldingen.
- **Installeren.** `scripts/build-app.sh --install` kopieert de app naar `/Applications` en stopt de draaiende
  versie. Daarna `open /Applications/Gong.app`. Na een nieuwe build vraagt macOS één keer opnieuw toegang tot het
  Keychain-item met de iCal-URL → *Altijd toestaan*.
- **Notch.** Op een MacBook met notch verdwijnen menubalk-iconen die achter de camera vallen. Gong's icoon komt
  links van de bestaande iconen te staan. Oplossing: minder iconen, of een menubalk-manager zoals Ice
  (`brew install --cask jordanbaird-ice`, optie *Use Ice Bar*).
- **Meet in de desktop-app.** Gong opent de Meet-link in je standaardbrowser. Wil je de Google Meet-PWA: Chrome →
  `chrome://apps` → rechtsklik Google Meet → *Open in venster*, en in de app-instellingen *Ondersteunde links
  openen in deze app* aanzetten.
- **Kamerreserveringen** tellen als "andere genodigde": een solo-blok met een vergaderruimte blokkeert dus ook.
- **Stoppen terwijl de modal open staat** kan alleen via het menu (⌘Q op de modal is bewust uit); uitloggen, herstarten en afsluiten gaan altijd door.


## Vertalingen

Alle UI-tekst loopt via `L("English text")` (`Sources/GongCore/Localization.swift`). Na het toevoegen of wijzigen van tekst: `python3 scripts/l10n.py` (schrijft `Resources/en.lproj` en meldt ontbrekende vertalingen); `LocalizationTests` faalt zolang een taal een sleutel mist of een game-tekst niet in de pixelfont past.
