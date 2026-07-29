# Cool 阶段感知（防漂移规则）

> 此规则每轮注入，防止长上下文时遗忘 Cool 流程状态。
> Hook 平台额外执行 `cool-hook-guard.sh` 进行硬性拦截；
> 此 Rule 是所有平台通用的软性防线。

> **术语单源**：phase / change / gate / decision point / hotfix / tweak /
> decision_mode / review mode / auto-after-review / agent-assess /
> context-compaction / finishing-branch 等术语定义单源在 `CONTEXT.md`。本规则
> 文件只定义阶段允许操作表与守卫语义，不重复术语定义。

## 全局规则

### 阶段感知（最高优先级）

有活跃 cool change 时（`openspec/changes/<name>/.cool.yaml` 存在），**每次开始执行操作前**必须读取 `phase` 字段确认当前阶段。

**阶段与允许操作：**

| 阶段 | 允许 | 禁止 |
|------|------|------|
| `open` | 创建 proposal/design/tasks, 运行 guard | 写源代码 |
| `design` | brainstorming, 创建 Design Doc, 运行 guard | 写源代码 |
| `build` | 写源代码、测试、执行计划 | 跳过用户确认点 |
| `review`  | 读代码、生成审查报告、写入 review-report.md | 写源代码、修改实现 |
| `verify` | 验证、branch handling | 跳过失败处理 |
| `archive` | 确认归档、运行归档脚本 | 写源代码 |

### open 阶段写前 guard 平台差异

open 阶段写 `proposal.md`/`design.md`/`tasks.md` 前的顺序约束（clarify-review pass + 产物链式顺序）按平台分层实现：

| 平台 | 写前 guard 形态 | 说明 |
|------|----------------|------|
| Claude Code | `cool-hook-guard.sh` PreToolUse 硬拦 | 写 proposal/design/tasks 前校验 review-log 含 `clarify-review pass` + 产物顺序（design 需 proposal 存在 / tasks 需 design 存在），未通过 `exit 2` |
| Cursor/Trae/Qoder | `cool-phase-guard.md` 规则级 + `cool-guard.sh` 阶段退出事后校验 | 降级：规则级约束，非硬拦 |

与 `cool-decision-hook.sh`（仅 Claude Code 启用）同策略，**不声称等价硬拦截**。无 PreToolUse 能力的宿主依赖规则软性约束 + 阶段退出时 `cool-guard.sh` 事后校验。

### Skill 调用（不可用普通对话替代）

以下操作必须通过 Skill 工具加载，Skill 不可用时应停止流程并提示安装：

- **brainstorming** — design 阶段、build 阶段中等规模 spec 变更
- **writing-plans** — build 阶段创建实现计划
- **executing-plans** / **subagent-driven-development** — build 阶段执行
- **test-driven-development** — build 阶段 `tdd_mode: tdd` 时，第一个 task 前
- **systematic-debugging** — 遇到崩溃/测试失败/构建失败时
- **verification-before-completion** — verify 阶段
- **using-git-worktrees** — build 阶段选择 worktree 隔离时

### 脚本执行（不可跳过）

- **阶段退出**: `cool-guard <name> <phase> --apply`（必须看到 ALL CHECKS PASSED）
- **压缩恢复**: `cool-state check <name> <phase> --recover`
- **状态更新**: 关键操作后通过 `cool-state set` 更新字段，禁止手工编辑 .cool.yaml
- **handoff 生成**: `cool-handoff <name> design --write`（禁止手写摘要）

### 用户确认（不可自动跳过）

以下决策点必须暂停等待用户明确选择，不得根据推荐规则自动填写：

- **open**: 需求澄清完成（`clarify-review`）、artifact 评审（`open-review`）、范围拆分（`scope-split-review`）、意图判定（`intent`）、change 名称命名（`change-name`）、分支命名（`branch-name`）——均调 `cool-state gate <name> <point>` 按指令办；`decision_mode: manual` 下 gate 返回 BLOCK，必须人工确认
- **design**: brainstorming 方案确认（`design-review`，auto-after-review，调 gate）、上下文压缩（`context-compaction`，recommend 下 agent 自评（agent-assess 档），manual 下 block）
- **build**: plan-ready（`plan-ready`，auto-after-review）、构建配置（`build-config`，auto-after-review）、subagent 能力降级（`subagent-dispatch`，auto）、平台能力降级（`platform-capability`，auto）、范围拆分（`scope-split-review`，auto-after-review）——均调 gate 按指令办
- **verify**: 验证失败处理（`verify-drift-review`，auto-after-review）、CRITICAL 失败（`verify-critical`，block）、3 次失败上限（`verify-fail-limit`，block）、spec 矛盾处理（`spec-contradiction`，block）、分支处理（`finishing-branch`，auto）、丢弃工作（`discard`，block）——均调 gate 按指令办
- **archive**: 归档前最终确认（`archive`，block，必须人工）

## Design 阶段专项

1. 第一个脚本操作 = `cool-handoff <name> design --write`（未生成 handoff 禁止加载 brainstorming）
2. brainstorming in progress: incrementally update brainstorm-summary.md（每轮澄清或方案迭代后增量更新恢复检查点，未确认内容标注为待确认/候选）
3. brainstorming 完成后下一步 = brainstorm-summary.md 定稿 → Design Doc → guard
4. active compaction gate: brainstorm-summary.md 定稿后、创建 Design Doc 前，优先触发宿主平台原生上下文压缩；无法程序化触发时暂停提示用户手动压缩或确认继续
5. **绝对不能直接开始写实现代码** — 必须先创建 Design Doc 并通过 guard

## Build 阶段专项

1. plan 创建后必须询问用户选择继续或暂停（`build_pause` 机制）
2. 每个 task 完成后必须: tasks.md 打勾 → git commit（不得积攒）
3. 遇到失败必须加载 **systematic-debugging** skill，根因未定位前不得提出源码修复
4. spec 变更分级: 小改直接编辑 | 中改加载 brainstorming | 大改暂停等用户确认拆分

## Verify 阶段专项

1. 第一步运行 `cool-state scale <name>` 确定验证级别
2. 验证失败后列出失败项等用户选择，CRITICAL 必须修
3. 连续 3 次失败后必须让用户选择接受偏差或继续修

## 上下文压缩恢复

如果怀疑发生上下文压缩（之前对话被摘要、找不到之前讨论的内容），立即运行：

```bash
"$COOL_BASH" "$COOL_STATE" check <name> <phase> --recover
```

按脚本输出的 **Recovery action** 决定下一步。

## 阶段退出后自动过渡

guard `--apply` 成功后，必须调用下一阶段的 skill：

- open → `cool-design`（full）/ `cool-build`（hotfix/tweak）
- design → `cool-build`
- build → 根据 `.cool.yaml` 的 `review_mode` 字段：
  - `review_mode: skip`（tweak）→ 自动衔接 `/cool-verify`
  - `review_mode: full`（full workflow）→ 自动衔接 `/cool-review`（两阶段审查）
  - `review_mode: light`（hotfix）→ 自动衔接 `/cool-review`（仅规格合规审查）
- verify → `cool-archive`
