<p align="center">
  <img src="Docs/images/og-image.webp" alt="MacMix — Mac’inizin sesi. Hepsi MacMix’te. macOS menü çubuğu için yerel bir mikser: sistem ses düzeyi, çıkış ve giriş aygıtları ve her uygulamanın sesi." width="100%">
  <br>
  <sub>Ekran görüntüsü dağıtım sürümüne aittir. Bazı özellikler MacMix Studio gerektirir.</sub>
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
  <a href="README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <a href="README.th.md">ไทย</a> · <a href="README.vi.md">Tiếng Việt</a> · <b>Türkçe</b> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/macOS_i%C3%A7in_indir-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="MacMix’i macOS için indir">
  </a>
</p>

<p align="center">
  <a href="#özellikler">Özellikler</a> ·
  <a href="#açık-kaynak-ve-dağıtım-sürümü">Açık kaynak ve dağıtım sürümü</a> ·
  <a href="#kurulum">Kurulum</a> ·
  <a href="#gizlilik">Gizlilik</a> ·
  <a href="#kaynaktan-derleme">Kaynaktan derleme</a> ·
  <a href="#macmixi-destekleyin">Destek</a>
</p>

---

## Neden MacMix

macOS size tek bir ses kaydırıcısı verir. MacMix gerisini verir: müziğinize dokunmadan gürültülü bir uygulamanın sesini kısın, AirPods, hoparlör ve monitör arasında tek tıkla geçin ve aramadan önce doğru mikrofonu seçin. Hepsi menü çubuğundaki kompakt, yerel bir panelden, Sistem Ayarları’nı açmadan.

## Özellikler

### 🔊 Ses düzeyi

- Geçerli çıkış aygıtının **sistem ses düzeyi**, doğrudan menü çubuğunda.
- macOS ses denetimi sunmadığında DDC/CI ile **harici ekran hoparlörleri**; olağandışı aralık bildiren monitörler için uyumluluk düzeltmeleriyle.
- **Gerçek sıfır**: kaydırıcı %0’a indiğinde aygıt, hafif bir ses bırakmadan tamamen susar.

### 🎧 Aygıtlar

- Hoparlörler, kulaklıklar, AirPods, ekranlar ve daha fazlası arasında **çıkışı değiştirin**.
- **AirPlay alıcıları adlarıyla**: her HomePod veya AirPlay hoparlörü kendi satırında yer alır ve etkin bir gruptan tek bir alıcıya geçebilirsiniz.
- AirPods, Beats, HomePod, Apple TV, harici ekranlar ve Mac’inizin kendi hoparlörleri için **tanıdık simgeler**; ayrıca aygıtın kendi sağladığı simge.
- Aynı panelden **mikrofon değiştirin** ve giriş ses düzeyini ayarlayın.

### 🎚️ Uygulama başına karıştırma

- Çalarken **herhangi bir uygulamanın sesini kısın** ya da **%200**’e kadar yükseltin (isteğe bağlı, Ayarlar’da).
- **Ses düzeylerinizi hatırlar** ve uygulama yeniden çaldığında geri yükler.
- WebKit ile medya oynatan iPad uygulamaları dahil, web tabanlı oynatmanın arkasındaki **gerçek uygulamayı bulur**.

### 🍃 Hafif tasarım

- Menü çubuğunda sessizce çalışır; ayarlar için isteğe bağlı bir pencere sunar.
- Yerel SwiftUI, ses yerel olarak gerçek zamanlı işlenir, hesap gerekmez.
- Sparkle ile otomatik güncellemeler.

## Açık kaynak ve dağıtım sürümü

Bu depo MacMix’in **ücretsiz ve açık kaynak çekirdeğini** içerir. Releases sayfasındaki indirme **dağıtım sürümüdür**: ücretsiz kullanılan tek bir uygulama; **MacMix Studio** ise isteğe bağlı, tek seferlik bir yükseltmedir. Ayrı bir “Studio uygulaması” yoktur; lisans aynı uygulamada ek özelliklerin kilidini açar ve ayarlarınız olduğu gibi kalır.

| Dahil olan özellikler | <div align="center">Açık kaynak<br><sub>(bu depo)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Dağıtım sürümü<br><sub>(ücretsiz)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">Dağıtım sürümü<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| Sistem, ekran ve uygulama ses düzeyi | ✅ | ✅ | ✅ |
| Çıkış, AirPlay ve giriş aygıtı değiştirme | ✅ | ✅ | ✅ |
| Uygulama başına %200 yükseltme | ✅ | ✅ | ✅ |
| Geliştirici tarafından imzalı ve onaylı | — | ✅ | ✅ |
| Anonimleştirilmiş tanılama kayıtlarıyla geri bildirim | — | ✅ | ✅ |
| **Özel EQ** — her uygulamanın sesini ayarlayın ve ön ayar olarak kaydedin | — | — | ✅ |
| **Çoklu Cihaz Çıkışı** — bir uygulamayı aynı anda birden çok aygıtta çalın, her aygıtın kendi ses düzeyiyle | — | — | ✅ |
| **Pro Denetimler** — Bluetooth aygıt pil düzeyleri, Dinleme Modu ve Uzamsal Ses | — | — | ✅ |
| **Şu An Çalınan** — çalan medyayı görüntüleyin ve denetleyin | — | — | ✅ |
| **Sahne Ön Ayarları** — aygıtları ve uygulama ses düzeylerini kaydedin, tek tıkla geçin | — | — | ✅ |
| **Sistem Ses Düzeyi Denetimleri** — daha akıcı denetim için ses tuşlarını devralın | — | — | ✅ |
| **Giriş Aygıtını Kilitle** — macOS’in mikrofonunuzu değiştirmesini önleyin | — | — | ✅ |
| **Engelleme Listesi** — seçtiğiniz uygulamaları karıştırma dışında bırakın | — | — | ✅ |
| **Kişiselleştirme** — özel temalar | — | — | ✅ |
| **Beta Sürümlere Erken Erişim** — yeni özellikleri ilk siz deneyin | — | — | ✅ |

> [!NOTE]
> Studio özellikleri özel olarak geliştirilir ve bu depoda yer almaz. Uygulama başına karıştırma ve 2.0 sürümünden önceki tüm özellikler dahil, ücretsiz olan her şey ücretsiz ve açık kaynak kalacaktır. Ortak çekirdekteki düzeltmeler dağıtım sürümünde doğrulandıktan sonra bu depoya gelir; bu nedenle buradaki kod en son sürümün biraz gerisinde olabilir.

## Kurulum

1. En son sürümden [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg) dosyasını indirin.
2. Disk görüntüsünü açın ve **MacMix**’i **Uygulamalar** klasörüne sürükleyin.
3. MacMix’i açın ve menü çubuğundaki simgesine tıklayın.

**Gereksinimler:** macOS Sonoma 14.4 veya üstü. Uygulama başına karıştırma ilk kullanımda **Sistem Sesi Kaydı** izni ister; diğer her şey bu izin olmadan çalışır.

## Gizlilik

MacMix sesi **Mac’inizde yerel olarak** işler. Asla ses kaydetmez, saklamaz veya yüklemez.

Uygulama başına karıştırma macOS ses işlem tap’leri üzerine kuruludur; bu yüzden MacMix başka bir uygulamanın ses düzeyini değiştirmeden önce macOS Sistem Sesi Kaydı izni ister. MacMix bu izni yalnızca yerel, gerçek zamanlı karıştırma için kullanır.

## Kaynaktan derleme

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

**MacMix** şemasını seçip **Run**’a basın. Xcode, Swift paketlerini (Sparkle ve Swift Atomics) otomatik olarak çözer.

Regresyon testleri yalnızca Xcode komut satırı araçlarını gerektiren basit betiklerdir:

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>Notlar ve sınırlamalar</strong></summary>

<br>

- Uygulamalar, yalnızca macOS ses çıkardıklarını bildirdiği sürece mikserde görünür.
- Uygulama ses düzeyleri yerel olarak saklanır ve aynı uygulama yeniden çaldığında geri yüklenir.
- Ekran ses düzeyi için, kullanılan kablo veya yuva üzerinden DDC/CI hoparlör ses düzeyini (VCP `0x62`) destekleyen bir monitör gerekir. DisplayLink adaptörleri, bazı HDMI bağlantıları, televizyonlar ve ekran menüsünde DDC/CI kapalı olan monitörler bunu sunmayabilir.
- AirPlay alıcı adları AirPlay aygıtının veri kaynaklarından gelir. macOS bir ad bildirmediğinde MacMix tahmin etmek yerine genel AirPlay aygıtını gösterir.

</details>

## MacMix’i destekleyin

MacMix gününüzün bir parçasıysa **MacMix Studio**’ya yükseltmeyi düşünün. Tek seferlik bir satın alma ile yukarıdaki özelliklerin kilidini açar ve ücretsiz, açık kaynak çekirdeği destekler.

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/Edinin-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="MacMix Studio’yu edinin"></a>
</p>

Hata bildirimleri ve fikirler [Issues](https://github.com/ljmng7/MacMix/issues) bölümünde memnuniyetle karşılanır.

## Lisans

Kaynak kodu [MIT Lisansı](LICENSE) ile yayımlanır. Uygulama simgesi, ekran görüntüleri ve diğer marka öğeleri MIT Lisansı kapsamında **değildir** ve izin alınmadan yeniden kullanılamaz. Bkz. [Marka öğeleri](BRAND-ASSETS.md).
