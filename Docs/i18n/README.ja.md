<p align="center">
  <img src="../images/og-image.webp" alt="MacMix — Macのサウンドを、すべてMacMixで。システム音量、出力・入力デバイス、アプリごとの音量をまとめて扱える、ネイティブなmacOSメニューバーミキサー。" width="100%">
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
  <a href="../../README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <b>日本語</b> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/macOS%E7%89%88%E3%82%92%E3%83%80%E3%82%A6%E3%83%B3%E3%83%AD%E3%83%BC%E3%83%89-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="macOS版 MacMix をダウンロード">
  </a>
</p>

<p align="center">
  <a href="#機能">機能</a> ·
  <a href="#オープンソース版と配布版">オープンソース版と配布版</a> ·
  <a href="#インストール">インストール</a> ·
  <a href="#プライバシー">プライバシー</a> ·
  <a href="#ソースからビルド">ソースからビルド</a> ·
  <a href="#macmix-を応援する">サポート</a> ·
  <a href="#ライセンスと商標">ライセンス</a>
</p>

---

## MacMix を選ぶ理由

macOS の音量スライダーはひとつだけ。MacMix はその先を補います。音楽はそのままにうるさいアプリだけ音量を下げ、AirPods・スピーカー・ディスプレイをワンクリックで切り替え、通話の前に正しいマイクを選ぶ。すべてメニューバーのコンパクトなネイティブパネルで完結し、システム設定を開く必要はありません。

## 機能

### 🔊 音量

- **システム音量**：現在の出力デバイスの音量をメニューバーから直接調整。
- **外部ディスプレイのスピーカー**：macOS が音量調整を提供しない場合は DDC/CI で調整。音量範囲を正しく報告しないディスプレイにも対応。
- **本当のゼロ**：スライダーを 0% にするとデバイスを完全に消音し、かすかな音も残しません。

### 🎧 デバイス

- **出力の切り替え**：スピーカー、ヘッドフォン、AirPods、ディスプレイなど。
- **AirPlay レシーバーを名前で表示**：HomePod や AirPlay スピーカーがそれぞれ1行で表示され、使用中のグループから1台だけに切り替えることもできます。
- **ひと目で分かるアイコン**：AirPods、Beats、HomePod、Apple TV、外部ディスプレイ、Mac 内蔵スピーカーに対応したアイコンに加え、デバイス自身が提供するアイコンも使用します。
- **マイクの切り替え**と入力音量の調整も同じパネルで。

### 🎚️ アプリごとのミックス

- **再生中のアプリの音量を個別に下げたり**、最大 **200%** まで上げたりできます（設定でオン）。
- **音量を記憶**し、アプリが再び再生を始めると復元します。
- **本当のアプリを特定**：Web エンジンで再生されるメディア（WebKit で再生する iPad アプリを含む）を、元のアプリとして表示します。

### 🍃 軽快な設計

- メニューバーで静かに動作し、必要に応じて設定ウインドウも使えます。
- ネイティブ SwiftUI。オーディオはローカルでリアルタイムに処理され、アカウントは不要です。
- 公式アプリは Sparkle で自動アップデートされます。

## オープンソース版と配布版

**MacMix の全機能は、MacMix Studio も含めてオープンソースです。** このリポジトリを自分でビルドすれば、すべての機能が解放された完全なアプリが手に入ります。ライセンスもアカウントも不要で、出し惜しみはありません。

Releases ページからダウンロードできるのは**配布版**、つまり同じアプリの公式ビルドです。無料で使え、**MacMix Studio** はそのビルドで Studio の機能を解放する任意の買い切り購入です。別の「Studio アプリ」はなく、ライセンスは同じアプリで機能を解放するだけなので、設定はそのまま残ります。

| 含まれる機能 | <div align="center">ソースからビルド<br><sub>（このリポジトリ）</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">配布版<br><sub>（無料）</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">配布版<br><sub>（Studio）</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| システム・ディスプレイ・アプリごとの音量 | ✅ | ✅ | ✅ |
| 出力・AirPlay・入力デバイスの切り替え | ✅ | ✅ | ✅ |
| アプリごとの 200% ブースト | ✅ | ✅ | ✅ |
| 匿名化された診断ログ付きのフィードバック | ✅ | ✅ | ✅ |
| **カスタムEQ** — アプリごとに音を調整し、プリセットとして保存 | ✅ | — | ✅ |
| **複数デバイス出力** — ひとつのアプリを複数のデバイスで同時に再生し、デバイスごとに音量を調整 | ✅ | — | ✅ |
| **Proコントロール** — Bluetooth デバイスのバッテリー残量の表示、リスニングモードと空間オーディオの操作 | ✅ | — | ✅ |
| **再生中** — 再生中のメディアを表示して操作 | ✅ | — | ✅ |
| **シーンプリセット** — デバイスとアプリの音量を保存し、ワンクリックで切り替え | ✅ | — | ✅ |
| **システム音量調節** — 音量キーを引き継ぎ、より滑らかに調整 | ✅ | — | ✅ |
| **入力デバイスを固定** — macOS によるマイクの自動切り替えを防止 | ✅ | — | ✅ |
| **ブラックリスト** — 指定したアプリをミックスの対象外に | ✅ | — | ✅ |
| **パーソナライズ** — カスタムテーマ | ✅ | — | ✅ |
| 開発者による署名と公証 | — | ✅ | ✅ |
| 自動アップデート | — | ✅ | ✅ |
| **ベータ版を先行体験** — 新機能をいち早く試す | — | — | ✅ |

> [!NOTE]
> 非公開なのは配布版のためだけに存在する部分、つまりライセンス認証、購入フロー、初回ガイド、アップデーターだけです。MacMix のビルドや実行にはどれも不要で、このリポジトリからのビルドには含まれていません。

## インストール

1. 最新リリースから [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg) をダウンロードします。
2. ディスクイメージを開き、**MacMix** を「アプリケーション」フォルダにドラッグします。
3. MacMix を起動し、メニューバーのアイコンをクリックします。

**動作環境：** macOS Sonoma 14.4 以降。アプリごとのミックスを初めて使うときに「**システムオーディオ録音**」の許可が必要です。それ以外の機能には不要です。

## プライバシー

MacMix はオーディオを**お使いの Mac 上で**処理します。オーディオを録音・保存・アップロードすることはありません。

アプリごとのミックスは macOS のオーディオプロセスタップを利用しているため、MacMix がほかのアプリの音量を変更する前に、macOS が「システムオーディオ録音」の許可を求めます。MacMix はこの許可をローカルでのリアルタイムミックスにのみ使用します。

## ソースからビルド

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

**MacMix** スキームを選んで **Run** を押します。Swift パッケージ（MenuBarExtraAccess と Swift Atomics）は Xcode が自動で解決します。ビルドしたアプリでは Studio のすべての機能が解放されています。

開発チームを設定していない場合、Xcode はローカル実行用にのみ署名するため、ビルドし直すたびに macOS が**システムオーディオ録音**の許可を再度求めることがあります。許可を維持するには、`Config/Local.example.xcconfig` を `Config/Local.xcconfig` にコピーし、自分の `DEVELOPMENT_TEAM` を設定してください。このファイルは Git に無視されます。

ソースからのビルドは自動アップデートされません。更新するには、最新のソースを取得してビルドし直してください。

回帰テストは Xcode コマンドラインツールだけで動く通常のスクリプトです：

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>補足と制限</strong></summary>

<br>

- アプリがミキサーに表示されるのは、macOS がそのアプリのオーディオ出力を報告している間だけです。
- アプリごとの音量はローカルに保存され、同じアプリが再び再生すると復元されます。
- ディスプレイの音量調整には、現在のケーブルやドックで DDC/CI のスピーカー音量（VCP `0x62`）に対応したディスプレイが必要です。DisplayLink アダプタ、一部の HDMI 経路、テレビ、OSD メニューで DDC/CI をオフにしたディスプレイでは使えない場合があります。
- AirPlay レシーバーの名前は AirPlay デバイスのデータソースから取得します。macOS がレシーバー名を報告しない場合、MacMix は名前を推測せず、通常の AirPlay デバイスとして表示します。

</details>

## MacMix を応援する

ソースからのビルドは、これからもずっと無料です。MacMix が毎日の一部になっているなら、**MacMix Studio** の購入をご検討ください。買い切りで、配布版（署名・公証済みで自動的に最新に保たれる公式アプリ）の Studio 機能が解放され、MacMix の開発を直接支えることになります。

<p align="center">
  <a href="https://macmix.jazminli.com/studio"><img src="https://img.shields.io/badge/%E5%85%A5%E6%89%8B%E3%81%99%E3%82%8B-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="MacMix Studio を入手"></a>
</p>

不具合の報告やアイデアは [Issues](https://github.com/ljmng7/MacMix/issues) へどうぞ。コードで貢献する場合は[コントリビューションガイド](../../CONTRIBUTING.md)をご覧ください。プルリクエストにはコントリビューターライセンス契約（CLA）への署名が必要です。

## ライセンスと商標

MacMix はフリーソフトウェアです。[GNU 一般公衆利用許諾書 第 3 版](../../LICENSE)（GPL-3.0）の条件のもとで、再配布や改変ができます。2.3.2 以前のバージョンは MIT License で公開されており、その条件で受け取ったコードは引き続きその条件で利用できます。

**商標。**「MacMix」という名前と MacMix のアプリアイコンは公式アプリを示すもので、公式ビルド専用です。GPL が対象とするのはコードであり、名前やブランドではありません。フォークや改変したビルドを配布する場合は、別の名前、別のアイコン、別のバンドル ID を使い、公式の MacMix として扱わないでください。自分で使うために MacMix をビルドして実行するのは、いつでも問題ありません。

アプリアイコン、スクリーンショット、その他のブランド素材は GPL の対象**外**で、許可なく再利用することはできません。詳しくは[ブランド素材](../../BRAND-ASSETS.md)をご覧ください。
