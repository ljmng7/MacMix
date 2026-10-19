<p align="center">
  <img src="Docs/images/og-image.webp" alt="MacMix — 你的 Mac 音量，盡在 MacMix。原生 macOS 選單列混音器：系統音量、輸出與輸入裝置、單一 App 的音量，一處搞定。" width="100%">
  <br>
  <sub>截圖為分發版，部分功能需要 MacMix Studio。</sub>
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
  <a href="README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <b>繁體中文</b> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
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
  <a href="#支援-macmix">支援</a>
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
- 透過 Sparkle 自動更新。

## 開源版與分發版

本儲存庫包含 MacMix **免費開源的核心部分**。Releases 頁面提供的下載是**分發版**：同一個 App，免費使用，**MacMix Studio** 是可選的一次性升級。沒有獨立的「Studio App」，授權只會在同一個 App 中解鎖額外功能，你的設定原封不動。

| 包含的功能 | <div align="center">開源版<br><sub>（本儲存庫）</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">分發版<br><sub>（免費）</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">分發版<br><sub>（Studio）</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| 系統、顯示器與單一 App 音量 | ✅ | ✅ | ✅ |
| 輸出、AirPlay 與輸入裝置切換 | ✅ | ✅ | ✅ |
| 單一 App 200% 音量增強 | ✅ | ✅ | ✅ |
| 開發者簽署與 Apple 公證 | — | ✅ | ✅ |
| 附帶匿名診斷記錄的意見回饋 | — | ✅ | ✅ |
| **自訂 EQ** — 為每個 App 調音，並儲存常用預設 | — | — | ✅ |
| **多裝置輸出** — 一個 App 同時在多台裝置播放，每台裝置分別調整音量 | — | — | ✅ |
| **Pro 級控制** — 查看藍牙裝置電量，控制聆聽模式與空間音訊 | — | — | ✅ |
| **播放中** — 查看並控制正在播放的媒體 | — | — | ✅ |
| **場景預設** — 儲存裝置與 App 音量，一鍵切換 | — | — | ✅ |
| **系統音量調節** — 接管音量鍵，調整更順暢 | — | — | ✅ |
| **鎖定輸入裝置** — 防止 macOS 自動切換麥克風 | — | — | ✅ |
| **黑名單** — 讓指定的 App 不參與混音 | — | — | ✅ |
| **個人化** — 自訂主題 | — | — | ✅ |
| **搶先體驗 Beta 版** — 搶先試用新功能 | — | — | ✅ |

> [!NOTE]
> Studio 功能為私有開發，不包含在本儲存庫中。已經免費提供的功能（包括單一 App 混音，以及 2.0 版之前的全部功能）將始終免費並保持開源。公共核心的修正會先在分發版中驗證，再同步到本儲存庫，因此這裡的原始碼可能略晚於最新版本。

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

選擇 **MacMix** scheme，然後按 **Run**。Xcode 會自動解析 Swift 套件（Sparkle 和 Swift Atomics）。

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

如果 MacMix 已經是你日常的一部分，歡迎升級到 **MacMix Studio**。一次性購買即可解鎖上方的全部功能，也直接支持免費開源的核心部分。

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/%E5%8F%96%E5%BE%97-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="取得 MacMix Studio"></a>
</p>

歡迎在 [Issues](https://github.com/ljmng7/MacMix/issues) 中回報問題或提出建議。

## 授權條款

原始碼以 [MIT License](LICENSE) 發佈。App 圖像、截圖和其他品牌素材**不在** MIT 授權範圍內，未經許可不得重複使用，詳見[品牌素材說明](BRAND-ASSETS.md)。
