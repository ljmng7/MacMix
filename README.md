<p align="center">
  <img src="Docs/images/og-image.webp" alt="MacMix — Your Mac's sound. All in MacMix. A native macOS menu bar mixer for system volume, output and input devices, and per-app sound." width="100%">
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest"><img src="https://img.shields.io/github/v/release/ljmng7/MacMix?label=release&color=7A5CFA" alt="Latest release"></a>
  <a href="https://github.com/ljmng7/MacMix/stargazers"><img src="https://img.shields.io/github/stars/ljmng7/MacMix?style=flat&color=F5B301&logo=github" alt="GitHub stars"></a>
  <a href="https://github.com/ljmng7/MacMix/releases"><img src="https://img.shields.io/github/downloads/ljmng7/MacMix/total?color=2F80ED" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14.4%2B-111111?logo=apple&logoColor=white" alt="macOS 14.4 or later">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift and SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-3DA639" alt="GPL-3.0 licensed code"></a>
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/197969?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-197969" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/197969/daily?language=Swift" alt="ljmng7%2FMacMix | Trendshift" width="250" height="55"/></a>
</p>

<p align="center">
  <b>English</b> · <a href="Docs/i18n/README.zh-Hans.md">简体中文</a> · <a href="Docs/i18n/README.zh-Hant.md">繁體中文</a> · <a href="Docs/i18n/README.ja.md">日本語</a> · <a href="Docs/i18n/README.ko.md">한국어</a> · <a href="Docs/i18n/README.fr.md">Français</a> · <a href="Docs/i18n/README.de.md">Deutsch</a> · <a href="Docs/i18n/README.es.md">Español</a> · <a href="Docs/i18n/README.it.md">Italiano</a> · <a href="Docs/i18n/README.pt-BR.md">Português (Brasil)</a> · <a href="Docs/i18n/README.ru.md">Русский</a> · <a href="Docs/i18n/README.ar.md">العربية</a> · <a href="Docs/i18n/README.hi.md">हिन्दी</a> · <a href="Docs/i18n/README.id.md">Bahasa Indonesia</a> · <a href="Docs/i18n/README.th.md">ไทย</a> · <a href="Docs/i18n/README.vi.md">Tiếng Việt</a> · <a href="Docs/i18n/README.tr.md">Türkçe</a> · <a href="Docs/i18n/README.nl.md">Nederlands</a> · <a href="Docs/i18n/README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/Download_for_macOS-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="Download MacMix for macOS">
  </a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#open-source-and-distribution">Open Source vs Distribution</a> ·
  <a href="#install">Install</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#build-from-source">Build from Source</a> ·
  <a href="#support-macmix">Support</a> ·
  <a href="#license-and-trademark">License</a>
</p>

---

## Why MacMix

macOS gives you one volume slider. MacMix gives you the rest: turn a noisy app down without touching your music, jump between AirPods, speakers and a monitor in one click, and pick the right microphone before a call — all from a compact native panel in the menu bar, without opening System Settings.

## Features

### 🔊 Volume

- **System volume** for the current output device, right in the menu bar.
- **External display speakers** over DDC/CI when macOS offers no volume control, with compatibility fixes for monitors that report unusual ranges.
- **True zero** — dragging a slider to 0% silences the device instead of leaving a faint residual level.

### 🎧 Devices

- **Switch outputs** between speakers, headphones, AirPods, displays and more.
- **AirPlay receivers by name** — each HomePod or AirPlay speaker gets its own row, and you can switch to a single receiver from an active group.
- **Recognizable icons** for AirPods, Beats, HomePod, Apple TV, external displays and your Mac's own speakers, plus the icon a device provides itself.
- **Switch microphones** and adjust input volume from the same panel.

### 🎚️ Per-App Mixing

- **Turn any app down** while it is playing, or boost it up to **200%** (optional, in Settings).
- **Remembers your levels** and restores them when the app plays again.
- **Finds the real app** behind web-based playback, including iPad apps that play media through WebKit.

### 🍃 Light by Design

- Lives quietly in the menu bar, with an optional window for settings.
- Native SwiftUI, audio processed locally in real time, no account required.
- The official app updates itself through Sparkle.

## Open Source and Distribution

**Every MacMix feature is open source, MacMix Studio included.** Build this repository yourself and you get the complete app with every feature unlocked — no license, no account, nothing held back.

The download on the Releases page is **Distribution**: the official build of the same app. It is free to use, with **MacMix Studio** as an optional one-time purchase that unlocks the Studio features in that build. There is no separate "Studio app"; a license unlocks features in the same app, and your settings stay where they are.

| Included features | <div align="center">Built from source<br><sub>(this repository)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(free)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| System, display and per-app volume | ✅ | ✅ | ✅ |
| Output, AirPlay and input device switching | ✅ | ✅ | ✅ |
| 200% per-app boost | ✅ | ✅ | ✅ |
| Feedback reports with anonymized diagnostic logs | ✅ | ✅ | ✅ |
| **Custom EQ** per app, with saved presets | ✅ | — | ✅ |
| **Multi-Device Output** — one app on several devices, each with its own volume | ✅ | — | ✅ |
| **Pro Control** — Bluetooth battery levels, Listening Mode and Spatial Audio | ✅ | — | ✅ |
| **Now Playing** — view and control the current media | ✅ | — | ✅ |
| **Scene Presets** — save devices and app volumes, switch in one click | ✅ | — | ✅ |
| **System Volume Controls** — take over the volume keys for smoother control | ✅ | — | ✅ |
| **Input Device Lock** — keep macOS from switching your microphone | ✅ | — | ✅ |
| **Blacklist** — leave selected apps out of mixing | ✅ | — | ✅ |
| **Personalization** — custom themes | ✅ | — | ✅ |
| Signed and notarized by the developer | — | ✅ | ✅ |
| Automatic updates | — | ✅ | ✅ |
| **Beta Early Access** — try new features first | — | — | ✅ |

> [!NOTE]
> Only the parts that exist solely for Distribution are kept private: license activation, the purchase flow, onboarding and the updater. None of them is needed to build or run MacMix, and builds from this repository contain none of them.

## Install

1. Download [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg) from the latest release.
2. Open the disk image and drag **MacMix** into **Applications**.
3. Launch MacMix and click its icon in the menu bar.

**Requirements:** macOS Sonoma 14.4 or later. Per-app mixing asks for **System Audio Recording** permission the first time you use it; everything else works without it.

## Privacy

MacMix processes audio **locally on your Mac**. It never records, saves or uploads audio.

Per-app mixing is built on macOS audio process taps, which is why macOS asks for System Audio Recording permission before MacMix can change another app's volume. MacMix uses that permission only for real-time local mixing.

## Build from Source

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

Select the **MacMix** scheme and press **Run**. Xcode resolves the Swift packages (MenuBarExtraAccess and Swift Atomics) automatically. Every Studio feature is unlocked in your build.

Without a development team, Xcode signs the app to run locally, and macOS may ask for System Audio Recording permission again after each rebuild. To keep the permission, copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig` and set your own `DEVELOPMENT_TEAM`. The file is ignored by Git.

Builds from source don't update themselves. To update, pull the latest source and build again.

The regression tests are plain scripts that only need the Xcode command line tools:

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>Notes and limitations</strong></summary>

<br>

- Apps appear in the mixer only while macOS reports that they are producing audio.
- Per-app levels are stored locally and restored when the same app plays again.
- Display volume needs a monitor that supports DDC/CI speaker volume (VCP `0x62`) over the current cable or dock. DisplayLink adapters, some HDMI paths, TVs and displays with DDC/CI turned off in their on-screen menu may not expose it.
- AirPlay receiver names come from the AirPlay device's data sources. When macOS does not report a receiver's name, MacMix shows the plain AirPlay device instead of guessing.

</details>

## Support MacMix

Building from source is, and will stay, free. If MacMix is part of your day, consider buying **MacMix Studio**: a one-time purchase that unlocks the Studio features in Distribution — the signed, notarized app that keeps itself up to date — and directly funds MacMix's development.

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/Get-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="Get MacMix Studio"></a>
</p>

Bug reports and ideas are welcome in [Issues](https://github.com/ljmng7/MacMix/issues). To contribute code, see [Contributing](CONTRIBUTING.md); pull requests need a signed Contributor License Agreement.

## License and Trademark

MacMix is free software: you can redistribute it and/or modify it under the terms of the [GNU General Public License, version 3](LICENSE) (GPL-3.0). Versions up to and including 2.3.2 were released under the MIT License; code you received under those terms stays available under them.

**Trademark.** The name "MacMix" and the MacMix app icon identify the official app and are reserved for official builds. The GPL covers the code, not the name or brand. If you distribute a fork or a modified build, give it a different name, a different icon and a different bundle identifier, and don't present it as the official MacMix. Building and running MacMix for yourself is always fine.

The app icon, screenshots and other brand assets are **not** covered by the GPL and may not be reused without permission — see [Brand Assets](BRAND-ASSETS.md).
