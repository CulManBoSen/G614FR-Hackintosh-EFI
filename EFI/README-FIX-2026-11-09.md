# G614FR（ASUS ROG / AMD）macOS 15 引导修复说明

日期：2026-11-09　　工作目录：U 盘 EFI（H:\EFI）

---

## 第四轮（11:15）：给功放补 _DSD 的 SSDT

### 发现
把你机器所有 ACPI 表（DSDT + 26 张 SSDT）导出后才发现：**BIOS 其实已经给了全部 cirrus 参数**，
但用的是"一个设备描述两个功放"的数组写法：

| 属性 | BIOS 原值 |
|---|---|
| cirrus,dev-index | { 0x40, 0x41 } |
| cirrus,speaker-position | { 0, 1 } |
| cirrus,boost-type | { 0, 0 } |
| cirrus,gpio1-func | { 0, 0 } |
| cirrus,gpio2-func | { 2, 2 } |
| cirrus,boost-ind-nanohenry | { 1000, 1000 } |
| cirrus,boost-peak-milliamp | { 4500, 4500 } |
| cirrus,boost-cap-microfarad | { 24, 24 } |

CirrusAudioFixup 只认 per-device 的标量（Linux 绑定那套），读到数组就判
`CS35L41_PROPERTIES_INCOMPLETE:cirrus,dev-index`，然后退回用 `_SUB` 认板子、又因为
`1043:1054` 不在它的板级表里而 `BOARD_NOT_AUTHORIZED`。

### 做法
1. `ACPI/SSDT-SPKR-DSD.aml`（338 字节，手写 AML，已逐字节回读校验）：
   `Scope(\_SB.I2CD.SPKR) { Name(_DSD, {UUID, Package(9){...}}) }`，把上面 9 个参数
   用**标量**重新给一遍，数值取自 BIOS 原值的第一个元素。
   同时源码 `SSDT-SPKR-DSD.dsl` 也放在 ACPI 目录里，方便日后改。
2. `config.plist` → `ACPI → Patch` 增加 `_DSD` → `XDSD` 改名（`TableSignature = DSDT`、`Count = 1`）。
   DSDT 里只有 1 处 `_DSD`（就是功放这个），改名后由我们的 SSDT 接管，不会影响触控板。
3. boot-args 增加 `-cirrusdbg`，方便下次从日志看到详细初始化过程。

### 接下来怎么看结果
- 有声音 → 完事，可以把 `-cirrusdbg` 去掉。
- 还是没声音 → 跑 `sudo sh /Volumes/1401/diag.sh`，看 `Cirrus_Platform_Authorized` /
  `Cirrus_Platform_Discovery` / `Cirrus_Runtime_Block_Reason` 三个字段。
- 爆音/破音/卡死 → 用 `config.plist.NO-SSDT` 回退（见 U 盘根目录 README-IF-BOOT-FAILS.txt）。


---

## 第三轮修改（2026-11-09 10:35，根据 diag-report.txt 定位）

### 0. 最重要的一条：之前的 boot-args 一次都没生效
报告里实际运行的是：
`... -vi2c-force-polling ... alcid=11` —— 没有 `yyavic-cc`、没有 `-yyavicnoverify`、没有 `nvrmacpibl`。

原因：OpenCore 的 `NVRAM → Add` 对**已存在**的变量不会覆盖，`boot-args` 必须先出现在
`NVRAM → Delete` 里。你的 `Delete` 里只有 `csr-active-config` 等，**没有 boot-args**，
所以 config 里改多少次启动参数都进不去。
→ 已在 `NVRAM → Delete → 7C436110-…` 中加入 `boot-args`。以后再改启动参数就会真生效。

这也解释了：
- Wi-Fi 一直不回来（`-yyavicnoverify` 从来没进过系统）；
- 亮度调不了（`nvrmacpibl=1` 也从来没生效）。

### 1. 键盘卡顿的真凶：键盘是 I2C HID，不是 PS/2
Windows 里键盘的设备是 `HID\ASUF1416&COL05`（"ASUS Keyboard"），和触控板属于同一个 I2C HID 设备。
报告里 `kmutil showloaded` 也确实**没有 VoodooPS2Controller**（之前那套 PS/2 配置是无效功，已全部关闭）。

而 boot-args 里的 `-vi2c-force-polling` 让整个 I2C HID 设备跑**轮询**模式：键盘靠 8ms 轮询去"问"
有没有按键，问慢了就排队、丢键 —— 正是"几秒好、几秒坏"。
→ 已去掉 `-vi2c-force-polling`，改用 GPIO 中断（VoodooGPIO 这个构建带完整 `VoodooGPIOAMD`，DSDT 里
也有 55 处 `GpioInt`，所以有戏）。
→ 风险：中断没配好时键盘/触控板会直接不动。兜底配置 `config.plist.POLLING`（见 U 盘
`README-IF-BOOT-FAILS.txt`）。

### 2. 声音：其实只差"授权"这一步（重大进展）
报告里 CirrusAudioFixup **已经挂上了**：
`Cirrus_Provider_Path = .../I2CD/VoodooI2CACPIController/.../SPKR`，`Cirrus_Bus = I2C`，
`i2cAddress = 0x40` —— 说明 I2C 传输这条路是通的（之前担心缺 `VoodooI2CTransferToAddress` 是多余的）。

它停在授权环节：
- `Cirrus_Platform_ACPI_SSID = 0x10431054`（你这台功放的 ACPI 子系统 ID）
- `Cirrus_Attach_Latest_Reason = BOARD_NOT_AUTHORIZED`
- `Cirrus_Platform_Discovery = CS35L41_PROPERTIES_INCOMPLETE:cirrus,dev-index`
- `Cirrus_Driver_Verdict = UNSUPPORTED_PLATFORM`

驱动内置的板级表里 ASUS ROG G614JI 是 `1043:1C9F`，你这台是 `1043:1054`，不在表里，所以拒绝初始化。
驱动支持 `-cirrusssid=` 覆盖固件 SSID（二进制里有 `Explicit firmware SSID override: 0x%08X`）。
→ 已加 `-cirrusssid=10431C9F`，让它按 G614JI 的固件/调音走。同一代 16 寸 ROG 模具，扬声器单元大概率同款。
   如果这次还是 `BOARD_NOT_AUTHORIZED` 或 `CS35L41_PROPERTIES_INCOMPLETE`，下一步就是给 `\_SB.I2CD.SPKR`
   写一个补 `_DSD`（`cirrus,dev-index` 等）的 SSDT，我可以手写 AML 做。

### 3. 亮度
`nvrmacpibl=1`（NVRM 的 ACPI 背光开关）之前同样没生效，这次会真生效，先看亮度滑块是否恢复。

### 4. 显示/整机"不顺"
`WindowServer` 6~15%、`kernel_task` 5~6%，CPU 98% 空闲 —— 不是 CPU 被吃满，是**内屏在 RTX 5070 Ti 上
走 NullMoth 软件帧缓冲**（`nvfb=1 nvaccel=1 nvfbheads=4`，且 `-nvkmsnosmooth` 明确关掉了流畅路径）。
这类卡顿只能靠调 NullMoth 的参数缓解，跟键盘/PS2 无关。
`nvfbhidpi=1` 我已去掉（它一直没生效过，现在生效只会让帧缓冲负载×4）。


---

## 第二轮修改（2026-11-09 10:10，对应"没 Wi-Fi / 还是卡 / 没声音"）

### 1. Wi-Fi 消失的真正原因
YYavicWiFi 0.7.2 是**按 build 硬校验**的：kext 里有字符串 `OS build %s (needs 24H32, macOS 15.8.1)`
和 `native Wi-Fi layer disabled, unsupported macOS`。你的是 **15.8.2**，所以它把自己关掉了 —— 不是装错。

处理：boot-args 加了 **`-yyavicnoverify`**（作者给测试者留的跳过校验开关）。
15.8.1 → 15.8.2 只是安全更新，IO80211/Skywalk 的类布局大概率没变，所以值得一试；
万一内核崩溃，用 U 盘根目录的 `README-IF-BOOT-FAILS.txt` 里的三步恢复（把 `config.plist.FALLBACK` 改名成 `config.plist`）。

`config.plist.FALLBACK` = YYavic 关 + AirportMtkWlan 开 + 无 noverify，是"一定能进系统"的兜底。

### 2. 系统调度不顺畅
上一轮把 VoodooI2C 换成了**带 AMD I2C 控制器支持**的构建。之前那个版本在你这台 AMD 机器上根本挂不上
`AMDI0010`，所以什么都没发生；现在它会真的接管 I2C，而 boot-args 里还有 `-vi2c-force-polling`
（强制轮询），等于让它在工作循环里不停轮询 → 整机掉帧、输入发滞。

处理：**已删掉 `-vi2c-force-polling`**，改回中断模式。副作用：如果触控板因此失灵，说明这台机器的
I2C 中断没接好，那就得在"触控板可用"和"整机顺滑"之间二选一，到时候告诉我，我再给你加回来。

### 3. 键盘"几秒好、几秒坏"的另一个重点怀疑：NullMoth 的 HiDPI
`config.plist.nullmoth-hidpi-20261109-100434` 说明 10:04 有人加了 `nvfbhidpi=1`（开机就在 HiDPI 下跑）。
你的内屏是靠 NullMoth 这个**软件帧缓冲**点亮的（RTX 没有硬件加速），HiDPI 会把像素量放大 4 倍，
编辑器/窗口一动就掉帧，表现出来就是"打字一顿一顿、过几秒又好了"。

建议做一次对照：把 `nvfbhidpi=1` 临时去掉，如果卡顿明显好转 → 就是这个，之后在"清晰"和"流畅"之间取舍。
（我没擅自删，因为这是你刚加的。）

### 4. 让机器自己把日志交出来：diag.sh
U 盘根目录新增 `diag.sh`。在 macOS 里执行一次：

```bash
sudo sh /Volumes/<U盘名字>/diag.sh
```

它会在 U 盘根目录生成 `diag-report.txt`，里面有：系统版本、已加载的第三方 kext、CirrusAudioFixup 的
IORegistry 节点、VoodooI2C 的 CSC3551 nub、音频设备列表、最近 15 分钟内核日志（cirrus/voodooi2c/ps2）、
`pmset -g batt` 与电池关键字段、以及 3 次 CPU 占用采样。

跑完重启回 Windows，我直接读这个文件就能判断：
- 声音到底是功放没初始化（`I2C_ADDRESSED_FUNCTION_UNSUPPORTED`）还是布局/静音问题；
- 卡顿是内核线程在占 CPU（`kernel_task` 高）还是帧缓冲问题；
- 电池 `ExternalConnected` / `IsCharging` 的真实值。

---


## 0. 备份与回滚

| 内容 | 位置 |
|---|---|
| 改动前完整 EFI | `H:\EFI-BACKUP-20261109-0930\`（23 MB，直接覆盖回来即可完全还原） |
| 改动前 config | `EFI\OC\config.plist.bak-before-yyavic-audio-20261109` |
| 被替换掉的旧 kext | `EFI\OC\Kexts-Backup\*.kext-old`（AppleALC / VoodooI2C / VoodooPS2Controller） |

回滚最快的办法：把 `EFI-BACKUP-20261109-0930` 里的 `EFI` 文件夹整个覆盖回 U 盘根目录。

---

## 1. 本次改了什么

### 1.1 内置键盘卡顿

| 项 | 改动 |
|---|---|
| VoodooPS2Controller | 2.3.7 → **2.3.8**（取自参考 EFI） |
| Kernel → Add | **只启用** `VoodooPS2Keyboard` 插件；`VoodooPS2Mouse`、`VoodooPS2Trackpad`、`VoodooInput` 三个插件显式设为 `Enabled = false` |

原因：原来只注入整包 `VoodooPS2Controller.kext`，四个插件全部跟着加载。这台机器的指点杆/触控板是 I2C（`ASUF1416`）+ VoodooI2CHID，PS/2 的 AUX（鼠标）口上其实没有设备，`VoodooPS2Mouse` / `VoodooPS2Trackpad` 会不断探测、复位这个空端口，和键盘共用同一条 i8042 通道，就会表现为"打字卡顿、按键丢字"。参考 EFI（G614JI）也是只留键盘插件，本次照此对齐。

如果换完后仍有轻微卡顿，可以在 boot-args 里追加 `ps2rst=0` 再试（跳过开机时对 PS/2 控制器的复位）。

### 1.2 联发科 MT7922 无线网卡（换 YYavicWiFi）

| 项 | 改动 |
|---|---|
| `AirportMtkWlan-Sequoia.kext` | **Enabled = false**（kext 文件仍保留，随时可切回） |
| `YYavicWiFi.kext` | 新增，0.7.2（GitHub: yusufcanyavic/YYavicWiFi），放在 Kernel → Add 最后 |
| boot-args | 新增 `yyavic-cc=CN`（把国家码/信道表设为中国） |

你的网卡在 Windows 下是 `PCI\VEN_14C3&DEV_0616`（RZ616 = MT7922），YYavicWiFi 0.7.1 起已支持 `14c3:0616`，会按芯片 ID 识别为 MT7922 并用 MT7922 固件（和 Linux 的 mt7921 驱动做法一致）。

**重要前提**：YYavicWiFi 的原生 Wi-Fi 层是针对 **macOS 15.8.1（build 24H32）** 的 IO80211Family / IOSkywalkFamily 布局编译的。

- 如果你的系统正好是 24H32 → 正常，开机 20~30 秒后菜单栏出现 Wi-Fi。
- 如果是其它 build → 该层会**自动禁用自己**（日志：`native Wi-Fi layer disabled, unsupported macOS`），此时**完全没有 Wi-Fi**。这种情况请把 `AirportMtkWlan-Sequoia` 重新设成 `Enabled = true`、`YYavicWiFi` 设为 false 先退回可用状态，再告诉我版本号。

查看版本：`sw_vers`（BuildVersion 就是 24H32 这种格式）。

**蓝牙**：0.7.2 会把 MT7922 的蓝牙 USB ID 伪装成 macOS 认识的 `0489:E0D8`，需要 `BlueToolFixup`（已启用）。另外 macOS 自带的 MT7922 蓝牙路径需要固件在 `/etc/bluetool/`：

- U 盘上已放好 `H:\YYavicWiFi-Bluetooth\`（`BT_RAM_CODE_MT7922_1_1_hdr.bin` + `setup-bluetooth.sh`）。
- 在 macOS 里执行一次：`cd /Volumes/<U盘>/YYavicWiFi-Bluetooth && sudo sh setup-bluetooth.sh`
- 若蓝牙反而失效：先执行上面的脚本；仍不行就把 `SimpleMtkBtFw.kext` 关掉再试（两者是两套蓝牙方案）。

### 1.3 内置扬声器无声（重点）

你的音频硬件（Windows 侧实测）：

- 声卡 codec：**Realtek ALC294**（`HDAUDIO\VEN_10EC&DEV_0294`，子系统 1043:1054）
- 功放：ACPI 设备 **`CSC3551`**（Cirrus Logic CS35L41 智能功放），父设备是 **`AMDI0010`（AMD I2C 控制器）**，即功放挂在 I2C 上
- 耳机是 codec 模拟直出，所以耳机正常、扬声器无声 —— 典型的"功放没被初始化"

| 项 | 改动 |
|---|---|
| AppleALC | 1.9.8 → **1.9.9** |
| `SimpleHDA.kext` | 新增（laobamac 1.0.0，参考 EFI 同款） |
| `CirrusAudioFixup.kext` | 新增 **1.2.0**（新版才对 `CSC3551` over I2C 建了匹配：`IOName = CSC3551 / CSC3556 / CLSA0100`） |
| `VoodooI2C.kext` | 换成参考 EFI 里那个**带 AMD I2C 控制器（AMDI0010/AMDI0510）支持**的构建，否则这台 AMD 机器上 I2C 控制器根本不会附着 |
| boot-args | 新增 `alcdelay=1000`；`alcid` **保持 11**（ALC294 的 11 号布局现在能把扬声器/耳机都枚举出来，先不动它） |

**还差的一步（大概率会卡在这里）**：
CirrusAudioFixup 走 I2C 时，要求 VoodooI2C 提供平台函数 `VoodooI2CTransferToAddress`，这只有 **hoaug-tran/VoodooI2C 的 `main` 分支**才有（上游 master 没有）。参考 EFI 里的 VoodooI2C 只补了 AMD 控制器匹配，没有这个函数，所以功放很可能读到 `I2C_ADDRESSED_FUNCTION_UNSUPPORTED` 后放弃。

进系统后这样确认：

```bash
# 1) 功放的 I2C nub 是否存在
ioreg -lw0 -p IOService -r -c VoodooI2CDeviceNub | grep -i -E "CSC3551|CLSA0100"

# 2) CirrusAudioFixup 是否附着 / 卡在哪
ioreg -lw0 -p IOService -r -c CirrusAudioFixup | grep -i -E "Cirrus_|Status"
log show --last 3m | grep -i cirrus
```

- 有 `CirrusAudioFixup` 节点且无报错 → 扬声器应该就出声了。
- 出现 `I2C_ADDRESSED_FUNCTION_UNSUPPORTED` / `NATIVE_I2C_PROVIDER_CONTRACT_UNAVAILABLE` → 必须换成 hoaug-tran/VoodooI2C `main` 分支编译出来的 kext（需要 macOS + Xcode 编译，作者没有提供预编译包）。这一步我可以再帮你出详细编译步骤。
- 顺带可试的布局：把 `alcid=11` 依次换成 `21`、`13`、`66`、`99`（ALC294 支持的布局），看哪个能把声音送到 I2S/ASP 通道。改完 `Reset NVRAM` 或重启生效。

### 1.4 关机变重启（本次**没有**改 EFI，原因如下）

我把你机器的 DSDT 从 Windows 注册表里导出分析过（`HKLM\HARDWARE\ACPI\DSDT\_ASUS_\Notebook`，71922 字节）：

- `_PTS` 正常，转调 `XPTS / SPTS / GPTS / NPTS`；
- USB 控制器路径是 `\_SB.PCI0.GP17.XHC0`、`XHC1`，`\_SB.PCI0.GP19.XHC2`，另有 ASMedia USB4 `UXHC`；
- **整张 DSDT 里没有 `PMEE` 字段**（只有 `PMRG` 区域和 `HPEN/SI3R/RSTU/CLPS/TMSE/SLPS/PWDE/BLNK` 这些位）。

所以 Dortania 那套 `_PTS → ZPTS` + 清 `XHC.PMEE` 的 FixShutdown 在你这台机器上**没有可写的字段，强行套用只会无效甚至报 ACPI 错误**，这就是我没往 ACPI 里塞 SSDT 的原因。

按可能性从高到低，建议这样排查（不改 EFI 也能验证）：

1. **先确认是不是真的"关机后又开机"**：进 macOS 终端执行 `sudo shutdown -h now`。
   - 能彻底断电 → 是 GUI/后台进程的问题（多半是第三方驱动，见第 3 条）。
   - 断电 1~2 秒后自己亮 → 是固件层唤醒，走第 2 条。
2. **BIOS**：`ErP Ready` 设为 `Enabled (S4+S5)`；关闭 `Wake on LAN`、`Power On By USB / PCIe`、`RTC Alarm Power On`、`Power On By Keyboard/Mouse`。这几个是笔记本"关机变重启"最常见的元凶。
3. **NullMoth NVIDIA 驱动**：你装了非官方的 NullMoth 驱动，显卡驱动在关机流程里挂住是会导致"重启而不是断电"的。临时把 `nvfb=1 nvaccel=1 nvfbheads=4 nvrmacpibl=1` 去掉（或先停用该驱动）再关机试一次，能立刻分辨责任方。
4. macOS 里关掉唤醒源：`sudo pmset -a hibernatemode 0 autopoweroff 0 powernap 0 womp 0`，并关闭"设置 → 电池 → 唤醒以供网络访问"。

如果 2、3 都排除了还是重启，我再按你这台机器的实际 XHC 路径写一个只做"关机前禁用 XHC 唤醒"的 SSDT（需要你先在 macOS 里 `ioreg` 抓一份 XHC 节点的 `_PRW`，或者我给你一个用 `_DSM` 的通用版本）。

### 1.5 没有充电动画 / 只显示电量

DSDT 里 AC 适配器设备是存在的：`ADP1`，`_HID = ACPI0003`，`_PSR` 从 EC 的 `SACM/ACST` 位读；电池是 `BAT0`（`_BIF/_BST` 都在）。也就是说 **ACPI 层没问题**，问题在 EC 状态位怎么被解读，或者电池本身没在充电。

进系统后先跑这三条，把结果发我就能定位：

```bash
pmset -g batt
ioreg -rn AppleSmartBattery | grep -E '"ExternalConnected"|"IsCharging"|"CurrentCapacity"|"Amperage"'
system_profiler SPPowerDataType | head -40
```

- `ExternalConnected = No` → AC 没被识别（可以换 `ACPIBatteryManager.kext` 试，它对部分 ASUS EC 的 `_BST` 解读比 SMCBatteryManager 准；ECEnabler 两者都支持）。
- `ExternalConnected = Yes` 但 `IsCharging = No` → **大概率是华硕的电池保养/80% 限制**（MyASUS 或 BIOS 里的 Battery Care / 充电上限），关掉限制再插电即可，这种情况换任何 kext 都不会有充电图标。
- 顺带说明：黑苹果上"充电"只体现为菜单栏电池图标里的闪电/插头符号，没有原版 Mac 那种动画，只要 `IsCharging = Yes` 图标就会变。

---

## 2. 开机后逐项验证清单

1. 键盘：连续快速打字 30 秒，看是否还丢字/卡顿。
2. Wi-Fi：`sw_vers` 确认 build；菜单栏出现 Wi-Fi 后连一个 **带密码** 的网络（这是原来必挂的场景），再断开重连一次。
3. 蓝牙：`system_profiler SPBluetoothDataType | head -20`，看 Chipset 是否为 `SRS_7922`、Transport 是否为 USB。
4. 音频：先插耳机确认仍正常，再拔掉放歌看扬声器；`log show --last 2m | grep -i cirrus` 看驱动日志。
5. 关机：用 `sudo shutdown -h now` 和菜单关机各试一次。

## 3. 当前 EFI 的 kext 启用状态（速查）

启用：Lilu / VirtualSMC / SMCBatteryManager / SMCLightSensor / ECEnabler / AppleALC / SimpleHDA / CirrusAudioFixup /
VoodooI2C(+GPIO/Services/Input) / VoodooI2CHID / VoodooPS2Controller(+仅 Keyboard 插件) /
YYavicWiFi / BlueToolFixup / SimpleMtkBtFw / RestrictEvents / BrightnessKeys / NVMeFix / RealtekRTL8111 /
USBToolBox / UTBMap / AMFIPass / AppleMCEReporterDisabler

停用：WhateverGreen（原本就是关的）/ AirportMtkWlan-Sequoia / AirportMtkWlan-Tahoe

boot-args：
`-v debug=0x100 keepsyms=1 -amfipassbeta -vi2c-force-polling revpatch=sbvmm nvfb=1 nvaccel=1 nvfbheads=4 -nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0 gfxrst=4 -lilubetaall alcid=11 nvrmacpibl=1 alcdelay=1000 yyavic-cc=CN`
