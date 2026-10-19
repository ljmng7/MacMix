<p align="center">
  <img src="Docs/images/og-image.webp" alt="MacMix — Der ganze Sound deines Mac. Alles in MacMix. Ein nativer Mixer für die macOS-Menüleiste: Systemlautstärke, Aus- und Eingabegeräte und der Ton jeder App." width="100%">
  <br>
  <sub>Der Screenshot zeigt die Vertriebsversion. Einige Funktionen erfordern MacMix Studio.</sub>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest"><img src="https://img.shields.io/github/v/release/ljmng7/MacMix?label=release&color=7A5CFA" alt="Latest release"></a>
  <a href="https://github.com/ljmng7/MacMix/stargazers"><img src="https://img.shields.io/github/stars/ljmng7/MacMix?style=flat&color=F5B301&logo=github" alt="GitHub stars"></a>
  <a href="https://github.com/ljmng7/MacMix/releases"><img src="https://img.shields.io/github/downloads/ljmng7/MacMix/total?color=2F80ED" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14.4%2B-111111?logo=apple&logoColor=white" alt="macOS 14.4+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift, SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/code-MIT-3DA639" alt="MIT License"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <b>Deutsch</b> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/F%C3%BCr_macOS_laden-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="MacMix für macOS laden">
  </a>
</p>

<p align="center">
  <a href="#funktionen">Funktionen</a> ·
  <a href="#open-source-und-vertriebsversion">Open Source vs. Vertriebsversion</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#datenschutz">Datenschutz</a> ·
  <a href="#aus-dem-quellcode-erstellen">Aus dem Quellcode erstellen</a> ·
  <a href="#macmix-unterstützen">Unterstützen</a>
</p>

---

## Warum MacMix

macOS gibt dir einen einzigen Lautstärkeregler. MacMix gibt dir den Rest: Mach eine laute App leiser, ohne die Musik anzufassen, wechsle mit einem Klick zwischen AirPods, Lautsprechern und Monitor, und wähle vor einem Anruf das richtige Mikrofon. Alles in einem kompakten, nativen Fenster in der Menüleiste, ohne die Systemeinstellungen zu öffnen.

## Funktionen

### 🔊 Lautstärke

- **Systemlautstärke** des aktuellen Ausgabegeräts, direkt in der Menüleiste.
- **Lautsprecher externer Displays** über DDC/CI, wenn macOS keine Lautstärkeregelung anbietet, mit Korrekturen für Monitore, die ungewöhnliche Wertebereiche melden.
- **Echte Null**: Bei 0 % ist das Gerät wirklich stumm, ohne leisen Restpegel.

### 🎧 Geräte

- **Ausgabe wechseln** zwischen Lautsprechern, Kopfhörern, AirPods, Displays und mehr.
- **AirPlay-Empfänger mit Namen**: Jeder HomePod und jeder AirPlay-Lautsprecher hat eine eigene Zeile, und du kannst aus einer aktiven Gruppe zu einem einzelnen Empfänger wechseln.
- **Erkennbare Symbole** für AirPods, Beats, HomePod, Apple TV, externe Displays und die eingebauten Lautsprecher deines Mac, dazu das Symbol, das ein Gerät selbst mitbringt.
- **Mikrofon wechseln** und die Eingangslautstärke im selben Fenster anpassen.

### 🎚️ Lautstärke pro App

- **Mach jede App leiser**, während sie spielt, oder verstärke sie auf bis zu **200 %** (optional in den Einstellungen).
- **Merkt sich deine Pegel** und stellt sie wieder her, wenn die App erneut spielt.
- **Findet die echte App** hinter Web-Wiedergabe, auch bei iPad-Apps, die Medien über WebKit abspielen.

### 🍃 Leicht gebaut

- Läuft unauffällig in der Menüleiste, mit optionalem Fenster für Einstellungen.
- Natives SwiftUI, Audio wird lokal in Echtzeit verarbeitet, kein Konto nötig.
- Automatische Updates über Sparkle.

## Open Source und Vertriebsversion

Dieses Repository enthält den **kostenlosen Open-Source-Kern** von MacMix. Der Download auf der Releases-Seite ist die **Vertriebsversion**: eine einzige kostenlose App, mit **MacMix Studio** als optionalem Einmalkauf. Es gibt keine separate „Studio-App“ – eine Lizenz schaltet in derselben App zusätzliche Funktionen frei, und deine Einstellungen bleiben erhalten.

| Enthaltene Funktionen | <div align="center">&nbsp;&nbsp;&nbsp;Open Source&nbsp;&nbsp;&nbsp;<br><sub>(dieses Repository)</sub></div> | <div align="center">&nbsp;&nbsp;&nbsp;Vertriebsversion&nbsp;&nbsp;&nbsp;<br><sub>(kostenlos)</sub></div> | <div align="center">&nbsp;&nbsp;&nbsp;Vertriebsversion&nbsp;&nbsp;&nbsp;<br><sub>(Studio)</sub></div> |
| --- | :---: | :---: | :---: |
| System-, Display- und App-Lautstärke | ✅ | ✅ | ✅ |
| Wechsel von Ausgabe-, AirPlay- und Eingabegeräten | ✅ | ✅ | ✅ |
| 200 % Verstärkung pro App | ✅ | ✅ | ✅ |
| Vom Entwickler signiert und notarisiert | — | ✅ | ✅ |
| Feedback mit anonymisierten Diagnoseprotokollen | — | ✅ | ✅ |
| **Eigener EQ** — Klang jeder App anpassen und als Voreinstellung sichern | — | — | ✅ |
| **Ausgabe auf mehrere Geräte** — eine App auf mehreren Geräten gleichzeitig, jedes mit eigener Lautstärke | — | — | ✅ |
| **Pro-Steuerung** — Akkustand von Bluetooth-Geräten, Hörmodus und 3D-Audio | — | — | ✅ |
| **Aktuelle Wiedergabe** — laufende Medien sehen und steuern | — | — | ✅ |
| **Szenenvoreinstellungen** — Geräte und App-Lautstärken sichern und mit einem Klick wechseln | — | — | ✅ |
| **Systemlautstärkeregelung** — Lautstärketasten übernehmen für eine feinere Regelung | — | — | ✅ |
| **Eingabegerät sperren** — verhindern, dass macOS das Mikrofon wechselt | — | — | ✅ |
| **Sperrliste** — bestimmte Apps vom Mischen ausnehmen | — | — | ✅ |
| **Personalisierung** — eigene Designs | — | — | ✅ |
| **Frühzugang zu Betaversionen** — neue Funktionen zuerst ausprobieren | — | — | ✅ |

> [!NOTE]
> Studio-Funktionen werden privat entwickelt und sind nicht Teil dieses Repositorys. Alles, was bisher kostenlos war – einschließlich der Lautstärke pro App und aller Funktionen vor Version 2.0 –, bleibt kostenlos und Open Source. Korrekturen am gemeinsamen Kern gelangen in dieses Repository, nachdem sie in der Vertriebsversion geprüft wurden. Der Quellcode hier kann der neuesten Version daher etwas hinterherhinken.

## Installation

1. Lade [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg) aus der neuesten Version herunter.
2. Öffne das Image und ziehe **MacMix** in den Ordner **Programme**.
3. Starte MacMix und klicke auf sein Symbol in der Menüleiste.

**Voraussetzungen:** macOS Sonoma 14.4 oder neuer. Für die Lautstärke pro App wird beim ersten Mal die Berechtigung **Systemaudioaufnahme** abgefragt; alles andere funktioniert ohne sie.

## Datenschutz

MacMix verarbeitet Audio **lokal auf deinem Mac**. Audio wird nie aufgenommen, gespeichert oder hochgeladen.

Die Lautstärke pro App basiert auf Audio-Prozess-Taps von macOS. Deshalb fragt macOS nach der Berechtigung Systemaudioaufnahme, bevor MacMix die Lautstärke einer anderen App ändern kann. MacMix nutzt diese Berechtigung nur für das lokale Mischen in Echtzeit.

## Aus dem Quellcode erstellen

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

Wähle das Schema **MacMix** und klicke auf **Run**. Xcode lädt die Swift-Pakete (Sparkle und Swift Atomics) automatisch.

Die Regressionstests sind einfache Skripte, die nur die Xcode-Befehlszeilentools benötigen:

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>Hinweise und Einschränkungen</strong></summary>

<br>

- Apps erscheinen im Mixer nur, solange macOS meldet, dass sie Audio ausgeben.
- Die Pegel pro App werden lokal gespeichert und wiederhergestellt, wenn dieselbe App erneut spielt.
- Die Display-Lautstärke erfordert einen Monitor, der DDC/CI-Lautsprecherlautstärke (VCP `0x62`) über das aktuelle Kabel oder Dock unterstützt. DisplayLink-Adapter, manche HDMI-Verbindungen, Fernseher und Displays mit im OSD-Menü deaktiviertem DDC/CI bieten das möglicherweise nicht an.
- Die Namen von AirPlay-Empfängern stammen aus den Datenquellen des AirPlay-Geräts. Meldet macOS keinen Namen, zeigt MacMix das allgemeine AirPlay-Gerät, statt zu raten.

</details>

## MacMix unterstützen

Wenn MacMix zu deinem Alltag gehört, denk über ein Upgrade auf **MacMix Studio** nach. Ein Einmalkauf schaltet die Funktionen oben frei und finanziert den kostenlosen Open-Source-Kern.

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/Holen-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="MacMix Studio holen"></a>
</p>

Fehlerberichte und Ideen sind in den [Issues](https://github.com/ljmng7/MacMix/issues) willkommen.

## Lizenz

Der Quellcode steht unter der [MIT-Lizenz](LICENSE). App-Symbol, Screenshots und andere Markenelemente fallen **nicht** unter die MIT-Lizenz und dürfen nicht ohne Erlaubnis weiterverwendet werden – siehe [Markenelemente](BRAND-ASSETS.md).
