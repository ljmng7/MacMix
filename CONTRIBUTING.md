# Contributing to MacMix

Thanks for helping make MacMix better. Bug reports, ideas and pull requests are all welcome.

## Contributor License Agreement

Before a pull request can be merged, you need to sign the MacMix Contributor License Agreement (CLA). You only sign it once, and it covers all your future contributions.

Before your first pull request is merged, you'll be sent the agreement to sign.

**Why a CLA?** MacMix is published under the GPL-3.0, and the official app is built from this same code together with a few private parts: license activation, the purchase flow and the updater. The CLA lets the author ship your contribution in the official app as well as in this repository. You keep the copyright to your work, and your contribution stays available under the GPL-3.0 here.

## Before You Start

- For anything larger than a small fix, open an issue first so we can agree on the approach.
- Keep each pull request focused on one change.
- Licensing, purchases and updates are not part of this repository. Pull requests that add them, or that add other payment or update mechanisms, won't be accepted.

## Building and Testing

See [Build from Source](README.md#build-from-source). Run the regression tests before opening a pull request:

```sh
for test in tests/run-*.sh; do bash "$test"; done
swift test --package-path Packages/MacMixStudio
```

## Translations

User-facing text lives in the String Catalogs (`*.xcstrings`) under `MacMix/`. Corrections to existing translations are welcome; please mention in the pull request which language you speak.

---

# 参与贡献

感谢你帮助改进 MacMix。欢迎提交问题反馈、建议和 Pull Request。

## 贡献者许可协议（CLA）

Pull Request 在合并前需要签署 MacMix 贡献者许可协议（CLA）。只需签署一次，即可覆盖你之后的全部贡献。

你的第一个 Pull Request 合并前，会收到需要签署的协议。

**为什么需要 CLA？** MacMix 以 GPL-3.0 发布，而官方应用由同一份代码加上少量私有部分（许可证激活、购买流程和更新器）构建。CLA 让作者能够把你的贡献同时用于本仓库和官方应用。你保留自己作品的著作权，你的贡献在本仓库中也会继续以 GPL-3.0 提供。

## 开始之前

- 除了小修复以外，请先开一个 Issue，就实现方式达成一致。
- 每个 Pull Request 只做一件事。
- 许可证、购买和更新功能不属于本仓库。添加这些功能，或添加其他付费、更新机制的 Pull Request 不会被接受。

## 构建与测试

参见 [从源码构建](Docs/i18n/README.zh-Hans.md#从源码构建)。提交 Pull Request 前请运行回归测试：

```sh
for test in tests/run-*.sh; do bash "$test"; done
swift test --package-path Packages/MacMixStudio
```

## 翻译

界面文字位于 `MacMix/` 下的字符串目录（`*.xcstrings`）中。欢迎修正现有翻译，请在 Pull Request 中说明你使用的语言。
