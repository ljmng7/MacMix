<p align="center">
  <img src="../images/og-image.webp" alt="MacMix — Semua suara Mac Anda, ada di MacMix. Mixer bawaan untuk bar menu macOS: volume sistem, perangkat output dan input, serta suara setiap app." width="100%">
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
  <a href="../../README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <b>Bahasa Indonesia</b> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/Unduh_untuk_macOS-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="Unduh MacMix untuk macOS">
  </a>
</p>

<p align="center">
  <a href="#fitur">Fitur</a> ·
  <a href="#sumber-terbuka-dan-distribution">Sumber terbuka vs. Distribution</a> ·
  <a href="#instalasi">Instalasi</a> ·
  <a href="#privasi">Privasi</a> ·
  <a href="#build-dari-kode-sumber">Build dari kode sumber</a> ·
  <a href="#dukung-macmix">Dukung</a> ·
  <a href="#lisensi-dan-merek-dagang">Lisensi</a>
</p>

---

## Mengapa MacMix

macOS memberi Anda satu penggeser volume. MacMix memberi sisanya: kecilkan app yang berisik tanpa menyentuh musik Anda, beralih antara AirPods, speaker, dan monitor dengan satu klik, lalu pilih mikrofon yang tepat sebelum panggilan. Semuanya dari panel bawaan yang ringkas di bar menu, tanpa membuka Pengaturan Sistem.

## Fitur

### 🔊 Volume

- **Volume sistem** untuk perangkat output saat ini, langsung dari bar menu.
- **Speaker layar eksternal** melalui DDC/CI saat macOS tidak menyediakan kontrol volume, dengan perbaikan untuk monitor yang melaporkan rentang tidak biasa.
- **Nol sungguhan**: menggeser ke 0% membuat perangkat benar-benar senyap, tanpa sisa suara samar.

### 🎧 Perangkat

- **Ganti output** antara speaker, headphone, AirPods, layar, dan lainnya.
- **Penerima AirPlay dengan nama**: setiap HomePod atau speaker AirPlay punya barisnya sendiri, dan Anda bisa beralih dari grup aktif ke satu penerima.
- **Ikon yang mudah dikenali** untuk AirPods, Beats, HomePod, Apple TV, layar eksternal, dan speaker bawaan Mac Anda, ditambah ikon yang disediakan perangkat itu sendiri.
- **Ganti mikrofon** dan atur volume input dari panel yang sama.

### 🎚️ Mixing per app

- **Kecilkan app apa pun** saat sedang diputar, atau naikkan hingga **200%** (opsional, di Pengaturan).
- **Mengingat level Anda** dan memulihkannya saat app diputar lagi.
- **Menemukan app sebenarnya** di balik pemutaran web, termasuk app iPad yang memutar media melalui WebKit.

### 🍃 Ringan sejak awal

- Berjalan tenang di bar menu, dengan jendela pengaturan opsional.
- SwiftUI bawaan, audio diproses secara lokal dan real time, tanpa akun.
- App resmi memperbarui dirinya sendiri melalui Sparkle.

## Sumber terbuka dan Distribution

**Semua fitur MacMix bersumber terbuka, termasuk MacMix Studio.** Bangun repositori ini sendiri dan Anda mendapatkan app lengkap dengan semua fitur terbuka: tanpa lisensi, tanpa akun, tanpa ada yang ditahan.

Unduhan di halaman Releases adalah **Distribution**: build resmi dari app yang sama. App ini gratis digunakan, dengan **MacMix Studio** sebagai pembelian opsional sekali bayar yang membuka fitur Studio di build tersebut. Tidak ada “app Studio” terpisah; lisensi membuka fitur di app yang sama, dan pengaturan Anda tetap utuh.

| Fitur yang disertakan | <div align="center">Dibangun dari kode sumber<br>terbuka<br><sub>(repositori ini)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(gratis)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| Volume sistem, layar, dan per app | ✅ | ✅ | ✅ |
| Peralihan perangkat output, AirPlay, dan input | ✅ | ✅ | ✅ |
| Penguatan 200% per app | ✅ | ✅ | ✅ |
| Laporan masukan dengan log diagnostik anonim | ✅ | ✅ | ✅ |
| **EQ Kustom** — setel suara setiap app dan simpan preset Anda | ✅ | — | ✅ |
| **Output Multi-Perangkat** — satu app di beberapa perangkat sekaligus, masing-masing dengan volumenya sendiri | ✅ | — | ✅ |
| **Kontrol Pro** — level baterai perangkat Bluetooth, Mode Mendengarkan, dan Audio Spasial | ✅ | — | ✅ |
| **Sedang Diputar** — lihat dan kontrol media yang sedang diputar | ✅ | — | ✅ |
| **Preset Adegan** — simpan perangkat dan volume app, lalu beralih dengan satu klik | ✅ | — | ✅ |
| **Kontrol Volume Sistem** — ambil alih tombol volume untuk kontrol yang lebih halus | ✅ | — | ✅ |
| **Kunci Perangkat Input** — cegah macOS mengganti mikrofon Anda | ✅ | — | ✅ |
| **Daftar Blokir** — keluarkan app tertentu dari mixing | ✅ | — | ✅ |
| **Personalisasi** — tema kustom | ✅ | — | ✅ |
| Ditandatangani dan dinotarisasi oleh pengembang | — | ✅ | ✅ |
| Pembaruan otomatis | — | ✅ | ✅ |
| **Akses Awal Beta** — coba fitur baru lebih dulu | — | — | ✅ |

> [!NOTE]
> Hanya bagian yang ada khusus untuk Distribution yang tetap privat: aktivasi lisensi, alur pembelian, pengenalan awal, dan pembaru. Tidak satu pun diperlukan untuk membangun atau menjalankan MacMix, dan build dari repositori ini tidak berisi satu pun di antaranya.

## Instalasi

1. Unduh [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg) dari rilis terbaru.
2. Buka image disk dan seret **MacMix** ke folder **Aplikasi**.
3. Buka MacMix dan klik ikonnya di bar menu.

**Persyaratan:** macOS Sonoma 14.4 atau yang lebih baru. Mixing per app meminta izin **Perekaman Audio Sistem** saat pertama kali digunakan; fitur lain berfungsi tanpanya.

## Privasi

MacMix memproses audio **secara lokal di Mac Anda**. MacMix tidak pernah merekam, menyimpan, atau mengunggah audio.

Mixing per app dibangun di atas tap proses audio macOS, itulah sebabnya macOS meminta izin Perekaman Audio Sistem sebelum MacMix dapat mengubah volume app lain. MacMix hanya menggunakan izin itu untuk mixing lokal secara real time.

## Build dari kode sumber

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

Pilih skema **MacMix** lalu tekan **Run**. Xcode akan mengambil paket Swift (MenuBarExtraAccess dan Swift Atomics) secara otomatis. Semua fitur Studio terbuka di build Anda.

Tanpa tim pengembang, Xcode menandatangani app hanya untuk dijalankan secara lokal, dan macOS mungkin meminta izin **Perekaman Audio Sistem** lagi setiap kali Anda membangun ulang. Agar izin tetap tersimpan, salin `Config/Local.example.xcconfig` menjadi `Config/Local.xcconfig` dan isi `DEVELOPMENT_TEAM` Anda sendiri. File ini diabaikan oleh Git.

Build dari kode sumber tidak memperbarui dirinya sendiri. Untuk memperbarui, ambil kode sumber terbaru lalu bangun ulang.

Tes regresi adalah skrip biasa yang hanya memerlukan alat baris perintah Xcode:

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>Catatan dan batasan</strong></summary>

<br>

- App hanya muncul di mixer selama macOS melaporkan bahwa app tersebut mengeluarkan audio.
- Level per app disimpan secara lokal dan dipulihkan saat app yang sama diputar lagi.
- Volume layar memerlukan monitor yang mendukung volume speaker DDC/CI (VCP `0x62`) melalui kabel atau dock yang digunakan. Adaptor DisplayLink, beberapa jalur HDMI, TV, dan layar dengan DDC/CI dinonaktifkan di menu OSD mungkin tidak menyediakannya.
- Nama penerima AirPlay berasal dari sumber data perangkat AirPlay. Jika macOS tidak melaporkan nama penerima, MacMix menampilkan perangkat AirPlay biasa alih-alih menebak.

</details>

## Dukung MacMix

Membangun dari kode sumber gratis dan akan tetap gratis. Jika MacMix sudah menjadi bagian dari hari Anda, pertimbangkan untuk membeli **MacMix Studio**: pembelian sekali bayar yang membuka fitur Studio di Distribution — app yang ditandatangani, dinotarisasi, dan selalu memperbarui dirinya — serta langsung mendanai pengembangan MacMix.

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/Dapatkan-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="Dapatkan MacMix Studio"></a>
</p>

Laporan bug dan ide sangat diterima di [Issues](https://github.com/ljmng7/MacMix/issues). Untuk berkontribusi kode, lihat [panduan kontribusi](../../CONTRIBUTING.md); pull request memerlukan Perjanjian Lisensi Kontributor (CLA) yang sudah ditandatangani.

## Lisensi dan merek dagang

MacMix adalah perangkat lunak bebas: Anda boleh mendistribusikan ulang dan/atau mengubahnya sesuai ketentuan [GNU General Public License versi 3](../../LICENSE) (GPL-3.0). Versi hingga dan termasuk 2.3.2 dirilis di bawah Lisensi MIT; kode yang Anda terima dengan ketentuan tersebut tetap tersedia di bawahnya.

**Merek dagang.** Nama “MacMix” dan ikon app MacMix menandai app resmi dan hanya untuk build resmi. GPL mencakup kode, bukan nama atau merek. Jika Anda mendistribusikan fork atau build yang dimodifikasi, beri nama lain, ikon lain, dan bundle identifier lain, dan jangan menampilkannya sebagai MacMix resmi. Membangun dan memakai MacMix untuk diri sendiri selalu diperbolehkan.

Ikon app, tangkapan layar, dan aset merek lainnya **tidak** tercakup dalam GPL dan tidak boleh digunakan ulang tanpa izin. Lihat [Aset merek](../../BRAND-ASSETS.md).
