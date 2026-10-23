<p align="center">
  <img src="../images/og-image.webp" alt="MacMix — Cały dźwięk Twojego Maca. Wszystko w MacMix. Natywny mikser na pasek menu macOS: głośność systemu, urządzenia wyjściowe i wejściowe oraz dźwięk każdej aplikacji." width="100%">
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
  <a href="../../README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <b>Polski</b>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/Pobierz_na_macOS-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="Pobierz MacMix na macOS">
  </a>
</p>

<p align="center">
  <a href="#funkcje">Funkcje</a> ·
  <a href="#open-source-i-distribution">Open source a Distribution</a> ·
  <a href="#instalacja">Instalacja</a> ·
  <a href="#prywatność">Prywatność</a> ·
  <a href="#kompilacja-ze-źródeł">Kompilacja ze źródeł</a> ·
  <a href="#wesprzyj-macmix">Wsparcie</a> ·
  <a href="#licencja-i-znak-towarowy">Licencja</a>
</p>

---

## Dlaczego MacMix

macOS daje Ci jeden suwak głośności. MacMix daje całą resztę: przycisz hałaśliwą aplikację bez ruszania muzyki, przełączaj się między AirPods, głośnikami i monitorem jednym kliknięciem i wybierz właściwy mikrofon przed rozmową. Wszystko z kompaktowego, natywnego panelu na pasku menu, bez otwierania Ustawień systemowych.

## Funkcje

### 🔊 Głośność

- **Głośność systemu** dla bieżącego urządzenia wyjściowego, prosto z paska menu.
- **Głośniki monitorów zewnętrznych** przez DDC/CI, gdy macOS nie oferuje regulacji głośności, z poprawkami dla monitorów zgłaszających nietypowe zakresy.
- **Prawdziwe zero**: przesunięcie suwaka na 0% całkowicie wycisza urządzenie, bez cichego szczątkowego dźwięku.

### 🎧 Urządzenia

- **Przełączaj wyjście** między głośnikami, słuchawkami, AirPods, monitorami i innymi urządzeniami.
- **Odbiorniki AirPlay z nazwami**: każdy HomePod i głośnik AirPlay ma własny wiersz, a z aktywnej grupy można przejść do jednego odbiornika.
- **Rozpoznawalne ikony** dla AirPods, Beats, HomePod, Apple TV, monitorów zewnętrznych i wbudowanych głośników Maca, a także ikona dostarczana przez samo urządzenie.
- **Przełączaj mikrofony** i reguluj głośność wejścia w tym samym panelu.

### 🎚️ Miksowanie aplikacji

- **Przycisz dowolną aplikację** podczas odtwarzania albo wzmocnij ją do **200%** (opcjonalnie, w ustawieniach).
- **Zapamiętuje poziomy** i przywraca je, gdy aplikacja znów zaczyna grać.
- **Znajduje właściwą aplikację** stojącą za odtwarzaniem w przeglądarce, w tym aplikacje na iPada odtwarzające multimedia przez WebKit.

### 🍃 Lekki z założenia

- Działa dyskretnie na pasku menu, z opcjonalnym oknem ustawień.
- Natywny SwiftUI, dźwięk przetwarzany lokalnie w czasie rzeczywistym, bez konta.
- Oficjalna aplikacja aktualizuje się sama przez Sparkle.

## Open source i Distribution

**Wszystkie funkcje MacMix mają otwarty kod, łącznie z MacMix Studio.** Gdy samodzielnie zbudujesz to repozytorium, otrzymasz pełną aplikację z odblokowanymi wszystkimi funkcjami: bez licencji, bez konta, bez żadnych ograniczeń.

Do pobrania na stronie Releases jest **Distribution**: oficjalna kompilacja tej samej aplikacji. Jest darmowa, a **MacMix Studio** to opcjonalny jednorazowy zakup, który odblokowuje funkcje Studio w tej kompilacji. Nie ma osobnej „aplikacji Studio” — licencja odblokowuje funkcje w tej samej aplikacji, a Twoje ustawienia pozostają bez zmian.

| Zawarte funkcje | <div align="center">Zbudowana ze źródeł<br><sub>(to repozytorium)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(darmowa)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| Głośność systemu, monitora i aplikacji | ✅ | ✅ | ✅ |
| Przełączanie urządzeń wyjściowych, AirPlay i wejściowych | ✅ | ✅ | ✅ |
| Wzmocnienie aplikacji do 200% | ✅ | ✅ | ✅ |
| Zgłoszenia z anonimowymi dziennikami diagnostycznymi | ✅ | ✅ | ✅ |
| **Własny EQ** — dostrój dźwięk każdej aplikacji i zapisuj własne ustawienia | ✅ | — | ✅ |
| **Wyjście na wiele urządzeń** — jedna aplikacja na kilku urządzeniach naraz, każde z własną głośnością | ✅ | — | ✅ |
| **Sterowanie Pro** — poziom baterii urządzeń Bluetooth, tryb słuchania i dźwięk przestrzenny | ✅ | — | ✅ |
| **Teraz odtwarzane** — podgląd i sterowanie bieżącym odtwarzaniem | ✅ | — | ✅ |
| **Ustawienia scen** — zapisuj urządzenia i głośność aplikacji, przełączaj jednym kliknięciem | ✅ | — | ✅ |
| **Sterowanie głośnością systemu** — przejmij klawisze głośności dla płynniejszej regulacji | ✅ | — | ✅ |
| **Zablokuj urządzenie wejściowe** — nie pozwól macOS zmieniać mikrofonu | ✅ | — | ✅ |
| **Lista blokowanych** — wyklucz wybrane aplikacje z miksowania | ✅ | — | ✅ |
| **Personalizacja** — własne motywy | ✅ | — | ✅ |
| Podpisana i poświadczona przez dewelopera | — | ✅ | ✅ |
| Automatyczne aktualizacje | — | ✅ | ✅ |
| **Wczesny dostęp do wersji beta** — wypróbuj nowości jako pierwszy | — | — | ✅ |

> [!NOTE]
> Prywatne pozostają tylko elementy istniejące wyłącznie na potrzeby Distribution: aktywacja licencji, proces zakupu, ekran powitalny i mechanizm aktualizacji. Żaden z nich nie jest potrzebny do zbudowania ani uruchomienia MacMix, a kompilacje z tego repozytorium ich nie zawierają.

## Instalacja

1. Pobierz [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg) z najnowszego wydania.
2. Otwórz obraz dysku i przeciągnij **MacMix** do folderu **Aplikacje**.
3. Uruchom MacMix i kliknij jego ikonę na pasku menu.

**Wymagania:** macOS Sonoma 14.4 lub nowszy. Miksowanie aplikacji przy pierwszym użyciu prosi o uprawnienie **Nagrywanie dźwięku systemowego**; wszystko inne działa bez niego.

## Prywatność

MacMix przetwarza dźwięk **lokalnie na Twoim Macu**. Nigdy nie nagrywa, nie zapisuje ani nie wysyła dźwięku.

Miksowanie aplikacji opiera się na tapach procesów audio macOS, dlatego macOS prosi o uprawnienie Nagrywanie dźwięku systemowego, zanim MacMix zmieni głośność innej aplikacji. MacMix używa go wyłącznie do lokalnego miksowania w czasie rzeczywistym.

## Kompilacja ze źródeł

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

Wybierz schemat **MacMix** i kliknij **Run**. Xcode automatycznie pobierze pakiety Swift (MenuBarExtraAccess i Swift Atomics). W Twojej kompilacji wszystkie funkcje Studio są odblokowane.

Bez zespołu deweloperskiego Xcode podpisuje aplikację tylko do uruchamiania lokalnie, a macOS może po każdej kompilacji ponownie prosić o uprawnienie **Nagrywanie dźwięku systemowego**. Aby zachować uprawnienie, skopiuj `Config/Local.example.xcconfig` do `Config/Local.xcconfig` i ustaw własne `DEVELOPMENT_TEAM`. Git ignoruje ten plik.

Kompilacje ze źródeł nie aktualizują się same. Aby zaktualizować, pobierz najnowszy kod i zbuduj aplikację ponownie.

Testy regresyjne to zwykłe skrypty, które wymagają tylko narzędzi wiersza poleceń Xcode:

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>Uwagi i ograniczenia</strong></summary>

<br>

- Aplikacje pojawiają się w mikserze tylko wtedy, gdy macOS zgłasza, że odtwarzają dźwięk.
- Poziomy aplikacji są zapisywane lokalnie i przywracane, gdy ta sama aplikacja znów gra.
- Głośność monitora wymaga ekranu obsługującego głośność głośników DDC/CI (VCP `0x62`) przez używany kabel lub stację dokującą. Przejściówki DisplayLink, niektóre połączenia HDMI, telewizory i monitory z wyłączonym DDC/CI w menu ekranowym mogą jej nie udostępniać.
- Nazwy odbiorników AirPlay pochodzą ze źródeł danych urządzenia AirPlay. Jeśli macOS nie poda nazwy, MacMix pokazuje ogólne urządzenie AirPlay zamiast zgadywać.

</details>

## Wesprzyj MacMix

Budowanie ze źródeł jest i pozostanie darmowe. Jeśli MacMix jest częścią Twojego dnia, rozważ zakup **MacMix Studio**: jednorazowej opłaty, która odblokowuje funkcje Studio w Distribution — podpisanej, notaryzowanej aplikacji, która sama się aktualizuje — i bezpośrednio finansuje rozwój MacMix.

<p align="center">
  <a href="https://macmix.jazminli.com/studio"><img src="https://img.shields.io/badge/Kup-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="Kup MacMix Studio"></a>
</p>

Zgłoszenia błędów i pomysły są mile widziane w [Issues](https://github.com/ljmng7/MacMix/issues). Jeśli chcesz współtworzyć kod, przeczytaj [zasady współpracy](../../CONTRIBUTING.md); pull requesty wymagają podpisania umowy licencyjnej współtwórcy (CLA).

## Licencja i znak towarowy

MacMix jest wolnym oprogramowaniem: możesz je rozpowszechniać i/lub modyfikować na warunkach [Powszechnej Licencji Publicznej GNU, wersja 3](../../LICENSE) (GPL-3.0). Wersje do 2.3.2 włącznie zostały wydane na licencji MIT; kod otrzymany na tych warunkach pozostaje na nich dostępny.

**Znak towarowy.** Nazwa „MacMix” i ikona aplikacji MacMix identyfikują oficjalną aplikację i są zastrzeżone dla oficjalnych kompilacji. GPL obejmuje kod, a nie nazwę ani markę. Jeśli rozpowszechniasz fork lub zmodyfikowaną kompilację, nadaj jej inną nazwę, inną ikonę i inny identyfikator pakietu oraz nie przedstawiaj jej jako oficjalnego MacMix. Budowanie i używanie MacMix na własny użytek jest zawsze w porządku.

Ikona aplikacji, zrzuty ekranu i inne elementy marki **nie** są objęte licencją GPL i nie mogą być wykorzystywane bez zgody. Zobacz [Elementy marki](../../BRAND-ASSETS.md).
