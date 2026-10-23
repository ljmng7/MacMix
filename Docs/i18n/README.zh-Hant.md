<p align="center">
  <img src="../images/og-image.webp" alt="MacMix — 你的 Mac 音量，盡在 MacMix。原生 macOS 選單列混音器：系統音量、輸出與輸入裝置、單一 App 的音量，一處搞定。" width="100%">
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest"><img src="https://img.shields.io/github/v/release/ljmng7/MacMix?label=release&color=7A5CFA" alt="Latest release"></a>
  <a href="https://github.com/ljmng7/MacMix/stargazers"><img src="https://img.shields.io/github/stars/ljmng7/MacMix?style=flat&color=F5B301&logo=github" alt="GitHub stars"></a>
  <a href="https://github.com/ljmng7/MacMix/releases"><img src="https://img.shields.io/github/downloads/ljmng7/MacMix/total?color=2F80ED" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14.4%2B-111111?logo=apple&logoColor=white" alt="macOS 14.4+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift, SwiftUI">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-3DA639" alt="GPL-3.0 授權"></a>
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/197969?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-197969" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/197969/daily?language=Swift" alt="ljmng7%2FMacMix | Trendshift" width="250" height="55"/></a>
</p>

<p align="center">
  <a href="../../README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <b>繁體中文</b> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/%E4%B8%8B%E8%BC%89_macOS_%E7%89%88-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="下載 macOS 版 MacMix">
  </a>
</p>

<p align="center">
  <a href="#功能">功能</a> ·
  <a href="#開源版與分發版">開源版與分發版</a> ·
  <a href="#安裝">安裝</a> ·
  <a href="#隱私權">隱私權</a> ·
  <a href="#從原始碼建置">從原始碼建置</a> ·
  <a href="#支援-macmix">支援</a> ·
  <a href="#授權條款與商標">授權條款</a>
</p>

---

## 為什麼選擇 MacMix

macOS 只給你一個音量滑桿，MacMix 把其餘的都補上了：調低吵雜的 App 而不影響音樂，一鍵在 AirPods、喇叭和顯示器之間切換，開會前選好正確的麥克風。這些都在選單列的一個精巧原生面板中完成，不必打開系統設定。

## 功能

### 🔊 音量

- **系統音量**：在選單列直接調整目前輸出裝置的音量。
- **外接顯示器喇叭**：macOS 不提供音量控制時，透過 DDC/CI 調整，並相容音量範圍回報異常的顯示器。
- **真正的 0%**：滑桿拖到 0% 時裝置完全靜音，不會殘留微弱聲音。

### 🎧 裝置

- **切換輸出裝置**：喇叭、耳機、AirPods、顯示器等。
- **依名稱顯示 AirPlay 接收裝置**：每台 HomePod 或 AirPlay 喇叭各占一列，也能從使用中的群組切換到單一裝置。
- **一眼認出的圖像**：AirPods、Beats、HomePod、Apple TV、外接顯示器和 Mac 內建喇叭都有對應圖像，也會使用裝置本身提供的圖像。
- **切換麥克風**：並在同一面板中調整輸入音量。

### 🎚️ 單一 App 混音

- **單獨調低任何 App** 的音量，或視需要提升到最高 **200%**（可在設定中開啟）。
- **記住你的設定**：App 再次播放時自動恢復。
- **找到真正的 App**：透過網頁核心播放的媒體（包括使用 WebKit 播放的 iPad App）會歸到對應的 App 名下。

### 🍃 輕巧

- 安靜地待在選單列，另有可選的設定視窗。
- 原生 SwiftUI，音訊在本機即時處理，無需帳號。
- 官方版透過 Sparkle 自動更新。

## 開源版與分發版

**MacMix 的全部功能都已開源，包括 MacMix Studio。** 自行建置本儲存庫，就能得到功能完整、全部解鎖的 App：不需要授權，不需要帳號，沒有任何保留。

Releases 頁面提供的下載是**分發版**，也就是同一個 App 的官方建置。分發版可免費使用，**MacMix Studio** 是可選的一次性購買，用於在分發版中解鎖 Studio 功能。沒有獨立的「Studio App」，授權只會在同一個 App 中解鎖功能，你的設定原封不動。

| 包含的功能 | <div align="center">從原始碼建置<br><sub>（本儲存庫）</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">分發版<br><sub>（免費）</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">分發版<br><sub>（Studio）</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| 系統、顯示器與單一 App 音量 | ✅ | ✅ | ✅ |
| 輸出、AirPlay 與輸入裝置切換 | ✅ | ✅ | ✅ |
| 單一 App 200% 音量增強 | ✅ | ✅ | ✅ |
| 附帶匿名診斷記錄的意見回饋 | ✅ | ✅ | ✅ |
| **自訂 EQ** — 為每個 App 調音，並儲存常用預設 | ✅ | — | ✅ |
| **多裝置輸出** — 一個 App 同時在多台裝置播放，每台裝置分別調整音量 | ✅ | — | ✅ |
| **Pro 級控制** — 查看藍牙裝置電量，控制聆聽模式與空間音訊 | ✅ | — | ✅ |
| **播放中** — 查看並控制正在播放的媒體 | ✅ | — | ✅ |
| **場景預設** — 儲存裝置與 App 音量，一鍵切換 | ✅ | — | ✅ |
| **系統音量調節** — 接管音量鍵，調整更順暢 | ✅ | — | ✅ |
| **鎖定輸入裝置** — 防止 macOS 自動切換麥克風 | ✅ | — | ✅ |
| **黑名單** — 讓指定的 App 不參與混音 | ✅ | — | ✅ |
| **個人化** — 自訂主題 | ✅ | — | ✅ |
| 開發者簽署與 Apple 公證 | — | ✅ | ✅ |
| 自動更新 | — | ✅ | ✅ |
| **搶先體驗 Beta 版** — 搶先試用新功能 | — | — | ✅ |

> [!NOTE]
> 只有分發版專用的部分保持私有：授權啟用、購買流程、首次引導和更新程式。建置和執行 MacMix 都不需要它們，從本儲存庫建置的 App 也不包含它們。

## 安裝

1. 從最新版本下載 [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg)。
2. 打開磁碟映像檔，將 **MacMix** 拖到「應用程式」檔案夾。
3. 啟動 MacMix，按一下選單列中的圖像。

**系統需求：** macOS Sonoma 14.4 或以上版本。首次使用單一 App 混音時需要授予「**系統錄音**」權限，其他功能不需要此權限。

## 隱私權

MacMix **在你的 Mac 本機**處理音訊，不會錄製、儲存或上傳任何音訊。

單一 App 混音建立在 macOS 的音訊程序 tap 之上，因此 macOS 會在 MacMix 調整其他 App 的音量前要求「系統錄音」權限。MacMix 只將該權限用於本機即時混音。

## 從原始碼建置

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

選擇 **MacMix** scheme，然後按 **Run**。Xcode 會自動解析 Swift 套件（MenuBarExtraAccess 和 Swift Atomics）。你建置出的 App 已解鎖全部 Studio 功能。

沒有設定開發團隊時，Xcode 會以「僅在本機執行」的方式簽署，每次重新建置後 macOS 可能會再次要求「系統錄音」權限。如要保留權限，請把 `Config/Local.example.xcconfig` 複製為 `Config/Local.xcconfig`，並填入你自己的 `DEVELOPMENT_TEAM`。這個檔案不會被 Git 追蹤。

從原始碼建置的 App 不會自動更新。需要更新時，拉取最新原始碼重新建置即可。

回歸測試是一般的腳本，只需要 Xcode 命令列工具：

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>說明與限制</strong></summary>

<br>

- 只有在 macOS 判斷 App 正在輸出音訊時，它才會出現在混音列表中。
- 單一 App 音量儲存在本機，同一 App 再次播放時自動恢復。
- 顯示器音量需要顯示器在目前的線材或擴充座上支援 DDC/CI 喇叭音量（VCP `0x62`）。DisplayLink 轉接器、部分 HDMI 連線、電視，以及在 OSD 選單中關閉 DDC/CI 的顯示器可能無法使用。
- AirPlay 接收裝置的名稱來自 AirPlay 裝置的資料來源。macOS 未提供名稱時，MacMix 會顯示一般的 AirPlay 裝置，而不會猜測名稱。

</details>

## 支援 MacMix

從原始碼建置始終免費。如果 MacMix 已經是你日常的一部分，歡迎購買 **MacMix Studio**：一次性購買，在分發版（經過簽署與公證、可自動更新的官方 App）中解鎖 Studio 功能，並直接支持 MacMix 的開發。

<p align="center">
  <a href="https://macmix.jazminli.com/studio"><img src="https://img.shields.io/badge/%E5%8F%96%E5%BE%97-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="取得 MacMix Studio"></a>
</p>

歡迎在 [Issues](https://github.com/ljmng7/MacMix/issues) 中回報問題或提出建議。貢獻程式碼請參閱[貢獻指南](../../CONTRIBUTING.md)；提交 Pull Request 前需要簽署貢獻者授權協議（CLA）。

## 授權條款與商標

MacMix 是自由軟體：你可以依據 [GNU 通用公眾授權條款第 3 版](../../LICENSE)（GPL-3.0）的條款再散布和修改它。2.3.2 及更早的版本以 MIT 授權條款發佈；你依據這些條款取得的程式碼，仍可繼續按 MIT 授權條款使用。

**商標。**「MacMix」名稱和 MacMix App 圖像用於識別官方 App，僅限官方建置使用。GPL 授權的是程式碼，而不是名稱或品牌。如果你散布 fork 或修改後的建置，請使用不同的名稱、不同的圖像和不同的 Bundle ID，並且不要把它當作官方 MacMix 發佈。自行建置和使用 MacMix 始終沒有問題。

App 圖像、截圖和其他品牌素材**不在** GPL 授權範圍內，未經許可不得重複使用，詳見[品牌素材說明](../../BRAND-ASSETS.md)。
