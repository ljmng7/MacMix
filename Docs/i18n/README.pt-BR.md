<p align="center">
  <img src="../images/og-image.webp" alt="MacMix — Todo o som do seu Mac, no MacMix. Um mixer nativo para a barra de menus do macOS: volume do sistema, dispositivos de saída e entrada e o som de cada app." width="100%">
  <br>
  <sub>A captura mostra a versão distribuída. Alguns recursos exigem o MacMix Studio.</sub>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest"><img src="https://img.shields.io/github/v/release/ljmng7/MacMix?label=release&color=7A5CFA" alt="Latest release"></a>
  <a href="https://github.com/ljmng7/MacMix/stargazers"><img src="https://img.shields.io/github/stars/ljmng7/MacMix?style=flat&color=F5B301&logo=github" alt="GitHub stars"></a>
  <a href="https://github.com/ljmng7/MacMix/releases"><img src="https://img.shields.io/github/downloads/ljmng7/MacMix/total?color=2F80ED" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14.4%2B-111111?logo=apple&logoColor=white" alt="macOS 14.4+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="Swift, SwiftUI">
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/code-MIT-3DA639" alt="MIT License"></a>
</p>

<p align="center">
  <a href="../../README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <b>Português (Brasil)</b> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/Baixar_para_macOS-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="Baixar o MacMix para macOS">
  </a>
</p>

<p align="center">
  <a href="#recursos">Recursos</a> ·
  <a href="#código-aberto-e-versão-distribuída">Código aberto vs. versão distribuída</a> ·
  <a href="#instalação">Instalação</a> ·
  <a href="#privacidade">Privacidade</a> ·
  <a href="#compilar-a-partir-do-código">Compilar a partir do código</a> ·
  <a href="#apoie-o-macmix">Apoiar</a>
</p>

---

## Por que o MacMix

O macOS oferece um único controle de volume. O MacMix oferece o resto: abaixe um app barulhento sem mexer na música, alterne entre AirPods, alto-falantes e monitor com um clique e escolha o microfone certo antes de uma chamada. Tudo em um painel nativo e compacto na barra de menus, sem abrir os Ajustes do Sistema.

## Recursos

### 🔊 Volume

- **Volume do sistema** do dispositivo de saída atual, direto na barra de menus.
- **Alto-falantes de monitores externos** via DDC/CI quando o macOS não oferece controle de volume, com correções para monitores que informam faixas incomuns.
- **Zero de verdade**: ao levar um controle a 0%, o dispositivo fica totalmente mudo, sem volume residual.

### 🎧 Dispositivos

- **Troque a saída** entre alto-falantes, fones, AirPods, monitores e mais.
- **Receptores AirPlay pelo nome**: cada HomePod ou alto-falante AirPlay ganha sua própria linha, e você pode passar de um grupo ativo para um único receptor.
- **Ícones reconhecíveis** para AirPods, Beats, HomePod, Apple TV, monitores externos e os alto-falantes do seu Mac, além do ícone fornecido pelo próprio dispositivo.
- **Troque o microfone** e ajuste o volume de entrada no mesmo painel.

### 🎚️ Mixagem por app

- **Abaixe qualquer app** enquanto ele toca, ou aumente até **200%** (opcional, nos Ajustes).
- **Lembra seus níveis** e os restaura quando o app volta a tocar.
- **Encontra o app real** por trás da reprodução na web, incluindo apps de iPad que reproduzem mídia via WebKit.

### 🍃 Leve por natureza

- Fica discreto na barra de menus, com uma janela de ajustes opcional.
- SwiftUI nativo, áudio processado localmente em tempo real, sem conta.
- Atualizações automáticas com o Sparkle.

## Código aberto e versão distribuída

Este repositório contém o **núcleo gratuito e de código aberto** do MacMix. O download da página Releases é a **versão distribuída**: um único app gratuito, com o **MacMix Studio** como upgrade opcional de compra única. Não existe um “app Studio” separado: a licença apenas desbloqueia recursos extras no mesmo app, e seus ajustes continuam onde estão.

| Recursos incluídos | <div align="center">Código aberto<br><sub>(este repositório)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Versão<br>distribuída<br><sub>(gratuita)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Versão<br>distribuída<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| Volume do sistema, do monitor e por app | ✅ | ✅ | ✅ |
| Troca de dispositivos de saída, AirPlay e entrada | ✅ | ✅ | ✅ |
| Amplificação de 200% por app | ✅ | ✅ | ✅ |
| Assinada e autenticada pelo desenvolvedor | — | ✅ | ✅ |
| Envio de feedback com registros de diagnóstico anônimos | — | ✅ | ✅ |
| **EQ personalizado** — ajuste o som de cada app e salve seus presets | — | — | ✅ |
| **Saída para vários dispositivos** — um app em vários dispositivos ao mesmo tempo, cada um com seu próprio volume | — | — | ✅ |
| **Controles Pro** — bateria de dispositivos Bluetooth, Modo de Audição e Áudio Espacial | — | — | ✅ |
| **Reproduzindo agora** — veja e controle a mídia atual | — | — | ✅ |
| **Predefinições de cena** — salve dispositivos e volumes dos apps e alterne com um clique | — | — | ✅ |
| **Controles de Volume do Sistema** — assuma as teclas de volume para um ajuste mais suave | — | — | ✅ |
| **Bloquear dispositivo de entrada** — impeça o macOS de trocar seu microfone | — | — | ✅ |
| **Lista de bloqueio** — deixe apps específicos fora da mixagem | — | — | ✅ |
| **Personalização** — temas personalizados | — | — | ✅ |
| **Acesso antecipado às betas** — experimente as novidades primeiro | — | — | ✅ |

> [!NOTE]
> Os recursos do Studio são desenvolvidos de forma privada e não fazem parte deste repositório. Tudo o que já é gratuito, incluindo a mixagem por app e todos os recursos anteriores à versão 2.0, continuará gratuito e de código aberto. As correções do núcleo comum chegam a este repositório depois de validadas na versão distribuída, então o código aqui pode ficar um pouco atrás da versão mais recente.

## Instalação

1. Baixe [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg) da versão mais recente.
2. Abra a imagem de disco e arraste o **MacMix** para **Aplicativos**.
3. Abra o MacMix e clique no ícone dele na barra de menus.

**Requisitos:** macOS Sonoma 14.4 ou posterior. A mixagem por app pede a permissão **Gravação de Áudio do Sistema** no primeiro uso; o resto funciona sem ela.

## Privacidade

O MacMix processa o áudio **localmente no seu Mac**. Ele nunca grava, salva ou envia áudio.

A mixagem por app usa os taps de processos de áudio do macOS; por isso o macOS pede a permissão Gravação de Áudio do Sistema antes que o MacMix possa alterar o volume de outro app. O MacMix usa essa permissão apenas para a mixagem local em tempo real.

## Compilar a partir do código

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

Selecione o esquema **MacMix** e clique em **Run**. O Xcode resolve automaticamente os pacotes Swift (Sparkle e Swift Atomics).

Os testes de regressão são scripts simples que só precisam das ferramentas de linha de comando do Xcode:

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>Observações e limitações</strong></summary>

<br>

- Os apps aparecem no mixer apenas enquanto o macOS informa que estão reproduzindo áudio.
- Os níveis por app ficam salvos localmente e são restaurados quando o mesmo app volta a tocar.
- O volume do monitor exige uma tela compatível com volume de alto-falantes DDC/CI (VCP `0x62`) pelo cabo ou dock em uso. Adaptadores DisplayLink, algumas conexões HDMI, TVs e telas com DDC/CI desativado no menu OSD podem não oferecer esse controle.
- Os nomes dos receptores AirPlay vêm das fontes de dados do dispositivo AirPlay. Quando o macOS não informa o nome, o MacMix mostra o dispositivo AirPlay genérico em vez de adivinhar.

</details>

## Apoie o MacMix

Se o MacMix faz parte do seu dia, considere fazer o upgrade para o **MacMix Studio**. É uma compra única que desbloqueia os recursos acima e financia o núcleo gratuito e de código aberto.

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/Obter-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="Obter o MacMix Studio"></a>
</p>

Relatos de bugs e ideias são bem-vindos em [Issues](https://github.com/ljmng7/MacMix/issues).

## Licença

O código-fonte é distribuído sob a [Licença MIT](../../LICENSE). O ícone do app, as capturas de tela e outros elementos da marca **não** estão cobertos pela Licença MIT e não podem ser reutilizados sem permissão. Veja [Elementos da marca](../../BRAND-ASSETS.md).
