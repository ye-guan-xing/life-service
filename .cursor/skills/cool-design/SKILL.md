---
name: cool-design
description: "Cool 阶段 2：深度设计。使用 /cool-design 调用。通过 brainstorming 产出 Design Doc 和 delta spec。"
---

# Cool 阶段 2：深度设计（Design）

## 前置条件

- 活跃 change 已存在（proposal.md、design.md、tasks.md）
- 无 Design Doc（`docs/superpowers/specs/` 下无对应文件）

## 步骤

### 0. 入口状态验证（Entry Check）

执行入口验证：

```bash
COOL_ENV="${COOL_ENV:-$(find . "$HOME"/.*/skills "$HOME/.config" "$HOME/.gemini" -path '*/cool/scripts/cool-env.sh' -type f -print -quit 2>/dev/null)}"
if [ -z "$COOL_ENV" ]; then
  echo "ERROR: cool-env.sh not found. Ensure the cool skill is installed." >&2
  return 1
fi
. "$COOL_ENV"
"$COOL_BASH" "$COOL_STATE" check <name> design
```

验证通过后继续 Step 1。验证失败时脚本会输出具体失败原因。

**幂等性**：所有 design 阶段操作可以安全重试。如果 `handoff_context` 和 `handoff_hash` 已存在，先确认它们与当前产物一致再决定是否重新生成。

### 1a. 生成 OpenSpec → Superpowers 交接包

**必须由脚本生成，不允许 agent 临场手写 summary 代替。**

```bash
"$COOL_BASH" "$COOL_HANDOFF" <change-name> design --write
```

脚本会根据 change `.cool.yaml` 的 `context_compression` 快照生成并记录交接包。

默认 `context_compression: off` 时生成：

```text
openspec/changes/<name>/.cool/handoff/design-context.json
openspec/changes/<name>/.cool/handoff/design-context.md
```

启用 beta（项目 `.cool/config.yaml` 中 `context_compression: beta`）时生成：

```text
openspec/changes/<name>/.cool/handoff/spec-context.json
openspec/changes/<name>/.cool/handoff/spec-context.md
```

并在 `.cool.yaml` 写入：

```yaml
handoff_context: openspec/changes/<name>/.cool/handoff/design-context.json
handoff_hash: <sha256>
```

默认交接包是 **compact 可追溯摘录**，不是 agent summary：
- `design-context.json`：机器索引，包含 change、phase、canonical spec、source paths、hash
- `design-context.md`：供 Superpowers 阅读的上下文，包含脚本标记、source path、line range、sha256、确定性摘录

beta 交接包是 **结构化 spec projection**，用于减少 OpenSpec 原文 token 占用但避免实现漂移。

如确实需要全文上下文，可显式运行：

```bash
"$COOL_BASH" "$COOL_HANDOFF" <change-name> design --write --full
```

### 1b. 执行 Brainstorming（带上下文）

**立即执行：** 使用 Skill 工具加载 Superpowers `brainstorming` 技能。禁止跳过此步骤。

技能加载时，ARGUMENTS 必须包含：

```text
Language: 使用触发本次工作流的用户请求语言输出
```

技能加载后，按其指引使用以下上下文：

```text
Change: <change-name>
OpenSpec Context Pack: openspec/changes/<name>/.cool/handoff/design-context.md
Machine handoff: openspec/changes/<name>/.cool/handoff/design-context.json

如 context_compression: beta，则使用：
OpenSpec Context Pack: openspec/changes/<name>/.cool/handoff/spec-context.md
Machine handoff: openspec/changes/<name>/.cool/handoff/spec-context.json

OpenSpec 产物是上游事实源，但不得用"跳过重复上下文探索"削弱 Superpowers brainstorming 的澄清流程。
你的任务是基于交接包做深度技术设计：实现方案、技术风险、测试策略、边界条件。
如发现目标、范围、非目标、验收场景或关键约束仍不清楚，必须先继续提问并形成设计方案，不得只进行一轮问答就创建 Design Doc。
不要重写 proposal/spec；如发现 OpenSpec delta spec 缺少验收场景，只能提出 Spec Patch，并回写 OpenSpec delta spec；不要在 Design Doc 中创建第二份需求 spec。

Design Doc frontmatter 必须最小化，只包含：
---
cool_change: <change-name>
role: technical-design
canonical_spec: openspec
---

按 Superpowers brainstorming 技能原流程推进：澄清问题、2-3 个方案、分段确认设计。不得提前写入 Design Doc。
```

禁止在未加载该技能的情况下继续。

如 Superpowers `brainstorming` 技能不可用，停止流程并提示安装或启用 Superpowers 技能，不要用普通对话替代该步骤。

技能加载后，按其指引产出设计方案（以对话形式呈现）：
- 技术方案：架构、数据流、关键技术选型与风险
- 测试策略
- 需求/范围缺口与需回写的 Spec Patch
- 如需补充验收场景，标明将回写的 delta spec 变更

brainstorming 阶段不写入 Design Doc 文件，仅产出设计方案供 Step 1c 用户确认。确认后才创建 `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` 并回写 delta spec。

但为了上下文压缩恢复，brainstorming 过程中必须增量更新 `brainstorm-summary.md`。每轮澄清或方案迭代后，只要产生新的已确认事实、关键约束、候选方案、取舍/风险、测试策略或 Spec Patch 候选，就更新该文件；未确认内容必须标注为"待确认"或"候选"。该文件是恢复检查点，不是 Design Doc，也不得替代 Step 1c 的用户确认。

### 1c. 用户确认设计方案（阻塞点）

#### recommend 模式决策闸门（design-review）

在下方 manual 阻塞确认之前，当 `decision_mode: recommend` 时，运行 gate 并按其指令办：

```bash
DM=$("$COOL_BASH" "$COOL_STATE" gate <name> design-review)
```

- `BLOCK:`（manual 模式，或 material 升级）→ 走下方原阻塞设计方案确认。
- `REVIEW:`（auto-after-review，尚未通过）→ 用 `cool/reference/review-checklist.md` 通用节复核（产物 = brainstorming 设计方案；上游 = proposal + 澄清摘要）。`subagent_dispatch: confirmed` 时派后台 subagent，否则主 agent 自检。分级 pass/minor/material：
  - `pass` → `cool-state review-log <name> design-review 1 pass [issue]`（设 `COOL_REVIEW_BY=subagent|self` 与派发路径一致），再运行 `cool-state gate <name> design-review` 取得 `PROCEED:`，然后自主选推荐方案并进入 Design Doc 创建（跳过下方 manual 阻塞确认）。
  - `minor` → 内联修方案 1 次 → 再复核 1 次（round 2）；round 2 `pass` → `review-log ... 2 pass`，重跑 gate 取得 `PROCEED:` 后继续；round 2 非 pass → 升级用户（落入阻塞）。
  - `material` → 软阻塞，surface 用户选择（继续 brainstorming / 拆 change / 接受），**不自主决定**。
- `PROCEED:`（auto-after-review 已通过）→ 自主选推荐方案并进入 Design Doc 创建（不询问）。

注：本点行为契约由 `predecision-review` capability 枚举，不新建独立 cool-design spec。

brainstorming 产出设计方案后，**必须使用当前平台可用的用户输入/确认机制暂停并等待用户明确确认设计方案**。不得在用户确认前创建最终 Design Doc、写入 `design_doc`、运行 design guard，或进入 `/cool-build`。

暂停时只展示必要摘要：
- 采用的技术方案
- 关键取舍与风险
- 测试策略
- 如有 Spec Patch，列出将回写的 delta spec 变更

用户明确确认后，才继续 Step 2。若用户要求调整，继续 brainstorming 迭代，直到用户确认。

### 1d-bis. 领域建模纪律（按需触发）

brainstorming 过程中，按需（非强制门）在设计触及新概念或争议概念时进行领域建模：

1. **L1/L2 判定** —— 若当前项目根存在 `assets/skills/cool/SKILL.md`（即 cool-flow 仓库自身），操作 **L1**（`assets/skills/cool/CONTEXT.md` + `assets/skills/cool/adr/`）。否则操作 **L2**（项目根 `CONTEXT.md` + `adr/`）。
2. **术语冲突检测** —— 引入或精炼概念时，检查当前项目 CONTEXT.md 是否有 overloaded/近义术语。若有，在 Flagged Ambiguities 节消歧。
3. **边界压测** —— 压测概念边界（该术语是否泄漏实现细节？是否与既有术语冲突？）。
4. **内联更新** —— 将解决的术语写入当前项目 CONTEXT.md（Terms / Leading Words / Flagged Ambiguities 节）。L2 在首次涉及术语时惰性创建 `CONTEXT.md`；不涉及术语则不建。
5. **ADR 准入判断** —— 对设计中浮现的难逆决策，套用三重过滤（难逆 + 缺上下文惊讶 + 真权衡）。通过则按 `adr/README.md` 写 ADR。L2 仅在决策通过时惰性创建 `adr/`。

这是软纪律——guard_design 仅做事后存在性 warn（见 cool-guard.sh）。术语质量/冲突/overload 不可机械强制，由 review-checklist 兜底。

### 1d. Brainstorming 检查点定稿

用户确认设计方案后，在创建 Design Doc 前，创建或更新已增量维护的检查点文件，将其定稿为确认后的设计方案摘要：

```bash
mkdir -p openspec/changes/<name>/.cool/handoff
```

`openspec/changes/<name>/.cool/handoff/brainstorm-summary.md` 结构：

```markdown
# Brainstorm Summary

- Change: <change-name>
- Date: <YYYY-MM-DD>

## 确认的技术方案

<用户确认的方案摘要>

## 关键取舍与风险

<主要取舍和风险>

## 测试策略

<测试方法概述>

## Spec Patch

<将回写的 delta spec 变更，无则写"无">
```

**上下文压缩说明**：每次增量更新 `brainstorm-summary.md` 后，都是相对安全的压缩恢复点。Brainstorming 完成后，如上下文窗口紧张，应优先在此处进行压缩。压缩后重新加载以下文件继续 Step 2：
- `openspec/changes/<name>/.cool/handoff/brainstorm-summary.md`
- `openspec/changes/<name>/.cool/handoff/design-context.md`（或 beta 模式的 `spec-context.md`）
- `openspec/changes/<name>/.cool/handoff/design-context.json`（或 beta 模式的 `spec-context.json`）

### 1e. 主动上下文压缩门

完成 Step 1d 并确认 `brainstorm-summary.md` 已写入后，进入 Design Doc 创建前的主动压缩门。此时 OpenSpec 交接包、brainstorming 决策和待确认项都已落盘，应主动释放前面读取 Spec 和 brainstorming 消耗的上下文，为 Step 2 及后续 Build 阶段保留窗口。

执行规则：
- 如果当前平台提供原生上下文压缩/清理机制，必须在这里触发一次主动压缩；不要尝试用 shell 脚本伪造压缩命令
- 压缩恢复提示必须包含 change 名称、当前步骤（Design Step 2）、以及上方三类需重新加载的 handoff 文件
- 如果当前平台无法由 agent 程序化触发压缩：这是决策点 `context-compaction`。运行 `"$COOL_BASH" "$COOL_STATE" gate <name> context-compaction`，按输出分支：
  - `ASSESS: context-compaction agent-self-assess.`（recommend 模式）——agent 自评上下文余量：充足则自主继续 Step 2（不询问）；紧张且平台无法程序化触发压缩则停止，提示用户手动执行 `/compact`（保留 block 路径），用户确认无法压缩或要求继续时，才继续 Step 2。
  - `BLOCK: ask the user for context-compaction.`（manual 模式）——暂停并提示用户在宿主平台执行手动压缩；用户确认无法压缩或要求继续时，才继续 Step 2。

### 2. 创建 Design Doc

基于 brainstorming 对话的完整上下文（仍在主 session 中），创建 Design Doc。

Design Doc frontmatter 必须最小化：

```yaml
---
cool_change: <change-name>
role: technical-design
canonical_spec: openspec
---
```

将 Design Doc 写入 `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`。
如需回写 delta spec（Spec Patch），同时编辑对应的 `specs/*/spec.md`。

Design Doc 写入后，用 `cool-state abspath` 输出绝对路径告知用户：

```bash
ABS=$("$COOL_BASH" "$COOL_STATE" abspath docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md)
echo "Design Doc 已写入：$ABS"
```

**上下文压缩恢复**：若上下文已被压缩，从 `brainstorm-summary.md` + handoff 上下文恢复。若用户尚未确认设计方案，回到 Step 1b/1c 继续 brainstorming；若用户已确认，继续创建 Design Doc。

### 3. 更新 Cool 状态

先记录 design_doc 路径。如果 Spec Patch 回写了 delta spec，必须重新生成 handoff 以更新 hash：

```bash
# 记录 design_doc 路径
"$COOL_BASH" "$COOL_STATE" set <name> design_doc docs/superpowers/specs/YYYY-MM-DD-topic-design.md

# 如有 delta spec 变更，重新生成 handoff（更新 hash）
"$COOL_BASH" "$COOL_HANDOFF" <change-name> design --write

# 阶段守卫推进 phase 到下一阶段
"$COOL_BASH" "$COOL_GUARD" <change-name> design --apply
```

如果没有 delta spec 变更，跳过 handoff 重新生成步骤。状态文件自动更新，无需手动编辑其他字段。

## 退出条件

- Design Doc 已创建并保存
- Design Doc frontmatter 包含 `cool_change`、`role: technical-design`、`canonical_spec: openspec`
- `handoff_context` 和 `handoff_hash` 已写入 `.cool.yaml`（由 guard 强制校验）
- `handoff_hash` 与当前 OpenSpec open 阶段产物一致（由 guard 强制校验）
- 如有新能力或补充验收场景，OpenSpec delta spec 已创建/更新
- `design_doc` 已写入 `.cool.yaml`
- **阶段守卫**：运行 `"$COOL_BASH" "$COOL_GUARD" <change-name> design --apply`，全部 PASS 后由守卫推进到 `phase: build`

```bash
"$COOL_BASH" "$COOL_GUARD" <change-name> design --apply
```

## 上下文压缩恢复

design 阶段在 brainstorming 过程中可能触发上下文压缩。恢复时先运行：

```bash
"$COOL_BASH" "$COOL_STATE" check <change-name> design --recover
```

脚本输出结构化恢复上下文（阶段、已完成字段、待完成字段、恢复动作）。按 Recovery action 判断下一步。

## 自动衔接下一阶段

阶段守卫推进 phase 后，运行：

```bash
"$COOL_BASH" "$COOL_STATE" next <change-name>
```

脚本根据 `phase`、`workflow`、`auto_transition` 输出确定性的下一步：
- `NEXT: auto` → 调用 `SKILL` 指向的 skill 进入下一阶段
- `NEXT: manual` → 不要调用下一 skill，按 `HINT` 提示用户手动运行 `/<SKILL>`
- `NEXT: done` → 流程已完成，无需继续
