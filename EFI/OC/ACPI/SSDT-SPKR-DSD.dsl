DefinitionBlock ("", "SSDT", 2, "ASUS", "SPKRDSD", 0x00000000)
{
    External (_SB_.I2CD.SPKR, DeviceObj)

    // ASUS G614FR: BIOS 的 _DSD 用的是 "一个设备两个功放" 的数组格式，
    // CirrusAudioFixup 只认 per-device 标量，所以把原表 _DSD 改名成 XDSD（见 config 的 ACPI->Patch），
    // 再在这里用标量格式重新给一遍。数值全部来自 BIOS 原值（取第一个元素）。
    Scope (_SB_.I2CD.SPKR)
    {
        Name (_DSD, Package (0x02)
        {
            ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"),
            Package (0x09)
            {
                Package (0x02) { "cirrus,dev-index",            0x00 },
                Package (0x02) { "cirrus,speaker-id",           0x00 },
                Package (0x02) { "cirrus,speaker-position",     0x00 },
                Package (0x02) { "cirrus,boost-type",           0x00 },
                Package (0x02) { "cirrus,gpio1-func",           0x00 },
                Package (0x02) { "cirrus,gpio2-func",           0x02 },
                Package (0x02) { "cirrus,boost-ind-nanohenry",  1000 },
                Package (0x02) { "cirrus,boost-peak-milliamp",  4500 },
                Package (0x02) { "cirrus,boost-cap-microfarad", 24 }
            }
        })
    }
}
