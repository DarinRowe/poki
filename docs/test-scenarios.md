# Poki 测试场景总表（能力评估基线）

> 自动生成，请勿手改。生成时间：2026-11-19 08:09:39 UTC；仓库：`dev/local-poki-improvements` @ `39a6218`（有未提交改动）；环境：darwin arm64、Node v24.22.1。
>
> 重新生成：`node bin/test-catalog.mjs`（默认实跑 Node 主套件、Agent 套件、动作效率场景与变体）；`--static` 只盘点，`--rust` 加上 desktop Rust 工作区，`--no-eval` 跳过动作效率场景。机器可读版本：`docs/test-scenarios.json`；每次运行追加一条趋势记录到 `.runtime/test-catalog/history.jsonl`。

## 1. 总览

共 **862** 个场景：**497** 个本机可自动运行，**306** 个需要 iOS 模拟器/Xcode，**59** 个需要真机或人工操作。
本次实跑 **492** 个：通过 480，失败 12，超时 2，其中 flaky 0，通过率 98%；未运行 368 个（静态盘点或需要设备/账号）。

| 套件 | 入口 | 场景 | 实跑 | 通过 | 失败 | 超时 | flaky | 未跑 | 自动化 | 墙钟耗时 | 说明 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- |
| Node 协议/单元套件 | `npm test` | 337 | 337 | 337 | 0 | 0 | · | 0 | 自动（本机） | 313.3 s | `npm test` 跑的套件：协议桥、设备/模拟器适配、批处理、观察、安装流程、协调与租约。设备程序以隔离夹具替身，不碰真机与模拟器 UI。 |
| Agent 套件 | `cd agent && npm test` | 68 | 66 | 54 | 12 | 2 | · | 0 | 自动（本机） | 272.9 s | `agent/test` 的套件：任务运行器、开屏/回执/错误路由、imessage 与 telegram 渠道、超时与步骤处理。 |
| 动作效率对照场景 | `POKI_EVAL_GROUP=all node --test test/suite/action-efficiency.test.mjs` | 6 | 6 | 6 | 0 | 0 | · | 0 | 自动（本机） | 27.4 s | 同一合成夹具上成对比较：引用直达与条件等待开/关（before/after），独立验收动作记录与最终屏幕。6 个场景 × 2 组。 |
| 动作效率场景·变体（扰动） | `POKI_EVAL_SCENARIO=interruption,canvas POKI_EVAL_VARIANT=1 node --test test/suite/action-efficiency.test.mjs` | 2 | 2 | 2 | 0 | 0 | · | 0 | 自动（本机） | 11.8 s | 把遮挡场景的角色、按钮与出现时序，以及 Canvas 场景的目标与 AX 干扰项换掉后的同一批场景，用来检验系统是否只记住了原场景的表面特征。 |
| Poki Gym 模拟器场景 | `.github/workflows/ios-gym.yml（scorecard / scorecard-inprocess）` | 36 | 0 | 0 | 0 | 0 | · | 36 | 需 iOS 模拟器 | — | 一个模拟器 App，每个场景屏对应一种会卡住 UI 自动化的真实情况；scorecard 逐屏驱动 look/do、系统 App 与故障注入。本机未运行（需 Xcode 与模拟器）。 |
| Swift 测试（PokiCore / Poki 应用） | `xcodebuild test（PokiCoreTests / PokiTests）` | 267 | 0 | 0 | 0 | 0 | · | 267 | 需 iOS 模拟器 | — | PokiCore 的 XCTest（复连、故障、look/do、soak、例行流程）与 Poki 应用的 XCTest（会话、剪贴板、语音、交接）。静态盘点，本机未运行。 |
| Rust 测试（desktop / native） | `cargo test（desktop 工作区、native/bridge、native/launcher）` | 84 | 81 | 81 | 0 | 0 | · | 3 | 自动（本机） | 10.8 s | Poki 的 Rust 代码：Setup 工作区（USB/Wi-Fi、Apple 账号、签名）、真机桥、Launcher、soak 与远程会话。 |
| 真机人工检查清单 | `docs/device-test-checklist.md` | 54 | 0 | 0 | 0 | 0 | · | 54 | 需真机 | — | 必须在真机上按顺序执行的检查项：回环、配对、Launcher、中继、审批、Live Activity。 |
| 人工验证预案 | `docs/verification/*.md、docs/native-ime-testing.md` | 4 | 0 | 0 | 0 | 0 | · | 4 | 需真机 | — | 针对真机、真实网络与 IME 的验证预案；不进入自动套件。 |
| 模拟器/真机验收脚本 | `bin/verify-*.mjs、bin/eval-first-call.mjs` | 4 | 0 | 0 | 0 | 0 | · | 4 | 需真机 | — | 对真实设备做 UI 与状态变更的验收脚本，故意不进入 npm test。 |
| **合计** | | **862** | **492** | **480** | **12** | **2** | **0** | **368** | | **636.3 s** | |

### 本次最慢的 10 个场景

| 场景 | 文件 | 耗时 |
| --- | --- | ---: |
| A stop request takes effect while the reply to an earlier mid-task message is still sending | `agent/test/steer.test.mjs` | 30.0 s |
| recognized prompts report their type without forcing a human handoff | `test/coordination.test.mjs` | 16.3 s |
| screen_change says changed, unchanged, or unknown, and only unchanged carries the no-change advice | `test/observation.test.mjs` | 14.4 s |
| a recognition that began inside the five seconds still finishes and is used | `test/coordination.test.mjs` | 13.7 s |
| six coordinate taps in one batch read the screen once at the end, not around every tap | `test/observation.test.mjs` | 13.6 s |
| launch_app on a simulator waits for a readable interface and reports when there is none | `test/coordination.test.mjs` | 11.6 s |
| a tap on a phone with slow accessibility reads still ends with the screen | `test/observation.test.mjs` | 11.0 s |
| input receipt survives recording recovery failure and stopping prevents revival | `test/coordination.test.mjs` | 10.6 s |
| handle_alert sends nothing when its read outlasts the five seconds, and that read is stopped | `test/coordination.test.mjs` | 10.3 s |
| tap_text sends nothing when its read outlasts the five seconds, and that read is stopped | `test/coordination.test.mjs` | 10.3 s |

## 2. 能力矩阵（按能力维度的场景覆盖）

| 能力 | Node 协议/单元套件 | Agent 套件 | 动作效率对照场景 | 动作效率场景·变体（扰动） | Poki Gym 模拟器场景 | Swift 测试（PokiCore / Poki 应用） | Rust 测试（desktop / native） | 真机人工检查清单 | 人工验证预案 | 模拟器/真机验收脚本 | 合计 | 自动 | 本次通过率 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 观察（observe）：读屏 / 元素树 / 截图 / OCR / AX | 91 | 17 | 2 | 1 | 22 | 90 | · | · | 1 | 3 | 227 | 111 | 92% |
| 操作（act）：点击 / 输入 / 手势 / 滚动 / 按键 | 56 | 1 | 5 | 2 | 28 | 40 | · | · | 1 | 3 | 136 | 64 | 100% |
| 批量与等待（batch）：批量动作 / 条件等待 / 回执校验 | 140 | 7 | 2 | · | · | · | · | · | · | · | 149 | 149 | 95% |
| 会话与传输（session）：协议 / 鉴权 / 租约 / 守护进程 / 连接恢复 | 137 | · | · | · | · | 92 | 31 | 33 | 3 | · | 296 | 168 | 100% |
| 安装与配对（install）：Setup / 配对 / 签名 / 更新 | 62 | 3 | · | · | · | 15 | 53 | 31 | 1 | · | 165 | 118 | 100% |
| Agent 端（agent）：任务运行器 / 渠道 / 模型交互 | · | 50 | · | · | · | 68 | · | · | · | 1 | 119 | 50 | 94% |
| 安全与审批（safety）：审批 / 输入锁 / 危险操作 | 40 | 1 | · | · | 2 | 14 | · | 17 | · | 1 | 75 | 41 | 100% |
| 稳定性与容错（stability）：soak / 超时 / 中断 / 恢复 | 86 | 15 | 2 | 1 | 9 | 114 | 8 | · | 2 | · | 237 | 112 | 100% |
| 效率与资源（efficiency）：耗时 / 调用数 / 内存 / CPU | 3 | 9 | 6 | 2 | 1 | 5 | · | · | · | 1 | 27 | 20 | 65% |
| 诊断与证据（diagnostics）：日志 / 录制 / 回放 / 截图证据 | 32 | 15 | · | · | · | 6 | · | 2 | · | · | 55 | 47 | 94% |

> 一个场景可命中多个能力维度；「自动」指本机无需模拟器/真机即可复跑。

## 3. 泛化能力评估（防过拟合）

AI 改代码时最容易发生的事，是把系统调成“只在这几个场景上对”。这一层把场景按“平时能不能看”分开，评估只看留出、变体和未见场景，避免用一个不断被针对的集合给自己打分。

### 场景分层

| 层 | 定义 | 场景 | 实跑 | 通过 | 失败 | 通过率 | 使用方式 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| 回归（核心） | regression | 756 | 484 | 472 | 12 | 97.5% | 日常回归：防止破坏已有行为，改动时随时可看 |
| 开发集 | development | 3 | 3 | 3 | 0 | 100% | 改动时可见，允许反复调参 |
| 留出集 | holdout | 3 | 3 | 3 | 0 | 100% | 只在评估日运行，不得用来调参或挑场景 |
| 变体（扰动） | variant | 2 | 2 | 2 | 0 | 100% | 替换角色、文案、出现时序，检验是否只记住一种呈现 |
| 未见场景（模拟器/真机） | unseen | 36 | 0 | 0 | 0 | — | 未进入日常循环，检验对真正新界面的泛化 |
| 真机人工 | device | 58 | 0 | 0 | 0 | — | 人工判断，覆盖自动化难及的系统界面 |
| 验收脚本 | acceptance | 4 | 0 | 0 | 0 | — | 一次性设备验收，不作为日常循环 |

### 泛化指标

- 开发集 → 留出集通过率差：+0 个百分点（开发集 100%，留出集 100%）。差距为正且越大，越可能是过拟合。
- 变体通过率：100%（场景内角色/文案/时序已替换）。
- 能力维度覆盖：10/10（留出集覆盖：操作、稳定性与容错、效率与资源、观察；未见场景覆盖：观察、操作、稳定性与容错、效率与资源、安全与审批）。
- 工具覆盖：93.1%；运行环境：3 类（本机 / 模拟器 / 真机）。

### 反过拟合协议

1. **留出集冻结**：`holdout` 场景只在评估日跑，平时不跑、不照着它改代码；把它当作考试题，而不是练习题。
2. **变体必跑**：每次评估都跑 `POKI_EVAL_VARIANT=1` 的变体场景；只看原场景通过没有意义。
3. **每轮加新题**：每次能力评估至少新增 1–2 个此前没见过的场景（Gym 新屏、真机清单新条目或新的合成页面），加入后只跑一次就归档为留出。
4. **盲选场景**：评估用的场景由没有参与实现的人挑，或从 Gym/真机清单里随机抽；不要由写代码的人指定。
5. **按能力维度打分**：报告每个能力维度的通过率（第 2 节），不要只报一个总数；某个维度为 0 比总体 98% 更重要。
6. **区分特例与通病**：失败的修复必须是通用的（改机制），如果只能“针对这个场景”修，就把该场景记为过拟合证据。
7. **审计测试改动**：一次改动如果修改的是测试期望值而不是被测行为，视为过拟合信号，需要说明理由。
8. **趋势看留出集**：用 `.runtime/test-catalog/history.jsonl` 对比多次评估的留出集通过率与变体通过率，而不是开发集。

### 本轮自动提示

- 未见场景（Poki Gym / 真机清单）本轮未运行：只能说明“回归没坏”，不能说明“泛化好”。

## 4. 工具覆盖（MCP 工具目录 58 项）

- **提及覆盖**：58/58（100%）。工具名是否在单元测试或文档里出现过；出现清单断言也会算，所以这个数偏高。
- **端到端覆盖**：54/58（93.1%）。工具是否在 Gym scorecard、动作效率场景、真机清单或验收脚本里被真实驱动；判断能力面看这个。

端到端尚未驱动的工具（4）：`touch_path`、`draw_strokes`、`request_human_action`、`run_code`。

## 5. Node 协议/单元套件

- 入口：`npm test`
- 场景：337（通过 337，失败 0，超时 0，未跑 0），墙钟 313.3 s
- 单场景耗时：中位 913 ms，P95 7.8 s，最长 16.3 s

**`test/ax-viewport.test.mjs`** — 5 场景（通过 5，失败 0，超时 0，合计 5.6 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| a verified USB portrait viewport avoids capture and maps a tap to the same HID point | 观察、操作、诊断与证据 | ✅ 通过 | 891 ms |
| a root mismatch uses one real frame for image fallback | 观察、操作 | ✅ 通过 | 725 ms |
| rotation after a geometry-only observation invalidates the old reference | 观察、操作 | ✅ 通过 | 830 ms |
| a fresh AX text target can use verified USB geometry without the screenshot service | 观察、操作 | ✅ 通过 | 1.5 s |
| a partial AX root still uses screenshot geometry for a text tap | 观察、操作 | ✅ 通过 | 1.6 s |

**`test/batch-device-choice.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 1.4 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| A batch with no device and two phones reports the device choice instead of crashing in the read-back | 批量与等待、会话与传输、稳定性与容错 | ✅ 通过 | 547 ms |
| a batch pinned to one simulator enumerates once and reads back that simulator | 批量与等待、会话与传输 | ✅ 通过 | 865 ms |

**`test/batch-input-recovery.test.mjs`** — 5 场景（通过 5，失败 0，超时 0，合计 10.9 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| Launch and fill use the current localized input; a wrong label returns an executable recovery without typing | 批量与等待、稳定性与容错 | ✅ 通过 | 3.1 s |
| Ordinary app name launch recovers a cold directory disconnect, uses the warm directory, and reports persistent failures without launching | 批量与等待、稳定性与容错 | ✅ 通过 | 2.6 s |
| Input on a phone without displayservice reports nothing sent and names the preparation command | 批量与等待、稳定性与容错 | ✅ 通过 | 680 ms |
| batch reuses its final read as an action receipt and excludes uncertain input from the suffix | 批量与等待、稳定性与容错 | ✅ 通过 | 2.4 s |
| fill retries a refused target once only when the fresh focused field and its value still match | 批量与等待、稳定性与容错 | ✅ 通过 | 2.1 s |

**`test/call-log.test.mjs`** — 1 场景（通过 1，失败 0，超时 0，合计 7.5 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| POKI_MCP_CALL_LOG records each call by tool, time and verdict, and nothing it was given | 诊断与证据 | ✅ 通过 | 7.5 s |

**`test/conditional-actions.test.mjs`** — 7 场景（通过 7，失败 0，超时 0，合计 7.6 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| verified reference and new condition share fresh AX reads with the batch receipt | 批量与等待 | ✅ 通过 | 951 ms |
| guarded references refuse externally changed targets, foreground, rotation and overlays | 批量与等待、稳定性与容错 | ✅ 通过 | 1.5 s |
| already satisfied and timed-out expectations cannot masquerade as action success | 批量与等待 | ✅ 通过 | 1.1 s |
| an overlay refusal explains recovery and invalidates the blocked reference | 批量与等待、安全与审批、稳定性与容错 | ✅ 通过 | 1.0 s |
| exact tap text uses OCR rather than an AX substring | 批量与等待 | ✅ 通过 | 1.5 s |
| an expectation distinguishes a destination label from a same-named button | 批量与等待 | ✅ 通过 | 768 ms |
| an expectation can verify selection while the same tab is visible throughout | 批量与等待 | ✅ 通过 | 784 ms |

**`test/coordination.test.mjs`** — 111 场景（通过 111，失败 0，超时 0，合计 329.5 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| old element refs cannot be reinterpreted by a later element list | 会话与传输、批量与等待 | ✅ 通过 | 1.1 s |
| a system prompt during input is an ordinary failure that stop_on_error decides | 会话与传输、批量与等待 | ✅ 通过 | 2.3 s |
| AX miss uses OCR from the same captured observation | 会话与传输、批量与等待、诊断与证据 | ✅ 通过 | 785 ms |
| two MCP sessions arbitrate aliases, batches and release across HTTP responses | 会话与传输、批量与等待 | ✅ 通过 | 1.2 s |
| cancel bypasses the queue, retains a batch prefix, invalidates queued calls and allows takeover | 会话与传输、批量与等待、稳定性与容错 | ✅ 通过 | 893 ms |
| lease expiry stops accepted work and stdio exit releases a renewed lease | 会话与传输、批量与等待 | ✅ 通过 | 1.6 s |
| SDK cancellation reaches an owned external process without a device lease | 会话与传输、批量与等待、稳定性与容错 | ✅ 通过 | 589 ms |
| wait_for deadline includes an in-flight device read and prevents OCR after timeout | 会话与传输、批量与等待、稳定性与容错 | ✅ 通过 | 1.3 s |
| observations bind image and structure, share prompt OCR, and invalidate refs on known changes | 会话与传输、批量与等待、稳定性与容错 | ✅ 通过 | 3.1 s |
| input receipt survives recording recovery failure and stopping prevents revival | 会话与传输、批量与等待、稳定性与容错、诊断与证据 | ✅ 通过 | 10.6 s |
| cancel interrupts the human dialog process and never executes the approved action | 会话与传输、批量与等待、安全与审批、稳定性与容错、诊断与证据 | ✅ 通过 | 479 ms |
| list_devices sends the user to Finder when usbmuxd answers with no device | 会话与传输、批量与等待 | ✅ 通过 | 477 ms |
| an occupied simulator cannot be booted through explicit, selected or batch paths | 会话与传输、批量与等待 | ✅ 通过 | 686 ms |
| cancel during recording recovery preserves dispatched input and finishes cleanup before takeover | 会话与传输、批量与等待、稳定性与容错、诊断与证据 | ✅ 通过 | 1.3 s |
| request cancellation leaves another device and another session recording intact | 会话与传输、批量与等待、稳定性与容错、诊断与证据 | ✅ 通过 | 1.3 s |
| healthy recording survives more than four inputs without consuming automatic retry budget | 会话与传输、批量与等待、稳定性与容错、诊断与证据 | ✅ 通过 | 9.0 s |
| automatic recording retries remain bounded after repeated unexpected disconnects | 会话与传输、批量与等待、诊断与证据 | ✅ 通过 | 3.9 s |
| renewal and rejected management calls preserve SDK cancellation identity | 会话与传输、批量与等待、稳定性与容错 | ✅ 通过 | 712 ms |
| an English query taps a mixed Chinese and English label | 会话与传输、批量与等待 | ✅ 通过 | 1.5 s |
| an English query taps a mixed Chinese and English label > handle_alert: Allow Paste | 会话与传输、批量与等待 | ✅ 通过 | 1.5 s |
| an English query taps a mixed Chinese and English label > handle_alert: 允许粘贴 | 会话与传输、批量与等待 | ✅ 通过 | 1.5 s |
| an English query taps a mixed Chinese and English label > handle_alert: 允 许 粘 贴 | 会话与传输、批量与等待 | ✅ 通过 | 1.6 s |
| an English query taps a mixed Chinese and English label > handle_alert: Don't Allow Paste | 会话与传输、批量与等待 | ✅ 通过 | 1.5 s |
| an English query taps a mixed Chinese and English label > take_screenshot: Enter iPhone Passcode | 会话与传输、批量与等待 | ✅ 通过 | 825 ms |
| an English query taps a mixed Chinese and English label > observe_device: Apple Account Password | 会话与传输、批量与等待 | ✅ 通过 | 862 ms |
| an English query taps a mixed Chinese and English label > list_elements: 账户密码 | 会话与传输、批量与等待 | ✅ 通过 | 889 ms |
| an English query taps a mixed Chinese and English label > list_elements: 面容 ID | 会话与传输、批量与等待 | ✅ 通过 | 959 ms |
| an English query taps a mixed Chinese and English label > list_elements: Face ID | 会话与传输、批量与等待 | ✅ 通过 | 882 ms |
| an English query taps a mixed Chinese and English label > list_elements: 触控 ID | 会话与传输、批量与等待 | ✅ 通过 | 795 ms |
| an English query taps a mixed Chinese and English label > list_elements: Touch ID | 会话与传输、批量与等待 | ✅ 通过 | 792 ms |
| an English query taps a mixed Chinese and English label > list_elements: Touch ID for “微信” | 会话与传输、批量与等待 | ✅ 通过 | 801 ms |
| an English query taps a mixed Chinese and English label > list_elements: “VPN”想添加 VPN 配置 | 会话与传输、批量与等待 | ✅ 通过 | 794 ms |
| an English query taps a mixed Chinese and English label > list_elements: 「VPN」想要加入 VPN 設定 | 会话与传输、批量与等待 | ✅ 通过 | 913 ms |
| an English query taps a mixed Chinese and English label > list_elements: 安装描述文件 | 会话与传输、批量与等待 | ✅ 通过 | 964 ms |
| an English query taps a mixed Chinese and English label > list_elements: 安裝描述檔 | 会话与传输、批量与等待 | ✅ 通过 | 853 ms |
| recognized prompts report their type without forcing a human handoff | 会话与传输、批量与等待 | ✅ 通过 | 16.3 s |
| purchase prompts require a button label before generic acceptance can tap | 会话与传输、批量与等待 | ✅ 通过 | 758 ms |
| purchase prompts allow an explicit button and generic dismissal | 会话与传输、批量与等待 | ✅ 通过 | 3.4 s |
| wireless Settings and app launch use the paired device when host CoreDevice cannot discover it | 会话与传输、批量与等待 | ✅ 通过 | 1.2 s |
| uncertain launches stop permissive batches and preserve the accepted prefix and launch receipt | 会话与传输、批量与等待 | ✅ 通过 | 2.1 s |
| a verified launch continues its batch when screenshots are unavailable, but a different foreground stops it | 会话与传输、批量与等待 | ✅ 通过 | 3.1 s |
| launch reconnects a stalled foreground observation without relaunching the app | 会话与传输、批量与等待 | ✅ 通过 | 3.6 s |
| paired application listing survives missing host discovery and preserves system filtering | 会话与传输、批量与等待 | ✅ 通过 | 501 ms |
| unknown container eligibility is decided by the copy service rather than rejected by app listing | 会话与传输、批量与等待 | ✅ 通过 | 535 ms |
| paired install and uninstall verify inventory, and uncertain installation stops permissive batches | 会话与传输、批量与等待 | ✅ 通过 | 1.2 s |
| completed application mutations retain service confirmation when inventory verification fails | 会话与传输、批量与等待 | ✅ 通过 | 716 ms |
| interrupted installation retains a private recovery record for its exact device staging directory | 会话与传输、批量与等待、稳定性与容错、诊断与证据 | ✅ 通过 | 1.5 s |
| a wrong later step stops the batch before any step runs | 会话与传输、批量与等待 | ✅ 通过 | 245 ms |
| a batch accepts the prefixed tool name a client shows to its model | 会话与传输、批量与等待 | ✅ 通过 | 247 ms |
| tap_text waits for a target that appears after it was called | 会话与传输、批量与等待 | ✅ 通过 | 2.7 s |
| a target only text recognition can read is tapped where it holds still, not where the deadline caught it | 会话与传输、批量与等待 | ✅ 通过 | 4.1 s |
| a missing target taps nothing and lets the next call fix only that step | 会话与传输、批量与等待 | ✅ 通过 | 5.6 s |
| scroll reports whether the screen moved and what it now shows | 会话与传输、批量与等待 | ✅ 通过 | 3.0 s |
| a tap that accessibility cannot read back reports the screen from OCR | 会话与传输、批量与等待 | ✅ 通过 | 1.5 s |
| a delivered tap stays a success when neither accessibility nor OCR can read the screen | 会话与传输、批量与等待 | ✅ 通过 | 1.5 s |
| a tap that leaves the screen as it was when its target was found says no change was observed | 会话与传输、批量与等待、稳定性与容错 | ✅ 通过 | 2.7 s |
| a batch pauses before the steps that follow a tap with no observed change, and names the step to check | 会话与传输、批量与等待、稳定性与容错 | ✅ 通过 | 4.2 s |
| a tap that only changes what is selected counts as a change, and the batch goes on | 会话与传输、批量与等待、稳定性与容错 | ✅ 通过 | 3.1 s |
| the application itself is not a tap target, even when the text is its name | 会话与传输、批量与等待 | ✅ 通过 | 5.7 s |
| a fill the phone could not confirm fails like one on a simulator and says what the field holds | 会话与传输、批量与等待 | ✅ 通过 | 1.7 s |
| launch_app on a simulator waits for a readable interface and reports when there is none | 会话与传输、批量与等待 | ✅ 通过 | 11.6 s |
| launch_app on a simulator says the launched app is in front | 会话与传输、批量与等待 | ✅ 通过 | 717 ms |
| fill enters plain text exactly when the simulator keyboard is an input method | 会话与传输、批量与等待 | ✅ 通过 | 3.6 s |
| a fill that could not enter its text stops the batch | 会话与传输、批量与等待 | ✅ 通过 | 1.8 s |
| a field that vanishes while typing fails the fill and the send after it never runs | 会话与传输、批量与等待 | ✅ 通过 | 1.8 s |
| fill leaves an empty field alone before typing, because backspace can delete what holds it | 会话与传输、批量与等待 | ✅ 通过 | 1.9 s |
| fill still clears a field that holds text | 会话与传输、批量与等待 | ✅ 通过 | 1.7 s |
| fill targets the input when another element shares its name, and never an element that takes no text | 会话与传输、批量与等待 | ✅ 通过 | 2.0 s |
| fill can still aim at text recognized on a screen accessibility cannot read | 会话与传输、批量与等待 | ✅ 通过 | 5.8 s |
| fill aims again when a list slides the field away, so the row now under the old place keeps its text | 会话与传输、批量与等待 | ✅ 通过 | 2.0 s |
| a tap that lands on another row stops the fill before any text and before the send | 会话与传输、批量与等待 | ✅ 通过 | 1.7 s |
| a field that already has focus takes the text with no touch at all | 会话与传输、批量与等待 | ✅ 通过 | 1.4 s |
| two fields named "Title" holding the same text with no id get no touch, text or Return, wherever fill aims | 会话与传输、批量与等待 | ✅ 通过 | 1.2 s |
| two fields named "Title" holding different text stay apart when the tap moves the list | 会话与传输、批量与等待 | ✅ 通过 | 2.1 s |
| text that lands in another field named "Title" fails the fill and submit never runs | 会话与传输、批量与等待 | ✅ 通过 | 843 ms |
| two fields named "" holding the same text with no id get no touch, text or Return, wherever fill aims | 会话与传输、批量与等待 | ✅ 通过 | 1.2 s |
| two fields named "" holding different text stay apart when the tap moves the list | 会话与传输、批量与等待 | ✅ 通过 | 2.0 s |
| text that lands in another field named "" fails the fill and submit never runs | 会话与传输、批量与等待 | ✅ 通过 | 789 ms |
| a same-looking field that appears after the tap gets no text and no Return | 会话与传输、批量与等待 | ✅ 通过 | 959 ms |
| text that lands in another field fails the fill and submit never runs | 会话与传输、批量与等待 | ✅ 通过 | 1.1 s |
| a field found by name is refused when another shares its id and text, with no tap on the phone | 会话与传输、批量与等待 | ✅ 通过 | 696 ms |
| a phone fill on a new row being edited leaves the row above alone, the overwrite this guards against | 会话与传输、批量与等待 | ✅ 通过 | 1.7 s |
| a phone fill at coordinates with no field there leaves the row being edited alone | 会话与传输、批量与等待 | ✅ 通过 | 1.1 s |
| a phone fill by ref follows its field when another row has moved under the old place | 会话与传输、批量与等待 | ✅ 通过 | 2.1 s |
| a phone fill taps a field not being edited, then tells native which field it means | 会话与传输、批量与等待 | ✅ 通过 | 1.9 s |
| a phone tap that gives the edit to another row stops the batch with no text sent | 会话与传输、批量与等待 | ✅ 通过 | 5.2 s |
| a phone field that never starts editing gets two taps and no text | 会话与传输、批量与等待 | ✅ 通过 | 5.0 s |
| a phone field native refuses stops the batch before the send | 会话与传输、批量与等待 | ✅ 通过 | 1.4 s |
| tap_text sends nothing when its read outlasts the five seconds, and that read is stopped | 会话与传输、批量与等待 | ✅ 通过 | 10.3 s |
| tap_text sends nothing to a target that never holds its place | 会话与传输、批量与等待 | ✅ 通过 | 8.2 s |
| fill sends nothing when its read outlasts the five seconds, and that read is stopped | 会话与传输、批量与等待 | ✅ 通过 | 10.3 s |
| fill sends nothing to a target that never holds its place | 会话与传输、批量与等待 | ✅ 通过 | 8.1 s |
| handle_alert sends nothing when its read outlasts the five seconds, and that read is stopped | 会话与传输、批量与等待 | ✅ 通过 | 10.3 s |
| handle_alert sends nothing to a target that never holds its place | 会话与传输、批量与等待 | ✅ 通过 | 8.2 s |
| a recognition that began inside the five seconds still finishes and is used | 会话与传输、批量与等待 | ✅ 通过 | 13.7 s |
| no new look starts after the five seconds, so a late empty read never reaches OCR | 会话与传输、批量与等待 | ✅ 通过 | 10.3 s |
| fill taps again when the first tap does not give the field focus | 会话与传输、批量与等待 | ✅ 通过 | 3.8 s |
| a field that never takes focus fails the fill and stops the batch | 会话与传输、批量与等待 | ✅ 通过 | 5.2 s |
| a lost tap never types over the field that still has focus | 会话与传输、批量与等待 | ✅ 通过 | 4.8 s |
| input to a simulator stays on one connection while it keeps coming | 会话与传输、批量与等待 | ✅ 通过 | 3.1 s |
| a connection the simulator dropped while idle is replaced and the tap still lands | 会话与传输、批量与等待 | ✅ 通过 | 3.9 s |
| a connection lost during a send reports an unknown outcome and sends nothing again | 会话与传输、批量与等待 | ✅ 通过 | 2.3 s |
| typing selects the keyboard again when it changed under a live connection | 会话与传输、批量与等待、稳定性与容错 | ✅ 通过 | 2.6 s |
| an app launches on the en_US keyboard even with a connection already open | 会话与传输、批量与等待 | ✅ 通过 | 2.4 s |
| a large max_scrolls is not refused | 会话与传输、批量与等待 | ✅ 通过 | 460 ms |
| a tap after another input waits until the app can take touches | 会话与传输、批量与等待 | ✅ 通过 | 2.1 s |
| a device named in a batch step holds for that step, whatever is selected | 会话与传输、批量与等待 | ✅ 通过 | 2.8 s |
| the screen a batch ends with belongs to the device its last step used | 会话与传输、批量与等待 | ✅ 通过 | 5.9 s |
| a target read on one device is never tapped on another | 会话与传输、批量与等待 | ✅ 通过 | 7.8 s |
| application names reuse a per-device directory across sessions and refresh after mutations | 会话与传输、批量与等待 | ✅ 通过 | 3.3 s |
| verify:false omits action verification and batches observe once after all inputs | 会话与传输、批量与等待 | ✅ 通过 | 4.0 s |

**`test/cua-wda.test.mjs`** — 3 场景（通过 3，失败 0，超时 0，合计 3.7 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| look and do answer the same way on WebDriverAgent: numbered elements, screenshot, actions sent | 操作、观察 | ✅ 通过 | 3.5 s |
| an input WDA refuses is not_sent, and one it never answered is unknown | 操作、观察 | ✅ 通过 | 129 ms |
| a runner that stops taking connections is reported as down, its action not sent and nothing after it | 操作、观察 | ✅ 通过 | 65 ms |

**`test/cua.test.mjs`** — 16 场景（通过 16，失败 0，超时 0，合计 24.6 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| do reports each action as sent, waits, and reads once with a screenshot | 操作、观察 | ✅ 通过 | 562 ms |
| literal typing is verified, restores the clipboard, and refuses an unrestorable clipboard | 操作、观察 | ✅ 通过 | 1.4 s |
| uncertain literal input is not replayed and stops actions after it | 操作、观察、诊断与证据 | ✅ 通过 | 1.6 s |
| an unverified literal write cannot be followed by Return | 操作、观察 | ✅ 通过 | 804 ms |
| an element number that is not in the latest read is refused with the current list, and nothing is sent | 操作、观察 | ✅ 通过 | 122 ms |
| scroll_to swipes until the target is on screen, in one action | 操作、观察 | ✅ 通过 | 2.7 s |
| long_press, drag and pinch take element numbers or points, with defaults | 操作、观察、稳定性与容错 | ✅ 通过 | 993 ms |
| a dark, locked screen stops dispatching | 操作、观察 | ✅ 通过 | 23 ms |
| the actions of one call stop at the action time cap | 操作、观察 | ✅ 通过 | 4.1 s |
| on a simulator, do launches the app with simctl | 操作、观察 | ✅ 通过 | 1.8 s |
| on a simulator, do types with the simulator keyboard | 操作、观察 | ✅ 通过 | 1.3 s |
| CUA preserves an exact search expression despite a rewriting hardware input method | 操作、观察 | ✅ 通过 | 1.1 s |
| literal typing does not overwrite a clipboard changed concurrently | 操作、观察、稳定性与容错 | ✅ 通过 | 1.1 s |
| verified literal input has enough bounded budget to allow Return after a slow paste | 操作、观察 | ✅ 通过 | 5.2 s |
| a pending native paste is unknown and its clipboard is retained without Return | 操作、观察 | ✅ 通过 | 800 ms |
| a rich clipboard change with the same text is never overwritten by the JS wrapper | 操作、观察、稳定性与容错 | ✅ 通过 | 1.1 s |

**`test/default-device.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 1.4 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| POKI_MCP_DEVICE picks the device when several match, and an explicit device still wins | 会话与传输 | ✅ 通过 | 995 ms |
| Without POKI_MCP_DEVICE two matching devices still ask for a choice | 会话与传输 | ✅ 通过 | 362 ms |

**`test/draw.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 6.1 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| touch_path and draw_strokes reach the phone as timed HID strokes and invalid paths send nothing | 操作 | ✅ 通过 | 4.0 s |
| simulator strokes each touch down, follow their timing and lift in their own HID batch | 操作 | ✅ 通过 | 2.2 s |

**`test/eval-metrics.test.mjs`** — 3 场景（通过 3，失败 0，超时 0，合计 1 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| paired arms share input and separate rounds vary it | 效率与资源、诊断与证据 | ✅ 通过 | 0 ms |
| token accounting preserves provider cache semantics and missing usage | 效率与资源、诊断与证据 | ✅ 通过 | 0 ms |
| tool wall time only counts overlapping intervals once | 效率与资源、诊断与证据 | ✅ 通过 | 0 ms |

**`test/input-lock.test.mjs`** — 14 场景（通过 14，失败 0，超时 0，合计 2.4 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| input lock is off unless POKI_INPUT_LOCK=1, and reads its limits from the environment | 安全与审批 | ✅ 通过 | 1 ms |
| the lock is keyed by the id each step resolves to, and covers every device when that is unclear | 安全与审批 | ✅ 通过 | 0 ms |
| without the lock every session shares one queue, as before | 安全与审批 | ✅ 通过 | 84 ms |
| with the lock, a read from another session runs while input holds the device | 安全与审批 | ✅ 通过 | 81 ms |
| with the lock, input from two sessions to one device runs one at a time | 安全与审批 | ✅ 通过 | 83 ms |
| with the lock, input to two different devices runs side by side | 安全与审批 | ✅ 通过 | 41 ms |
| with the lock, one session keeps its own order even for reads | 安全与审批 | ✅ 通过 | 47 ms |
| a session that waits too long gets an error naming the holder and its tool | 安全与审批 | ✅ 通过 | 302 ms |
| an unknown device excludes input to every device | 安全与审批 | ✅ 通过 | 11 ms |
| reads are capped at POKI_MAX_CONCURRENT_READS | 安全与审批 | ✅ 通过 | 63 ms |
| an aborted wait leaves the queue and does not run | 安全与审批 | ✅ 通过 | 103 ms |
| a phone named by one session and given by its UDID in another takes one input lock | 安全与审批 | ✅ 通过 | 1.6 s |
| already cancelled work cannot enter either lock queue | 安全与审批、稳定性与容错 | ✅ 通过 | 0 ms |
| cancellation during device resolution does not leave a lock waiter behind | 安全与审批、稳定性与容错 | ✅ 通过 | 0 ms |

**`test/install-download.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 130 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| DMG 504 falls back to the asset API but still rejects a checksum mismatch | 安装与配对 | ✅ 通过 | 14 ms |
| a bridge download failure installs a verified local IPA with its matching signing zip | 安装与配对 | ✅ 通过 | 115 ms |

**`test/install-iphone.test.mjs`** — 39 场景（通过 39，失败 0，超时 0，合计 16.6 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| runs every step in order, stops at each person step with one sentence, and continues once it is done | 安装与配对、稳定性与容错 | ✅ 通过 | 278 ms |
| runs every step in order, stops at each person step with one sentence, and continues once it is done > trust-timeout | 安装与配对、稳定性与容错 | ✅ 通过 | 320 ms |
| runs every step in order, stops at each person step with one sentence, and continues once it is done > sign-fails | 安装与配对、稳定性与容错 | ✅ 通过 | 226 ms |
| runs every step in order, stops at each person step with one sentence, and continues once it is done > usbmuxd | 安装与配对、稳定性与容错 | ✅ 通过 | 139 ms |
| a step that fails gives a machine-readable code, its reason and what to do, and retries only what can heal | 安装与配对、稳定性与容错 | ✅ 通过 | 686 ms |
| a DDI signing refusal gives Xcode recovery steps in the JSON failure result | 安装与配对、稳定性与容错 | ✅ 通过 | 371 ms |
| a person stop that nobody answers ends with exit 3 and a rerun resumes from that step | 安装与配对、稳定性与容错 | ✅ 通过 | 534 ms |
| the diagnostics bundle and the issue draft keep the failure but drop identifiers, tokens, keys, pairing records and relay addresses | 安装与配对、稳定性与容错、诊断与证据 | ✅ 通过 | 131 ms |
| the issue draft is only printed: it never runs gh, and it says the person must approve it first | 安装与配对、稳定性与容错、安全与审批 | ✅ 通过 | 88 ms |
| the agent guide documents every error code the installer can print | 安装与配对、稳定性与容错 | ✅ 通过 | 1 ms |
| phones and diagnose find the Poki Setup that run installs into ~/Applications, and a missing one is an error code, not a stack | 安装与配对、稳定性与容错 | ✅ 通过 | 223 ms |
| phones and diagnose use the helper the last run started, wherever it was | 安装与配对、稳定性与容错 | ✅ 通过 | 99 ms |
| findSetupBridge names setup_app_missing and lists where it looked | 安装与配对、稳定性与容错 | ✅ 通过 | 3 ms |
| the Apple code never goes on a command line: it is typed to stdin, and a code in the arguments is refused | 安装与配对、稳定性与容错 | ✅ 通过 | 132 ms |
| the Apple code command in the prompt works pasted into a new Terminal outside the checkout, and reaches the install that is waiting, with or without --state | 安装与配对、稳定性与容错 | ✅ 通过 | 543 ms |
| the installer shows its own version and build, and diagnose and the issue draft carry the versions of the installer, Poki Setup and the installed Poki | 安装与配对、稳定性与容错 | ✅ 通过 | 472 ms |
| the bundle and the draft drop the Apple Account holder, the Mac name and phone names in other languages | 安装与配对、稳定性与容错 | ✅ 通过 | 264 ms |
| with nothing to reuse, Poki Setup windows ask for the Apple Account and the code, so the person never opens Terminal | 安装与配对、稳定性与容错 | ✅ 通过 | 918 ms |
| closing the Poki Setup window stops with apple_credentials_missing instead of signing in | 安装与配对、稳定性与容错 | ✅ 通过 | 691 ms |
| closing the Poki Setup window stops with apple_credentials_missing instead of signing in > Poki Setup is signed in | 安装与配对、稳定性与容错 | ✅ 通过 | 228 ms |
| closing the Poki Setup window stops with apple_credentials_missing instead of signing in > the keychain item is there | 安装与配对、稳定性与容错 | ✅ 通过 | 770 ms |
| a sign-in Poki Setup already keeps, or a password already in the keychain, is reused without any window | 安装与配对、稳定性与容错 | ✅ 通过 | 999 ms |
| a network error while signing in is retried with what the person already typed, without asking again | 安装与配对、稳定性与容错 | ✅ 通过 | 835 ms |
| diagnose reads Poki Setup's own log where Poki Setup keeps it on macOS | 安装与配对、稳定性与容错、诊断与证据 | ✅ 通过 | 86 ms |
| diagnose drops the Apple team id and certificate ids from Poki Setup's log | 安装与配对、稳定性与容错、诊断与证据 | ✅ 通过 | 96 ms |
| a phone that is already paired is not a person stop: the Trust reminder becomes a note | 安装与配对、稳定性与容错 | ✅ 通过 | 262 ms |
| Poki says by itself that it is open, so the install goes on with nobody running done open_poki | 安装与配对、稳定性与容错 | ✅ 通过 | 256 ms |
| Poki says by itself that it is open, so the install goes on with nobody running done open_poki > through Poki Setup | 安装与配对、稳定性与容错 | ✅ 通过 | 701 ms |
| Poki says by itself that it is open, so the install goes on with nobody running done open_poki > Poki Setup 0.2.1 and Xcode: through devicectl | 安装与配对、稳定性与容错 | ✅ 通过 | 1.0 s |
| with --model-key, the key goes from the Mac keychain into Poki sealed, Poki takes it, and it never appears in output, state, logs, diagnostics or a command line | 安装与配对、稳定性与容错、诊断与证据 | ✅ 通过 | 1.7 s |
| without --model-key the installer never reads a model key from the keychain | 安装与配对、稳定性与容错 | ✅ 通过 | 262 ms |
| a missing keychain item stops with model_key_missing and names the item, not a key | 安装与配对、稳定性与容错 | ✅ 通过 | 520 ms |
| with no way into Poki's files (Poki Setup 0.2.1, no Xcode), the install falls back to asking the person | 安装与配对、稳定性与容错 | ✅ 通过 | 543 ms |
| when Poki's local connection does not answer, the installer says Poki's own sentence for the VPN app and goes on once it answers | 安装与配对、稳定性与容错 | ✅ 通过 | 362 ms |
| the install-poki skill walks the same steps and person stops as the installer, in order | 安装与配对、稳定性与容错 | ✅ 通过 | 1 ms |
| the install-poki skill walks the same steps and person stops as the installer, in order > false | 安装与配对、稳定性与容错 | ✅ 通过 | 285 ms |
| the install-poki skill walks the same steps and person stops as the installer, in order > true | 安装与配对、稳定性与容错 | ✅ 通过 | 297 ms |
| expired signing is renewed on rerun and an expired final record is rejected | 安装与配对、稳定性与容错、诊断与证据 | ✅ 通过 | 582 ms |
| a Poki too old to write its hello still counts as open once devicectl sees it running | 安装与配对、稳定性与容错 | ✅ 通过 | 683 ms |

**`test/install-model-key.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 839 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| a key the installer seals opens in Poki's Swift code, only for that phone key, that app and that provider | 安装与配对 | ✅ 通过 | 839 ms |
| a hello whose key does not match its id, or is not a P-256 point, gets no sealed key | 安装与配对 | ✅ 通过 | 0 ms |

**`test/install-records.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 496 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| records copies the chats, voice turns and log off the phone into one readable file in time order, without keys or relay addresses | 安装与配对、诊断与证据 | ✅ 通过 | 265 ms |
| records on a phone where Poki never saved anything says so instead of failing | 安装与配对、诊断与证据 | ✅ 通过 | 231 ms |

**`test/native-session.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 1.1 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| consecutive local MCP observations retain the native helper process | 会话与传输 | ✅ 通过 | 636 ms |
| a local native helper that exits before ready reports its exit status and stderr | 会话与传输 | ✅ 通过 | 485 ms |

**`test/observation-output.test.mjs`** — 15 场景（通过 15，失败 0，超时 0，合计 20.4 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| observe_device omits PNG only when requested | 观察、批量与等待 | ✅ 通过 | 773 ms |
| missing prompt OCR remains explicit without an image attachment | 观察、批量与等待 | ✅ 通过 | 739 ms |
| observe_device rejects non-boolean include_image | 观察、批量与等待 | ✅ 通过 | 251 ms |
| a tree that names only the top of the screen gets the screenshot text it left out | 观察、批量与等待 | ✅ 通过 | 1.4 s |
| a Tesseract process timeout leaves the screenshot and reports prompt OCR unavailable | 观察、批量与等待、稳定性与容错 | ✅ 通过 | 5.5 s |
| numeric_region returns OCR boxes in the original screen coordinates | 观察、批量与等待 | ✅ 通过 | 707 ms |
| image fallback serves visible AX without attaching an image or invoking OCR | 观察、批量与等待 | ✅ 通过 | 674 ms |
| image fallback supplies a screenshot when AX misses the target or fails | 观察、批量与等待 | ✅ 通过 | 826 ms |
| an AX read deadline still yields the screenshot in image fallback mode | 观察、批量与等待 | ✅ 通过 | 2.9 s |
| hybrid routes known visible text through AX, OCR, then a single image | 观察、批量与等待 | ✅ 通过 | 1.3 s |
| hybrid returns one image after the OCR deadline and can read the next frame | 观察、批量与等待 | ✅ 通过 | 2.3 s |
| hybrid text-only requests use AX or OCR without attaching a PNG | 观察、批量与等待 | ✅ 通过 | 775 ms |
| text-only fallback reports missing evidence and keeps explicit visual requests distinct | 观察、批量与等待、诊断与证据 | ✅ 通过 | 951 ms |
| explicit hybrid visual request goes straight to the screenshot | 观察、批量与等待 | ✅ 通过 | 637 ms |
| hybrid can try local OCR without repeating an insufficient AX read | 观察、批量与等待 | ✅ 通过 | 593 ms |

**`test/observation.test.mjs`** — 13 场景（通过 13，失败 0，超时 0，合计 65.0 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| a tap on a phone with slow accessibility reads still ends with the screen | 观察 | ✅ 通过 | 11.0 s |
| a readback cut off by its deadline reports the last complete read instead of nothing | 观察 | ✅ 通过 | 6.8 s |
| screen_change says changed, unchanged, or unknown, and only unchanged carries the no-change advice | 观察、稳定性与容错 | ✅ 通过 | 14.4 s |
| six coordinate taps in one batch read the screen once at the end, not around every tap | 观察 | ✅ 通过 | 13.6 s |
| a gated tool says who approved it, and the status names the tools approval covers | 观察、安全与审批 | ✅ 通过 | 5.4 s |
| launch_app on a phone ends with the screen, says when the app resumed, and fresh relaunches it | 观察 | ✅ 通过 | 1.3 s |
| a screenshot says it was not saved to the device Photos library | 观察 | ✅ 通过 | 533 ms |
| a screen that only lags behind the touch is not called unchanged | 观察、稳定性与容错 | ✅ 通过 | 6.3 s |
| a different app in front counts as a change even when its tree has not arrived | 观察、稳定性与容错 | ✅ 通过 | 1.3 s |
| a screen says when its read began and how old it is | 观察 | ✅ 通过 | 2.1 s |
| launch_app gives the app a moment to come to the front and says how long it took | 观察 | ✅ 通过 | 1.9 s |
| the Home Screen is named com.apple.springboard, and later reads of it say so too | 观察 | ✅ 通过 | 2 ms |
| the status shows the commit recorded at build time when git is not there | 观察、诊断与证据 | ✅ 通过 | 324 ms |

**`test/ocr.test.mjs`** — 5 场景（通过 5，失败 0，超时 0，合计 134 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| TSV keeps Unicode line text, pixel bounds and normalized confidence | 观察 | ✅ 通过 | 1 ms |
| configured Tesseract backend avoids the hung Vision binary and retains coordinate mapping | 观察 | ✅ 通过 | 10 ms |
| an unset OCR backend defaults to Tesseract | 观察、稳定性与容错 | ✅ 通过 | 0 ms |
| spaced Chinese OCR text still triggers the paste prompt warning | 观察 | ✅ 通过 | 0 ms |
| Tesseract discovers installed Chinese packs and respects an explicit language override | 观察 | ✅ 通过 | 123 ms |

**`test/post-action-do-rotation.test.mjs`** — 1 场景（通过 1，失败 0，超时 0，合计 2.1 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| rotation before a do coordinate tap refreshes dimensions | 观察、操作 | ✅ 通过 | 2.1 s |

**`test/post-action-observation.test.mjs`** — 11 场景（通过 11，失败 0，超时 0，合计 29.1 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| opted-in input supplies post-action refs without an extra observation request | 观察 | ✅ 通过 | 2.2 s |
| optional image OCR captures AFTER the stable AX read | 观察、诊断与证据 | ✅ 通过 | 2.2 s |
| an AX-only ref remains usable without a redundant capture until input invalidates it | 观察、诊断与证据 | ✅ 通过 | 3.8 s |
| a changed post-input image does not invalidate stable AX simply because the scene revision advances | 观察、稳定性与容错 | ✅ 通过 | 2.3 s |
| rotation between coordinate taps refreshes viewport before HID conversion | 观察 | ✅ 通过 | 3.9 s |
| unverifiable AX root safely falls back to capture for coordinate taps | 观察、诊断与证据 | ✅ 通过 | 3.9 s |
| verify:false coordinate tap refreshes dimensions after rotation | 观察 | ✅ 通过 | 2.3 s |
| rotation before a batch swipe step refreshes dimensions | 观察 | ✅ 通过 | 3.1 s |
| rotation before a batch drag step refreshes dimensions | 观察 | ✅ 通过 | 3.1 s |
| unchanged screen after delayed confirmation still has a reusable AX receipt | 观察、稳定性与容错 | ✅ 通过 | 2.2 s |
| changed delayed confirmation rejects post-action AX reuse | 观察、稳定性与容错 | ✅ 通过 | 105 ms |

**`test/prepare-device.test.mjs`** — 4 场景（通过 4，失败 0，超时 0，合计 639 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| prepare-device explains an image whose manifest the installer cannot read instead of printing the installer panic | 安装与配对 | ✅ 通过 | 188 ms |
| prepare-device explains Apple declining to sign the image instead of printing the installer panic | 安装与配对 | ✅ 通过 | 220 ms |
| prepare-device explains another image mounted at /System/Developer instead of printing the installer panic | 安装与配对 | ✅ 通过 | 134 ms |
| prepare-device sends the user to Finder when usbmuxd answers with no device | 安装与配对 | ✅ 通过 | 97 ms |

**`test/prepare-remote.test.mjs`** — 1 场景（通过 1，失败 0，超时 0，合计 1.2 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| remote setup persists a Bonjour host for future resolution and preserves IP setups | 安装与配对 | ✅ 通过 | 1.2 s |

**`test/protocol.test.mjs`** — 19 场景（通过 19，失败 0，超时 0，合计 23.9 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| native | 会话与传输、安全与审批 | ✅ 通过 | 2.8 s |
| JavaScript | 会话与传输、安全与审批 | ✅ 通过 | 2.9 s |
| fill asks for a daemon restart after native or JavaScript updates and recovers after restart | 会话与传输、安全与审批、稳定性与容错 | ✅ 通过 | 5.7 s |
| stdio reaches the authenticated local MCP service and rejects an absent device | 会话与传输、安全与审批 | ✅ 通过 | 3.2 s |
| an all-profile HTTP service still lets each stdio client choose its own list | 会话与传输、安全与审批 | ✅ 通过 | 421 ms |
| Poki Agent opens its own MCP with the complete catalog even when the parent uses the default profile | 会话与传输、安全与审批、稳定性与容错、诊断与证据 | ✅ 通过 | 464 ms |
| Poki Agent uses its own tool profile and falls back for an older endpoint | 会话与传输、安全与审批 | ✅ 通过 | 850 ms |
| the direct Agent client cancels timed-out input and does not replay input across a daemon restart | 会话与传输、安全与审批、稳定性与容错、诊断与证据 | ✅ 通过 | 1.3 s |
| the daemon releases a direct Agent lease if its process exits without closing | 会话与传输、安全与审批 | ✅ 通过 | 2.0 s |
| screenshot coordinates preserve HID corners and reject out-of-frame input | 会话与传输、安全与审批 | ✅ 通过 | 0 ms |
| a connected client keeps working when the service restarts on the same port with a new token | 会话与传输、安全与审批、稳定性与容错 | ✅ 通过 | 396 ms |
| a connected client keeps working when the service restarts on another port with a new token | 会话与传输、安全与审批、稳定性与容错 | ✅ 通过 | 360 ms |
| a connected client says to run npm start while the service is down after SIGTERM, and works again once it is back | 会话与传输、安全与审批 | ✅ 通过 | 332 ms |
| a connected client says to run npm start while the service is down after SIGKILL, and works again once it is back | 会话与传输、安全与审批 | ✅ 通过 | 349 ms |
| a client started with no service says to run npm start, with the endpoint file left behind or gone | 会话与传输、安全与审批 | ✅ 通过 | 404 ms |
| a token the service still rejects after the re-read is reported without printing any token | 会话与传输、安全与审批 | ✅ 通过 | 448 ms |
| a call cut off by a restart is not sent again, because the phone may already have acted | 会话与传输、安全与审批、稳定性与容错 | ✅ 通过 | 769 ms |
| bin/call.mjs says a select_device choice lasts for that run only | 会话与传输、安全与审批 | ✅ 通过 | 1.0 s |
| bin/setup says what to install for a missing prerequisite | 会话与传输、安全与审批 | ✅ 通过 | 42 ms |

**`test/remote.test.mjs`** — 1 场景（通过 1，失败 0，超时 0，合计 2.3 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| Remote screen capture survives observation cancellation and daemon restart after new connections are refused | 会话与传输、稳定性与容错、诊断与证据 | ✅ 通过 | 2.3 s |

**`test/run-code.test.mjs`** — 7 场景（通过 7，失败 0，超时 0，合计 11.1 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| run_code runs several steps in one call and returns a value derived from a tool receipt | 操作 | ✅ 通过 | 831 ms |
| run_code returns an action with the screen it produced, as a direct call does | 操作 | ✅ 通过 | 1.4 s |
| run_code denies require, fetch, process and dynamic import, and the daemon keeps serving | 操作 | ✅ 通过 | 338 ms |
| run_code reports a return value that is not JSON as a script error and keeps its calls | 操作 | ✅ 通过 | 306 ms |
| run_code stops when an action reports sent=false, and no later step runs even under try/catch | 操作 | ✅ 通过 | 711 ms |
| run_code times out, cancels the in-flight device call, and the daemon serves the next call | 操作、稳定性与容错 | ✅ 通过 | 6.4 s |
| run_code stops a runaway loop at its tool-call ceiling | 操作 | ✅ 通过 | 1.1 s |

**`test/save-screenshot.test.mjs`** — 1 场景（通过 1，失败 0，超时 0，合计 746 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| saving a screenshot keeps the original pixels and uses the filename format | 诊断与证据、观察 | ✅ 通过 | 746 ms |

**`test/scroll-container.test.mjs`** — 14 场景（通过 14，失败 0，超时 0，合计 7.7 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| quick scrolling returns a single unverified AX window with duplicates and no tap refs | 操作、观察 | ✅ 通过 | 615 ms |
| a batch can explicitly request stable evidence after a final quick scroll | 操作、观察、诊断与证据 | ✅ 通过 | 713 ms |
| an unnamed overlay stops a quick scroll batch before the next step | 操作、观察 | ✅ 通过 | 616 ms |
| an uncertain quick swipe is neither observed nor replayed | 操作、观察、诊断与证据 | ✅ 通过 | 9 ms |
| a batch reports an AX-only tap miss from the lookup tree without reading again | 操作、观察 | ✅ 通过 | 2 ms |
| the tap after scroll_to reuses its AX sample and still checks motion | 操作、观察 | ✅ 通过 | 2.2 s |
| a vertical search followed by a tap on the same label pages with a held release | 操作、观察 | ✅ 通过 | 2.1 s |
| scroll_to stops after a drag with uncertain delivery | 操作、观察 | ✅ 通过 | 11 ms |
| a bounded scroll search returns its last viewport without rereading or running the suffix | 操作、观察 | ✅ 通过 | 215 ms |
| a stopped scroll search does not reuse a viewport from a different foreground | 操作、观察 | ✅ 通过 | 213 ms |
| an AX-only search can find visible text without capturing or scrolling | 操作、观察 | ✅ 通过 | 2 ms |
| default search still finds visual text omitted from AX | 操作、观察、稳定性与容错 | ✅ 通过 | 14 ms |
| a one-page scroll inside a named row moves only that row, without coasting, and says which container moved | 操作、观察 | ✅ 通过 | 926 ms |
| whatMoved names the container whose items shifted together | 操作、观察 | ✅ 通过 | 0 ms |

**`test/setup-app-channel.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 1 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| app-* tags map to channels | 安装与配对 | ✅ 通过 | 0 ms |
| ios-* and desktop-* tags keep their channels | 安装与配对 | ✅ 通过 | 0 ms |

**`test/simulator-orientation.test.mjs`** — 3 场景（通过 3，失败 0，超时 0，合计 2.0 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| simulator maps landscape_left screen points to portrait HID coordinates | 操作 | ✅ 通过 | 782 ms |
| simulator maps landscape_right screen points to portrait HID coordinates | 操作 | ✅ 通过 | 656 ms |
| simulator refuses coordinates on an unconfirmed landscape screen | 操作 | ✅ 通过 | 540 ms |

**`test/terminate-app.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 1 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| terminate_app matches a devicectl file URL to the plain app path | 操作 | ✅ 通过 | 1 ms |
| terminate_app returns already_stopped only when that app is not running | 操作 | ✅ 通过 | 0 ms |

**`test/update.test.mjs`** — 10 场景（通过 10，失败 0，超时 0，合计 17.9 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| older | 安装与配对 | ✅ 通过 | 2.1 s |
| equal | 安装与配对 | ✅ 通过 | 1.1 s |
| newer | 安装与配对 | ✅ 通过 | 1.0 s |
| disabled | 安装与配对 | ✅ 通过 | 1.1 s |
| offline | 安装与配对 | ✅ 通过 | 985 ms |
| cached | 安装与配对 | ✅ 通过 | 905 ms |
| default | 安装与配对、稳定性与容错 | ✅ 通过 | 946 ms |
| MCP and CLI expose releases, honor opt-out and stay quiet offline | 安装与配对 | ✅ 通过 | 8.1 s |
| MCP and CLI expose releases, honor opt-out and stay quiet offline > preserves ignored files when upstream starts tracking them | 安装与配对 | ✅ 通过 | 328 ms |
| poki update fast-forwards a clean main checkout and preserves dirty or non-main checkouts | 安装与配对 | ✅ 通过 | 1.4 s |

**`test/vision-ocr.test.mjs`** — 7 场景（通过 7，失败 0，超时 0，合计 118 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| real page probes stay in the background until a similar page has two fast replies | 观察 | ✅ 通过 | 3 ms |
| a slow foreground reply falls back and demotes only its page | 观察 | ✅ 通过 | 16 ms |
| a hung foreground recognition is reaped after the hard deadline | 观察 | ✅ 通过 | 57 ms |
| caller cancellation keeps the shared worker and discards the late reply | 观察、稳定性与容错 | ✅ 通过 | 1 ms |
| an unused worker exits and critical pressure interrupts a busy worker | 观察 | ✅ 通过 | 22 ms |
| warning pressure lets an active recognition finish and then retires the worker | 观察 | ✅ 通过 | 0 ms |
| abandoned warmup reaps the child without waiting for the hard warmup limit | 观察 | ✅ 通过 | 21 ms |

**`test/voice-bridge.test.mjs`** — 3 场景（通过 3，失败 0，超时 0，合计 4.6 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| a voice tap_text the phone has not checked taps nothing; once checked it taps once | 操作、安全与审批 | ✅ 通过 | 2.7 s |
| a voice tap_text with Poki in front taps nothing, checked or not | 操作、安全与审批 | ✅ 通过 | 918 ms |
| a voice tap_text on an element known only by its identifier shows the phone that name | 操作、安全与审批 | ✅ 通过 | 954 ms |

## 6. Agent 套件

- 入口：`cd agent && npm test`
- 场景：68（通过 54，失败 12，超时 2，未跑 0），墙钟 272.9 s
- 单场景耗时：中位 10 ms，P95 2.4 s，最长 30.0 s

**`agent/test/agent-observation-reuse.test.mjs`** — 7 场景（通过 0，失败 7，超时 0，合计 18 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| Agent reuses eligible receipt and omits the second explicit list_elements read | 观察、批量与等待、效率与资源 | ❌ 失败 | 10 ms |
| Agent retains list_elements fallback for a legacy receipt | 观察、批量与等待、效率与资源 | ❌ 失败 | 1 ms |
| Agent uses a PID-bound terminal batch observation without another list_elements call | 观察、批量与等待、效率与资源 | ❌ 失败 | 1 ms |
| Agent uses a PID-bound terminal batch observation without another list_elements call > single scroll | 观察、批量与等待、效率与资源 | ❌ 失败 | 1 ms |
| Agent uses a PID-bound terminal batch observation without another list_elements call > batch | 观察、批量与等待、效率与资源 | ❌ 失败 | 1 ms |
| Agent uses quick scroll evidence for browsing and still requires a final observation | 观察、批量与等待、效率与资源、诊断与证据 | ❌ 失败 | 2 ms |
| Agent still reads the screen when a quick sample is unavailable | 观察、批量与等待、效率与资源 | ❌ 失败 | 1 ms |

**`agent/test/channels.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 13.1 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| bluebubbles CLI carries task, progress, system prompt handling, completion and failure through local HTTP services | Agent 端 | ✅ 通过 | 7.5 s |
| telegram CLI carries task, progress, system prompt handling, completion and failure through local HTTP services | Agent 端 | ✅ 通过 | 5.7 s |

**`agent/test/fast-observation-reuse.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 2 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| fast route reuses one eligible post-action observation for its next step | 观察、效率与资源 | ✅ 通过 | 2 ms |
| fast route falls back to real observation when a prompt check is unavailable | 观察、效率与资源 | ✅ 通过 | 0 ms |

**`agent/test/gateway-setup.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 831 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| Optional gateway CLI skips downloads, cleans failures and preserves existing destinations | Agent 端、安装与配对 | ✅ 通过 | 541 ms |
| Private-config launcher checks only the configured chat and does not disclose credentials | Agent 端、安装与配对 | ✅ 通过 | 291 ms |

**`agent/test/learned-route.test.mjs`** — 4 场景（通过 4，失败 0，超时 0，合计 2.5 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| A taught route runs from the poki entry with no model access | Agent 端 | ✅ 通过 | 704 ms |
| A taught route returns to its start page when the phone was left on another page | Agent 端 | ✅ 通过 | 633 ms |
| A taught route that cannot reach its start fails at once when no model is available | Agent 端 | ✅ 通过 | 559 ms |
| A route a model run taught opens Settings once and lets each next look confirm its actions | Agent 端 | ✅ 通过 | 595 ms |

**`agent/test/messages.test.mjs`** — 1 场景（通过 1，失败 0，超时 0，合计 62 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| BlueBubbles limits reads and replies to one sender, skips history and resumes consumed IDs | Agent 端 | ✅ 通过 | 62 ms |

**`agent/test/openai.test.mjs`** — 6 场景（通过 6，失败 0，超时 0，合计 506 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| OpenAI protocol: default | Agent 端、稳定性与容错 | ✅ 通过 | 399 ms |
| OpenAI protocol: rejected | Agent 端 | ✅ 通过 | 31 ms |
| OpenAI protocol: downgraded | Agent 端 | ✅ 通过 | 21 ms |
| OpenAI protocol: auth-error | Agent 端 | ✅ 通过 | 23 ms |
| OpenAI protocol: fast-defaults | Agent 端、稳定性与容错 | ✅ 通过 | 14 ms |
| OpenAI protocol: chat-completions | Agent 端 | ✅ 通过 | 20 ms |

**`agent/test/opening.test.mjs`** — 1 场景（通过 0，失败 0，超时 1，合计 —）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| （整个文件超时，未返回场景结果） — no result after 240 s | Agent 端 | ⏱️ 超时 | — |

**`agent/test/poki-cli.test.mjs`** — 6 场景（通过 6，失败 0，超时 0，合计 9.1 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| public commands report help and reject API secrets without echoing them | Agent 端 | ✅ 通过 | 2.4 s |
| login reuses SDK credentials and API key stays in the environment | Agent 端、诊断与证据 | ✅ 通过 | 1.1 s |
| task forwarding preserves the real CLI result and model request count | Agent 端 | ✅ 通过 | 1.8 s |
| device discovery lists ambiguous phones and status reports service failure | Agent 端 | ✅ 通过 | 2.3 s |
| fresh OAuth login persists through the SDK and hides provider failures | Agent 端、诊断与证据 | ✅ 通过 | 720 ms |
| channel commands reach existing read checks without sending messages | Agent 端 | ✅ 通过 | 724 ms |

**`agent/test/post-action-observation.test.mjs`** — 6 场景（通过 6，失败 0，超时 0，合计 3 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| reuses only a bound, fresh, full post-action observation | 观察 | ✅ 通过 | 2 ms |
| a PID-only foreground must match the verified launch of the expected app | 观察 | ✅ 通过 | 0 ms |
| rejects uncertain input, missing identity and observations captured before the action | 观察、诊断与证据 | ✅ 通过 | 1 ms |
| rejects incomplete refs, prompt warnings, inaccessible sources and stale data | 观察、稳定性与容错 | ✅ 通过 | 0 ms |
| accepts optional screenshot only AFTER stable AX and rejects reversed order | 观察 | ✅ 通过 | 0 ms |
| model-facing action receipts exclude nested AX while retaining actual receipt fields | 观察 | ✅ 通过 | 0 ms |

**`agent/test/readout.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 2 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| A learned fixed field reads the new value and refuses missing or ambiguous fields | Agent 端、诊断与证据 | ✅ 通过 | 2 ms |
| A learned list never reads a hidden row, whether its visible flag is false or 0 | Agent 端、诊断与证据 | ✅ 通过 | 0 ms |

**`agent/test/route-answer.test.mjs`** — 1 场景（通过 1，失败 0，超时 0，合计 367 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| Route answers use changed current activity names and times and reject unknown references | Agent 端、操作、稳定性与容错 | ✅ 通过 | 367 ms |

**`agent/test/routes.test.mjs`** — 12 场景（通过 12，失败 0，超时 0，合计 67 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| A repeated city label preserves the verified header when learning and reading a route | Agent 端 | ✅ 通过 | 22 ms |
| Learned route search must not disguise filesystem failures as cache corruption | Agent 端 | ✅ 通过 | 1 ms |
| An oversized matching task never mislabels a healthy route as a broken cache file | Agent 端 | ✅ 通过 | 3 ms |
| A disabled or hidden control is never a tap candidate, whether its flag is false or 0 | Agent 端 | ✅ 通过 | 0 ms |
| A demonstrated Settings route replays from the top of Settings after the free space changed | Agent 端、稳定性与容错、诊断与证据 | ✅ 通过 | 5 ms |
| A demonstrated Settings route replays from the top of Settings after the free space changed > iOS version, first run | Agent 端、稳定性与容错、诊断与证据 | ✅ 通过 | 3 ms |
| A demonstrated Settings route replays from the top of Settings after the free space changed > iOS version, second run | Agent 端、稳定性与容错、诊断与证据 | ✅ 通过 | 2 ms |
| A demonstrated Settings route replays from the top of Settings after the free space changed > trust store version | Agent 端、稳定性与容错、诊断与证据 | ✅ 通过 | 9 ms |
| A model run whose first batch missed a tap still teaches a route that replays from the top of Settings | Agent 端、诊断与证据 | ✅ 通过 | 14 ms |
| A model run whose first batch missed a tap still teaches a route that replays from the top of Settings > a stale tap that changed nothing | Agent 端、稳定性与容错、诊断与证据 | ✅ 通过 | 3 ms |
| A model run whose first batch missed a tap still teaches a route that replays from the top of Settings > a failed scroll that still moved the page | Agent 端、诊断与证据 | ✅ 通过 | 0 ms |
| A failed step is dropped only when the screen after it is the screen it failed on | Agent 端 | ✅ 通过 | 4 ms |

**`agent/test/self-chat.test.mjs`** — 2 场景（通过 2，失败 0，超时 0，合计 1.1 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| An idle self-chat supervisor exits on SIGTERM without calling device cleanup | Agent 端 | ✅ 通过 | 1.0 s |
| Self-chat refuses readiness when the physical device executable is missing | Agent 端 | ✅ 通过 | 132 ms |

**`agent/test/steer.test.mjs`** — 3 场景（通过 0，失败 3，超时 0，合计 30.1 s）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| A message sent during a task reaches result verification of the stopped task | Agent 端 | ❌ 失败 | 60 ms |
| A message sent during a task is acknowledged with how to stop it | Agent 端 | ❌ 失败 | 2 ms |
| A stop request takes effect while the reply to an earlier mid-task message is still sending | Agent 端 | ❌ 失败 | 30.0 s |

**`agent/test/step-timeout-cli.test.mjs`** — 1 场景（通过 0，失败 0，超时 1，合计 —）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| （整个文件超时，未返回场景结果） — no result after 240 s | Agent 端、稳定性与容错 | ⏱️ 超时 | — |

**`agent/test/step-timeout.test.mjs`** — 3 场景（通过 3，失败 0，超时 0，合计 2 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| Same-page attempts expire; progressing steps and pages can run beyond 60 seconds | Agent 端、稳定性与容错 | ✅ 通过 | 2 ms |
| Scrolling or swiping new text into view cannot renew the same page deadline | Agent 端、稳定性与容错 | ✅ 通过 | 0 ms |
| Chrome screens without headings renew only after successful navigation, not same-page attempts | Agent 端、稳定性与容错 | ✅ 通过 | 1 ms |

**`agent/test/telegram.test.mjs`** — 3 场景（通过 3，失败 0，超时 0，合计 65 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| Telegram authorizes private users before dispatch and preserves acknowledged offsets across restart | Agent 端、稳定性与容错 | ✅ 通过 | 33 ms |
| Telegram preserves long text, retries only the failed chunk and edits per-task progress | Agent 端 | ✅ 通过 | 23 ms |
| Telegram uploads at most one photo per reply and only resends text on a rejection | Agent 端 | ✅ 通过 | 10 ms |

**`agent/test/tool-timeout.test.mjs`** — 1 场景（通过 1，失败 0，超时 0，合计 13 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| Phone calls finish within 130 seconds or cancel the pending MCP request | 稳定性与容错、Agent 端 | ✅ 通过 | 13 ms |

**`agent/test/unlock-device.test.mjs`** — 1 场景（通过 1，失败 0，超时 0，合计 354 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| Unlock host sends the configured passcode only on stdin and hides helper errors | 安全与审批、安装与配对 | ✅ 通过 | 354 ms |

**`agent/test/verification-trace.test.mjs`** — 2 场景（通过 0，失败 2，超时 0，合计 13 ms）

| 场景 | 能力 | 结果 | 耗时 |
| --- | --- | --- | ---: |
| A batch that fails partway gives the verifier each step it ran, the failure and the final screen | 观察、诊断与证据 | ❌ 失败 | 10 ms |
| A visual answer carries the hybrid screenshot to verification without learning a text route | 观察、诊断与证据 | ❌ 失败 | 3 ms |

## 7. 动作效率对照场景

- 入口：`POKI_EVAL_GROUP=all node --test test/suite/action-efficiency.test.mjs`
- 场景：6（通过 6，失败 0，超时 0，未跑 0），墙钟 27.4 s
- 单场景耗时：中位 3.1 s，P95 6.1 s，最长 6.1 s

| 场景 | 位置 | 能力 | 结果 | 说明 |
| --- | --- | --- | --- | --- |
| reference（计数器：点一次恰好 +1） | `test/suite/action-efficiency.test.mjs` | 操作、效率与资源 | ✅ 通过 | before 1453 ms / 2 calls；after 417 ms / 2 calls |
| navigation（切页：详情就绪后返回列表） | `test/suite/action-efficiency.test.mjs` | 操作、批量与等待、效率与资源 | ✅ 通过 | before 2313 ms / 4 calls；after 731 ms / 4 calls |
| recovery（回执丢失：从当前计数继续） | `test/suite/action-efficiency.test.mjs` | 稳定性与容错、批量与等待、效率与资源 | ✅ 通过 | before 2297 ms / 7 calls；after 790 ms / 7 calls |
| interruption（滚动中弹窗：关掉后只点指定行） | `test/suite/action-efficiency.test.mjs` | 操作、稳定性与容错、效率与资源 | ✅ 通过 | before 3184 ms / 4 calls；after 2387 ms / 4 calls |
| focus（延迟焦点：保存一次且保留相邻字段） | `test/suite/action-efficiency.test.mjs` | 操作、观察、效率与资源 | ✅ 通过 | before 3978 ms / 5 calls；after 2075 ms / 5 calls |
| canvas（Canvas OCR：按文字定位后点击） | `test/suite/action-efficiency.test.mjs` | 观察、操作、效率与资源 | ✅ 通过 | before 2512 ms / 2 calls；after 2514 ms / 2 calls |

## 8. 动作效率场景·变体（扰动）

- 入口：`POKI_EVAL_SCENARIO=interruption,canvas POKI_EVAL_VARIANT=1 node --test test/suite/action-efficiency.test.mjs`
- 场景：2（通过 2，失败 0，超时 0，未跑 0），墙钟 11.8 s
- 单场景耗时：中位 5.0 s，P95 5.8 s，最长 5.8 s

| 场景 | 位置 | 能力 | 结果 | 说明 |
| --- | --- | --- | --- | --- |
| interruption（滚动中弹窗：关掉后只点指定行） | `test/suite/action-efficiency.test.mjs` | 操作、稳定性与容错、效率与资源 | ✅ 通过 | before 3275 ms / 4 calls；after 2553 ms / 4 calls |
| canvas（Canvas OCR：按文字定位后点击） | `test/suite/action-efficiency.test.mjs` | 观察、操作、效率与资源 | ✅ 通过 | before 2493 ms / 2 calls；after 2509 ms / 2 calls |

## 9. Poki Gym 模拟器场景

- 入口：`.github/workflows/ios-gym.yml（scorecard / scorecard-inprocess）`
- 场景：36（通过 0，失败 0，超时 0，未跑 36），墙钟 —

| 场景 | 位置 | 能力 | 结果 | 说明 |
| --- | --- | --- | --- | --- |
| gym:animation — A view that never idles, and a Next button | `native/ios-gym/Gym/GymApp.swift` | 观察、操作、稳定性与容错 | ⚪ 未运行 | 需 Xcode 构建 Poki Gym 并在模拟器上运行 scorecard |
| gym:alert — A system alert with Cancel and OK | `native/ios-gym/Gym/GymApp.swift` | 观察、操作 | ⚪ 未运行 | 需 Xcode 构建 Poki Gym 并在模拟器上运行 scorecard |
| gym:paste — An empty text field for the paste prompt | `native/ios-gym/Gym/GymApp.swift` | 操作 | ⚪ 未运行 | 需 Xcode 构建 Poki Gym 并在模拟器上运行 scorecard |
| gym:list — 300 rows; Row 250 sets the state | `native/ios-gym/Gym/GymApp.swift` | 操作、观察 | ⚪ 未运行 | 需 Xcode 构建 Poki Gym 并在模拟器上运行 scorecard |
| gym:sheet — A half sheet with a Done button | `native/ios-gym/Gym/GymApp.swift` | 操作 | ⚪ 未运行 | 需 Xcode 构建 Poki Gym 并在模拟器上运行 scorecard |
| gym:focus — A field that takes focus 1.5 s after Start | `native/ios-gym/Gym/GymApp.swift` | 操作、观察 | ⚪ 未运行 | 需 Xcode 构建 Poki Gym 并在模拟器上运行 scorecard |
| gym:dense — 1,500 small elements, a slow tree | `native/ios-gym/Gym/GymApp.swift` | 观察、效率与资源 | ⚪ 未运行 | 需 Xcode 构建 Poki Gym 并在模拟器上运行 scorecard |
| gym:dup — Two elements with one label and frame over a Twin button | `native/ios-gym/Gym/GymApp.swift` | 观察、操作 | ⚪ 未运行 | 需 Xcode 构建 Poki Gym 并在模拟器上运行 scorecard |
| gym:fullscreen — A web view filling the screen with one link | `native/ios-gym/Gym/GymApp.swift` | 观察、操作 | ⚪ 未运行 | 需 Xcode 构建 Poki Gym 并在模拟器上运行 scorecard |
| gym:nav — Push a page with a system back button | `native/ios-gym/Gym/GymApp.swift` | 操作 | ⚪ 未运行 | 需 Xcode 构建 Poki Gym 并在模拟器上运行 scorecard |
| gym:interrupt — 300 rows; an alert pops up 2 s after the screen opens | `native/ios-gym/Gym/GymApp.swift` | 稳定性与容错、操作 | ⚪ 未运行 | 需 Xcode 构建 Poki Gym 并在模拟器上运行 scorecard |
| gym:approval — A button that needs the owner's approval before it is tapped | `native/ios-gym/Gym/GymApp.swift` | 安全与审批、操作 | ⚪ 未运行 | 需 Xcode 构建 Poki Gym 并在模拟器上运行 scorecard |
| scorecard 1. Animation that never idles: the tree must still come, and the Next button must work, in time. | `native/ios-gym/check/GymScorecard.swift:284` | 观察、操作 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 2. A system alert on top of the screen. | `native/ios-gym/check/GymScorecard.swift:298` | 操作、观察 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 3. Typing into an empty field (direct typing; the paste prompt never comes up). | `native/ios-gym/check/GymScorecard.swift:305` | 操作 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 4. A long list: scroll_to by text, then tap. | `native/ios-gym/check/GymScorecard.swift:330` | 操作、观察 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 5. A half sheet. | `native/ios-gym/check/GymScorecard.swift:347` | 操作、观察 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 6. Focus that arrives late: type with no target once the field has focus. | `native/ios-gym/check/GymScorecard.swift:353` | 操作、观察 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 7. A dense tree: 3,000 elements. Reads must stay in budget and the button must be reachable. | `native/ios-gym/check/GymScorecard.swift:360` | 观察、操作 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 8. Two decoys with the button's label and frame: the real button must still be tapped. | `native/ios-gym/check/GymScorecard.swift:378` | 操作、观察 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 9. A web view filling the screen with one link. | `native/ios-gym/check/GymScorecard.swift:382` | 操作、观察 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 10. A navigation push and the system back button. | `native/ios-gym/check/GymScorecard.swift:398` | 操作、观察 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 11. An alert that pops up in the middle of a scroll: scroll_to must answer, the alert must be dismissable, and the scroll must go on afterwards. | `native/ios-gym/check/GymScorecard.swift:408` | 操作、观察 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 12. The app relaunches while a wait_until runs (a crash, or a process killed under memory pressure): the wait must answer, and the next read must be a tree read of the new process. (Needs simctl from outside: the runner path's host only.) | `native/ios-gym/check/GymScorecard.swift:422` | 稳定性与容错 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 13. Settings: search with mixed Latin and CJK text, then the field cleared and searched again. | `native/ios-gym/check/GymScorecard.swift:447` | 操作、观察 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 14. Notes: a new note, typing, a clear and a second type. The CI simulator runtime has no Notes; then Contacts, with a new contact's First name field, stands in (the same typing path). | `native/ios-gym/check/GymScorecard.swift:508` | 操作、观察 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 15. Safari: a page with links, scroll_to on page text, a link tapped. | `native/ios-gym/check/GymScorecard.swift:556` | 操作、观察 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 16. Photos: a grid cell tapped, then back to the grid. | `native/ios-gym/check/GymScorecard.swift:609` | 操作、观察 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 17. A payment button: do holds the tap for the owner's answer and says so when they decline; once they allow it (here the host answers after a few seconds, as the owner would on the Live Activity) the tap is sent in the same call. (The menu row says "approval", not "pay": a row whose label named the payment would itself ask.) | `native/ios-gym/check/GymScorecard.swift:653` | 安全与审批、操作 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 18. finish: true on the last do: the phone goes back to the app the task began in. A task begins with its first call after the last finish, so the origin is whatever is in front then: the gym (launched from outside on the runner path) or the home screen the earlier finish left. | `native/ios-gym/check/GymScorecard.swift:674` | 操作、观察 | ⚪ 未运行 | 需模拟器 + WebDriverAgent（runner 路径）或应用内进程（in-process 路径） |
| scorecard 故障注入：keyboard intro | `native/ios-gym/check/GymScorecard.swift` | 稳定性与容错 | ⚪ 未运行 | 需模拟器；faults 只在 runner 路径运行 |
| scorecard 故障注入：relaunch in wait_until | `native/ios-gym/check/GymScorecard.swift` | 稳定性与容错 | ⚪ 未运行 | 需模拟器；faults 只在 runner 路径运行 |
| scorecard 故障注入：routine | `native/ios-gym/check/GymScorecard.swift` | 稳定性与容错 | ⚪ 未运行 | 需模拟器；faults 只在 runner 路径运行 |
| scorecard 故障注入：finish | `native/ios-gym/check/GymScorecard.swift` | 稳定性与容错 | ⚪ 未运行 | 需模拟器；faults 只在 runner 路径运行 |
| scorecard 故障注入：busy runner | `native/ios-gym/check/GymScorecard.swift` | 稳定性与容错 | ⚪ 未运行 | 需模拟器；faults 只在 runner 路径运行 |
| scorecard 故障注入：runner killed | `native/ios-gym/check/GymScorecard.swift` | 稳定性与容错 | ⚪ 未运行 | 需模拟器；faults 只在 runner 路径运行 |

## 10. Swift 测试（PokiCore / Poki 应用）

- 入口：`xcodebuild test（PokiCoreTests / PokiTests）`
- 场景：267（通过 0，失败 0，超时 0，未跑 267），墙钟 —

**`native/ios/PokiCore/Tests/PokiCoreTests/CoreTests.swift`** — 67 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testBase32` | 8 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testJSONRoundTrip` | 13 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testDeadlineDoesNotWaitForAnOperationThatIgnoresCancellation` | 18 | 会话与传输、观察、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testSensitiveWordsMatchWholeWords` | 29 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheBuiltInConnectionSendsTheOwnerBackToPokiNotToAProxyApp` | 38 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAProxyAppKeepsItsOwnInstructions` | 47 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testLookListsElementsWithAPicture` | 58 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAStuckTreeStillAnswersInTimeWithThePicture` | 67 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testANothingRunnerAnswersFastAndAsksForARestart` | 77 | 会话与传输、观察、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testACallWaitsForARunnerThatIsStartingThenGoesOn` | 97 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testARunnerThatNeverStartsIsAnsweredWithinTheCap` | 108 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTapByNumberHitsTheCentre` | 118 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAStaleNumberSendsNothing` | 127 | 会话与传输、观察、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAStuckTapIsReportedAsMaybeDeliveredAndNothingAfterItIsSent` | 136 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTypingClearsWithDeletesInOneRequest` | 148 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheSecondCallIsBusyInsteadOfQueued` | 156 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testADeletionWaitsForTheOwnerAndSendsNothing` | 174 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheInAppChatPathWaitsForTheOwnerToo` | 196 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testApprovalDuringTheWaitRunsTheActionsInTheSameCall` | 206 | 会话与传输、观察、安全与审批 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheDefaultWaitOutlastsAHumanApprovalAndEndsWithTheRequest` | 220 | 会话与传输、观察、安全与审批、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheApprovalWaitEndsBeforeTheRelayGivesUp` | 254 | 会话与传输、观察、安全与审批 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnApprovalTooLateForTheRelayIsKeptForTheNextCallInsteadOfRunning` | 274 | 会话与传输、观察、安全与审批 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnApprovalWithTimeToSpareRunsInTheSameCallBehindARelay` | 293 | 会话与传输、观察、安全与审批 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testACancelledCallDoesNotRunWhenTheOwnerApprovesLater` | 308 | 会话与传输、观察、安全与审批、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testDeclinedSendsNothing` | 322 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testOtherActionsWithdrawThePendingRequestSoTheAutomationCannotApproveIt` | 337 | 会话与传输、观察、安全与审批 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTappingAContactInPhonePlacesNoCallWithoutTheOwner` | 349 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAVoiceTapOnSendInMessagesWaitsForTheOwner` | 362 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAVoiceTapInPokiCannotApproveThePendingRequest` | 384 | 会话与传输、观察、安全与审批 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnotherVoiceTapWithdrawsThePendingRequest` | 401 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAVoiceTapWithNoReadableTextAsksTheOwner` | 418 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testDoAsksForAButtonOnlyItsIdentifierCallsSend` | 428 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testDoTapsNothingInPoki` | 442 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnUnansweredRequestEndsByItselfWhenItsTimeIsUp` | 456 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testInWalletWaitingAndLeavingNeedNoApprovalButATapDoes` | 475 | 会话与传输、观察、安全与审批 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testInWalletTheAgentCanHandTheScreenToTheOwnerWithoutApproval` | 488 | 会话与传输、观察、安全与审批 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATapOnNothingReadableInPhoneAsks` | 498 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testActionsAfterALaunchAreCheckedAgainstTheLaunchedApp` | 511 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testARoutineRunInWalletAsksBeforeItsPointTap` | 532 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testARoutinesPointTapInPhoneIsNotSentWithoutTheOwner` | 546 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAPointAfterATapReturnsAFreshScreenBeforeChoosingWhetherToAsk` | 566 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testInAMessagingAppReturnAfterTypingAsks` | 593 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testARoutinesTypedReturnInAMessagingAppIsNotSentWithoutTheOwner` | 620 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATapAfterALaunchAsksInAnAppOnNoList` | 638 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testPasswordsNeedApproval` | 647 | 会话与传输、观察、安全与审批 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testInitializeListAndCall` | 665 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testInitializeWarmsTheHostUp` | 681 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testSessionsAreReportedAndHostToolsListedAndCalled` | 689 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testToolEventsCarryTheCallersSession` | 722 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testGetIsNotAllowed` | 733 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testHandshakeRequestsAndKeepalive` | 741 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheRelayAddressThePersonEntersDecidesWhereThePhoneDials` | 777 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnAnswerReadyAfterTheConnectionDroppedComesWithTheNextCall` | 795 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheRelayIsDialedAgainAfterADrop` | 831 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAFinishedCallCarriesTheAppAndAThumbnail` | 844 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheSummariesTheAppLogsKeepNoTypedText` | 857 | 会话与传输、观察、诊断与证据 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testDownloadsIntoPlaceAndKeepsAVerifiedCopy` | 882 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testFinishGoesBackToTheAppTheTaskBeganIn` | 921 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testALaunchThatFinishesReadsTheLaunchedAppBeforeGoingBack` | 939 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testFinishWhereTheTaskBeganSendsNothing` | 964 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testFinishSaysSoWhenTheAppDoesNotComeToTheFront` | 976 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheClientEndingItsSessionEndsTheTask` | 988 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testFinishingFromTheAppGoesBackOnce` | 1006 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATaskDroppedWithoutSwitchingSendsNothingLater` | 1020 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testACallAfterTheTaskGapStartsANewTask` | 1034 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnAppWhoseTreeCannotBeReadIsStillTheAppInFront` | 1050 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnAppOpenedWithoutAnAccessibilityServerIsOpenedAgainFreshAndRead` | 1083 | 会话与传输、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios/PokiCore/Tests/PokiCoreTests/FaultTests.swift`** — 95 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testMixedScriptTextIsTypedDirectlyAndReadBackExactly` | 58 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAFailedStepLogsItsErrorLineWithoutTheTypedText` | 83 | 稳定性与容错、诊断与证据 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATypeThatLandedButAnsweredWithAFailureCountsAsTyped` | 99 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATypeThatDidNotLandIsSentAgainOnce` | 112 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAFailingTypeIsSentAgainOnlyOnce` | 124 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAHalfTypedFieldIsNotTypedIntoAgain` | 135 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnEmptySearchFieldShowingItsPlaceholderIsTypedIntoAgain` | 173 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnEmptyFieldThatReadsNullIsTypedIntoAgain` | 186 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAFailingTypeInAPlaceholderFieldIsNeverCalledHalfTyped` | 199 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheLogNamesAHalfTypedFieldButNeverItsContent` | 212 | 稳定性与容错、诊断与证据 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheLogNeverHoldsTheOwnersOwnTextFromTheField` | 225 | 稳定性与容错、诊断与证据 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATextThatEqualsThePlaceholderIsNotTypedTwice` | 239 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAPlaceholderThatStartsTheTextDoesNotMakeAHalfTypedFieldEmpty` | 252 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAPlaceholderThatContainsTheTextDoesNotCountAsTypedText` | 265 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAFieldWhosePlaceholderCannotBeReadIsNotTypedIntoAgainAndSaysSo` | 278 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testPasteIsTheBackupAndPutsTheOwnersClipboardBack` | 291 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnUnreadableClipboardIsNeverOverwritten` | 303 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAMissingPasteMenuStillRestoresTheClipboard` | 315 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testClearingWithNothingFocusedKeepsTheSession` | 325 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testWaitUntilSettledAsAWordWaitsForAStillScreen` | 335 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testALockedPhoneTakesNoInputAndLookSaysSo` | 342 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testARunnerRestartedMidCallGetsANewSessionAndTheTapGoesThrough` | 354 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testARunnerThatDiesMidDoStopsAndSaysWhatWasSent` | 368 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnAppSwitchMidGestureIsReportedAndTheReadStillComes` | 384 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAHugeTreeIsReadInTimeAndTheListIsCapped` | 397 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testASlowRunnerNeverHoldsACallPastItsDeadline` | 408 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAHangingSessionCreationDoesNotOutliveTheToolDeadline` | 419 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testConcurrentReadsOpenOneSession` | 429 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testABusyRunnerIsNotRestartedWhileItStillAnswersStatus` | 439 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAWedgedRunnerThatAnswersNothingIsRestartedAfterTheProbe` | 457 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testHomeIsPressedOutsideTheSession` | 469 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testWithoutATreeTheTextInThePictureIsListedAndTappable` | 479 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testWithoutATreeAnEmptyPictureReadIsSaidSo` | 497 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAReadThatTimesOutKeepsTheSessionAndTheNextActionIsAnsweredBusyNotRunLate` | 517 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testGivingUpOnAnActionEndsTheSession` | 542 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheXMLTreeReadsLikeTheJSONOne` | 555 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testLaunchActivatesARunningAppAndGetsItsOwnTime` | 589 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheSafePartOfABatchGoesBeforeApprovalIsAsked` | 606 | 稳定性与容错、安全与审批 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testWaitUntilSettledWorksWhenEachReadIsSlow` | 627 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testALookNeverWaitsOnASessionOpenForTheSnapshotLimits` | 640 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testACutListingSaysWhatWasLeftOutAndScrollToGivesTheNumber` | 659 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testScrollToDeclaresTheEndOnlyAfterTwoConfirmedUnmovedSwipes` | 681 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheNumbersStandWhenNothingNewerWasRead` | 693 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testWaitUntilSettledTakesTheFreshReadBeforeItAndNeverEndsUnknown` | 711 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheRunnersStartIsNotTheActionsTime` | 734 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testEachActionHasItsOwnTime` | 745 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testANameInALongerLabelIsNotAPayment` | 756 | 稳定性与容错、安全与审批 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheDynamicIslandIsNeverListed` | 773 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATapThatOpensPokiBringsTheAppBack` | 790 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testPasteKeepsTheTextOnTheClipboardUntilItLandsAndChecksItFirst` | 822 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testPasteIsRefusedWhenTheClipboardCannotBeSet` | 838 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testThePictureIsTakenAgainWhenTheTreeCameLater` | 851 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheHomeScreenIsNamedAndANewScreenSaysItsNumbersStartAgain` | 859 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATapOnAnElementThatFillsTheScreenSaysSo` | 869 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAFailedActionWithAReadIsNotAnErrorAnswer` | 881 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testABusyRunnerAnswersWithThePicture` | 892 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTypingWaitsForAFieldToBeFocusedAndSaysWhenNoneWas` | 905 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testClearIsCheckedAndDoneAgainWhenSomethingIsLeft` | 928 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testBackTapsTheTopLeftButtonOrSwipesFromTheEdge` | 945 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheSameElementTwiceIsListedOnce` | 960 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testARefusedTreeIsAskedForAgainWithinTheRead` | 970 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAHandoffHoldsInputsUntilTheOwnerIsDone` | 989 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAStartingRunnerIsNotAnErrorAnswer` | 1029 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testABusyGateAnswersWithThePicture` | 1038 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATapOnAContainerNamesTheElementsInsideIt` | 1051 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAWedgedRunnerIsRestartedAndTheNextCallSaysWhy` | 1064 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAStallDoesNotOutliveTheRunner` | 1097 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAScrollThatOutrunsTheActionsTimeSaysHowFarItGot` | 1121 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheHostsOwnScreenshotIsUsedWhenTheRunnerGivesNone` | 1141 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATimedOutTreeIsReadAgainShallowerWithinTheCall` | 1155 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAWebViewWithNothingInTheTreeIsListedWithThePicturesText` | 1179 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testScrollToHasTwelveSecondsAndReadsAfterEverySwipe` | 1195 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testScrollToNeverEndsUnknownWhenTheRunnerFallsBehind` | 1216 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testScrollToReadsAnUnreadSwipeBeforeItSwipesAgain` | 1245 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testScrollToDragsBackWhenTheListMovedMoreThanAScreen` | 1287 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAFocusNoteIsDroppedWhenTheTextReadBack` | 1318 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheReadAfterATypeNamesTheReplacedField` | 1331 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnElementCutByTheScreenIsTappedAtTheCentreOfItsVisiblePart` | 1348 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheMCPAccountsForTheTimeAroundTheTool` | 1361 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATypeOfABareHostIntoSafarisAddressFieldSaysToAddTheScheme` | 1375 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testScrollToStartsAboveTheBottomChromeAndStopsWhenASwipeChangedTheScreen` | 1390 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testScrollToSaysHowFarEachSwipeMovedTheList` | 1419 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testStillChromeInsideTheListAreaDoesNotHideAnOvershoot` | 1442 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testALookAtAnAlertAloneSaysTheScreenBehindItIsNotListed` | 1468 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnElementCoveringTheScreenAloneSaysItsPartsAreNotInTheTree` | 1480 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testBackOnASheetSaysWhatDismissesIt` | 1490 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testALaunchOfAnAppThatIsNotInstalledIsOneLine` | 1501 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheReadAfterALaunchIsMadeAgainUntilTheLaunchedAppIsInFront` | 1515 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testWaitUntilGetsTheTimeItAsksForAndALongCallAccountsForItsTime` | 1535 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testThePictureOfTheReadBeforeStandsInWhenNoneComes` | 1547 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testALaunchUnderASystemAlertNamesTheAlert` | 1562 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAScrollUnderAnAlertNamesIt` | 1576 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testReturnIsTheKeyboardsOwnKeyWhenOneIsUp` | 1587 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTypingWaitsAsLongAsTheActionAllowsForABusyRunner` | 1604 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTypingWaitsForABusyRunnerAndSendsNothingWhenItIsNotThrough` | 1623 | 稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios/PokiCore/Tests/PokiCoreTests/HumanizeTests.swift`** — 21 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testASeededPlanRepeatsAndTwoSeedsDiffer` | 15 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATapPressesForAPersonsTimeAndStaysInsideTheElement` | 23 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATapOnAPointChosenOffTheCentreStaysWithinAPointOfIt` | 43 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAFlickLiftsAtSpeedAndARestingDragComesToAStop` | 54 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testADragCurvesSlightlyAndIsSampledUnevenly` | 78 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testOffGivesTheExactLegacySchedule` | 90 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTypingGoesInWordBurstsAtAQuickTypistsPace` | 100 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testLongTextTypesFasterAndCJKIsCutIntoShortBursts` | 114 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheW3CBodyCarriesEverySampleAsATimedStep` | 127 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAShapedTapGoesThroughActionsInsideTheElementAndAnOlderRunnerGetsWDAsTap` | 140 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAShapedSwipeIsAManySampleFlickAndADragComesToRest` | 164 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testARunnerWithoutActionsGetsThePressDrag` | 189 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testScrollToKeepsItsSlowTailVariedALittle` | 201 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testALongPressHoldsExactlyAsAskedAndThePasteMenuOpensWithOne` | 218 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testShapedTypingGoesInBurstsWithAPaceAndReadsBackWhole` | 229 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testClearDeletesInOneBurstThenTypesInBursts` | 244 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTypingWithNoTimeForBurstsGoesInOneCall` | 259 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testALongTextIsAtMostFourKeyCalls` | 271 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testASlowRunnerGetsTheRestOfTheTextInOneCall` | 284 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testThePinchIsTwoShapedFingers` | 297 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testOffSendsTheLegacyEndpointsExactly` | 311 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios/PokiCore/Tests/PokiCoreTests/LookDoTests.swift`** — 23 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testTheSessionTurnsOffWDAsWaitsAfterEveryGesture` | 20 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnElementUnderTheReplyBarIsTappedAnywayAndTheAnswerSaysWhatLiesOverIt` | 31 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testWhatScrollsInsideAListDoesNotCoverAButtonOutsideIt` | 46 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAPartlyCoveredElementIsTappedOnItsVisiblePart` | 62 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAPointOffTheScreenIsNotHittable` | 73 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testASwipeStartsInsideTheListClearOfTheReplyBarAsAQuickFlick` | 81 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testADragStopsBeforeLiftingAndUsesItsOwnSpeed` | 97 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnOlderRunnerFallsBackToItsDrag` | 108 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testASlowGestureIsNotTakenAsTheRunnerBeingGone` | 117 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testScreenChangedSaysWhenAnActionDidNothing` | 130 | 操作、观察、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testNumbersStayAndDoListsOnlyWhatChanged` | 144 | 操作、观察、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testRepeatsScrollBarsAndHoldersAreLeftOut` | 165 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testACollapsedCellGetsTheTextReadFromThePictureOnAFullRead` | 190 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheScreenshotIsOnePixelPerScreenPoint` | 208 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testWaitUntilReadsUntilTheTextAppears` | 215 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAWaitSaysHowLongItWaitedOnce` | 229 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testScrollToBringsATargetOutFromUnderTheBar` | 238 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAControlInsideABarOrAnInputBarListedApartFromItIsHittable` | 254 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheActionsGetTheirFullTimeAfterTheOwnerApproves` | 273 | 操作、观察、安全与审批 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testRowsListedBesideTheListDoNotShrinkTheSwipe` | 288 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheToolDescriptionsPointToScrollTo` | 300 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAFadingScrollIndicatorIsNotAChangeButASheetIs` | 332 | 操作、观察、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testVisionReadsTextWithTopLeftBoxes` | 359 | 操作、观察 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios/PokiCore/Tests/PokiCoreTests/ReconnectTests.swift`** — 4 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testTriesBackOffAndStopAtTheCap` | 7 | 会话与传输、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testNothingIsTriedAfterTheOwnerEndedItUntilTheyStartItAgain` | 13 | 会话与传输、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAConnectionThatHeldStartsTheCountOverButOneThatDroppedAtOnceDoesNot` | 24 | 会话与传输、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testATunnelInterfaceMeansAnotherVPNIsOn` | 35 | 会话与传输、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios/PokiCore/Tests/PokiCoreTests/RelaySoakTests.swift`** — 1 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testAnswersStayOnTheirConnectionOnceAndNeverAfterACancel` | 22 | 会话与传输、稳定性与容错、效率与资源 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios/PokiCore/Tests/PokiCoreTests/RoutineTests.swift`** — 11 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testATaskIsSavedAsARoutineByWhatItTapped` | 54 | Agent 端、会话与传输 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testARunRepeatsTheRoutineInOneCallAndReadsTheValue` | 66 | Agent 端、会话与传输 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testARunStopsWhereTheScreenDiffersAndSendsNothingMore` | 81 | Agent 端、会话与传输 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTwoLikeTargetsFarFromTheRecordedOneAreNotGuessedBetween` | 98 | Agent 端、会话与传输、诊断与证据 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheBriefStaysShortWhenTheMemoryIsFull` | 112 | Agent 端、会话与传输、效率与资源 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAStaleRoutineIsNotOfferedAndASaveOverItStartsItsRecordAgain` | 131 | Agent 端、会话与传输、稳定性与容错、诊断与证据 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheFirstLookOfATaskNamesTheRoutinesAndFinishOffersToSave` | 142 | Agent 端、会话与传输 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTypedTextBecomesAParameterAndAPasswordIsNeverKept` | 154 | Agent 端、会话与传输 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testNotesExportAndImportMoveTheMemoryBetweenPhones` | 173 | Agent 端、会话与传输、效率与资源 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheBackupCopyIsWrittenAndARestoredOneIsMergedIn` | 194 | Agent 端、会话与传输 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheToolIsListedAndAnswersWithoutTheRunner` | 211 | Agent 端、会话与传输 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios/PokiCore/Tests/PokiCoreTests/SoakTests.swift`** — 1 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testNoCallOutlivesItsDeadlineAgainstAMisbehavingRunner` | 90 | 稳定性与容错、效率与资源 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios/PokiLoopback/Tests/PokiLoopbackTests/LoopbackTests.swift`** — 4 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testTCPConversationIsReflectedWithoutChangingPortsPayloadOrChecksums` | 7 | 会话与传输、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testPacketsOutsideTheLocalTCPRouteAndMalformedPacketsAreDropped` | 22 | 会话与传输、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTunnelRoutesOnlyTheDeveloperAddressWithoutDNSOrIPv6` | 49 | 会话与传输、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testOnlyAnEndByTheOwnerOrAnotherVPNLeavesTheTunnelDown` | 69 | 会话与传输、稳定性与容错 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios-app/PokiTests/AppModelTests.swift`** — 15 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testRunningLauncherWaitsForTheInProcessSession` | 61 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testLoopbackDownIsNamedToTheAgent` | 73 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTunnelOnButNotReflectedSaysSo` | 88 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTunnelWithoutAnswerPutsDeveloperModeLast` | 98 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testLoopbackUpKeepsTheLauncherState` | 109 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testPairingRefusalThenAcceptance` | 116 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testHostSeesTheRunnerState` | 126 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testWorkingLoopbackWithNoChoiceIsTheStepDone` | 139 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testEverythingDoneWithoutAnAppleAccountLeavesNothingToSetUp` | 157 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testExpiryWarningOnlyInTheLastTwoDays` | 179 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testIdleStopSetting` | 187 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAPhoneThatNeverChoseAsksBeforeASensitiveTap` | 204 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnOwnerWhoTurnedAskingOffIsNotAsked` | 213 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testPasscodeWaitIsNamedAndClears` | 226 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAPasscodeWaitAsksTheOwnerAndTellsTheAgentWhoMustEnterIt` | 279 | Agent 端、安装与配对 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios-app/PokiTests/ChatHarnessTests.swift`** — 3 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testEachTaskTellsTheModelWhatMemoryHolds` | 45 | Agent 端、效率与资源 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheFinishedTaskAnswersWithTheRequestedFacts` | 66 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testThePromptNamesOnlyToolsTheModelHas` | 91 | Agent 端 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios-app/PokiTests/HandoffTests.swift`** — 3 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testASealedModelKeyIsTakenOnceAndTheHelloSaysSo` | 48 | Agent 端、会话与传输 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheHelloSaysWhetherTheLocalConnectionAnswers` | 83 | Agent 端、会话与传输 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAPokiSetupInstallTurnsPokiOnByItself` | 98 | Agent 端、会话与传输 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios-app/PokiTests/InProcessClipboardTests.swift`** — 2 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testAClipboardHoldingNoTextIsRefusedNotReadAsEmpty` | 19 | 操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTextOnTheClipboardIsReadBack` | 30 | 操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios-app/PokiTests/InProcessSessionTests.swift`** — 2 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testAFailedOpenIsAnsweredWithItsReasonAndTheCallTriesAgain` | 10 | 会话与传输 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testACallThatFindsTheSessionStillOpeningAsksForAnOpen` | 26 | 会话与传输 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

**`native/ios-app/PokiTests/VoiceModelTests.swift`** — 15 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `testTheConversationEndsWhenNobodySpeaksForEightSecondsAfterTheAnswer` | 129 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheConversationEndsWhenNobodySpeaksForEightSecondsAfterItOpens` | 143 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testSpeechAnsweredOnlyWithAnErrorStillEndsAfterEightSeconds` | 154 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testSpeakingAgainWithinEightSecondsGoesOnInTheSameConversation` | 164 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testANewConversationWithinFiveMinutesIsToldTheLastTurns` | 178 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAStepsResultIsSaidBeforeTheConversationEnds` | 208 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testGoingToTheBackgroundWhileConnectingEndsTheConversation` | 225 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testInTheBackgroundPokiStopsListeningUnlessAStepIsRunning` | 241 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAStepsResultHandedOverJustBeforeTheBackgroundIsStillSaid` | 268 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testInTheBackgroundOnlyAnErrorForTheAnswerRequestEndsTheConversation` | 286 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testASilentConversationInBetweenKeepsTheLastTurnsToCarryOver` | 315 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnAnswerThatNeverComesEndsTheConversationAfterSixtySecondsInTheForeground` | 336 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAnAnswerThatNeverComesEndsTheConversationThirtySecondsAfterTheBackground` | 354 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testAStepRunningLongerThanTheCapInTheBackgroundIsNotCutOff` | 383 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |
| `testTheLiveSessionSpeaksTheUsersLanguageAfterEnglishToolResults` | 431 | Agent 端、操作 | ⚪ 未运行 — 需 Xcode + iOS 模拟器（xcodebuild test） |

## 11. Rust 测试（desktop / native）

- 入口：`cargo test（desktop 工作区、native/bridge、native/launcher）`
- 场景：84（通过 81，失败 0，超时 0，未跑 3），墙钟 10.8 s

**`desktop/bridge/src/main.rs`** — 1 场景（通过 1，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `tests::the_container_commands_reach_only_the_two_hand_off_files` | 521 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/agent.rs`** — 2 场景（通过 2，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `agent::tests::steps_follow_the_setup_order` | 165 | 安装与配对 | ✅ 通过 |
| `agent::tests::prompt_names_the_tool` | 179 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/apple/gsa.rs`** — 3 场景（通过 3，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `apple::gsa::tests::spd_round_trip` | 483 | 安装与配对 | ✅ 通过 |
| `apple::gsa::tests::gcm_round_trip_16_byte_iv` | 503 | 安装与配对 | ✅ 通过 |
| `apple::gsa::sms_tests::picks_the_sms_phone` | 536 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/apple/identity.rs`** — 4 场景（通过 4，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `apple::identity::tests::key_csr_and_match` | 351 | 安装与配对 | ✅ 通过 |
| `apple::identity::replacement_tests::only_poki_certificates_are_candidates` | 379 | 安装与配对 | ✅ 通过 |
| `apple::identity::replacement_tests::a_yes_covers_only_the_certificate_asked_about` | 387 | 安装与配对 | ✅ 通过 |
| `apple::identity::replacement_tests::the_question_names_the_certificate_and_what_stops` | 400 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/apple/srp.rs`** — 1 场景（通过 1，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `apple::srp::tests::round_trip_with_reference_server` | 111 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/apple/store.rs`** — 1 场景（通过 1，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `apple::store::tests::file_round_trip` | 155 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/device/mod.rs`** — 1 场景（通过 1，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `device::list_tests::a_phone_on_cable_and_wifi_is_listed_once_by_cable` | 117 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/device/pairing.rs`** — 2 场景（通过 2，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `device::pairing::remote_tests::cutoff_is_26_4` | 239 | 安装与配对 | ✅ 通过 |
| `device::pairing::remote_tests::sending_host_survives_and_record_still_reads` | 247 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/keeper.rs`** — 1 场景（通过 1，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `keeper::tests::due_and_store` | 78 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/lib.rs`** — 1 场景（通过 1，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `version_tests::shows_the_build_in_brackets` | 67 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/mcp.rs`** — 1 场景（通过 1，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `mcp::tests::parse_and_redact` | 217 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/pairshare.rs`** — 2 场景（通过 2，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `pairshare::tests::big_record_still_serves_a_code` | 135 | 安装与配对 | ✅ 通过 |
| `pairshare::tests::link_shape` | 146 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/relay.rs`** — 1 场景（通过 1，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `relay::tests::worker_is_bundled` | 269 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/release.rs`** — 11 场景（通过 11，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `release::tests::tags_map_to_channels` | 641 | 安装与配对 | ✅ 通过 |
| `release::tests::channels_include_the_ones_above` | 661 | 安装与配对 | ✅ 通过 |
| `release::tests::rolling_release_wins_by_build_not_list_order` | 682 | 安装与配对 | ✅ 通过 |
| `release::tests::choice_is_saved` | 702 | 安装与配对 | ✅ 通过 |
| `release::tests::desktop_installer_found_on_any_release` | 711 | 安装与配对 | ✅ 通过 |
| `release::tests::build_suffix_sorts_after_version` | 724 | 安装与配对 | ✅ 通过 |
| `release::tests::betas_sort_below_their_stable_and_by_number` | 730 | 安装与配对 | ✅ 通过 |
| `release::tests::app_tags_map_to_channels` | 743 | 安装与配对 | ✅ 通过 |
| `release::tests::app_and_ios_releases_are_read_together` | 761 | 安装与配对 | ✅ 通过 |
| `release::tests::stable_wins_over_its_betas_on_every_channel` | 784 | 安装与配对 | ✅ 通过 |
| `release::update_tests::checksum_line_for_a_file` | 814 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/sign/entitlements.rs`** — 1 场景（通过 1，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `sign::entitlements::tests::keeps_identity_and_requested_only` | 41 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/sign/mod.rs`** — 3 场景（通过 3，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `sign::tests::ids` | 277 | 安装与配对 | ✅ 通过 |
| `sign::tests::package_installed_app_round_trip` | 288 | 安装与配对 | ✅ 通过 |
| `sign::tests::unpack_rewrites_and_drops_tunnel` | 314 | 安装与配对 | ✅ 通过 |

**`desktop/core/src/support.rs`** — 1 场景（通过 1，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `support::tests::masks` | 86 | 安装与配对 | ✅ 通过 |

**`native/bridge/src/apps.rs`** — 3 场景（通过 3，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `apps::tests::launch_name_resolution_prefers_exact_and_rejects_ambiguous_names` | 248 | 会话与传输 | ✅ 通过 |
| `apps::tests::localized_names_join_installed_bundles_and_ignore_folder_names` | 291 | 会话与传输 | ✅ 通过 |
| `apps::tests::an_executable_maps_to_the_bundle_that_contains_it` | 341 | 会话与传输 | ✅ 通过 |

**`native/bridge/src/installation.rs`** — 1 场景（通过 1，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `installation::tests::uppercase_ipa_passes_package_validation` | 127 | 会话与传输 | ✅ 通过 |

**`native/bridge/src/main.rs`** — 2 场景（通过 2，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `literal_input_contract_tests::legacy_type_text_keeps_snapshot_optional` | 949 | 会话与传输 | ✅ 通过 |
| `literal_input_contract_tests::cua_can_require_a_complete_snapshot_before_mutation` | 954 | 会话与传输 | ✅ 通过 |

**`native/bridge/src/pasteboard.rs`** — 9 场景（通过 9，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `pasteboard::tests::the_first_tree_of_a_read_says_which_field_is_being_edited` | 778 | 会话与传输 | ✅ 通过 |
| `pasteboard::tests::the_field_being_edited_passes_only_when_it_is_the_target` | 784 | 会话与传输 | ✅ 通过 |
| `pasteboard::tests::no_key_is_pressed_when_another_field_is_being_edited` | 791 | 会话与传输 | ✅ 通过 |
| `pasteboard::tests::no_key_is_pressed_when_no_field_is_being_edited` | 798 | 会话与传输 | ✅ 通过 |
| `pasteboard::tests::a_reused_cell_with_other_content_is_not_the_target` | 805 | 会话与传输 | ✅ 通过 |
| `pasteboard::tests::the_paste_prompt_says_where_to_touch_each_button` | 823 | 会话与传输 | ✅ 通过 |
| `pasteboard::tests::a_field_holding_the_words_is_not_a_paste_prompt` | 830 | 会话与传输 | ✅ 通过 |
| `pasteboard::tests::an_unconfirmed_input_is_an_error_with_a_next_step_for_the_model` | 836 | 会话与传输、稳定性与容错 | ✅ 通过 |
| `pasteboard::tests::clearing_without_a_known_editing_field_is_refused_but_appending_is_not` | 848 | 会话与传输 | ✅ 通过 |

**`native/bridge/src/remote.rs`** — 10 场景（通过 10，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `remote::tests::data_socket_uses_control_peer_address_and_listener_port` | 662 | 会话与传输 | ✅ 通过 |
| `remote::tests::only_bonjour_hosts_opt_into_control_refresh` | 690 | 会话与传输 | ✅ 通过 |
| `remote::tests::bonjour_explicit_reconnect_refreshes_control_and_preserves_live_tunnel` | 711 | 会话与传输 | ✅ 通过 |
| `remote::tests::dead_bonjour_tunnel_drops_stale_control` | 752 | 会话与传输 | ✅ 通过 |
| `remote::tests::non_bonjour_recovery_keeps_using_its_existing_control` | 783 | 会话与传输、稳定性与容错 | ✅ 通过 |
| `remote::tests::unreachable_control_reports_each_address_and_its_os_error` | 822 | 会话与传输、稳定性与容错 | ✅ 通过 |
| `remote::tests::failed_remote_replacement_keeps_the_working_tunnel` | 857 | 会话与传输、稳定性与容错 | ✅ 通过 |
| `remote::tests::first_request_after_replug_rebuilds_the_tunnel_and_never_claims_delivery` | 884 | 会话与传输 | ✅ 通过 |
| `remote::tests::a_request_refused_before_any_input_says_nothing_was_sent` | 932 | 会话与传输 | ✅ 通过 |
| `remote::tests::a_service_refused_on_a_live_tunnel_keeps_that_tunnel` | 1012 | 会话与传输 | ✅ 通过 |

**`native/launcher/src/remote.rs`** — 2 场景（通过 2，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `remote::tests::pair_verify_and_tunnel_failures_read_differently` | 218 | 安装与配对、稳定性与容错 | ✅ 通过 |
| `remote::tests::sending_host_comes_from_the_file_when_present` | 235 | 安装与配对 | ✅ 通过 |

**`native/launcher/src/tests.rs`** — 10 场景（通过 10，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `tests::config_defaults_to_the_loopback_and_local_runner` | 26 | 安装与配对 | ✅ 通过 |
| `tests::standalone_runner_listens_only_on_the_phone_loopback` | 34 | 安装与配对 | ✅ 通过 |
| `tests::pairing_files_of_either_kind_are_told_apart` | 43 | 安装与配对 | ✅ 通过 |
| `tests::without_the_loopback_it_waits_for_the_network_and_keeps_trying` | 57 | 安装与配对 | ✅ 通过 |
| `tests::a_remote_pairing_service_that_takes_the_connection_and_never_answers_is_not_called_developer_mode` | 80 | 安装与配对 | ✅ 通过 |
| `tests::status_is_true_only_for_a_200` | 104 | 安装与配对 | ✅ 通过 |
| `tests::pairing_advertises_what_bonjour_needs` | 126 | 安装与配对 | ✅ 通过 |
| `tests::an_unreadable_config_gives_null` | 160 | 安装与配对 | ✅ 通过 |
| `tests::disk_image_failures_name_their_own_fix` | 176 | 安装与配对、稳定性与容错 | ✅ 通过 |
| `tests::only_the_phone_saying_so_is_called_developer_mode_off` | 193 | 安装与配对 | ✅ 通过 |

**`native/launcher/tests/soak.rs`** — 3 场景

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `stop_goes_idle_at_once_even_while_an_attempt_hangs` | 75 | 安装与配对 | ⚪ 未运行 — 环境阻断：本机无法绑定测试用的网络地址（EADDRNOTAVAIL），需在未沙箱化的机器上运行 |
| `a_silent_phone_times_out_and_is_tried_again` | 94 | 安装与配对 | ⚪ 未运行 — 环境阻断：本机无法绑定测试用的网络地址（EADDRNOTAVAIL），需在未沙箱化的机器上运行 |
| `a_rude_phone_backs_off_and_restart_cuts_the_wait_short` | 107 | 安装与配对 | ⚪ 未运行 — 环境阻断：本机无法绑定测试用的网络地址（EADDRNOTAVAIL），需在未沙箱化的机器上运行 |

**`native/bridge/src`** — 6 场景（通过 6，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `gesture::tests::strokes_send_each_point_once_on_schedule_and_lift_between_strokes` | — | 会话与传输 | ✅ 通过 — 执行后枚举（源码盘点没有对应的 #[test] 行） |
| `remote::tests::a_socket_error_on_a_tunnel_whose_phone_still_answers_keeps_that_tunnel` | — | 会话与传输、稳定性与容错 | ✅ 通过 — 执行后枚举（源码盘点没有对应的 #[test] 行） |
| `remote::tests::a_tap_cut_off_after_it_reached_the_phone_is_not_repeated` | — | 会话与传输 | ✅ 通过 — 执行后枚举（源码盘点没有对应的 #[test] 行） |
| `gesture::tests::gesture_transmissions_keep_deadlines_order_holds_and_error_release` | — | 会话与传输、稳定性与容错 | ✅ 通过 — 执行后枚举（源码盘点没有对应的 #[test] 行） |
| `gesture::tests::the_documented_circle_with_fractional_times_is_accepted_and_drawn_on_schedule` | — | 会话与传输 | ✅ 通过 — 执行后枚举（源码盘点没有对应的 #[test] 行） |
| `remote::tests::a_tunnel_whose_phone_stops_answering_is_rebuilt` | — | 会话与传输 | ✅ 通过 — 执行后枚举（源码盘点没有对应的 #[test] 行） |

**`native/launcher/src`** — 1 场景（通过 1，失败 0）

| 场景 | 行 | 能力 | 结果 |
| --- | ---: | --- | --- |
| `tests::an_abandoned_pairing_ends_by_itself_within_ten_minutes` | — | 安装与配对 | ✅ 通过 — 执行后枚举（源码盘点没有对应的 #[test] 行） |

## 12. 真机人工检查清单

- 入口：`docs/device-test-checklist.md`
- 场景：54（通过 0，失败 0，超时 0，未跑 54），墙钟 —

| 场景 | 位置 | 能力 | 结果 | 说明 |
| --- | --- | --- | --- | --- |
| Poki (`ios-app.yml` build, or an Ad Hoc release) installed, developer trusted. Open Poki once. Poki automates the phone in its own process; Poki Runner is not installed. | `docs/device-test-checklist.md:9` | 安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Developer Mode on (Settings → Privacy & Security → Developer Mode). On a phone that never had it on, note whether the menu appears with only Poki installed (it used to appear once Poki Runner was installed). | `docs/device-test-checklist.md:10` | 安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Runner path only (Poki launched with `-automationPath runner`): Poki Runner (`ios-runner.yml` build) installed with the same signing tool and Apple ID as Poki; opening it by hand shows its screen and goes back to Poki. Sections 3 and 4 mark the lines that apply to this path. | `docs/device-test-checklist.md:11` | 安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Note the iOS version and whether the phone is on Wi-Fi or cellular for each step. | `docs/device-test-checklist.md:12` | 安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Built-in: install the local-VPN build with Network Extensions provisioned for both Poki and PokiTunnel. In Setup > Connect to this iPhone, tap Enable local connection and approve iOS's VPN prompt. The developer-service check passes; neither a saved profile nor VPN Connected alone counts. | `docs/device-test-checklist.md:16` | 会话与传输、安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Built-in: a normal web page still loads; no DNS or internet default route is installed by Poki. | `docs/device-test-checklist.md:19` | 会话与传输、安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Built-in: disconnect/reconnect, lock/unlock, and reboot recover after an explicit reconnect (or, with Poki on, Poki's own retry below). Opening Poki alone must not start the tunnel. Choosing External app stops only Poki's VPN. | `docs/device-test-checklist.md:20` | 会话与传输、安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Built-in, with Poki on: turn Poki's VPN off in Settings > VPN. It stays off (the log says `ended on purpose`), the agent's runner status says to open Poki and tap Enable local connection, and names no proxy app. Tapping it while Poki is on brings the runner back within seconds. The same when another VPN (LocalDevVPN) takes the packet tunnel, and after Turn off or Disconnect in Poki. | `docs/device-test-checklist.md:22` | 会话与传输、安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Built-in, with Poki on: the tunnel fails without anyone turning it off (kill the PokiTunnel process: Xcode > Debug > Attach to Process, PokiTunnel, then stop the session). With no hand on the phone, the log shows `local VPN: failed`, `reconnecting in 1 s`, `connected`, `back: 10.7.0.1 answers again; starting the runner now`, and the next agent call works. If it keeps failing, it tries 8 times in about 2 minutes (1, 2, 4, 8, 16, 30, 30, 30 s) and stops; then only Enable Local Connection in Setup starts it again. Opening Poki dials nothing (GitHub issue 44). | `docs/device-test-checklist.md:26` | 会话与传输、安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Built-in, with Poki on, the tunnel fails and a different VPN (WireGuard, a work VPN) is turned on before the retry comes: Poki does not dial if it detects that VPN. Setup says `Another VPN appears to be on…`, Home shows it under Needs attention, the log says `another VPN is on; not reconnecting`, and the other VPN stays connected. Detection is best effort: a VPN that sets no proxy, such as Tailscale, may not be detected, so Poki may still dial over it. Turning that VPN off and tapping Enable Local Connection brings the runner back, and the message goes. (The check reads the interfaces iOS has network settings for; confirm it sees a real VPN, and sees none with only Wi-Fi or cellular.) | `docs/device-test-checklist.md:32` | 会话与传输、安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Installed over 0.2.3 with a proxy app that was set up only in the proxy app (no connection chosen in Poki): Turn on says to choose a local connection first, and Setup > External app > Use the current VPN brings it back. Say this in the release notes for 0.2.3 users. | `docs/device-test-checklist.md:38` | 会话与传输、安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| External build: no PokiTunnel is embedded and no built-in enable button is offered. Continue with an external option below. Use this build when Network Extension signing is unavailable. | `docs/device-test-checklist.md:41` | 会话与传输、安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Or LocalDevVPN (App Store) on, for people without a proxy app. | `docs/device-test-checklist.md:43` | 会话与传输、安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Or Shadowrocket "Include route 10.7.0.1/32" on, with Shadowrocket connected. | `docs/device-test-checklist.md:44` | 会话与传输、安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Or Surge Enhanced Mode with the Poki module (`10.7.0.1 = reflect`), or Loon's plugin, or sing-box `loopback_address`. | `docs/device-test-checklist.md:45` | 会话与传输、安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| With a proxy app: a web page still loads through the proxy (the proxy keeps working). | `docs/device-test-checklist.md:46` | 会话与传输、安装与配对 | ⚪ 未运行 | 人工真机检查项 |
| Start pairing in Poki: the launcher emits `advertise`, and Poki appears in Settings' list of computers to pair with. | `docs/device-test-checklist.md:50` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Pick it: a PIN appears in Poki's Live Activity; type it on the phone. | `docs/device-test-checklist.md:51` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| `paired` arrives with a path; the file is in the app's container (never print its contents). | `docs/device-test-checklist.md:52` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Start pairing, then leave Settings without pairing: after 10 minutes Poki stops waiting (Try again shows), the Live Activity ends, and Poki no longer keeps itself running. Switching to another tab, or opening another Setup step, while pairing cancels it at once. | `docs/device-test-checklist.md:53` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Older iOS, or if this fails: use a pairing file made on a Mac (RPPairing or lockdown plist) and note which kind worked. | `docs/device-test-checklist.md:56` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| States move: connecting → pairing → (mounting_ddi on the first run after a restart) → running, with no launching (the launcher only mounts the disk image). Note the time of each. | `docs/device-test-checklist.md:60` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Mounting needs the internet: try it once with Wi-Fi and once on cellular. | `docs/device-test-checklist.md:61` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| `running` within 60 s, then the Poki log shows `in-process session ready` (the first time, iOS may ask for the passcode to allow automation). Note the seconds it reports. Then PokiCore `look` answers. | `docs/device-test-checklist.md:62` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Cancel the passcode prompt on a first open: the log shows `in-process session not ready`, and the agent's next `look` answers at once with `runner: failed` and the reason, not `starting` after 15 s. The call after that opens the session again. | `docs/device-test-checklist.md:63` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Background Poki and use other apps for 5 minutes: `look` and `do` still answer; if the session ended, the first call opens it again. Note what that first call answers and how long it took. | `docs/device-test-checklist.md:64` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Lock the phone for 2 minutes, unlock, then `do` once: the action is not sent to the ended session; a new session is opened and the action goes there. Note the time until it is back. | `docs/device-test-checklist.md:65` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Runner path only: states pass through launching; kill Poki Runner from the app switcher and within about 10 s the launcher relaunches it (`launching`, then `running`). | `docs/device-test-checklist.md:66` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Runner path only: background Poki for 5 minutes and lock the phone for 2 minutes; the runner stays up (the runner dies about 30 s after the launcher's connections close). | `docs/device-test-checklist.md:67` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Switch Wi-Fi off and on, and to cellular: does the launcher keep or regain `running`? Earlier tests over Tailscale found new developer connections only on Wi-Fi; record whether the loopback changes that. | `docs/device-test-checklist.md:68` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Turn the loopback off: the state becomes `waiting_network` with the fix text, and back to `running` after it is turned on again. | `docs/device-test-checklist.md:69` | 安装与配对、会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Deploy your relay (`deploy/cf-relay/deploy.sh`) and enter its address in Connect. The relay state reaches `ready`; the connector URL (`https://<relay host>/v1/<label>/<secret>/mcp`) is shown in Poki. | `docs/device-test-checklist.md:73` | 会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Add it in Claude as a connector; `tools/list` shows look, do, status. | `docs/device-test-checklist.md:74` | 会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| `look` within 2 s, with a screenshot and elements. | `docs/device-test-checklist.md:75` | 会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| A Clock task (World Clock → add a city) and a Notes task, timed from the first call to the last. | `docs/device-test-checklist.md:76` | 会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Force a hang: lock the phone during a long `do` (Runner path: background or kill Poki Runner's app); the call answers within 25 s, says what may have been delivered, and the next `look` answers at once. | `docs/device-test-checklist.md:77` | 会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| Phone offline (airplane mode): the MCP client gets the relay's "The phone is offline" error, not a hang. | `docs/device-test-checklist.md:78` | 会话与传输 | ⚪ 未运行 | 人工真机检查项 |
| `do` tapping a Delete button in Photos: nothing happens on screen, the Live Activity asks, the answer says `approval_required`. | `docs/device-test-checklist.md:82` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| Approve in the Live Activity after 45 s, without sending anything again: the same call goes on and taps, and the answer says `approved on the phone after 45 s`. Allow does not bring Poki to the front: the phone stays in the app it was in, and the tap lands there. | `docs/device-test-checklist.md:83` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| Do not approve: after about 115 s (about 50 s behind a relay still at `REQ_TIMEOUT_MS` 60000) the answer says `approval_required`. Approve afterwards and send the same actions: it taps once; a third time asks again. | `docs/device-test-checklist.md:84` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| Behind a relay still at `REQ_TIMEOUT_MS` 60000, approve at about 52 s: the answer says `approval_required` and the owner approved too late; nothing was tapped. Send the same actions again: they run at once. | `docs/device-test-checklist.md:85` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| Decline: `not_sent: the owner declined`. | `docs/device-test-checklist.md:86` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| While an approval is pending, have the agent tap the Live Activity's Approve button (`do` with the button's point): the pending request is withdrawn first, so nothing is approved. | `docs/device-test-checklist.md:87` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| Typing into a password field asks first, and the Live Activity hides the text. | `docs/device-test-checklist.md:88` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| A fresh install (or an alpha that never touched the switch): Agents › Approvals › Ask Before Sensitive Steps is on, and the first Delete asks. | `docs/device-test-checklist.md:89` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| With Poki in front while an agent's approval waits (the Dynamic Island hides Poki's own Live Activity then): the chat shows Allow this step? with Allow and Don't Allow; Allow runs the step and the phone goes back to the app the agent was in. | `docs/device-test-checklist.md:90` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| Leave an approval unanswered and send nothing more: after 2 minutes the Live Activity leaves Approval, Poki says the approval ran out, and the idle stop works again. | `docs/device-test-checklist.md:91` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| In Wallet: the agent can wait, hand the screen to you and press Home without being asked; a tap asks. | `docs/device-test-checklist.md:92` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| In Wallet, `do {run: name}` of a saved routine asks before anything is tapped. | `docs/device-test-checklist.md:93` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| In WeChat: tap the message field, type, then `{key: "return"}`: it asks before the return, and nothing is sent. In WeChat's search field the same return searches without asking, also after `{type: "…", ref: n}` on it. In the chat list, a `do` that taps a chat and then types by the search field's number from the list asks before the return. | `docs/device-test-checklist.md:94` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| In WeChat, `do {run: {name, with: {text_1: "…\n"}}}` of a saved routine that types into the message field: the run stops before that step, and nothing is sent. | `docs/device-test-checklist.md:95` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| `do [{launch: "com.apple.mobileslideshow"}, {wait: 500}, {tap: [x, y]}]`: Photos opens, then it asks before the tap. | `docs/device-test-checklist.md:96` | 安全与审批 | ⚪ 未运行 | 人工真机检查项 |
| It shows the current call (tool and summary), then the app and the thumbnail after each call. | `docs/device-test-checklist.md:100` | 安全与审批、诊断与证据 | ⚪ 未运行 | 人工真机检查项 |
| It stays while Poki is in the background, and ends when Poki stops. | `docs/device-test-checklist.md:101` | 安全与审批、诊断与证据 | ⚪ 未运行 | 人工真机检查项 |

## 13. 人工验证预案

- 入口：`docs/verification/*.md、docs/native-ime-testing.md`
- 场景：4（通过 0，失败 0，超时 0，未跑 4），墙钟 —

| 场景 | 位置 | 能力 | 结果 | 说明 |
| --- | --- | --- | --- | --- |
| verification/cellular-test-plan（3 个验证段：Remote session lifecycle / Physical iPhone checks / Tool catalog contract） | `docs/verification/cellular-test-plan.md:1` | 会话与传输、稳定性与容错 | ⚪ 未运行 | 人工验证预案，按文档步骤在真机/真网环境执行 |
| verification/lan-bonjour-recovery（4 个验证段：Current behavior / Automated validation / Physical validation …） | `docs/verification/lan-bonjour-recovery.md:1` | 会话与传输、稳定性与容错 | ⚪ 未运行 | 人工验证预案，按文档步骤在真机/真网环境执行 |
| verification/tailscale-pr-validation（4 个验证段：Automated checks / Real-device evidence / Cancellation repair verification …） | `docs/verification/tailscale-pr-validation.md:1` | 会话与传输、安装与配对 | ⚪ 未运行 | 人工验证预案，按文档步骤在真机/真网环境执行 |
| native-ime-testing（4 个验证段：Fast observations and source selection / Local checks without Xcode / Physical evidence …） | `docs/native-ime-testing.md:1` | 操作、观察 | ⚪ 未运行 | 人工验证预案，按文档步骤在真机/真网环境执行 |

## 14. 模拟器/真机验收脚本

- 入口：`bin/verify-*.mjs、bin/eval-first-call.mjs`
- 场景：4（通过 0，失败 0，超时 0，未跑 4），墙钟 —

| 场景 | 位置 | 能力 | 结果 | 说明 |
| --- | --- | --- | --- | --- |
| bin/verify-fixture.mjs（17 处断言） | `bin/verify-fixture.mjs:1` | 操作、观察 | ⚪ 未运行 | 验收脚本：需要专用一次性模拟器或真机，手动运行 |
| bin/verify-native-session.mjs（8 处断言） | `bin/verify-native-session.mjs:1` | 操作、观察、安全与审批 | ⚪ 未运行 | 验收脚本：需要专用一次性模拟器或真机，手动运行 |
| bin/verify-platform.mjs（19 处断言） — iOS 27 simulators leave the pasteboard empty after simctl pbcopy. On any other OS the same error is a failure. | `bin/verify-platform.mjs:1` | 操作、观察 | ⚪ 未运行 | 验收脚本：需要专用一次性模拟器或真机，手动运行 |
| bin/eval-first-call.mjs（度量脚本） — 度量全新的 Claude Code / Codex CLI 窗口在一次性模拟器上完成同一任务的往返次数与耗时（无断言，输出对照报告） | `bin/eval-first-call.mjs:1` | 效率与资源、Agent 端 | ⚪ 未运行 | 验收脚本：需要专用一次性模拟器或真机，手动运行 |

## 指标定义

- **场景数**：一条可独立判定的测试/检查（Node 的每一条 test 与 subtest、每个 XCTest 方法、每个 `#[test]`、每个 Gym 屏与 scorecard 步骤、每个人工检查项）。
- **实跑**：本次真实执行并拿到结果；**超时**：文件在限定时间内没有返回结果（进程被终止）；**未跑**：静态盘点或需要模拟器/真机。
- **通过率**：通过 /（通过 + 失败），失败包含断言失败、超时与执行错误。
- **墙钟**：整套运行的实际耗时（并行执行，不是各场景耗时之和）。
- **能力维度**：观察、操作、批量与等待、会话与传输、安装与配对、Agent 端、安全与审批、稳定性与容错、效率与资源、诊断与证据。
- **泛化层**：回归（平时可见）、开发集（调参可见）、留出集（只在评估日）、变体（换表面特征）、未见场景（模拟器/真机）、真机人工、验收脚本。
- **工具覆盖**：MCP 工具目录中的工具名是否出现在测试源码或验收文档里（只说明“有覆盖证据”，不代表参数级全覆盖）。

## 评估建议

### 日常回归（改动时）
1. `node bin/test-catalog.mjs`：看第 1 节通过率和墙钟是否回退，对比 `.runtime/test-catalog/history.jsonl` 的上一条记录。
2. 改完 `desktop/`、`native/bridge` 或 `native/launcher`：加 `--rust`，关注 Rust 套件的失败项与构建状态（`native/launcher` 需要先跑 `native/launcher/fetch-idevice.sh`）。
3. 只看回归与开发集，不要为了留出集通过而改代码（见第 3 节协议）。

### 评估日（完整一次，判断能力有没有真的长进）
1. 本机：`node bin/test-catalog.mjs --rust`（完整跑包含留出集与变体；把输出 JSON、本文件和历史记录一起留档）。
2. 模拟器：按 `.github/workflows/ios-gym.yml` 的 `scorecard`（runner 路径）和 `scorecard-inprocess` 跑 Gym；本机等价流程见 `native/ios-gym/README.md`（`xcodebuild build` + `swift run -c release poki-gym-check`）。
3. 真机：按 `docs/device-test-checklist.md` 顺序执行，把每一步的结果和用时写回对应行。
4. 比较三组结果：留出集/变体通过率（第 3 节）、Gym scorecard 的失败项、真机清单的未通过项；只看这组“没被针对性调过”的数字。
5. 把本文件与 `test-scenarios.json` 提交为该版本的能力基线；`--render docs/test-scenarios.json` 可在不重跑的情况下按新模板重排文档。

### 新增场景
- 新增 Node 测试文件：放进 `test/`（或 `agent/test/`）即可，下次运行自动出现在目录里；在 `bin/test-catalog.mjs` 的 `MAIN_FILE_TAGS`/`AGENT_FILE_TAGS` 里补一行能力标签。
- 新增 Gym 屏或 scorecard 步骤：改 `native/ios-gym`，目录会自动重新盘点。
- 新增人工检查项：写进 `docs/device-test-checklist.md`，按 `- [ ]` 条目统计。
- 新增后先跑一轮记下结果，再把它标记为留出/变体（只在评估日跑），避免它退化成第二个开发集。

## 已知缺口与不稳定项

- Agent 套件 / agent/test/opening.test.mjs：（整个文件超时，未返回场景结果）
- Agent 套件 / agent/test/step-timeout-cli.test.mjs：（整个文件超时，未返回场景结果）
- Rust 测试（desktop / native） / native/launcher/tests/soak.rs：stop_goes_idle_at_once_even_while_an_attempt_hangs（环境阻断：本机无法绑定测试用的网络地址（EADDRNOTAVAIL），需在未沙箱化的机器上运行）
- Rust 测试（desktop / native） / native/launcher/tests/soak.rs：a_silent_phone_times_out_and_is_tried_again（环境阻断：本机无法绑定测试用的网络地址（EADDRNOTAVAIL），需在未沙箱化的机器上运行）
- Rust 测试（desktop / native） / native/launcher/tests/soak.rs：a_rude_phone_backs_off_and_restart_cuts_the_wait_short（环境阻断：本机无法绑定测试用的网络地址（EADDRNOTAVAIL），需在未沙箱化的机器上运行）
- Agent 套件超时文件：agent/test/opening.test.mjs、agent/test/step-timeout-cli.test.mjs（这些场景当前拿不到结果）
- 失败：Agent 套件 / agent/test/agent-observation-reuse.test.mjs：Agent reuses eligible receipt and omits the second explicit list_elements read
- 失败：Agent 套件 / agent/test/agent-observation-reuse.test.mjs：Agent retains list_elements fallback for a legacy receipt
- 失败：Agent 套件 / agent/test/agent-observation-reuse.test.mjs：Agent uses a PID-bound terminal batch observation without another list_elements call
- 失败：Agent 套件 / agent/test/agent-observation-reuse.test.mjs：Agent uses a PID-bound terminal batch observation without another list_elements call > single scroll
- 失败：Agent 套件 / agent/test/agent-observation-reuse.test.mjs：Agent uses a PID-bound terminal batch observation without another list_elements call > batch
- 失败：Agent 套件 / agent/test/agent-observation-reuse.test.mjs：Agent uses quick scroll evidence for browsing and still requires a final observation
- 失败：Agent 套件 / agent/test/agent-observation-reuse.test.mjs：Agent still reads the screen when a quick sample is unavailable
- 失败：Agent 套件 / agent/test/steer.test.mjs：A message sent during a task reaches result verification of the stopped task
- 失败：Agent 套件 / agent/test/steer.test.mjs：A message sent during a task is acknowledged with how to stop it
- 失败：Agent 套件 / agent/test/steer.test.mjs：A stop request takes effect while the reply to an earlier mid-task message is still sending
- 失败：Agent 套件 / agent/test/verification-trace.test.mjs：A batch that fails partway gives the verifier each step it ran, the failure and the final screen
- 失败：Agent 套件 / agent/test/verification-trace.test.mjs：A visual answer carries the hybrid screenshot to verification without learning a text route
