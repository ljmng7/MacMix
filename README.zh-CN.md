<p align="center">
  <img src="Docs/images/og-image.webp" alt="MacMix — 你的Mac音量，尽在MacMix。原生 macOS 菜单栏混音器：系统音量、输出与输入设备、单个应用的音量，一处搞定。" width="100%">
  <br>
  <sub>截图为分发版，部分功能需要 MacMix Studio。</sub>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest"><img src="https://img.shields.io/github/v/release/ljmng7/MacMix?label=release&color=7A5CFA" alt="最新版本"></a>
  <a href="https://github.com/ljmng7/MacMix/stargazers"><img src="https://img.shields.io/github/stars/ljmng7/MacMix?style=flat&color=F5B301&logo=github" alt="GitHub Star 数"></a>
  <a href="https://github.com/ljmng7/MacMix/releases"><img src="https://img.shields.io/github/downloads/ljmng7/MacMix/total?color=2F80ED" alt="下载量"></a>
  <img src="https://img.shields.io/badge/macOS-14.4%2B-111111?logo=apple&logoColor=white" alt="macOS 14.4 或更高版本">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift 与 SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/code-MIT-3DA639" alt="代码采用 MIT 许可证"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <b>简体中文</b> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD_macOS_%E7%89%88-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="下载 macOS 版 MacMix">
  </a>
</p>

<p align="center">
  <a href="#功能">功能</a> ·
  <a href="#开源版与分发版">开源版与分发版</a> ·
  <a href="#安装">安装</a> ·
  <a href="#隐私">隐私</a> ·
  <a href="#从源码构建">从源码构建</a> ·
  <a href="#支持-macmix">支持</a>
</p>

---

## 为什么选择 MacMix

macOS 只给你一个音量滑块，MacMix 把剩下的都补上了：调低吵闹的应用而不影响音乐，一键在 AirPods、音箱和显示器之间切换，开会前选好正确的麦克风。这些都在菜单栏的一个紧凑原生面板里完成，不用打开系统设置。

## 功能

### 🔊 音量

- **系统音量**：在菜单栏直接调节当前输出设备的音量。
- **外接显示器扬声器**：macOS 不提供音量控制时，通过 DDC/CI 调节，并兼容音量范围上报异常的显示器。
- **真正的 0%**：滑块拖到 0% 时设备完全静音，不会残留微弱声音。

### 🎧 设备

- **切换输出设备**：扬声器、耳机、AirPods、显示器等。
- **按名称显示 AirPlay 接收设备**：每台 HomePod 或 AirPlay 音箱单独一行，也能从正在使用的组合中切换到单台设备。
- **一眼认出的图标**：AirPods、Beats、HomePod、Apple TV、外接显示器和 Mac 自带扬声器都有对应图标，也会使用设备自身提供的图标。
- **切换麦克风**：并在同一面板中调节输入音量。

### 🎚️ 单应用混音

- **单独调低任意应用**的音量，或按需提升到最高 **200%**（可在设置中开启）。
- **记住你的设置**：应用再次播放时自动恢复。
- **找到真正的应用**：通过网页内核播放的媒体（包括使用 WebKit 播放的 iPad 应用）会归到对应的应用名下。

### 🍃 轻巧

- 安静地待在菜单栏，另有可选的设置窗口。
- 原生 SwiftUI，音频在本机实时处理，无需账户。
- 通过 Sparkle 自动更新。

## 开源版与分发版

本仓库包含 MacMix **免费开源的核心部分**。Releases 页面提供的下载是**分发版**：同一个应用，免费使用，**MacMix Studio** 是可选的一次性升级。不存在单独的 “Studio 应用”，许可证只会在同一个应用里解锁额外功能，你的设置原样保留。

| 包含的功能 | <div align="center">&nbsp;&nbsp;&nbsp;开源版&nbsp;&nbsp;&nbsp;<br><sub>（本仓库）</sub></div> | <div align="center">&nbsp;&nbsp;&nbsp;分发版&nbsp;&nbsp;&nbsp;<br><sub>（免费）</sub></div> | <div align="center">&nbsp;&nbsp;&nbsp;分发版&nbsp;&nbsp;&nbsp;<br><sub>（Studio）</sub></div> |
| --- | :---: | :---: | :---: |
| 系统、显示器与单应用音量 | ✅ | ✅ | ✅ |
| 输出、AirPlay 与输入设备切换 | ✅ | ✅ | ✅ |
| 单应用 200% 音量增强 | ✅ | ✅ | ✅ |
| 开发者签名与 Apple 公证 | — | ✅ | ✅ |
| 附带匿名诊断日志的问题反馈 | — | ✅ | ✅ |
| **自定义 EQ**：为每个应用调音，并保存常用预设 | — | — | ✅ |
| **多设备输出**：一个应用同时在多台设备播放，每台设备单独调音量 | — | — | ✅ |
| **Pro 级控制**：查看蓝牙设备电量，控制聆听模式与空间音频 | — | — | ✅ |
| **播放中**：查看并控制正在播放的媒体 | — | — | ✅ |
| **场景预设**：保存设备与应用音量，一键切换 | — | — | ✅ |
| **系统音量调节**：接管音量键，调节更顺滑 | — | — | ✅ |
| **锁定输入设备**：防止 macOS 自动切换麦克风 | — | — | ✅ |
| **黑名单**：让指定应用不参与混音 | — | — | ✅ |
| **个性化**：自定义主题 | — | — | ✅ |
| **抢先体验 Beta 版**：抢先试用新功能 | — | — | ✅ |

> [!NOTE]
> Studio 功能为私有开发，不包含在本仓库中。已经免费提供的功能（包括单应用混音，以及 2.0 版本之前的全部功能）将始终免费并保持开源。公共核心的修复会在分发版中验证后再同步到本仓库，因此这里的源码可能略晚于最新发布版本。

## 安装

1. 从最新版本下载 [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg)。
2. 打开磁盘映像，把 **MacMix** 拖入“应用程序”文件夹。
3. 启动 MacMix，点击菜单栏中的图标。

**系统要求：** macOS Sonoma 14.4 或更高版本。首次使用单应用混音时需要授予“**系统录音**”权限，其他功能无需此权限。

## 隐私

MacMix **在你的 Mac 本机**处理音频，不会录制、保存或上传任何音频。

单应用混音基于 macOS 的音频进程 tap，因此 macOS 会在 MacMix 调节其他应用音量前请求“系统录音”权限。MacMix 只将该权限用于本机实时混音。

## 从源码构建

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

选择 **MacMix** scheme 并点击 **Run**。Xcode 会自动解析 Swift 依赖包（Sparkle 和 Swift Atomics）。

回归测试是普通脚本，只需要 Xcode 命令行工具：

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>说明与限制</strong></summary>

<br>

- 只有在 macOS 判断应用正在输出音频时，它才会出现在混音列表中。
- 单应用音量保存在本机，同一应用再次播放时自动恢复。
- 显示器音量需要显示器在当前线材或扩展坞上支持 DDC/CI 扬声器音量（VCP `0x62`）。DisplayLink 转接器、部分 HDMI 链路、电视，以及在 OSD 菜单中关闭了 DDC/CI 的显示器可能无法使用。
- AirPlay 接收设备的名称来自 AirPlay 设备的数据源。macOS 未提供名称时，MacMix 会显示普通的 AirPlay 设备，而不会猜测名称。

</details>

## 支持 MacMix

如果 MacMix 已经成为你日常的一部分，欢迎升级到 **MacMix Studio**。一次性购买即可解锁上面的全部功能，也直接支持免费开源的核心部分。

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/%E8%8E%B7%E5%8F%96-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="获取 MacMix Studio"></a>
</p>

欢迎在 [Issues](https://github.com/ljmng7/MacMix/issues) 中反馈问题或提出建议。

## 许可证

源代码基于 [MIT License](LICENSE) 发布。应用图标、截图和其他品牌素材**不在** MIT 授权范围内，未经许可不得复用，详见 [品牌素材说明](BRAND-ASSETS.md)。
