<p align="center">
  <img src="Docs/images/og-image.webp" alt="MacMix — Mac의 사운드, MacMix 하나로. 시스템 음량, 출력·입력 기기, 앱별 음량을 한곳에서 다루는 macOS 기본 메뉴 막대 믹서." width="100%">
  <br>
  <sub>스크린샷은 배포판입니다. 일부 기능은 MacMix Studio가 필요합니다.</sub>
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
  <a href="README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <b>한국어</b> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/macOS%EC%9A%A9_%EB%8B%A4%EC%9A%B4%EB%A1%9C%EB%93%9C-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="macOS용 MacMix 다운로드">
  </a>
</p>

<p align="center">
  <a href="#기능">기능</a> ·
  <a href="#오픈-소스판과-배포판">오픈 소스판과 배포판</a> ·
  <a href="#설치">설치</a> ·
  <a href="#개인정보-보호">개인정보 보호</a> ·
  <a href="#소스에서-빌드">소스에서 빌드</a> ·
  <a href="#macmix-후원하기">후원</a>
</p>

---

## MacMix를 써야 하는 이유

macOS에는 음량 슬라이더가 하나뿐입니다. MacMix는 나머지를 채웁니다. 음악은 그대로 두고 시끄러운 앱만 줄이고, AirPods·스피커·모니터를 클릭 한 번으로 오가고, 통화 전에 알맞은 마이크를 고르세요. 모두 메뉴 막대의 작고 깔끔한 패널에서 끝나며 시스템 설정을 열 필요가 없습니다.

## 기능

### 🔊 음량

- **시스템 음량**: 현재 출력 기기의 음량을 메뉴 막대에서 바로 조절합니다.
- **외장 디스플레이 스피커**: macOS가 음량 조절을 지원하지 않으면 DDC/CI로 조절하며, 음량 범위를 이상하게 보고하는 모니터도 지원합니다.
- **진짜 0%**: 슬라이더를 0%로 내리면 미세한 소리도 남기지 않고 기기를 완전히 음소거합니다.

### 🎧 기기

- **출력 전환**: 스피커, 헤드폰, AirPods, 디스플레이 등.
- **AirPlay 수신기를 이름으로 표시**: HomePod와 AirPlay 스피커가 각각 한 줄씩 표시되며, 사용 중인 그룹에서 수신기 하나로 전환할 수도 있습니다.
- **한눈에 알아보는 아이콘**: AirPods, Beats, HomePod, Apple TV, 외장 디스플레이, Mac 내장 스피커에 맞는 아이콘을 보여 주며, 기기가 직접 제공하는 아이콘도 사용합니다.
- **마이크 전환**과 입력 음량 조절도 같은 패널에서 할 수 있습니다.

### 🎚️ 앱별 믹싱

- 재생 중인 **앱의 음량을 따로 낮추거나** 최대 **200%**까지 높일 수 있습니다(설정에서 켜기).
- **음량을 기억**해 두었다가 앱이 다시 재생되면 복원합니다.
- **실제 앱을 찾아냅니다**: 웹 엔진으로 재생되는 미디어(WebKit으로 재생하는 iPad 앱 포함)를 해당 앱으로 표시합니다.

### 🍃 가볍게 설계

- 메뉴 막대에서 조용히 동작하며, 필요하면 설정 윈도우를 열 수 있습니다.
- 네이티브 SwiftUI, 오디오는 로컬에서 실시간으로 처리되며 계정이 필요 없습니다.
- Sparkle을 통한 자동 업데이트.

## 오픈 소스판과 배포판

이 저장소에는 MacMix의 **무료 오픈 소스 핵심**이 들어 있습니다. Releases 페이지에서 받는 것은 **배포판**으로, 무료로 쓸 수 있는 하나의 앱이며 **MacMix Studio**는 선택 사항인 일회성 업그레이드입니다. 별도의 'Studio 앱'은 없습니다. 라이선스는 같은 앱에서 추가 기능을 잠금 해제할 뿐이며 설정은 그대로 유지됩니다.

| 포함된 기능 | <div align="center">오픈 소스판<br><sub>(이 저장소)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">배포판<br><sub>(무료)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">배포판<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| 시스템·디스플레이·앱별 음량 | ✅ | ✅ | ✅ |
| 출력·AirPlay·입력 기기 전환 | ✅ | ✅ | ✅ |
| 앱별 200% 증폭 | ✅ | ✅ | ✅ |
| 개발자 서명 및 공증 | — | ✅ | ✅ |
| 익명 처리된 진단 로그가 첨부된 피드백 | — | ✅ | ✅ |
| **사용자 설정 EQ** — 앱마다 사운드를 조율하고 프리셋으로 저장 | — | — | ✅ |
| **다중 기기 출력** — 앱 하나를 여러 기기로 동시에 재생하고 기기마다 음량을 따로 조절 | — | — | ✅ |
| **Pro 제어** — 블루투스 기기 배터리 확인, 듣기 모드와 공간 음향 제어 | — | — | ✅ |
| **재생 중** — 현재 재생 중인 미디어를 확인하고 제어 | — | — | ✅ |
| **장면 프리셋** — 기기와 앱 음량을 저장하고 클릭 한 번으로 전환 | — | — | ✅ |
| **시스템 음량 조절** — 음량 키를 넘겨받아 더 부드럽게 조절 | — | — | ✅ |
| **입력 기기 고정** — macOS가 마이크를 자동으로 바꾸지 않도록 고정 | — | — | ✅ |
| **차단 목록** — 선택한 앱을 믹싱에서 제외 | — | — | ✅ |
| **개인 맞춤 설정** — 사용자 지정 테마 | — | — | ✅ |
| **베타 버전 미리 체험** — 새 기능을 먼저 사용 | — | — | ✅ |

> [!NOTE]
> Studio 기능은 비공개로 개발되며 이 저장소에 포함되지 않습니다. 지금까지 무료로 제공된 기능(앱별 믹싱과 버전 2.0 이전의 모든 기능)은 앞으로도 무료이며 오픈 소스로 유지됩니다. 공통 핵심의 수정 사항은 배포판에서 검증된 후 이 저장소에 반영되므로, 이곳의 소스 코드는 최신 릴리스보다 조금 늦을 수 있습니다.

## 설치

1. 최신 릴리스에서 [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg)를 다운로드합니다.
2. 디스크 이미지를 열고 **MacMix**를 '응용 프로그램' 폴더로 드래그합니다.
3. MacMix를 실행하고 메뉴 막대의 아이콘을 클릭합니다.

**요구 사항:** macOS Sonoma 14.4 이상. 앱별 믹싱을 처음 사용할 때 '**시스템 오디오 녹음**' 권한이 필요하며, 다른 기능은 이 권한 없이 동작합니다.

## 개인정보 보호

MacMix는 오디오를 **사용자의 Mac에서** 처리합니다. 오디오를 녹음하거나 저장하거나 업로드하지 않습니다.

앱별 믹싱은 macOS의 오디오 프로세스 탭을 기반으로 하므로, MacMix가 다른 앱의 음량을 바꾸기 전에 macOS가 '시스템 오디오 녹음' 권한을 요청합니다. MacMix는 이 권한을 로컬 실시간 믹싱에만 사용합니다.

## 소스에서 빌드

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

**MacMix** 스킴을 선택하고 **Run**을 누르세요. Swift 패키지(Sparkle, Swift Atomics)는 Xcode가 자동으로 가져옵니다.

회귀 테스트는 Xcode 명령어 도구만 있으면 되는 일반 스크립트입니다:

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>참고 및 제한 사항</strong></summary>

<br>

- 앱은 macOS가 오디오를 출력 중이라고 보고하는 동안에만 믹서에 표시됩니다.
- 앱별 음량은 로컬에 저장되며 같은 앱이 다시 재생되면 복원됩니다.
- 디스플레이 음량을 조절하려면 현재 케이블이나 독에서 DDC/CI 스피커 음량(VCP `0x62`)을 지원하는 모니터가 필요합니다. DisplayLink 어댑터, 일부 HDMI 경로, TV, OSD 메뉴에서 DDC/CI를 끈 디스플레이에서는 사용하지 못할 수 있습니다.
- AirPlay 수신기 이름은 AirPlay 기기의 데이터 소스에서 가져옵니다. macOS가 수신기 이름을 알려 주지 않으면 MacMix는 이름을 추측하지 않고 일반 AirPlay 기기로 표시합니다.

</details>

## MacMix 후원하기

MacMix가 일상의 일부가 되었다면 **MacMix Studio**로 업그레이드해 주세요. 한 번 구매로 위의 모든 기능이 잠금 해제되며, 무료 오픈 소스 핵심의 개발을 직접 지원합니다.

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/%EA%B5%AC%EB%A7%A4%ED%95%98%EA%B8%B0-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="MacMix Studio 구매하기"></a>
</p>

버그 제보와 아이디어는 [Issues](https://github.com/ljmng7/MacMix/issues)에 남겨 주세요.

## 라이선스

소스 코드는 [MIT License](LICENSE)로 공개됩니다. 앱 아이콘, 스크린샷 및 기타 브랜드 자산은 MIT License의 적용 대상이 **아니며** 허가 없이 재사용할 수 없습니다. 자세한 내용은 [브랜드 자산](BRAND-ASSETS.md)을 참고하세요.
