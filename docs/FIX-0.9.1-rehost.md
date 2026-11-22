# 0.9.1 rehost 适配记录

面向想复现 / 再生成签名的人。所有结论都在 2026-11-22 的一台 Windows 机器上实测得到。

## 1. 现象

### 1.1 原包 UE4SS v3（Mod 包自带）

```
UE4SS - v3.0.1 Beta #0 - Git SHA #4ff3595
[PS] Scan finished in 423.2986ms
[PS] Found GUObjectArray: ...
[PS] Found GMalloc: ...
[PS] Found FName::ToString: ...
[PS] Failed to find StaticConstructObject_Internal: StaticConstructObjectInternal: expected at least one value
[PS] You can supply your own AOB in 'UE4SS_Signatures/StaticConstructObject.lua'
[PS] Failed to find FUObjectHashTables::Get(): FUObjectHashTablesGet: expected at least one value
[PS] Failed to find GNatives: GNatives: expected at least one value
[PS] Scan failed
Fatal Error: PS scan timed out
```

三个符号找不到 → `Scan failed` → Lua 从不执行 → `fd-skeleton.ndjson` 始终 0 字节。

### 1.2 换成 UE4SS v4.0.0

把 `[EngineVersionOverride]` 清空（让 v4 自动识别）后扫描全过：

```
[PS] Found EngineVersion: 5.7
[PS] Found BuildConfiguration: Shipping
[PS] Found StaticConstructObject_Internal: 0x7ff63dab7910
[PS] Found FUObjectHashTables::Get(): 0x7ff63daa8630
[PS] Found GNatives: 0x7ff646fcc6d0
[PS] Found FName::FName(wchar_t*): 0x7ff63d881590
PS scan successful
Locating KismetStringLibrary...
Locating KismetStringLibrary CDO...
        → 访问违例 0xc0000005 @ UE4SS.dll+0xadd98a
```

把 Mod 关空（`mods.txt` 里没有条目）仍然在同一个地址崩，所以与 Mod 的 Lua 无关。
v3.0.1-1221 实验构建同样扫过后崩在同一位置。

## 2. 补签名（走 v3 而不是 v4）

思路：v3 从没崩过，它只是扫描失败。把 v4 已解出的三个地址换算成 v3 的 AOB 签名，
让 v3 扫过，就绕开了 v4 那条崩溃路径。

### 2.1 求 image base

v4 日志给的是运行时绝对地址，模块基址未知。用各符号的**相对差**（对基址不敏感）
配合 PE 节区间约束求解：

- 已知 `.text` = `0x1000 .. 0x830EEBC`，`.data` = `0xAAE8000 .. 0xB0FEC44`
- `GUObjectArray / GMalloc / GNatives` 必须落在 `.data`，其余必须落在 `.text`
- 基址按 Windows 分配粒度 64 KB 对齐

解出 `base = 0x7FF63C4C0000`，交叉验证：`FName::FName(wchar_t*)` 落在 RVA `0x13C1590`，
与 Mod 包自带签名文件里写的 `0x13CC410` 处于同一区域且 AOB 完全命中——互相印证。

### 2.2 三个符号

| 符号 | RVA | 签名 |
|---|---|---|
| `StaticConstructObject_Internal` | `0x15F7910` | `48 89 5C 24 10 48 89 74 24 18 48 89 7C 24 20 55 41 54 41 55 41 56 41 57 48 8D AC 24 60 FE FF FF 48 81 EC A0 02 00 00 48 8B 05`（48 字节，全文件唯一） |
| `FUObjectHashTables::Get()` | `0x15E8630` | `40 53 48 83 EC 20 8B 0D 74 53 B1 09 65 48 8B 04`（16 字节，全文件唯一） |
| `GNatives` | `0xAB0C6D0` | 见下 |

### 2.3 GNatives 的特殊处理

`GNatives` 是 `.data` 里的函数指针表，条目在镜像加载时按重定位整体改写
（文件里是 `0x140000000+` 偏好基址指针，内存里变成实际基址），所以**数据字节模式在内存里匹配不到**。
表头连续 255 项指向同一个 `execUndefined`，也无法靠加长窗口取唯一。

做法：锚定表内 `GNatives + 0x7F8` 处第一段无重定位的数据块

```
40 42 0F 00 00 00 80 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

命中后在 Lua 里回退：

```lua
function OnMatchFound(MatchAddress)
    return MatchAddress - 0x7F8
end
```

### 2.4 结果

```
[PS] Scan finished in 263.4777ms
[PS] Found GUObjectArray / GMalloc / FName::ToString / ConsoleManagerSingleton / GameEngineTick
PS scan successful
Locating KismetStringLibrary CDO...        ← 穿过去了，没有崩
Starting Lua mod 'fd_tcode_probe'
[FD-TCode][INFO] version=0.18.0 loaded
```

### 2.5 再生成的方法

换游戏版本后：

1. 用 UE4SS v4（`EngineVersionOverride` 留空）跑一次，从 `UE4SS.log` 抄出这几个绝对地址；
2. 同时取出模块基址（`Get-Process <exe> | %{ $_.Modules }` 里该模块的 `BaseAddress`，
   或者用第 2.1 节的区间约束反解）；
3. `RVA = 地址 - 基址`，在 exe 里从该 RVA 取 16–48 字节，确认**全文件唯一**；
4. 唯一性不足时加长窗口；数据段符号改用"附近无重定位块 + `OnMatchFound` 回退"的办法。

## 3. 本地动作门

签名通了以后 Mod 能加载，但 `fd-skeleton.ndjson` 仍为 0 字节。日志：

```
[FD-TCode][INFO] HAnime gate state=inactive ... reason=local_player_not_in_h
```

而游戏自己的日志显示动作确实变了：

```
LogTemp: Display: [Rehost] PlayerAction 0 -> 2 (player 895719, 1 roles)
```

原因：`core/local_player_action_gate.lua` 只靠

```
/Script/Paralogue.RoomManagerBase:OnLocalPlayerActionChanged
```

这个 hook 判断"本机玩家在 H 场景"。rehost 单机版把动作交给本地 DS 代理
（`PlayerCommoActionSystemDSProxy`）处理，这个 UFunction 从未被调用 → 门不打开 →
`hanime_detector.lua` 在第 990 行直接 `return status("inactive", false, {}, "local_player_not_in_h")`。

补丁（`payload/Mods/fd_tcode_probe/Scripts/fd_tcode/core/local_player_action_gate.lua`）：

- `FD_TCODE_FORCE_GATE=1` 时强制开门（`Gate.start` / `Gate.world_changed` 里置真并通知监听者，
  `Gate.is_active()` 恒真，`set_active(false)` 被忽略）；
- 增加 hook 计数日志，用于确认该 UFunction 是否真被调用：
  `Local action hook fired seen=N argc=M arg3=...`（只打印前 10 次）。

补后的日志：

```
[FD-TCode][INFO] Local action gate forced open (FD_TCODE_FORCE_GATE=1)
[FD-TCode][INFO] HAnime gate state=inactive ... reason=no_active_hanime_montage
```

`reason` 从 `local_player_not_in_h` 变成 `no_active_hanime_montage`，说明门已开、
检测器在等 H 场景蒙太奇。

## 4. 踩过的坑

- UE4SS 的 Lua 是 5.1 语义：`...` 不能穿透到内层闭包。写成
  `pcall(function() return tostring(select(3, ...)) end)` 会报
  `cannot use '...' outside a vararg function`，必须先 `local a3 = select(3, ...)`。
- v3 的 `EngineVersionOverride` 必须保持 `5 / 5.7`；清空只对 v4 有效。
- 签名文件里的 AOB 是**镜像内容**匹配，不是文件内容匹配；含重定位指针的数据段模式会失效。
