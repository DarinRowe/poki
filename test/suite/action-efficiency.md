# 动作效率验收

以同一构建的两个配置比较引用直达与条件等待。旧版组关闭两个开关，新版组打开两个开关。每次新建 MCP 会话和合成设备状态。配对复用同一任务输入，轮次交替新旧顺序。独立验收读取设备夹具的动作记录和最终状态。

| 分组 | 任务 | 验收 |
|---|---|---|
| 开发 | 计数器、切页、回执丢失后的恢复 | 点击一次恰好加一。详情页出现预期控件后返回。第二次计数已生效但回执丢失时，从当前计数继续。 |
| 留出 | 滚动中出现弹窗、延迟焦点并保存、Canvas OCR | 关闭遮挡后只点指定行。保存一次且旁边字段原值保留。OCR 定位后验收 Canvas 动作。 |

运行确定性脚本，无需模拟器运行时或模型账号。

```sh
POKI_EVAL_GROUP=development node --test test/suite/action-efficiency.test.mjs
POKI_EVAL_GROUP=holdout node --test test/suite/action-efficiency.test.mjs
POKI_EVAL_REPEAT=5 POKI_EVAL_RESULTS=/tmp/poki-script-results.jsonl node --test test/suite/action-efficiency.test.mjs
```

记录真实模型 usage 时，配置已登录的 Codex CLI。它调用同一个隔离 MCP 夹具。测试提示只允许使用夹具工具，新旧组的能力说明随开关而异。每轮复位和独立验收在计时之外。输出文件应为新的路径，测试会附加结果。可设置 `POKI_EVAL_SCENARIO=canvas` 单独诊断一个场景。

```sh
POKI_EVAL_MODEL=gpt-6.1-terra POKI_EVAL_RESULTS=/tmp/poki-model-results.jsonl node --test test/suite/action-efficiency.test.mjs
node test/suite/report-action-efficiency.mjs /tmp/poki-script-results.jsonl /tmp/poki-model-results.jsonl
```

比较两份源码时，将基线提交的 `src` 解包到独立目录，并设置 `POKI_EVAL_BEFORE_ROOT` 指向该目录。两组都会启用引用直达和条件等待，使用相同的任务说明。设置 `POKI_EVAL_VARIANT=1` 可替换遮挡场景的角色、按钮和出现时序，以及 Canvas 场景的目标和 AX 干扰项。原场景和变体可分别输出到不同的 JSONL 文件。

报告包含成功率、误动作和重复动作尝试、总耗时、中位数、P95、MCP 调用、显式读屏、内部 AX 和截图阶段、分阶段耗时及模型 token。工具时间使用调用区间的并集，剩余时间包含模型、客户端、启动和传输。Token 缺失保留为空，失败消耗计入每成功任务的成本。

可用模拟器上仍应运行 `bin/eval-first-call.mjs` 的 Safari T4 和现有真机对照，覆盖真实 URL、触控和系统界面。夹具的设备动作记录只能验收合成场景。
