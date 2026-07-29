# ADR 0002 — context-compaction gate 用 agent-assess，非 auto

## 约束

- 主动上下文压缩位于 design 阶段 brainstorm-summary 定稿与 Design Doc 创建之间。
- recommend 模式下，应允许 agent 询问用户是否压缩/继续，因为压缩是 agent 须自评的判断。
- cool-decision-hook 强制 `auto` 档 gate `exit 2` 阻止 AskUserQuestion——纯 `auto` 档会阻止 agent 询问。

## 选项

1. **agent-assess 档**（选定）—— agent 自评并输出 `ASSESS:`；非 `auto`，故钩子不阻止询问。
2. **auto 档** —— agent 不询问，自动决策。
3. **block 档** —— 恒暂停等人工。

## 拒绝理由

- 选项 2 拒绝：钩子 auto 档 `exit 2` 阻止 AskUserQuestion，破坏询问能力——违背判断型 gate 的目的。
- 选项 3 拒绝：对 agent 在 recommend 下可合理自评的 gate 而言过重。

## 决策

context-compaction gate 在 recommend 模式下用 `agent-assess` 档：agent 自评并输出 `ASSESS:`，且允许询问用户（因档位非 `auto`，决策钩子不阻止）。这是 agent-assess 作为独立档存在的决定性理由。

## 不变量

- agent-assess 保持非 auto 档，使决策钩子允许 AskUserQuestion。
- agent-assess 专用 context-compaction——未重开本 ADR 前勿泛化到其他 gate。
