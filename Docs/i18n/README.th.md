<p align="center">
  <img src="../images/og-image.webp" alt="MacMix — เสียงทั้งหมดของ Mac อยู่ใน MacMix มิกเซอร์แบบเนทีฟสำหรับแถบเมนู macOS: ระดับเสียงระบบ อุปกรณ์เอาต์พุตและอินพุต และเสียงของแต่ละแอป" width="100%">
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
  <a href="../../README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <b>ไทย</b> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
</p>

<p align="center">
  <a href="https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg">
    <img src="https://img.shields.io/badge/%E0%B8%94%E0%B8%B2%E0%B8%A7%E0%B8%99%E0%B9%8C%E0%B9%82%E0%B8%AB%E0%B8%A5%E0%B8%94%E0%B8%AA%E0%B8%B3%E0%B8%AB%E0%B8%A3%E0%B8%B1%E0%B8%9A_macOS-MacMix.dmg-111111?style=for-the-badge&logo=apple&logoColor=white&labelColor=7A5CFA" alt="ดาวน์โหลด MacMix สำหรับ macOS">
  </a>
</p>

<p align="center">
  <a href="#คุณสมบัติ">คุณสมบัติ</a> ·
  <a href="#รุ่นโอเพนซอร์สและรุ่นเผยแพร่">โอเพนซอร์สและรุ่นเผยแพร่</a> ·
  <a href="#การติดตั้ง">การติดตั้ง</a> ·
  <a href="#ความเป็นส่วนตัว">ความเป็นส่วนตัว</a> ·
  <a href="#สร้างจากซอร์สโค้ด">สร้างจากซอร์สโค้ด</a> ·
  <a href="#สนับสนุน-macmix">สนับสนุน</a> ·
  <a href="#สัญญาอนุญาตและเครื่องหมายการค้า">สัญญาอนุญาต</a>
</p>

---

## ทำไมต้อง MacMix

macOS ให้แถบเลื่อนระดับเสียงมาเพียงอันเดียว MacMix เติมส่วนที่เหลือให้ครบ: ลดเสียงแอปที่ดังรบกวนโดยไม่แตะเพลงของคุณ สลับระหว่าง AirPods ลำโพง และจอภาพได้ในคลิกเดียว และเลือกไมโครโฟนที่ถูกต้องก่อนเริ่มสาย ทั้งหมดนี้ทำได้จากแผงเนทีฟขนาดกะทัดรัดในแถบเมนู โดยไม่ต้องเปิดการตั้งค่าระบบ

## คุณสมบัติ

### 🔊 ระดับเสียง

- **ระดับเสียงระบบ** ของอุปกรณ์เอาต์พุตปัจจุบัน ปรับได้ทันทีจากแถบเมนู
- **ลำโพงของจอภาพภายนอก** ผ่าน DDC/CI เมื่อ macOS ไม่มีตัวควบคุมระดับเสียงให้ พร้อมการแก้ไขสำหรับจอที่รายงานช่วงค่าผิดปกติ
- **ศูนย์จริง**: เลื่อนแถบไปที่ 0% แล้วอุปกรณ์จะเงียบสนิท ไม่มีเสียงแผ่ว ๆ หลงเหลือ

### 🎧 อุปกรณ์

- **สลับเอาต์พุต** ระหว่างลำโพง หูฟัง AirPods จอภาพ และอื่น ๆ
- **แสดงตัวรับ AirPlay ตามชื่อ**: HomePod หรือลำโพง AirPlay แต่ละตัวมีแถวของตัวเอง และสลับจากกลุ่มที่ใช้งานอยู่ไปยังตัวรับเดียวได้
- **ไอคอนที่จดจำได้ง่าย** สำหรับ AirPods, Beats, HomePod, Apple TV, จอภาพภายนอก และลำโพงในตัวของ Mac รวมถึงไอคอนที่อุปกรณ์ให้มาเอง
- **สลับไมโครโฟน** และปรับระดับเสียงอินพุตได้จากแผงเดียวกัน

### 🎚️ มิกซ์เสียงแยกแต่ละแอป

- **ลดเสียงแอปใดก็ได้** ขณะกำลังเล่น หรือเพิ่มได้สูงสุด **200%** (เลือกเปิดได้ในการตั้งค่า)
- **จำระดับเสียงของคุณ** และคืนค่าเมื่อแอปกลับมาเล่นอีกครั้ง
- **ค้นหาแอปตัวจริง** ที่อยู่เบื้องหลังการเล่นผ่านเว็บ รวมถึงแอป iPad ที่เล่นสื่อผ่าน WebKit

### 🍃 ออกแบบให้เบา

- ทำงานเงียบ ๆ ในแถบเมนู พร้อมหน้าต่างการตั้งค่าเมื่อต้องการ
- SwiftUI แบบเนทีฟ ประมวลผลเสียงบนเครื่องแบบเรียลไทม์ ไม่ต้องใช้บัญชี
- แอปทางการอัปเดตตัวเองผ่าน Sparkle

## รุ่นโอเพนซอร์สและรุ่นเผยแพร่

**ฟีเจอร์ทั้งหมดของ MacMix เป็นโอเพนซอร์ส รวมถึง MacMix Studio** หากบิลด์ที่เก็บนี้เอง คุณจะได้แอปฉบับเต็มที่ปลดล็อกทุกฟีเจอร์ โดยไม่ต้องใช้สัญญาอนุญาต ไม่ต้องมีบัญชี และไม่มีอะไรถูกกันไว้

ไฟล์ดาวน์โหลดในหน้า Releases คือ **รุ่นเผยแพร่** ซึ่งเป็นบิลด์ทางการของแอปเดียวกัน ใช้ได้ฟรี โดยมี **MacMix Studio** เป็นการซื้อครั้งเดียวแบบไม่บังคับเพื่อปลดล็อกฟีเจอร์ Studio ในบิลด์นั้น ไม่มี “แอป Studio” แยกต่างหาก สัญญาอนุญาตเพียงปลดล็อกฟีเจอร์ในแอปเดิม และการตั้งค่าของคุณยังคงอยู่เหมือนเดิม

| คุณสมบัติที่รวมอยู่ | <div align="center">บิลด์จากซอร์สโค้ด<br><sub>(ที่เก็บนี้)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">รุ่นเผยแพร่<br><sub>(ฟรี)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">รุ่นเผยแพร่<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| ระดับเสียงระบบ จอภาพ และแต่ละแอป | ✅ | ✅ | ✅ |
| สลับอุปกรณ์เอาต์พุต AirPlay และอินพุต | ✅ | ✅ | ✅ |
| เพิ่มเสียงแต่ละแอปได้ถึง 200% | ✅ | ✅ | ✅ |
| ส่งคำติชมพร้อมบันทึกการวินิจฉัยแบบไม่ระบุตัวตน | ✅ | ✅ | ✅ |
| **EQ แบบกำหนดเอง** — ปรับเสียงของแต่ละแอปและบันทึกเป็นค่าที่ตั้งไว้ | ✅ | — | ✅ |
| **เอาต์พุตหลายอุปกรณ์** — เล่นแอปเดียวบนหลายอุปกรณ์พร้อมกัน โดยแต่ละอุปกรณ์มีระดับเสียงของตัวเอง | ✅ | — | ✅ |
| **การควบคุมระดับ Pro** — ดูระดับแบตเตอรี่อุปกรณ์ Bluetooth ควบคุมโหมดการฟังและเสียงเชิงมิติพื้นที่ | ✅ | — | ✅ |
| **กำลังเล่น** — ดูและควบคุมสื่อที่กำลังเล่น | ✅ | — | ✅ |
| **ค่าฉากที่ตั้งไว้** — บันทึกอุปกรณ์และระดับเสียงแอป แล้วสลับได้ในคลิกเดียว | ✅ | — | ✅ |
| **การควบคุมระดับเสียงของระบบ** — รับช่วงปุ่มปรับเสียงเพื่อการควบคุมที่ลื่นไหลยิ่งขึ้น | ✅ | — | ✅ |
| **ล็อกอุปกรณ์อินพุต** — ป้องกันไม่ให้ macOS สลับไมโครโฟนเอง | ✅ | — | ✅ |
| **รายการบล็อก** — ไม่นำแอปที่เลือกเข้าร่วมการมิกซ์ | ✅ | — | ✅ |
| **การปรับแต่งเฉพาะบุคคล** — ธีมที่กำหนดเอง | ✅ | — | ✅ |
| ลงนามและรับรองโดยผู้พัฒนา | — | ✅ | ✅ |
| อัปเดตอัตโนมัติ | — | ✅ | ✅ |
| **ทดลองใช้รุ่นเบต้าก่อนใคร** — ลองคุณสมบัติใหม่ก่อนใคร | — | — | ✅ |

> [!NOTE]
> ส่วนที่ยังเป็นส่วนตัวมีเพียงส่วนที่มีไว้สำหรับรุ่นเผยแพร่เท่านั้น ได้แก่ การเปิดใช้งานสัญญาอนุญาต ขั้นตอนการซื้อ หน้าแนะนำเริ่มต้น และตัวอัปเดต ไม่มีส่วนใดจำเป็นต่อการบิลด์หรือรัน MacMix และบิลด์จากที่เก็บนี้ไม่มีส่วนเหล่านี้เลย

## การติดตั้ง

1. ดาวน์โหลด [`MacMix.dmg`](https://github.com/ljmng7/MacMix/releases/latest/download/MacMix.dmg) จากรุ่นล่าสุด
2. เปิดอิมเมจดิสก์แล้วลาก **MacMix** ไปไว้ในโฟลเดอร์ **แอปพลิเคชัน**
3. เปิด MacMix แล้วคลิกไอคอนในแถบเมนู

**ความต้องการของระบบ:** macOS Sonoma 14.4 ขึ้นไป การมิกซ์แยกแต่ละแอปจะขอสิทธิ์ **การบันทึกเสียงระบบ** ในการใช้งานครั้งแรก คุณสมบัติอื่นทำงานได้โดยไม่ต้องใช้สิทธิ์นี้

## ความเป็นส่วนตัว

MacMix ประมวลผลเสียง **บน Mac ของคุณเอง** และไม่เคยบันทึก จัดเก็บ หรืออัปโหลดเสียง

การมิกซ์แยกแต่ละแอปสร้างขึ้นบน audio process tap ของ macOS ดังนั้น macOS จะขอสิทธิ์การบันทึกเสียงระบบก่อนที่ MacMix จะเปลี่ยนระดับเสียงของแอปอื่นได้ MacMix ใช้สิทธิ์นี้เพื่อการมิกซ์บนเครื่องแบบเรียลไทม์เท่านั้น

## สร้างจากซอร์สโค้ด

```sh
git clone https://github.com/ljmng7/MacMix.git
cd MacMix
open MacMix.xcodeproj
```

เลือกสคีม **MacMix** แล้วกด **Run** Xcode จะดึงแพ็กเกจ Swift (MenuBarExtraAccess และ Swift Atomics) ให้อัตโนมัติ แอปที่คุณบิลด์จะปลดล็อกฟีเจอร์ Studio ทั้งหมด

หากไม่ได้ตั้งค่าทีมนักพัฒนา Xcode จะเซ็นแอปเพื่อรันบนเครื่องนี้เท่านั้น และ macOS อาจขอสิทธิ์ **การบันทึกเสียงระบบ** ใหม่ทุกครั้งที่บิลด์ใหม่ หากต้องการเก็บสิทธิ์ไว้ ให้คัดลอก `Config/Local.example.xcconfig` เป็น `Config/Local.xcconfig` แล้วใส่ `DEVELOPMENT_TEAM` ของคุณเอง Git จะไม่ติดตามไฟล์นี้

บิลด์จากซอร์สโค้ดจะไม่อัปเดตตัวเอง หากต้องการอัปเดต ให้ดึงซอร์สโค้ดล่าสุดแล้วบิลด์ใหม่

การทดสอบถดถอยเป็นสคริปต์ธรรมดาที่ต้องใช้เพียงเครื่องมือบรรทัดคำสั่งของ Xcode:

```sh
for test in tests/run-*.sh; do bash "$test"; done
```

<details>
<summary><strong>หมายเหตุและข้อจำกัด</strong></summary>

<br>

- แอปจะปรากฏในมิกเซอร์เฉพาะขณะที่ macOS รายงานว่ากำลังส่งเสียงออก
- ระดับเสียงของแต่ละแอปบันทึกไว้บนเครื่อง และคืนค่าเมื่อแอปเดิมกลับมาเล่น
- การปรับเสียงจอภาพต้องใช้จอที่รองรับระดับเสียงลำโพง DDC/CI (VCP `0x62`) ผ่านสายหรือด็อกที่ใช้อยู่ อะแดปเตอร์ DisplayLink การเชื่อมต่อ HDMI บางแบบ ทีวี และจอที่ปิด DDC/CI ในเมนู OSD อาจไม่รองรับ
- ชื่อตัวรับ AirPlay มาจากแหล่งข้อมูลของอุปกรณ์ AirPlay หาก macOS ไม่รายงานชื่อ MacMix จะแสดงเป็นอุปกรณ์ AirPlay ทั่วไปแทนการเดา

</details>

## สนับสนุน MacMix

การบิลด์จากซอร์สโค้ดฟรีและจะฟรีตลอดไป หาก MacMix เป็นส่วนหนึ่งในวันของคุณ ลองพิจารณาซื้อ **MacMix Studio** ซึ่งเป็นการซื้อครั้งเดียวที่ปลดล็อกฟีเจอร์ Studio ในรุ่นเผยแพร่ (แอปทางการที่ผ่านการเซ็นและรับรองจาก Apple และอัปเดตตัวเองอยู่เสมอ) และสนับสนุนการพัฒนา MacMix โดยตรง

<p align="center">
  <a href="https://macmix.jazminli.com/studio"><img src="https://img.shields.io/badge/%E0%B8%A3%E0%B8%B1%E0%B8%9A-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="รับ MacMix Studio"></a>
</p>

ยินดีรับรายงานข้อบกพร่องและไอเดียใน [Issues](https://github.com/ljmng7/MacMix/issues) หากต้องการร่วมพัฒนาโค้ด โปรดดู[แนวทางการมีส่วนร่วม](../../CONTRIBUTING.md) โดย pull request ต้องมีการลงนามในข้อตกลงสัญญาอนุญาตสำหรับผู้มีส่วนร่วม (CLA)

## สัญญาอนุญาตและเครื่องหมายการค้า

MacMix เป็นซอฟต์แวร์เสรี คุณสามารถเผยแพร่ซ้ำและ/หรือแก้ไขได้ภายใต้เงื่อนไขของ [GNU General Public License รุ่นที่ 3](../../LICENSE) (GPL-3.0) เวอร์ชันจนถึงและรวมถึง 2.3.2 เผยแพร่ภายใต้สัญญาอนุญาต MIT โค้ดที่คุณได้รับภายใต้เงื่อนไขนั้นยังใช้ได้ภายใต้เงื่อนไขเดิม

**เครื่องหมายการค้า** ชื่อ “MacMix” และไอคอนแอป MacMix ใช้ระบุแอปทางการ และสงวนไว้สำหรับบิลด์ทางการเท่านั้น GPL ครอบคลุมโค้ด ไม่ได้ครอบคลุมชื่อหรือแบรนด์ หากคุณเผยแพร่ fork หรือบิลด์ที่แก้ไขแล้ว โปรดใช้ชื่ออื่น ไอคอนอื่น และ bundle identifier อื่น และอย่านำเสนอว่าเป็น MacMix ทางการ การบิลด์และใช้ MacMix เองทำได้เสมอ

ไอคอนแอป ภาพหน้าจอ และสินทรัพย์แบรนด์อื่น ๆ **ไม่** อยู่ภายใต้ GPL และห้ามนำไปใช้ซ้ำโดยไม่ได้รับอนุญาต ดูที่ [สินทรัพย์แบรนด์](../../BRAND-ASSETS.md)
