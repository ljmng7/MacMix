<p align="center">
  <img src="../images/og-image.webp" alt="MacMix — Al het geluid van je Mac. Allemaal in MacMix. Een native mixer voor de macOS-menubalk: systeemvolume, uitvoer- en invoerapparaten en het geluid van elke app." width="100%">
  <br>
  <sub>De schermafbeelding toont de distributieversie. Sommige functies vereisen MacMix Studio.</sub>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest"><img src="https://img.shields.io/github/v/release/ljmng7/MacMix?label=release&color=7A5CFA" alt="Latest release"></a>
  <a href="https://github.com/ljmng7/MacMix/stargazers"><img src="https://img.shields.io/github/stars/ljmng7/MacMix?style=flat&color=F5B301&logo=github" alt="GitHub stars"></a>
  <a href="https://github.com/ljmng7/MacMix/releases"><img src="https://img.shields.io/github/downloads/ljmng7/MacMix/total?color=2F80ED" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14.4%2B-111111?logo=apple&logoColor=white" alt="macOS 14.4+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift, SwiftUI">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/code-MIT-3DA639" alt="MIT License"></a>
</p>

<p align="center">
  <a href="../../README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <b>Nederlands</b> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/Download_voor_macOS-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="Download MacMix voor macOS">
  </a>
</p>

<p align="center">
  <a href="#functies">Functies</a> ·
  <a href="#open-source-en-distributieversie">Open source vs. distributieversie</a> ·
  <a href="#installeren">Installeren</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#bouwen-vanuit-de-broncode">Bouwen vanuit de broncode</a> ·
  <a href="#macmix-steunen">Steunen</a>
</p>

---

## Waarom MacMix

macOS geeft je één volumeschuifknop. MacMix geeft je de rest: zet een luidruchtige app zachter zonder je muziek aan te raken, wissel met één klik tussen AirPods, luidsprekers en een monitor, en kies de juiste microfoon voor een gesprek. Alles vanuit een compact, native paneel in de menubalk, zonder Systeeminstellingen te openen.

## Functies

### 🔊 Volume

- **Systeemvolume** van het huidige uitvoerapparaat, direct in de menubalk.
- **Luidsprekers van externe beeldschermen** via DDC/CI wanneer macOS geen volumeregeling biedt, met oplossingen voor monitoren die ongebruikelijke bereiken melden.
- **Echt nul**: bij 0% is het apparaat volledig stil, zonder zacht restgeluid.

### 🎧 Apparaten

- **Wissel van uitvoer** tussen luidsprekers, koptelefoons, AirPods, beeldschermen en meer.
- **AirPlay-ontvangers op naam**: elke HomePod of AirPlay-luidspreker krijgt een eigen rij, en je kunt vanuit een actieve groep naar één ontvanger wisselen.
- **Herkenbare symbolen** voor AirPods, Beats, HomePod, Apple TV, externe beeldschermen en de luidsprekers van je Mac, plus het symbool dat een apparaat zelf meelevert.
- **Wissel van microfoon** en pas het invoervolume aan in hetzelfde paneel.

### 🎚️ Mixen per app

- **Zet elke app zachter** terwijl die speelt, of versterk tot **200%** (optioneel, in de instellingen).
- **Onthoudt je niveaus** en herstelt ze wanneer de app weer speelt.
- **Vindt de echte app** achter webweergave, ook iPad-apps die media via WebKit afspelen.

### 🍃 Licht van opzet

- Werkt rustig vanuit de menubalk, met een optioneel venster voor instellingen.
- Native SwiftUI, audio wordt lokaal en realtime verwerkt, geen account nodig.
- Automatische updates via Sparkle.

## Open source en distributieversie

Deze repository bevat de **gratis, opensource kern** van MacMix. De download op de Releases-pagina is de **distributieversie**: één gratis app, met **MacMix Studio** als optionele eenmalige upgrade. Er is geen aparte ‘Studio-app’: een licentie ontgrendelt extra functies in dezelfde app, en je instellingen blijven waar ze zijn.

| Inbegrepen functies | <div align="center">Open source<br><sub>(deze repository)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distributieversie<br><sub>(gratis)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distributieversie<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| Systeem-, beeldscherm- en app-volume | ✅ | ✅ | ✅ |
| Wisselen van uitvoer-, AirPlay- en invoerapparaten | ✅ | ✅ | ✅ |
| 200% versterking per app | ✅ | ✅ | ✅ |
| Ondertekend en genotariseerd door de ontwikkelaar | — | ✅ | ✅ |
| Feedback met geanonimiseerde diagnoselogboeken | — | ✅ | ✅ |
| **Aangepaste EQ** — stem het geluid van elke app af en bewaar je voorinstellingen | — | — | ✅ |
| **Uitvoer naar meerdere apparaten** — één app op meerdere apparaten tegelijk, elk met een eigen volume | — | — | ✅ |
| **Pro-bediening** — batterijniveau van Bluetooth-apparaten, luistermodus en ruimtelijke audio | — | — | ✅ |
| **Speelt nu** — bekijk en bedien wat er nu speelt | — | — | ✅ |
| **Scènevoorinstellingen** — bewaar apparaten en app-volumes en wissel met één klik | — | — | ✅ |
| **Systeemvolume regelen** — neem de volumetoetsen over voor soepelere regeling | — | — | ✅ |
| **Invoerapparaat vergrendelen** — voorkom dat macOS van microfoon wisselt | — | — | ✅ |
| **Blokkeerlijst** — laat geselecteerde apps buiten het mixen | — | — | ✅ |
| **Personalisatie** — eigen thema’s | — | — | ✅ |
| **Vroege toegang tot bèta’s** — probeer nieuwe functies als eerste | — | — | ✅ |

> [!NOTE]
> Studio-functies worden privé ontwikkeld en maken geen deel uit van deze repository. Alles wat al gratis is, waaronder mixen per app en alle functies van vóór versie 2.0, blijft gratis en open source. Oplossingen in de gedeelde kern komen in deze repository nadat ze in de distributieversie zijn gevalideerd, dus de broncode hier kan iets achterlopen op de nieuwste release.

## Installeren

1. Download [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg) van de nieuwste release.
2. Open de schijfkopie en sleep **MacMix** naar **Apps**.
3. Open MacMix en klik op het symbool in de menubalk.

**Vereisten:** macOS Sonoma 14.4 of nieuwer. Mixen per app vraagt de eerste keer om de toestemming **Systeemaudio-opname**; al het andere werkt zonder.

## Privacy

MacMix verwerkt audio **lokaal op je Mac**. Het neemt nooit audio op, slaat het niet op en uploadt het niet.

Mixen per app is gebouwd op audioproces-taps van macOS. Daarom vraagt macOS om de toestemming Systeemaudio-opname voordat MacMix het volume van een andere app kan wijzigen. MacMix gebruikt die toestemming alleen voor lokaal mixen in realtime.

## Bouwen vanuit de broncode

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

Kies het schema **MacMix** en klik op **Run**. Xcode haalt de Swift-pakketten (Sparkle en Swift Atomics) automatisch op.

De regressietests zijn eenvoudige scripts die alleen de Xcode-opdrachtregeltools nodig hebben:

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>Opmerkingen en beperkingen</strong></summary>

<br>

- Apps verschijnen alleen in de mixer zolang macOS meldt dat ze audio afspelen.
- Niveaus per app worden lokaal bewaard en hersteld wanneer dezelfde app weer speelt.
- Beeldschermvolume vereist een monitor die DDC/CI-luidsprekervolume (VCP `0x62`) ondersteunt via de huidige kabel of het huidige dock. DisplayLink-adapters, sommige HDMI-verbindingen, tv’s en beeldschermen waarop DDC/CI in het schermmenu is uitgeschakeld, bieden dit mogelijk niet.
- Namen van AirPlay-ontvangers komen uit de gegevensbronnen van het AirPlay-apparaat. Als macOS geen naam doorgeeft, toont MacMix het algemene AirPlay-apparaat in plaats van te gokken.

</details>

## MacMix steunen

Hoort MacMix bij je dag? Overweeg dan een upgrade naar **MacMix Studio**. Een eenmalige aankoop ontgrendelt de functies hierboven en financiert de gratis, opensource kern.

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/Nu_kopen-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="MacMix Studio kopen"></a>
</p>

Bugmeldingen en ideeën zijn welkom in [Issues](https://github.com/ljmng7/MacMix/issues).

## Licentie

De broncode wordt uitgebracht onder de [MIT-licentie](../../LICENSE). Het app-symbool, schermafbeeldingen en andere merkelementen vallen **niet** onder de MIT-licentie en mogen niet zonder toestemming worden hergebruikt. Zie [Merkelementen](../../BRAND-ASSETS.md).
