# ASUS ROG Strix G614FR — OpenCore EFI

macOS 15 (Sequoia) 在 **ASUS ROG Strix G614FR（2025）** 上的 OpenCore 配置。
AMD Ryzen 9 9955HX3D + RTX 5070 Ti（NullMoth 驱动，Metal 可用）+ MT7922。

> ⚠️ **本仓库的 SMBIOS 三码已清空**（序列号 / MLB / UUID / ROM）。
> 直接使用会导致 iCloud、App Store、iMessage 无法登录。请先用
> [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) 生成属于你自己的 `MacBookPro16,2` 三码，
> 填进 `config.plist → PlatformInfo → Generic`。**不要照抄别人的三码。**

---

## 硬件

| 部件 | 型号 | 状态 |
|---|---|---|
| CPU | AMD Ryzen 9 9955HX3D (16C/32T) | ✅ 全核可用 |
| 核显 | AMD Radeon 610M | ❌ 无驱动 |
| 独显 | NVIDIA RTX 5070 Ti Laptop | ✅ **NullMoth** 驱动（内屏输出 + Metal，可正常游戏） |
| 内存 | DDR5 SO-DIMM | ✅ |
| 硬盘 | NVMe (KIOXIA) | ✅ |
| 无线 | MediaTek MT7922 (14c3:0616) | ⚠️ 可用，但有两个硬限制（见已知问题） |
| 有线 | Realtek RTL8111/8168 | ✅ |
| 音频 | Realtek ALC294 + CSC3551 (CS35L41) ×2 | ✅ 内置扬声器 + 耳机 |
| 触控板 | I2C HID (ASUF1416) | ✅ 多指手势 |
| 键盘 | USB HID `0b05:19b6` | ⚠️ 见下方说明 |
| 读卡器 / 指纹 | — | ❌ |

**显卡**：这块 RTX 5070 Ti 在 macOS 下没有官方驱动，目前由 **NullMoth** 驱动，
通过 `nvfb` / `nvaccel` 系列启动参数启用。内屏输出、分辨率、HiDPI 正常，
**Metal 可以正常调用，游戏能正常跑** —— 它不是"只把画面画出来"的软帧缓冲。

需要说明的是：这是非官方驱动，行为跟官方卡不完全一样，个别图形应用仍可能有兼容性问题。
遇到渲染异常时先怀疑驱动侧，再排查配置。

---

## 工作状态

| 功能 | 状态 | 依赖 |
|---|---|---|
| 内屏输出 / 分辨率 / HiDPI | ✅ | **NullMoth** + `nvfb=1 nvfbheads=4 nvfbhidpi=1 nvfbdsr=1` |
| 亮度调节（Fn / 滑块） | ✅ | `BrightnessKeys.kext` + `nvrmacpibl=1` |
| 内置扬声器 + 耳机 | ✅ | `CirrusAudioFixup.kext` + `SimpleHDA.kext`（自编译，见下） |
| 音量调节 | ✅ | 同上 |
| Wi-Fi | ⚠️ | `YYavicWiFi.kext`；扫描不刷新，且**关掉后无法再打开** |
| 蓝牙 | ✅ | `SimpleMtkBtFw.kext` + `BlueToolFixup.kext` |
| 触控板 + 手势 | ✅ | `VoodooI2C` + `VoodooI2CHID` + EC 的 `TPD0` 补丁 |
| 键盘（含背光键） | ⚠️ | `NKeyGateB.kext`（自研，需 `nkg1=1`），见「已知问题」 |
| 电池 / 充电状态 | ✅ | `SMCBatteryManager` + `ECEnabler` + `SACM-AC-DETECT` 补丁 |
| 充电动画 | ❌ | 电量百分比正常，插入电源时电池图标不做充电动画 |
| 关机 | ❌ | 关机后仍会自动上电，见「已知问题」 |
| 睡眠 | ❌ | 未解决 |
| 3D / Metal / 游戏 | ✅ | **NullMoth**（`nvaccel=1`），Metal 调用正常 |
| AirDrop / 隔空播放 | ❌ | 网卡非博通 |

---

## BIOS 设置

| 项目 | 值 |
|---|---|
| Secure Boot | Disabled |
| Fast Boot | Disabled |
| Above 4G Decoding | Enabled |
| Re-Size BAR | 视情况，若启动异常请关闭 |
| VT-d / IOMMU | Disabled（或保留 + 使用 `DisableIoMapper`）|
| SATA / NVMe 模式 | AHCI |

---

## 使用方法

1. 复制本目录下的 `EFI` 到你的 EFI 分区（ESP）根目录
2. 用 GenSMBIOS 生成三码，填进 `PlatformInfo → Generic`
3. 首次启动前，把 `boot-args` 里与本机无关的参数删掉（见下表）
4. 从 BIOS 启动菜单选择带 `UEFI:` 前缀的启动项

### 关键启动参数

| 参数 | 作用 | 可删？ |
|---|---|---|
| `nvfb=1 nvaccel=1 nvfbheads=4 nvfbhidpi=1 nvfbdsr=1` | NullMoth 驱动 / 内屏输出 / 加速 | 删了就黑屏 |
| `nvrmacpibl=1` | 背光控制 | 删了亮度不可调 |
| `alcid=21 alcdelay=1000` | AppleALC 布局 | 按你的 codec 改 |
| `-yyavicnoverify yyavic-cc=CN` | 跳过网卡版本校验 | 换网卡后可删 |
| `nkg1=1` | 启用键盘厂商接口拦截 | 见已知问题 |
| `-cirrusdbg` | 功放调试日志 | 可删 |
| `amfi=0x80 amfi_get_out_of_my_way=0x1 ipc_control_port_options=0` | 关闭 AMFI（跑未签名 kext 必需） | 不建议删 |

---

## 自研组件说明

本仓库有三处内容是为这台机器单独适配或编写的，和「拿一份现成 EFI 直接用」不同：

### 1. `CirrusAudioFixup.kext`（内置扬声器）

CSC3551 (CS35L41) 功放驱动。上游
[hoaug-tran/CirrusAudioFixup](https://github.com/hoaug-tran/CirrusAudioFixup) 的板级表里
**没有 `1043:1054`**（本机 SUBSYS），所以按 OEM 驱动里 `CONF_0535` 的参数自行编译：

- 板级条目：`{0x10431054, 2, true, {0,1,0,0}, <reset>, 1, -1, 1000, 4500, 24}`
- 固件：`halo_cspl_RAM_revB2_29.85.0.wmfw`（revB2，对应 `DeviceID = 0x35A40`）
- 调音：`10431074_240712_V0_A0/V0_A1`（speaker-id 0）、`V1_A0/V1_A1`（speaker-id 1）
- 依赖 [hoaug-tran/VoodooI2C](https://github.com/hoaug-tran/VoodooI2C) `main` 分支（提供
  `VoodooI2CTransferToAddress`，上游 VoodooI2C 没有这个接口）

> ⚖️ **注意**：该 kext 内嵌的 `.wmfw` / `.bin` 提取自 ASUS 随机器提供的 Windows 音频驱动。
> 仅供个人研究使用；如需二次分发请自行评估授权。

### 2. `NKeyGateB.kext`（键盘）

这块键盘有一个厂商自定义 HID collection（usage page `0xff89`），它的 IN 端点
（`0x82`）**永远不返回数据**。macOS 的 `IOUserUSBHostHIDDevice` 读 10 次失败后会复位
**整个 USB 设备**（不是接口），导致键盘每 1~2 秒断流约 0.5 秒，表现为「丢字 / 卡顿」。

这个 kext 的作用是不让系统去碰那个接口。需要 `nkg1=1` 才生效，删掉该参数即完全惰性。

### 3. ACPI 补丁 `GPRW-STRIP-WAKE`（尝试方案，未根治）

让 `GPRW()` 返回 GPE 0，摘掉 PCIe/USB 的唤醒能力，用于尝试解决
**关机后自动上电**（关机 → 真断电 → 两三秒后自己开机 → BIOS 自检）。

**实测结果：没修好。** 把全部 ACPI 唤醒源摘掉之后，关机依然会自己上电 ——
说明唤醒源在 EC / 固件层，不在 ACPI 这一层。补丁目前保留（本身无副作用），
但不要指望它解决关机问题。

副作用：睡眠唤醒失效。

---

## 已知问题

| 问题 | 现状 | 说明 |
|---|---|---|
| 键盘偶发丢字 | 部分缓解 | 根因是键盘 MCU 固件缺陷（同型号在 Linux 上也有相同记录）。`NKeyGateB` 只能压制复位循环，改不了固件本身 |
| 关机后自动上电 | **未解决** | 已排除 panic/崩溃（Windows 关机完全正常，是断电后由固件重新上电）。已尝试：摘除全部 ACPI `_PRW` 唤醒源、关闭 `pmset` 定时唤醒与 `autorestart` —— 均无效。判断唤醒源在 EC / 固件层，下一步应去 BIOS 关 Wake on USB / USB S5 供电 / ErP |
| Wi-Fi 扫描不刷新 | 未解决 | 扫描列表只在**开机时建立一次**。开机之后才开启的热点（手机热点、随手开的 AP）在列表里根本不会出现，必须重启才能看到。属驱动侧限制，改配置无效 |
| Wi-Fi 关闭后无法重新开启 | 未解决 | 在菜单栏关掉 Wi-Fi 之后**再也打不开**（开关点了没反应），只能重启机器恢复。⚠️ **不要用"关掉再打开"去刷新列表**，代价是直接断网到重启 |
| 睡眠 | 不可用 | 与显卡驱动有关，未解决 |
| 图形兼容性 | 视应用而定 | 显卡走 NullMoth 非官方驱动，个别渲染/视频应用可能异常，属驱动侧问题 |
| 充电动画 | 无 | 电量与充电状态可读，但插入电源时电池图标没有充电动画（`SACM-AC-DETECT` 修好了 AC 检测，动画仍缺） |
| 电源键 | 无响应 | macOS 侧未识别按键事件，不影响使用（用菜单关机） |

---

## 目录结构

```
EFI/
├── BOOT/
│   └── BOOTx64.efi
└── OC/
    ├── ACPI/          # SSDT-EC / PLUG / USB-Reset / USBX / XOSI
    ├── Drivers/       # OpenRuntime / OpenCanopy / HfsPlus / ResetNvram / apfs_aligned
    ├── Kexts/         # 见下
    ├── Resources/     # OpenCanopy 图标
    ├── Tools/
    ├── OpenCore.efi
    └── config.plist
```

---

## 致谢

- [OpenCore](https://github.com/acidanthera/OpenCorePkg) / [Lilu](https://github.com/acidanthera/Lilu) / [WhateverGreen](https://github.com/acidanthera/WhateverGreen) / [VirtualSMC](https://github.com/acidanthera/VirtualSMC) / [AppleALC](https://github.com/acidanthera/AppleALC)
- [VoodooI2C](https://github.com/VoodooI2C/VoodooI2C)（fork: [hoaug-tran](https://github.com/hoaug-tran/VoodooI2C)）
- [CirrusAudioFixup](https://github.com/hoaug-tran/CirrusAudioFixup)
- [USBToolBox](https://github.com/USBToolBox/kext)
- **NullMoth**（RTX 5070 Ti 驱动：内屏输出 + Metal，可正常游戏）
- YYavicWiFi（MediaTek MT7922 驱动）
- [Dortania's OpenCore Install Guide](https://dortania.github.io/OpenCore-Install-Guide/)

---

## 免责声明

本项目仅用于**在你自己拥有的硬件上安装 macOS** 的技术研究。
macOS 是 Apple Inc. 的商标与受版权保护的软件；macOS 最终用户许可协议（EULA）并不允许
在非 Apple 硬件上安装。使用本仓库内容的风险由你自行承担。
仓库不包含任何 Apple 二进制文件或 macOS 安装介质。
