<p align="center">
  <img src="../images/og-image.webp" alt="MacMix — Весь звук вашего Mac — в MacMix. Нативный микшер для строки меню macOS: системная громкость, устройства вывода и ввода и звук каждого приложения." width="100%">
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
  <a href="../../README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <b>Русский</b> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/%D0%A1%D0%BA%D0%B0%D1%87%D0%B0%D1%82%D1%8C_%D0%B4%D0%BB%D1%8F_macOS-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="Скачать MacMix для macOS">
  </a>
</p>

<p align="center">
  <a href="#возможности">Возможности</a> ·
  <a href="#открытый-код-и-distribution">Открытый код и Distribution</a> ·
  <a href="#установка">Установка</a> ·
  <a href="#конфиденциальность">Конфиденциальность</a> ·
  <a href="#сборка-из-исходников">Сборка из исходников</a> ·
  <a href="#поддержать-macmix">Поддержать</a> ·
  <a href="#лицензия-и-товарный-знак">Лицензия</a>
</p>

---

## Зачем нужен MacMix

В macOS один ползунок громкости. MacMix добавляет всё остальное: приглушите шумное приложение, не трогая музыку, переключайтесь между AirPods, колонками и монитором в один клик и выбирайте нужный микрофон перед звонком. Всё это — в компактной нативной панели в строке меню, без открытия Системных настроек.

## Возможности

### 🔊 Громкость

- **Системная громкость** текущего устройства вывода прямо в строке меню.
- **Динамики внешних мониторов** через DDC/CI, когда macOS не даёт регулировать громкость, с исправлениями для мониторов, сообщающих необычные диапазоны.
- **Настоящий ноль**: при 0 % устройство полностью замолкает, без слабого остаточного звука.

### 🎧 Устройства

- **Переключайте вывод** между динамиками, наушниками, AirPods, мониторами и другими устройствами.
- **Приёмники AirPlay по имени**: у каждого HomePod или динамика AirPlay своя строка, и из активной группы можно переключиться на один приёмник.
- **Узнаваемые значки** для AirPods, Beats, HomePod, Apple TV, внешних мониторов и встроенных динамиков Mac, а также значок, который предоставляет само устройство.
- **Переключайте микрофоны** и меняйте громкость входа в той же панели.

### 🎚️ Громкость приложений

- **Приглушайте любое приложение** во время воспроизведения или усиливайте его до **200 %** (включается в настройках).
- **Запоминает уровни** и восстанавливает их, когда приложение снова начинает играть.
- **Находит настоящее приложение** за веб-воспроизведением, включая приложения для iPad, которые воспроизводят медиа через WebKit.

### 🍃 Лёгкость по задумке

- Незаметно работает в строке меню, окно настроек — по желанию.
- Нативный SwiftUI, звук обрабатывается локально в реальном времени, учётная запись не нужна.
- Официальное приложение обновляется само через Sparkle.

## Открытый код и Distribution

**Все функции MacMix открыты, включая MacMix Studio.** Соберите этот репозиторий сами — и получите полное приложение со всеми разблокированными функциями: без лицензии, без учётной записи, без ограничений.

На странице Releases можно скачать **Distribution** — официальную сборку того же приложения. Она бесплатна, а **MacMix Studio** — необязательная разовая покупка, которая разблокирует функции Studio в этой сборке. Отдельного «приложения Studio» нет: лицензия разблокирует функции в том же приложении, а ваши настройки остаются на месте.

| Что входит | <div align="center">Сборка из исходников<br>код<br><sub>(этот репозиторий)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(бесплатно)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Distribution<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| Громкость системы, монитора и приложений | ✅ | ✅ | ✅ |
| Переключение устройств вывода, AirPlay и ввода | ✅ | ✅ | ✅ |
| Усиление приложений до 200 % | ✅ | ✅ | ✅ |
| Отзывы с анонимизированными диагностическими журналами | ✅ | ✅ | ✅ |
| **Пользовательский EQ** — настраивайте звук каждого приложения и сохраняйте пресеты | ✅ | — | ✅ |
| **Вывод на несколько устройств** — одно приложение на нескольких устройствах сразу, у каждого своя громкость | ✅ | — | ✅ |
| **Управление Pro** — заряд устройств Bluetooth, режим прослушивания и пространственное аудио | ✅ | — | ✅ |
| **Сейчас играет** — просмотр и управление текущим воспроизведением | ✅ | — | ✅ |
| **Предустановки сцен** — сохраняйте устройства и громкость приложений и переключайтесь в один клик | ✅ | — | ✅ |
| **Управление системной громкостью** — перехват клавиш громкости для более плавной регулировки | ✅ | — | ✅ |
| **Закрепить устройство ввода** — macOS не будет сама менять микрофон | ✅ | — | ✅ |
| **Чёрный список** — исключите выбранные приложения из микширования | ✅ | — | ✅ |
| **Персонализация** — собственные темы | ✅ | — | ✅ |
| Подпись и нотаризация разработчиком | — | ✅ | ✅ |
| Автоматические обновления | — | ✅ | ✅ |
| **Ранний доступ к бета-версиям** — пробуйте новые функции первыми | — | — | ✅ |

> [!NOTE]
> Закрытыми остаются только части, которые нужны исключительно для Distribution: активация лицензии, процесс покупки, приветственный экран и механизм обновлений. Ни одна из них не нужна для сборки или запуска MacMix, и сборки из этого репозитория их не содержат.

## Установка

1. Скачайте [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg) из последнего релиза.
2. Откройте образ диска и перетащите **MacMix** в папку **Программы**.
3. Запустите MacMix и нажмите на его значок в строке меню.

**Требования:** macOS Sonoma 14.4 или новее. При первом использовании громкости приложений потребуется разрешение **Запись системного звука**; остальное работает без него.

## Конфиденциальность

MacMix обрабатывает звук **локально на вашем Mac**. Он никогда не записывает, не сохраняет и не отправляет аудио.

Громкость приложений построена на аудио-тапах процессов macOS, поэтому macOS запрашивает разрешение «Запись системного звука», прежде чем MacMix сможет менять громкость другого приложения. MacMix использует это разрешение только для локального микширования в реальном времени.

## Сборка из исходников

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

Выберите схему **MacMix** и нажмите **Run**. Xcode автоматически подтянет пакеты Swift (MenuBarExtraAccess и Swift Atomics). В вашей сборке все функции Studio разблокированы.

Без команды разработчика Xcode подписывает приложение только для локального запуска, и macOS может заново запрашивать разрешение **Запись системного звука** после каждой сборки. Чтобы сохранить разрешение, скопируйте `Config/Local.example.xcconfig` в `Config/Local.xcconfig` и укажите свой `DEVELOPMENT_TEAM`. Git игнорирует этот файл.

Сборки из исходников не обновляются сами. Чтобы обновиться, получите свежий код и соберите приложение заново.

Регрессионные тесты — это обычные скрипты, которым нужны только инструменты командной строки Xcode:

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>Примечания и ограничения</strong></summary>

<br>

- Приложения появляются в микшере, только пока macOS сообщает, что они выводят звук.
- Уровни приложений хранятся локально и восстанавливаются, когда то же приложение снова играет.
- Для громкости монитора нужен дисплей с поддержкой громкости динамиков DDC/CI (VCP `0x62`) через текущий кабель или док-станцию. Адаптеры DisplayLink, некоторые подключения HDMI, телевизоры и мониторы с выключенным в экранном меню DDC/CI могут её не поддерживать.
- Имена приёмников AirPlay берутся из источников данных устройства AirPlay. Если macOS не сообщает имя, MacMix показывает обычное устройство AirPlay, а не угадывает.

</details>

## Поддержать MacMix

Сборка из исходников бесплатна и останется бесплатной. Если MacMix стал частью вашего дня, подумайте о покупке **MacMix Studio**: разовая покупка разблокирует функции Studio в Distribution — подписанном, нотаризованном приложении, которое само обновляется, — и напрямую поддерживает разработку MacMix.

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/%D0%9F%D0%BE%D0%BB%D1%83%D1%87%D0%B8%D1%82%D1%8C-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="Получить MacMix Studio"></a>
</p>

Сообщения об ошибках и идеи принимаются в [Issues](https://github.com/ljmng7/MacMix/issues). Чтобы внести вклад в код, прочитайте [руководство для участников](../../CONTRIBUTING.md); для pull request нужно подписать лицензионное соглашение участника (CLA).

## Лицензия и товарный знак

MacMix — свободное программное обеспечение: вы можете распространять и/или изменять его на условиях [Стандартной общественной лицензии GNU, версия 3](../../LICENSE) (GPL-3.0). Версии до 2.3.2 включительно выпускались по лицензии MIT; код, полученный на этих условиях, остаётся доступным на них.

**Товарный знак.** Название «MacMix» и значок приложения MacMix обозначают официальное приложение и зарезервированы для официальных сборок. GPL распространяется на код, а не на название или бренд. Если вы распространяете форк или изменённую сборку, дайте ей другое название, другой значок и другой идентификатор пакета и не выдавайте её за официальный MacMix. Собирать и использовать MacMix для себя можно всегда.

Значок приложения, снимки экрана и другие элементы бренда **не** подпадают под GPL, и их нельзя использовать без разрешения. Подробнее — в разделе [Элементы бренда](../../BRAND-ASSETS.md).
