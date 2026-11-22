# Fallen Doll — TCode Mod 修复版（fd_tcode_probe 0.18.0 + 0.9.1 rehost 适配）

把 [MotionBridge](https://github.com/Huarch/MotionBridge) 的 Fallen Doll Playtest 骨骼流 Mod
（`fd_tcode_probe` 0.18.0）跑在 **0.9.1 rehost 本地授权版** 上所需的补丁。

原版 Mod 只声明支持 Fallen Doll Playtest `0.9.0`。在 0.9.1 rehost 版上直装会卡在
UE4SS 的符号扫描（`Fatal Error: PS scan timed out`），即使换 UE4SS v4 能扫过，也会在
`Locating KismetStringLibrary CDO` 之后崩溃。本仓库补上三处签名 + 一处逻辑补丁后，
Mod 可以正常加载、检测 HAnime 并输出骨骼流。

## 验证环境

| 项 | 值 |
|---|---|
| 游戏 | Fallen Doll Playtest 0.9.1 rehost，`Paralogue-Win64-Shipping.exe` SHA-256 `85EB598DDEB29F7D38DE737B1F584C3EFE6D1194A25B9B673B64C25E99828771`（191,914,496 字节，已打本地授权补丁） |
| 引擎 | UE 5.7 Shipping（`LogInit: Build: UE5-CL-0`） |
| UE4SS | v3.0.1 Beta #0（Mod 包自带的那份，Git SHA `4ff3595`） |
| 宿主 | MotionBridge v0.1.7（Windows x64 portable） |

## 包含内容

```
payload/Mods/fd_tcode_probe/        Mod 本体（0.18.0，含已打补丁的 local_player_action_gate.lua）
payload/Mods/mods.txt               加载顺序（fd_tcode_probe : 1）
payload/UE4SS_Signatures/           4 个 AOB 签名
  FName_Constructor.lua             原包自带（在本作 exe 中命中 RVA 0x13C1590）
  StaticConstructObject.lua         新增，见下文
  GUObjectHashTables.lua            新增，见下文
  GNatives.lua                      新增，见下文
payload/UE4SS-settings.ini          UE4SS 配置（EngineVersionOverride 5 / 5.7）
launcher/start-game-with-mod.cmd    一键启动：校验回环授权 → 起授权服务器 → 起 MotionBridge → 起游戏
docs/upstream/                      上游 Mod 的原始 README 与第三方声明
docs/FIX-0.9.1-rehost.md            技术细节：崩溃现象、地址推导、门补丁原因
```

## 使用

1. 先用上游安装包（`MotionBridge-FallenDoll-Playtest-Mod-0.18.0` 的 `Install Mod.cmd`）
   正常装一遍，让 `Paralogue\Binaries\Win64\` 下出现 `dwmapi.dll` + `ue4ss\`（含 UE4SS v3.0.1）。
2. 把 `payload\Mods\fd_tcode_probe`、`payload\Mods\mods.txt` 覆盖到 `ue4ss\Mods\`。
3. 把 `payload\UE4SS_Signatures\*.lua` 覆盖到 `ue4ss\UE4SS_Signatures\`。
4. 确认 `ue4ss\UE4SS-settings.ini` 里 `[EngineVersionOverride] MajorVersion = 5` / `MinorVersion = 7`。
5. 启动时设置环境变量 `FD_TCODE_FORCE_GATE=1`（`launcher\start-game-with-mod.cmd` 已包含），
   再进游戏触发 HAnime。`%USERPROFILE%\.f8\studio\games\fallen-doll\runtime\fd-skeleton.ndjson`
   开始滚动、MotionBridge 从 **STREAM WAITING** 转 **STREAM ONLINE** 即成功。

## 两处修复

### 1. 三个 UE4SS 符号签名（`payload/UE4SS_Signatures/`）

Mod 包自带的 UE4SS v3 在本作 exe 上找不到 `StaticConstructObject_Internal`、
`FUObjectHashTables::Get`、`GNatives`，扫描超时后直接 `Fatal Error`，Lua 一行都不执行。
UE4SS v4 自带的 patternsleuth 规则能解出这三个地址，但它随后在
`Locating KismetStringLibrary CDO` 处崩在 `UE4SS.dll+0xadd98a`（`0xc0000005`）。

解法：用 v4 解出的绝对地址反推 image base，得到 RVA，再从 exe 里取**全文件唯一**的字节窗口，
写成 v3 认的 `UE4SS_Signatures/*.lua`。v3 扫描通过后**不会**走到 v4 那条崩溃路径。

| 符号 | RVA | 签名做法 |
|---|---|---|
| `StaticConstructObject_Internal` | `0x15F7910` | 48 字节精确匹配（.text） |
| `FUObjectHashTables::Get()` | `0x15E8630` | 16 字节精确匹配（.text） |
| `GNatives` | `0xAB0C6D0` | `.data` 指针表，条目在加载时全部重定位、内存里匹配不到；锚定表内 `+0x7F8` 第一处无重定位数据块，`OnMatchFound` 回退 `-0x7F8` |

> 签名与具体 exe 绑定。换游戏版本后 RVA 会变，必须重新生成（见 `docs/FIX-0.9.1-rehost.md`）。

### 2. 本地动作门（`core/local_player_action_gate.lua`）

原版 Mod 用 `RoomManagerBase:OnLocalPlayerActionChanged` 判断"本机玩家是否在 H 场景"。
rehost 单机版把动作走的是本地 DS 代理（游戏日志 `[Rehost] PlayerAction 0 -> 2`），
该 UFunction 不被调用 → 门永远是 `inactive` → 检测器直接返回 `reason=local_player_not_in_h`
→ 骨骼文件一直是 0 字节（MotionBridge 永远 STREAM WAITING）。

补丁行为：

- `FD_TCODE_FORCE_GATE=1` 时强制开门（默认关闭，不影响原逻辑）。单机场景下门本身只是为了
  多人时排除远端玩家的 H 场景，强制打开对单人使用是安全的。
- 增加 hook 触发计数日志（`Local action hook fired seen=N argc=M arg3=...`），便于确认该 UFunction
  在本构建里到底有没有被调用；将来找到正确的触发点后可以去掉强制开门。

## 已知限制

- 只在本仓库表格里那一个 exe 上验证过；游戏本体更新后签名全部失效。
- 门是强制打开的，多人模式下若同房间里远端玩家进入 H 场景，本机也可能收到事件（本构建的单机
  本地 DS 模式下不会发生）。
- Mod 的 HAnime 识别依赖其内置的 montage / 资产目录；若日志出现 `reason=unknown_hanime_identity`
  或 `unknownMontages>0`，说明该动作不在 0.18.0 的目录里，需要作者更新 Mod 数据。

## 来源与授权

- Mod 本体 `fd_tcode_probe` 0.18.0、`FName_Constructor.lua`、`UE4SS-settings.ini` 来自
  [Huarch / MotionBridge-GameMod](https://github.com/Huarch/MotionBridge-GameMod) 的
  `MotionBridge-FallenDoll-Playtest-Mod-0.18.0` 发行包，版权归原作者，原许可见
  `docs/upstream/THIRD_PARTY_NOTICES.md`。
- UE4SS 为第三方项目（[UE4SS-RE/RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)），本仓库不分发其二进制。
- 本仓库只包含本机为 0.9.1 rehost 构建额外编写的三个签名文件、一处 Lua 逻辑补丁和一份启动脚本，
  不包含任何游戏资源、exe 或 pak。
- 如原作者对再分发有异议，删除即可。
