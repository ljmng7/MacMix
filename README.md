# MacMix

Language: English | [简体中文](README.zh-CN.md)

MacMix is a lightweight macOS menu bar audio mixer for quickly controlling system volume, audio devices, microphone input, and per-app output levels.

<p align="center">
  <img src="Docs/images/screenshot.png" alt="MacMix menu bar audio mixer screenshot" width="440">
</p>

## Features

- Control system output volume from the menu bar.
- Switch between available output devices.
- Switch between available input devices.
- Adjust microphone input volume.
- Mix individual app volumes in real time.
- Keep the menu bar panel focused by showing or hiding output and input sections.
- Launch automatically at login.
- Uses a native SwiftUI interface designed for macOS.

## Download

Download the latest release from the [GitHub Releases page](https://github.com/ljmng7/MacMix/releases/latest).

## Requirements

- macOS 15.0 or later.
- System Audio Recording permission is required only when using per-app audio mixing.

## Installation

1. Download the `.dmg` file from the latest release.
2. Open the disk image.
3. Drag MacMix into your Applications folder.
4. Launch MacMix and use the menu bar volume icon to open the mixer.

## Privacy

MacMix performs audio mixing locally on your Mac. The app requests System Audio Recording permission because macOS requires that permission before an app can process another app's audio for per-app volume control.

MacMix does not record, save, or upload audio.

## Build From Source

1. Clone the repository:

   ```sh
   git clone https://github.com/ljmng7/MacMix.git
   cd MacMix
   ```

2. Open `MacMix.xcodeproj` in Xcode.
3. Select the `MacMix` scheme.
4. Build and run the app.

## Notes

Per-app mixing depends on macOS audio process taps, so apps may appear in the mixer only while they are actively producing output audio.
