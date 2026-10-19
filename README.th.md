<p align="center">
  <img src="Docs/images/og-image.webp" alt="MacMix — เสียงทั้งหมดของ Mac อยู่ใน MacMix มิกเซอร์แบบเนทีฟสำหรับแถบเมนู macOS: ระดับเสียงระบบ อุปกรณ์เอาต์พุตและอินพุต และเสียงของแต่ละแอป" width="100%">
  <br>
  <sub>ภาพหน้าจอนี้เป็นรุ่นเผยแพร่ คุณสมบัติบางอย่างต้องใช้ MacMix Studio</sub>
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
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.es.md">Español</a> · <a href="README.it.md">Italiano</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a> · <a href="README.ar.md">العربية</a> · <a href="README.hi.md">हिन्दी</a> · <a href="README.id.md">Bahasa Indonesia</a> · <b>ไทย</b> · <a href="README.vi.md">Tiếng Việt</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.nl.md">Nederlands</a> · <a href="README.pl.md">Polski</a>
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
  <a href="#สนับสนุน-macmix">สนับสนุน</a>
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
- อัปเดตอัตโนมัติผ่าน Sparkle

## รุ่นโอเพนซอร์สและรุ่นเผยแพร่

ที่เก็บนี้มี **แกนหลักของ MacMix ที่ฟรีและเป็นโอเพนซอร์ส** ส่วนไฟล์ดาวน์โหลดในหน้า Releases คือ **รุ่นเผยแพร่** ซึ่งเป็นแอปเดียวที่ใช้ได้ฟรี โดยมี **MacMix Studio** เป็นการอัปเกรดแบบซื้อครั้งเดียวที่เลือกได้ ไม่มี “แอป Studio” แยกต่างหาก ไลเซนส์เพียงปลดล็อกคุณสมบัติเพิ่มเติมในแอปเดิม และการตั้งค่าของคุณยังคงอยู่ครบ

| คุณสมบัติที่รวมอยู่ | <div align="center">โอเพนซอร์ส<br><sub>(ที่เก็บนี้)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">รุ่นเผยแพร่<br><sub>(ฟรี)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> | <div align="center">รุ่นเผยแพร่<br><sub>(Studio)</sub><br><sub>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</sub></div> |
| --- | :---: | :---: | :---: |
| ระดับเสียงระบบ จอภาพ และแต่ละแอป | ✅ | ✅ | ✅ |
| สลับอุปกรณ์เอาต์พุต AirPlay และอินพุต | ✅ | ✅ | ✅ |
| เพิ่มเสียงแต่ละแอปได้ถึง 200% | ✅ | ✅ | ✅ |
| ลงนามและรับรองโดยผู้พัฒนา | — | ✅ | ✅ |
| ส่งคำติชมพร้อมบันทึกการวินิจฉัยแบบไม่ระบุตัวตน | — | ✅ | ✅ |
| **EQ แบบกำหนดเอง** — ปรับเสียงของแต่ละแอปและบันทึกเป็นค่าที่ตั้งไว้ | — | — | ✅ |
| **เอาต์พุตหลายอุปกรณ์** — เล่นแอปเดียวบนหลายอุปกรณ์พร้อมกัน โดยแต่ละอุปกรณ์มีระดับเสียงของตัวเอง | — | — | ✅ |
| **การควบคุมระดับ Pro** — ดูระดับแบตเตอรี่อุปกรณ์ Bluetooth ควบคุมโหมดการฟังและเสียงเชิงมิติพื้นที่ | — | — | ✅ |
| **กำลังเล่น** — ดูและควบคุมสื่อที่กำลังเล่น | — | — | ✅ |
| **ค่าฉากที่ตั้งไว้** — บันทึกอุปกรณ์และระดับเสียงแอป แล้วสลับได้ในคลิกเดียว | — | — | ✅ |
| **การควบคุมระดับเสียงของระบบ** — รับช่วงปุ่มปรับเสียงเพื่อการควบคุมที่ลื่นไหลยิ่งขึ้น | — | — | ✅ |
| **ล็อกอุปกรณ์อินพุต** — ป้องกันไม่ให้ macOS สลับไมโครโฟนเอง | — | — | ✅ |
| **รายการบล็อก** — ไม่นำแอปที่เลือกเข้าร่วมการมิกซ์ | — | — | ✅ |
| **การปรับแต่งเฉพาะบุคคล** — ธีมที่กำหนดเอง | — | — | ✅ |
| **ทดลองใช้รุ่นเบต้าก่อนใคร** — ลองคุณสมบัติใหม่ก่อนใคร | — | — | ✅ |

> [!NOTE]
> คุณสมบัติของ Studio พัฒนาแบบส่วนตัวและไม่ได้อยู่ในที่เก็บนี้ ทุกอย่างที่ฟรีอยู่แล้ว รวมถึงการมิกซ์แยกแต่ละแอปและคุณสมบัติทั้งหมดก่อนเวอร์ชัน 2.0 จะยังคงฟรีและเป็นโอเพนซอร์สต่อไป การแก้ไขในแกนหลักร่วมจะเข้ามาในที่เก็บนี้หลังจากผ่านการตรวจสอบในรุ่นเผยแพร่แล้ว ดังนั้นโค้ดที่นี่อาจตามหลังรุ่นล่าสุดเล็กน้อย

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

เลือกสคีม **MacMix** แล้วกด **Run** Xcode จะดึงแพ็กเกจ Swift (Sparkle และ Swift Atomics) ให้โดยอัตโนมัติ

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

หาก MacMix เป็นส่วนหนึ่งในวันของคุณ ลองอัปเกรดเป็น **MacMix Studio** ซื้อครั้งเดียวเพื่อปลดล็อกคุณสมบัติด้านบน และช่วยสนับสนุนแกนหลักที่ฟรีและเป็นโอเพนซอร์ส

<p align="center">
  <a href="https://checkout.dodopayments.com/buy/pdt_0NmJ2vOqulR07tfZqwKtU?quantity=1"><img src="https://img.shields.io/badge/%E0%B8%A3%E0%B8%B1%E0%B8%9A-MacMix_Studio-7A5CFA?style=for-the-badge&labelColor=241A3D" alt="รับ MacMix Studio"></a>
</p>

ยินดีรับรายงานข้อบกพร่องและไอเดียใน [Issues](https://github.com/ljmng7/MacMix/issues)

## สัญญาอนุญาต

ซอร์สโค้ดเผยแพร่ภายใต้ [สัญญาอนุญาต MIT](LICENSE) ไอคอนแอป ภาพหน้าจอ และสินทรัพย์แบรนด์อื่น ๆ **ไม่** อยู่ภายใต้สัญญาอนุญาต MIT และห้ามนำไปใช้ซ้ำโดยไม่ได้รับอนุญาต ดูที่ [สินทรัพย์แบรนด์](BRAND-ASSETS.md)
