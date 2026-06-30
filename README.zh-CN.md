# MacMix

语言：[English](README.md) | 简体中文

MacMix 是一款轻量级 macOS 菜单栏音频混音工具，可以快速控制系统音量、音频设备、麦克风输入以及每个应用的输出音量。

<p align="center">
  <img src="Docs/images/screenshot.png" alt="MacMix 菜单栏音频混音器截图" width="440">
</p>

## 功能

- 在菜单栏中控制系统输出音量。
- 快速切换可用的输出设备。
- 快速切换可用的输入设备。
- 调整麦克风输入音量。
- 实时调节单个应用的音量。
- 可按需显示或隐藏菜单栏面板中的输出、输入区域。
- 支持开机自动启动。
- 使用原生 SwiftUI 构建，界面贴近 macOS。

## 下载

前往 [GitHub Releases 页面](https://github.com/ljmng7/MacMix/releases/latest) 下载最新版本。

## 系统要求

- macOS 15.0 或更高版本。
- 仅在使用单个应用音量混音时，需要授予“系统录音”权限。

## 安装

1. 从最新 Release 下载 `.dmg` 文件。
2. 打开磁盘映像。
3. 将 MacMix 拖入“应用程序”文件夹。
4. 启动 MacMix，然后通过菜单栏中的音量图标打开混音面板。

## 隐私

MacMix 只在你的 Mac 本机进行音频混音。应用请求“系统录音”权限，是因为 macOS 要求应用在处理其他应用音频前必须获得该权限，以便实现单个应用音量控制。

MacMix 不会录制、保存或上传音频。

## 从源码构建

1. 克隆仓库：

   ```sh
   git clone https://github.com/ljmng7/MacMix.git
   cd MacMix
   ```

2. 用 Xcode 打开 `MacMix.xcodeproj`。
3. 选择 `MacMix` scheme。
4. 构建并运行应用。

## 说明

单个应用混音依赖 macOS 的音频进程 tap，因此应用通常只有在正在输出音频时才会出现在混音列表中。
