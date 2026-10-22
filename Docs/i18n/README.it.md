<p align="center">
  <img src="../images/og-image.webp" alt="MacMix — Tutto il suono del tuo Mac, in MacMix. Un mixer nativo per la barra dei menu di macOS: volume di sistema, dispositivi di uscita e di ingresso e audio di ogni app." width="100%">
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest"><img src="https://img.shields.io/github/v/release/ljmng7/MacMix?label=release&color=7A5CFA" alt="Latest release"></a>
  <a href="https://github.com/ljmng7/MacMix/stargazers"><img src="https://img.shields.io/github/stars/ljmng7/MacMix?style=flat&color=F5B301&logo=github" alt="GitHub stars"></a>
  <a href="https://github.com/ljmng7/MacMix/releases"><img src="https://img.shields.io/github/downloads/ljmng7/MacMix/total?color=2F80ED" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14.4%2B-111111?logo=apple&logoColor=white" alt="macOS 14.4+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift, SwiftUI">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-3DA639" alt="GPL-3.0"></a>
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/197969?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-197969" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/197969/daily?language=Swift" alt="ljmng7%2FMacMix | Trendshift" width="250" height="55"/></a>
</p>

<p align="center">
  <a href="../../README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <b>Italiano</b> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/Scarica_per_macOS-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="Scarica MacMix per macOS">
  </a>
</p>

<p align="center">
  <a href="#funzionalità">Funzionalità</a> ·
  <a href="#versione-open-source-e-distribution">Open source e Distribution</a> ·
  <a href="#installazione">Installazione</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#compilare-dal-codice-sorgente">Compilare dal codice sorgente</a> ·
  <a href="#supporta-macmix">Supporta</a> ·
  <a href="#licenza-e-marchio">Licenza</a>
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
- L’app ufficiale si aggiorna da sola con Sparkle.

## Versione open source e Distribution

**Tutte le funzionalità di MacMix sono open source, MacMix Studio compreso.** Compilando tu stesso questo repository ottieni l’app completa con tutte le funzionalità sbloccate: senza licenza, senza account, senza nulla di escluso.

Il download dalla pagina Releases è **Distribution**: la build ufficiale della stessa app. È gratuita, e **MacMix Studio** è un acquisto facoltativo una tantum che sblocca le funzionalità Studio in quella build. Non esiste un’«app Studio» separata: una licenza sblocca funzionalità nella stessa app e le tue impostazioni restano dove sono.

| Funzionalità incluse | <div align="center">Compilato dal sorgente<br><sub>(questo repository)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(gratuita)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| Volume di sistema, dei monitor e per app | ✅ | ✅ | ✅ |
| Scelta dei dispositivi di uscita, AirPlay e ingresso | ✅ | ✅ | ✅ |
| Amplificazione al 200% per app | ✅ | ✅ | ✅ |
| Segnalazioni con log diagnostici anonimizzati | ✅ | ✅ | ✅ |
| **EQ personalizzato** — regola il suono di ogni app e salva i tuoi preset | ✅ | — | ✅ |
| **Uscita su più dispositivi** — un’app su più dispositivi contemporaneamente, ognuno con il proprio volume | ✅ | — | ✅ |
| **Controlli Pro** — livello della batteria dei dispositivi Bluetooth, modalità di ascolto e audio spaziale | ✅ | — | ✅ |
| **In riproduzione** — visualizza e controlla i contenuti in riproduzione | ✅ | — | ✅ |
| **Preset scene** — salva dispositivi e volumi delle app e cambia con un clic | ✅ | — | ✅ |
| **Controlli del volume di sistema** — gestisci i tasti del volume per una regolazione più fluida | ✅ | — | ✅ |
| **Blocca dispositivo di ingresso** — impedisci a macOS di cambiare microfono | ✅ | — | ✅ |
| **Lista nera** — escludi alcune app dal mix | ✅ | — | ✅ |
| **Personalizzazione** — temi personalizzati | ✅ | — | ✅ |
| Firmata e autenticata dallo sviluppatore | — | ✅ | ✅ |
| Aggiornamenti automatici | — | ✅ | ✅ |
| **Accesso anticipato alle beta** — prova per primo le novità | — | — | ✅ |

> [!NOTE]
> Restano private solo le parti che esistono esclusivamente per Distribution: attivazione della licenza, procedura d’acquisto, introduzione iniziale e sistema di aggiornamento. Nessuna è necessaria per compilare o eseguire MacMix, e le build da questo repository non ne contengono nessuna.

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

Seleziona lo schema **MacMix** e premi **Run**. Xcode risolve automaticamente i pacchetti Swift (MenuBarExtraAccess e Swift Atomics). Nella tua build tutte le funzionalità Studio sono sbloccate.

Senza un team di sviluppo, Xcode firma l’app solo per l’esecuzione locale e macOS potrebbe richiedere di nuovo l’autorizzazione **Registrazione audio di sistema** dopo ogni compilazione. Per mantenere l’autorizzazione, copia `Config/Local.example.xcconfig` in `Config/Local.xcconfig` e imposta il tuo `DEVELOPMENT_TEAM`. Il file è ignorato da Git.

Le build dal sorgente non si aggiornano da sole. Per aggiornare, scarica il sorgente più recente e ricompila.

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

Compilare dal sorgente è gratuito e lo resterà. Se MacMix fa parte della tua giornata, valuta l’acquisto di **MacMix Studio**: un pagamento una tantum che sblocca le funzionalità Studio in Distribution — l’app firmata, notarizzata e sempre aggiornata — e finanzia direttamente lo sviluppo di MacMix.

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/Ottieni-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="Ottieni MacMix Studio"></a>
</p>

Segnalazioni di bug e idee sono benvenute nelle [Issues](https://github.com/ljmng7/MacMix/issues). Per contribuire con del codice, consulta la [guida per i contributi](../../CONTRIBUTING.md); le pull request richiedono la firma di un Contributor License Agreement (CLA).

## Licenza e marchio

MacMix è software libero: puoi ridistribuirlo e/o modificarlo secondo i termini della [GNU General Public License, versione 3](../../LICENSE) (GPL-3.0). Le versioni fino alla 2.3.2 inclusa sono state rilasciate con licenza MIT; il codice ricevuto a quelle condizioni resta disponibile alle stesse condizioni.

**Marchio.** Il nome «MacMix» e l’icona dell’app MacMix identificano l’app ufficiale e sono riservati alle build ufficiali. La GPL copre il codice, non il nome né il marchio. Se distribuisci un fork o una build modificata, usa un nome diverso, un’icona diversa e un bundle identifier diverso, e non presentarla come il MacMix ufficiale. Compilare e usare MacMix per te stesso è sempre consentito.

L’icona dell’app, gli screenshot e gli altri elementi del marchio **non** sono coperti dalla GPL e non possono essere riutilizzati senza autorizzazione. Vedi [Elementi del marchio](../../BRAND-ASSETS.md).
