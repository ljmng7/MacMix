<p align="center">
  <img src="../images/og-image.webp" alt="MacMix — Todo el sonido de tu Mac, en MacMix. Un mezclador nativo para la barra de menús de macOS: volumen del sistema, dispositivos de salida y entrada, y el sonido de cada app." width="100%">
  <br>
  <sub>La captura muestra Distribution. Algunas funciones requieren MacMix Studio.</sub>
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
  <a href="../../README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <b>Español</b> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/Descargar_para_macOS-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="Descargar MacMix para macOS">
  </a>
</p>

<p align="center">
  <a href="#funciones">Funciones</a> ·
  <a href="#código-abierto-y-distribution">Código abierto vs. Distribution</a> ·
  <a href="#instalación">Instalación</a> ·
  <a href="#privacidad">Privacidad</a> ·
  <a href="#compilar-desde-el-código">Compilar desde el código</a> ·
  <a href="#apoya-macmix">Apoyar</a>
</p>

---

## Por qué MacMix

macOS te da un solo control de volumen. MacMix te da todo lo demás: baja una app ruidosa sin tocar tu música, pasa de los AirPods a los altavoces o a un monitor con un clic y elige el micrófono correcto antes de una llamada. Todo desde un panel nativo y compacto en la barra de menús, sin abrir Ajustes del Sistema.

## Funciones

### 🔊 Volumen

- **Volumen del sistema** del dispositivo de salida actual, directamente en la barra de menús.
- **Altavoces de pantallas externas** mediante DDC/CI cuando macOS no ofrece control de volumen, con correcciones para monitores que informan rangos inusuales.
- **Cero de verdad**: al llevar un control al 0 %, el dispositivo queda en silencio total, sin volumen residual.

### 🎧 Dispositivos

- **Cambia de salida** entre altavoces, auriculares, AirPods, pantallas y más.
- **Receptores AirPlay por su nombre**: cada HomePod o altavoz AirPlay tiene su propia fila, y puedes pasar de un grupo activo a un solo receptor.
- **Iconos reconocibles** para AirPods, Beats, HomePod, Apple TV, pantallas externas y los altavoces de tu Mac, además del icono que aporta el propio dispositivo.
- **Cambia de micrófono** y ajusta el volumen de entrada desde el mismo panel.

### 🎚️ Mezcla por app

- **Baja cualquier app** mientras suena, o súbela hasta el **200 %** (opcional, en Ajustes).
- **Recuerda tus niveles** y los restaura cuando la app vuelve a sonar.
- **Encuentra la app real** detrás de la reproducción web, incluidas las apps de iPad que reproducen contenido con WebKit.

### 🍃 Ligero por diseño

- Vive discretamente en la barra de menús, con una ventana de ajustes opcional.
- SwiftUI nativo, audio procesado localmente en tiempo real, sin cuenta.
- Actualizaciones automáticas con Sparkle.

## Código abierto y Distribution

Este repositorio contiene el **núcleo gratuito y de código abierto** de MacMix. La descarga de la página Releases es **Distribution**: una sola app gratuita, con **MacMix Studio** como mejora opcional de pago único. No existe una «app Studio» aparte: una licencia desbloquea funciones extra en la misma app y tus ajustes se mantienen.

| Funciones incluidas | <div align="center">Código<br>abierto<br><sub>(este repositorio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(gratis)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| Volumen del sistema, de pantallas y por app | ✅ | ✅ | ✅ |
| Cambio de dispositivos de salida, AirPlay y entrada | ✅ | ✅ | ✅ |
| Amplificación al 200 % por app | ✅ | ✅ | ✅ |
| Firmada y notarizada por el desarrollador | — | ✅ | ✅ |
| Informes de comentarios con registros de diagnóstico anónimos | — | ✅ | ✅ |
| **EQ personalizado** — ajusta el sonido de cada app y guarda tus preajustes | — | — | ✅ |
| **Salida a varios dispositivos** — una app en varios dispositivos a la vez, cada uno con su propio volumen | — | — | ✅ |
| **Controles Pro** — batería de los dispositivos Bluetooth, modo de escucha y audio espacial | — | — | ✅ |
| **En reproducción** — consulta y controla lo que está sonando | — | — | ✅ |
| **Preajustes de escena** — guarda dispositivos y volúmenes de apps y cambia con un clic | — | — | ✅ |
| **Controles de volumen del sistema** — toma el control de las teclas de volumen para un ajuste más suave | — | — | ✅ |
| **Bloquear dispositivo de entrada** — evita que macOS cambie tu micrófono | — | — | ✅ |
| **Lista negra** — deja apps concretas fuera de la mezcla | — | — | ✅ |
| **Personalización** — temas personalizados | — | — | ✅ |
| **Acceso anticipado a las betas** — prueba las novedades antes que nadie | — | — | ✅ |

> [!NOTE]
> Las funciones de Studio se desarrollan de forma privada y no forman parte de este repositorio. Todo lo que ya es gratis, incluida la mezcla por app y todas las funciones anteriores a la versión 2.0, seguirá siendo gratis y de código abierto. Las correcciones del núcleo común llegan a este repositorio después de validarse en Distribution, por lo que el código puede ir un poco por detrás de la última versión.

## Instalación

1. Descarga [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg) de la última versión.
2. Abre la imagen de disco y arrastra **MacMix** a **Aplicaciones**.
3. Abre MacMix y haz clic en su icono de la barra de menús.

**Requisitos:** macOS Sonoma 14.4 o posterior. La mezcla por app pide el permiso **Grabación de audio del sistema** la primera vez que la usas; todo lo demás funciona sin él.

## Privacidad

MacMix procesa el audio **localmente en tu Mac**. Nunca graba, guarda ni sube audio.

La mezcla por app se basa en los taps de procesos de audio de macOS; por eso macOS pide el permiso Grabación de audio del sistema antes de que MacMix pueda cambiar el volumen de otra app. MacMix usa ese permiso solo para la mezcla local en tiempo real.

## Compilar desde el código

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

Selecciona el esquema **MacMix** y pulsa **Run**. Xcode resuelve automáticamente los paquetes Swift (Sparkle y Swift Atomics).

Las pruebas de regresión son scripts sencillos que solo necesitan las herramientas de línea de comandos de Xcode:

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>Notas y limitaciones</strong></summary>

<br>

- Las apps aparecen en el mezclador solo mientras macOS indica que están reproduciendo audio.
- Los niveles por app se guardan localmente y se restauran cuando la misma app vuelve a sonar.
- El volumen de pantalla requiere un monitor compatible con el volumen de altavoces DDC/CI (VCP `0x62`) mediante el cable o la base actuales. Los adaptadores DisplayLink, algunas conexiones HDMI, los televisores y las pantallas con DDC/CI desactivado en su menú OSD pueden no ofrecerlo.
- Los nombres de los receptores AirPlay proceden de las fuentes de datos del dispositivo AirPlay. Si macOS no informa del nombre, MacMix muestra el dispositivo AirPlay genérico en lugar de adivinarlo.

</details>

## Apoya MacMix

Si MacMix forma parte de tu día a día, plantéate pasarte a **MacMix Studio**. Es un pago único que desbloquea las funciones anteriores y financia el núcleo gratuito y de código abierto.

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/Obtener-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="Obtener MacMix Studio"></a>
</p>

Los informes de errores y las ideas son bienvenidos en [Issues](https://github.com/ljmng7/MacMix/issues).

## Licencia

El código fuente se publica con la [licencia MIT](../../LICENSE). El icono de la app, las capturas y otros recursos de marca **no** están cubiertos por la licencia MIT y no pueden reutilizarse sin permiso. Consulta [Recursos de marca](../../BRAND-ASSETS.md).
