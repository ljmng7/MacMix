<p align="center">
  <img src="Docs/images/og-image.webp" alt="MacMix — Tutto il suono del tuo Mac, in MacMix. Un mixer nativo per la barra dei menu di macOS: volume di sistema, dispositivi di uscita e di ingresso e audio di ogni app." width="100%">
  <br>
  <sub>Lo screenshot mostra la versione distribuita. Alcune funzionalità richiedono MacMix Studio.</sub>
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
  <a href="README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <b>Italiano</b> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/Scarica_per_macOS-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="Scarica MacMix per macOS">
  </a>
</p>

<p align="center">
  <a href="#funzionalità">Funzionalità</a> ·
  <a href="#versione-open-source-e-versione-distribuita">Open source e versione distribuita</a> ·
  <a href="#installazione">Installazione</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#compilare-dal-codice-sorgente">Compilare dal codice sorgente</a> ·
  <a href="#supporta-macmix">Supporta</a>
</p>

---

## Perché MacMix

macOS ti dà un solo cursore del volume. MacMix ti dà tutto il resto: abbassa un’app rumorosa senza toccare la musica, passa da AirPods ad altoparlanti o monitor con un clic e scegli il microfono giusto prima di una chiamata. Tutto da un pannello nativo e compatto nella barra dei menu, senza aprire Impostazioni di Sistema.

## Funzionalità

### 🔊 Volume

- **Volume di sistema** del dispositivo di uscita attuale, direttamente nella barra dei menu.
- **Altoparlanti dei monitor esterni** tramite DDC/CI quando macOS non offre il controllo del volume, con correzioni per i monitor che riportano intervalli insoliti.
- **Zero vero**: portando un cursore allo 0% il dispositivo tace del tutto, senza volume residuo.

### 🎧 Dispositivi

- **Cambia uscita** tra altoparlanti, cuffie, AirPods, monitor e altro.
- **Ricevitori AirPlay per nome**: ogni HomePod o altoparlante AirPlay ha la sua riga, e puoi passare da un gruppo attivo a un singolo ricevitore.
- **Icone riconoscibili** per AirPods, Beats, HomePod, Apple TV, monitor esterni e gli altoparlanti del tuo Mac, oltre all’icona fornita dal dispositivo stesso.
- **Cambia microfono** e regola il volume di ingresso dallo stesso pannello.

### 🎚️ Mix per app

- **Abbassa qualsiasi app** mentre riproduce, o amplificala fino al **200%** (opzionale, nelle impostazioni).
- **Ricorda i tuoi livelli** e li ripristina quando l’app riprende a suonare.
- **Trova l’app reale** dietro la riproduzione web, comprese le app per iPad che riproducono contenuti tramite WebKit.

### 🍃 Leggero per natura

- Resta discreto nella barra dei menu, con una finestra di impostazioni opzionale.
- SwiftUI nativo, audio elaborato localmente in tempo reale, nessun account.
- Aggiornamenti automatici con Sparkle.

## Versione open source e versione distribuita

Questo repository contiene il **nucleo gratuito e open source** di MacMix. Il download dalla pagina Releases è la **versione distribuita**: un’unica app gratuita, con **MacMix Studio** come aggiornamento facoltativo a pagamento singolo. Non esiste un’«app Studio» separata: una licenza sblocca funzionalità extra nella stessa app e le tue impostazioni restano dove sono.

| Funzionalità incluse | <div align="center">Open source<br><sub>(questo repository)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Versione distribuita<br><sub>(gratuita)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Versione distribuita<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| Volume di sistema, dei monitor e per app | ✅ | ✅ | ✅ |
| Scelta dei dispositivi di uscita, AirPlay e ingresso | ✅ | ✅ | ✅ |
| Amplificazione al 200% per app | ✅ | ✅ | ✅ |
| Firmata e autenticata dallo sviluppatore | — | ✅ | ✅ |
| Segnalazioni con log diagnostici anonimizzati | — | ✅ | ✅ |
| **EQ personalizzato** — regola il suono di ogni app e salva i tuoi preset | — | — | ✅ |
| **Uscita su più dispositivi** — un’app su più dispositivi contemporaneamente, ognuno con il proprio volume | — | — | ✅ |
| **Controlli Pro** — livello della batteria dei dispositivi Bluetooth, modalità di ascolto e audio spaziale | — | — | ✅ |
| **In riproduzione** — visualizza e controlla i contenuti in riproduzione | — | — | ✅ |
| **Preset scene** — salva dispositivi e volumi delle app e cambia con un clic | — | — | ✅ |
| **Controlli del volume di sistema** — gestisci i tasti del volume per una regolazione più fluida | — | — | ✅ |
| **Blocca dispositivo di ingresso** — impedisci a macOS di cambiare microfono | — | — | ✅ |
| **Lista nera** — escludi alcune app dal mix | — | — | ✅ |
| **Personalizzazione** — temi personalizzati | — | — | ✅ |
| **Accesso anticipato alle beta** — prova per primo le novità | — | — | ✅ |

> [!NOTE]
> Le funzionalità Studio sono sviluppate privatamente e non fanno parte di questo repository. Tutto ciò che è già gratuito, compreso il mix per app e tutte le funzionalità precedenti alla versione 2.0, resterà gratuito e open source. Le correzioni del nucleo comune arrivano in questo repository dopo essere state verificate nella versione distribuita, quindi il codice qui può essere leggermente indietro rispetto all’ultima versione.

## Installazione

1. Scarica [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg) dall’ultima versione.
2. Apri l’immagine disco e trascina **MacMix** in **Applicazioni**.
3. Avvia MacMix e fai clic sulla sua icona nella barra dei menu.

**Requisiti:** macOS Sonoma 14.4 o successivo. Il mix per app richiede il permesso **Registrazione audio di sistema** al primo utilizzo; tutto il resto funziona anche senza.

## Privacy

MacMix elabora l’audio **localmente sul tuo Mac**. Non registra, salva né carica mai l’audio.

Il mix per app si basa sui tap dei processi audio di macOS: per questo macOS chiede il permesso Registrazione audio di sistema prima che MacMix possa modificare il volume di un’altra app. MacMix usa questo permesso solo per il mix locale in tempo reale.

## Compilare dal codice sorgente

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

Seleziona lo schema **MacMix** e premi **Run**. Xcode risolve automaticamente i pacchetti Swift (Sparkle e Swift Atomics).

I test di regressione sono semplici script che richiedono solo gli strumenti da riga di comando di Xcode:

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>Note e limitazioni</strong></summary>

<br>

- Le app compaiono nel mixer solo mentre macOS segnala che stanno riproducendo audio.
- I livelli per app sono salvati localmente e ripristinati quando la stessa app riprende a suonare.
- Il volume del monitor richiede un display che supporti il volume degli altoparlanti DDC/CI (VCP `0x62`) tramite il cavo o il dock in uso. Adattatori DisplayLink, alcuni collegamenti HDMI, TV e monitor con DDC/CI disattivato nel menu OSD potrebbero non offrirlo.
- I nomi dei ricevitori AirPlay provengono dalle sorgenti dati del dispositivo AirPlay. Se macOS non fornisce un nome, MacMix mostra il dispositivo AirPlay generico invece di indovinare.

</details>

## Supporta MacMix

Se MacMix fa parte della tua giornata, valuta il passaggio a **MacMix Studio**. È un acquisto una tantum che sblocca le funzionalità qui sopra e finanzia il nucleo gratuito e open source.

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/Ottieni-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="Ottieni MacMix Studio"></a>
</p>

Segnalazioni di bug e idee sono benvenute nelle [Issues](https://github.com/ljmng7/MacMix/issues).

## Licenza

Il codice sorgente è distribuito con [licenza MIT](LICENSE). L’icona dell’app, gli screenshot e gli altri elementi del marchio **non** sono coperti dalla licenza MIT e non possono essere riutilizzati senza autorizzazione. Vedi [Elementi del marchio](BRAND-ASSETS.md).
