# R27U91 / 雷鸟 U9 DDC 对照测试

此分支基于公开 fork，移植私有版 2.2.1 的 DDC 修复；不包含私有 Studio 模块。
保留异常最大音量 0/65535 回退到 100，接受类型字段 00 或 01 的有效回复。

两个布尔键位于 `Config/MacMix-Info.plist`，仅作用于显示器名称 R27U91（忽略大小写）。
其他显示器保留标准静音行为。可改 plist 后重新编译，或用以下命令覆盖；每次切换后退出并重新打开 App。

| 模式 | MacMixDDCU9SendMuteCommands | MacMixDDCU9InvertMuteValues |
| --- | --- | --- |
| A：只写音量（默认） | false | false |
| B：标准静音值 | true | false |
| C：反转静音值 | true | true |

反转仅交换 0x8D 的数据：标准静音=1、取消静音=2；反转后静音=2、取消静音=1。
关闭发送开关时，反转开关不生效，静音通过 0x62=0 实现。

```sh
# A：不发送 0x8D
defaults write jazmin.MacMix MacMixDDCU9SendMuteCommands -bool false
defaults write jazmin.MacMix MacMixDDCU9InvertMuteValues -bool false

# B：标准值
defaults write jazmin.MacMix MacMixDDCU9SendMuteCommands -bool true
defaults write jazmin.MacMix MacMixDDCU9InvertMuteValues -bool false

# C：反转值
defaults write jazmin.MacMix MacMixDDCU9SendMuteCommands -bool true
defaults write jazmin.MacMix MacMixDDCU9InvertMuteValues -bool true

# 删除覆盖，恢复 plist 默认
defaults delete jazmin.MacMix MacMixDDCU9SendMuteCommands
defaults delete jazmin.MacMix MacMixDDCU9InvertMuteValues
```

若自行修改了 Bundle Identifier（例如 jazmin.MacMix.DDCDiagnostic），将上述 jazmin.MacMix 替换为实际值。
用户默认值覆盖 plist，所以改 plist 前应删除已有覆盖。

测试每个模式前，用显示器 OSD 恢复非静音和较低的已知音量，再启动 App 播放同一段音频。
分别测试滑块 10%、30%、50%，静音按钮及取消静音，滑块到 0 后再提高；记录 OSD 音量和实际声音。
模式 A 不能解除先前通过 0x8D 留下的硬件静音，必须先通过 OSD 恢复。
只有 B 无声、C 正常且静音/取消静音都符合预期，才支持“值反转”的假设；A 正常仅能说明额外的 0x8D 有影响。

回归测试：`bash tests/run-ddc-volume-tests.sh`。
自动化测试覆盖真实回复、范围、各开关组合和其他型号隔离；实际硬件声音仍需用户验证。
