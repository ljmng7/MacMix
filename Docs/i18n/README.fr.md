<p align="center">
  <img src="../images/og-image.webp" alt="MacMix — Tout le son de votre Mac, dans MacMix. Un mixeur natif pour la barre des menus de macOS : volume du système, appareils de sortie et d’entrée, et son de chaque app." width="100%">
  <br>
  <sub>Capture de Distribution. Certaines fonctionnalités nécessitent MacMix Studio.</sub>
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
  <a href="https://trendshift.io/repositories/197969?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-197969" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/197969/daily?language=Swift" alt="ljmng7%2FMacMix | Trendshift" width="250" height="55"/></a>
</p>

<p align="center">
  <a href="../../README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <b>Français</b> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/T%C3%A9l%C3%A9charger_pour_macOS-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="Télécharger MacMix pour macOS">
  </a>
</p>

<p align="center">
  <a href="#fonctionnalités">Fonctionnalités</a> ·
  <a href="#version-open-source-et-distribution">Open source ou Distribution</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#confidentialité">Confidentialité</a> ·
  <a href="#compiler-depuis-les-sources">Compiler depuis les sources</a> ·
  <a href="#soutenir-macmix">Soutenir</a>
</p>

---

## Pourquoi MacMix

macOS vous donne un seul curseur de volume. MacMix vous donne tout le reste : baissez une app bruyante sans toucher à votre musique, passez des AirPods aux haut-parleurs ou à un moniteur en un clic, et choisissez le bon micro avant un appel. Le tout depuis un panneau natif et compact dans la barre des menus, sans ouvrir les Réglages Système.

## Fonctionnalités

### 🔊 Volume

- **Volume du système** de l’appareil de sortie actuel, directement dans la barre des menus.
- **Haut-parleurs des écrans externes** via DDC/CI quand macOS ne propose aucun réglage, avec des correctifs pour les moniteurs qui signalent des plages inhabituelles.
- **Un vrai zéro** : à 0 %, l’appareil est réellement silencieux, sans volume résiduel.

### 🎧 Appareils

- **Changez de sortie** entre haut-parleurs, casques, AirPods, écrans et plus encore.
- **Récepteurs AirPlay par leur nom** : chaque HomePod ou enceinte AirPlay a sa propre ligne, et vous pouvez passer d’un groupe actif à un seul récepteur.
- **Des icônes reconnaissables** pour les AirPods, Beats, HomePod, Apple TV, écrans externes et haut-parleurs intégrés de votre Mac, ainsi que l’icône fournie par l’appareil lui-même.
- **Changez de micro** et réglez le volume d’entrée depuis le même panneau.

### 🎚️ Mixage par app

- **Baissez n’importe quelle app** pendant la lecture, ou amplifiez-la jusqu’à **200 %** (option dans les réglages).
- **Mémorise vos niveaux** et les restaure quand l’app joue à nouveau.
- **Retrouve la vraie app** derrière la lecture web, y compris les apps iPad qui lisent du contenu via WebKit.

### 🍃 Léger par nature

- Se fait discret dans la barre des menus, avec une fenêtre de réglages facultative.
- SwiftUI natif, audio traité localement en temps réel, aucun compte requis.
- Mises à jour automatiques avec Sparkle.

## Version open source et Distribution

Ce dépôt contient le **cœur gratuit et open source** de MacMix. Le téléchargement de la page Releases est **Distribution** : une seule app, gratuite, avec **MacMix Studio** en mise à niveau facultative à achat unique. Il n’existe pas d’« app Studio » séparée : une licence débloque simplement des fonctionnalités dans la même app, et vos réglages restent en place.

| Fonctionnalités incluses | <div align="center">Open source<br><sub>(ce dépôt)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(gratuite)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| Volume du système, des écrans et de chaque app | ✅ | ✅ | ✅ |
| Choix des appareils de sortie, AirPlay et d’entrée | ✅ | ✅ | ✅ |
| Amplification à 200 % par app | ✅ | ✅ | ✅ |
| Signée et notarisée par le développeur | — | ✅ | ✅ |
| Rapports de feedback avec journaux de diagnostic anonymisés | — | ✅ | ✅ |
| **Égaliseur personnalisé** — réglez le son de chaque app et enregistrez vos préréglages | — | — | ✅ |
| **Sortie multi-appareils** — une app sur plusieurs appareils à la fois, chacun avec son propre volume | — | — | ✅ |
| **Contrôles Pro** — niveau de batterie des appareils Bluetooth, mode d’écoute et audio spatial | — | — | ✅ |
| **À l’écoute** — affichez et contrôlez le média en cours | — | — | ✅ |
| **Préréglages de scènes** — enregistrez appareils et volumes des apps, changez en un clic | — | — | ✅ |
| **Commandes du volume système** — prenez en charge les touches de volume pour un réglage plus fluide | — | — | ✅ |
| **Verrouiller le périphérique d’entrée** — empêchez macOS de changer de micro | — | — | ✅ |
| **Liste noire** — excluez certaines apps du mixage | — | — | ✅ |
| **Personnalisation** — thèmes personnalisés | — | — | ✅ |
| **Accès anticipé aux bêtas** — essayez les nouveautés en premier | — | — | ✅ |

> [!NOTE]
> Les fonctionnalités Studio sont développées en privé et ne font pas partie de ce dépôt. Tout ce qui est déjà gratuit, y compris le mixage par app et toutes les fonctionnalités antérieures à la version 2.0, restera gratuit et open source. Les correctifs du cœur commun arrivent dans ce dépôt après validation dans Distribution ; le code ici peut donc avoir un léger retard sur la dernière version.

## Installation

1. Téléchargez [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg) depuis la dernière version.
2. Ouvrez l’image disque et faites glisser **MacMix** dans **Applications**.
3. Lancez MacMix et cliquez sur son icône dans la barre des menus.

**Configuration requise :** macOS Sonoma 14.4 ou ultérieur. Le mixage par app demande l’autorisation **Enregistrement audio du système** à la première utilisation ; le reste fonctionne sans elle.

## Confidentialité

MacMix traite l’audio **localement sur votre Mac**. Il n’enregistre, ne conserve et n’envoie jamais d’audio.

Le mixage par app repose sur les taps de processus audio de macOS : c’est pourquoi macOS demande l’autorisation Enregistrement audio du système avant que MacMix puisse modifier le volume d’une autre app. MacMix utilise cette autorisation uniquement pour le mixage local en temps réel.

## Compiler depuis les sources

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

Sélectionnez le schéma **MacMix** et cliquez sur **Run**. Xcode résout automatiquement les paquets Swift (Sparkle et Swift Atomics).

Les tests de non-régression sont de simples scripts qui ne nécessitent que les outils en ligne de commande de Xcode :

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>Remarques et limites</strong></summary>

<br>

- Une app n’apparaît dans le mixeur que lorsque macOS indique qu’elle produit du son.
- Les niveaux par app sont enregistrés localement et restaurés quand la même app joue à nouveau.
- Le volume des écrans nécessite un moniteur compatible avec le volume des haut-parleurs DDC/CI (VCP `0x62`) via le câble ou le dock utilisé. Les adaptateurs DisplayLink, certaines liaisons HDMI, les téléviseurs et les écrans dont le DDC/CI est désactivé dans le menu OSD peuvent ne pas le proposer.
- Les noms des récepteurs AirPlay proviennent des sources de données de l’appareil AirPlay. Si macOS ne fournit pas de nom, MacMix affiche l’appareil AirPlay générique au lieu de deviner.

</details>

## Soutenir MacMix

Si MacMix fait partie de votre quotidien, pensez à passer à **MacMix Studio**. C’est un achat unique qui débloque les fonctionnalités ci-dessus et finance le cœur gratuit et open source.

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/Obtenir-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="Obtenir MacMix Studio"></a>
</p>

Signalements de bugs et idées sont les bienvenus dans les [Issues](https://github.com/ljmng7/MacMix/issues).

## Licence

Le code source est publié sous [licence MIT](../../LICENSE). L’icône de l’app, les captures d’écran et les autres éléments de marque ne sont **pas** couverts par la licence MIT et ne peuvent pas être réutilisés sans autorisation. Voir [Éléments de marque](../../BRAND-ASSETS.md).
