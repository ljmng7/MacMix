<p align="center">
  <img src="Docs/images/og-image.webp" alt="MacMix — Your Mac's sound. All in MacMix. A native macOS menu bar mixer for system volume, output and input devices, and per-app sound." width="100%">
  <br>
  <sub>Screenshot shows the distribution build. Some features require MacMix Studio.</sub>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest"><img src="https://img.shields.io/github/v/release/ljmng7/MacMix?label=release&color=7A5CFA" alt="Latest release"></a>
  <a href="https://github.com/ljmng7/MacMix/stargazers"><img src="https://img.shields.io/github/stars/ljmng7/MacMix?style=flat&color=F5B301&logo=github" alt="GitHub stars"></a>
  <a href="https://github.com/ljmng7/MacMix/releases"><img src="https://img.shields.io/github/downloads/ljmng7/MacMix/total?color=2F80ED" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14.4%2B-111111?logo=apple&logoColor=white" alt="macOS 14.4 or later">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift and SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/code-MIT-3DA639" alt="MIT licensed code"></a>
</p>

<p align="center">
  <b>English</b> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/Download_for_macOS-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="Download MacMix for macOS">
  </a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#open-source-and-distribution-builds">Open Source vs Distribution</a> ·
  <a href="#install">Install</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#build-from-source">Build from Source</a> ·
  <a href="#support-macmix">Support</a>
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
- Automatic updates through Sparkle.

## Open Source and Distribution Builds

This repository contains the **free, open-source core** of MacMix. The download on the Releases page is the **distribution build**: one app that is free to use, with **MacMix Studio** as an optional one-time upgrade. There is no separate "Studio app" — a license unlocks extra features in the same app, and your settings stay where they are.

| Included features | <div align="center">Open source<br><sub>(this repository)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution build<br><sub>(free)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution build<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| System, display and per-app volume | ✅ | ✅ | ✅ |
| Output, AirPlay and input device switching | ✅ | ✅ | ✅ |
| 200% per-app boost | ✅ | ✅ | ✅ |
| Signed and notarized by the developer | — | ✅ | ✅ |
| Feedback reports with anonymized diagnostic logs | — | ✅ | ✅ |
| **Custom EQ** per app, with saved presets | — | — | ✅ |
| **Multi-Device Output** — one app on several devices, each with its own volume | — | — | ✅ |
| **Pro Control** — Bluetooth battery levels, Listening Mode and Spatial Audio | — | — | ✅ |
| **Now Playing** — view and control the current media | — | — | ✅ |
| **Scene Presets** — save devices and app volumes, switch in one click | — | — | ✅ |
| **System Volume Controls** — take over the volume keys for smoother control | — | — | ✅ |
| **Input Device Lock** — keep macOS from switching your microphone | — | — | ✅ |
| **Blacklist** — leave selected apps out of mixing | — | — | ✅ |
| **Personalization** — custom themes | — | — | ✅ |
| **Beta Early Access** — try new features first | — | — | ✅ |

> [!NOTE]
> Studio features are developed privately and are not part of this repository. Everything that has been free — including per-app mixing and every feature available before version 2.0 — will stay free and open source. Fixes to the shared core reach this repository after they have been validated in the distribution build, so the source here can trail the latest release a little.

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

Select the **MacMix** scheme and press **Run**. Xcode resolves the Swift packages (Sparkle and Swift Atomics) automatically.

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

If MacMix is part of your day, consider upgrading to **MacMix Studio**. It is a one-time purchase that unlocks the features above and funds the free, open-source core.

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/Get-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="Get MacMix Studio"></a>
</p>

Bug reports and ideas are welcome in [Issues](https://github.com/ljmng7/MacMix/issues).

## License

The source code is released under the [MIT License](LICENSE). The app icon, screenshots and other brand assets are **not** covered by the MIT License and may not be reused without permission — see [Brand Assets](BRAND-ASSETS.md).
