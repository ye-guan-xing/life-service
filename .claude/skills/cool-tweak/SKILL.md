---
name: cool-tweak
description: "Cool 预设路径：非 bug 类小改动（tweak）。跳过 brainstorming 和完整计划，直接 open → 轻量构建 → 轻量验证 → archive。适用于文案、配置、文档或 prompt 的局部优化。"
---

# Cool 预设路径：Tweak

tweak 是 Cool 五段式能力的预设工作流，而非独立的并行流程。它复用 open、build、verify、archive 能力，只跳过 brainstorming 和完整计划。

适用于非 bug 类小范围改动，例如文案调整、配置调整、文档或 prompt 局部优化。

**适用条件**（全部满足）：
1. 无新增能力
2. 无架构变更
3. 无接口变更
4. 通常不超过 3 个任务（文件数约束见下方升级条件）

**不适用**：如果改动过程中发现需要能力、架构或接口调整，应升级为完整 `/cool` 工作流。

---

## 流程（预设工作流，4 个阶段）

### 0. 输出语言约束

精简的 OpenSpec 产物必须使用触发本次工作流的用户请求语言。

执行链：open → 轻量构建 → 轻量验证 → archive。tweak 为每个阶段提供默认决策：精简 open、轻量构建、轻量验证，以及验证通过后的最终归档确认。

启动前定位 Cool 脚本：

```bash
COOL_ENV="${COOL_ENV:-$(find . "$HOME"/.*/skills "$HOME/.config" "$HOME/.gemini" -path '*/cool/scripts/cool-env.sh' -type f -print -quit 2>/dev/null)}"
if [ -z "$COOL_ENV" ]; then
  echo "ERROR: cool-env.sh not found. Ensure the cool skill is installed." >&2
  return 1
fi
. "$COOL_ENV"
```

### 1. 快速开启（preset open）

复用 Cool open 能力创建 change，但使用 tweak 默认值：不执行 `openspec-explore` 长时间探索，直接进入精简 change 创建。

**立即执行：** 使用 Skill 工具加载 `openspec-new-change` 技能。禁止跳过此步骤。

技能加载后，按其指引创建精简产物：
- `proposal.md` — 改动动机 + 目标 + 范围
- `design.md` — 简要实施说明（无需方案对比）
- `tasks.md` — 不超过 3 个任务
- **无需 delta spec**（除非改动修改了现有 spec 验收场景；一旦需要 delta spec，升级为完整 `/cool`）

初始化 Cool 状态文件：

```bash
"$COOL_BASH" "$COOL_STATE" init <name> tweak
```

写任何 artifacts 前先切到 feature 分支——保护分支不得承载 change 产物（同 `/cool-open` step 2 规则）。读取 `protected_branches`；当前分支是保护分支时，用平台用户输入机制确认分支名（推荐 `tweak/YYYYMMDD/<name>`）后 `"$COOL_BASH" "$COOL_STATE" open-branch <name> --branch <NAME>`；否则 `"$COOL_BASH" "$COOL_STATE" open-branch <name>` 沿用当前分支。`open-branch` 记录 `base_branch`/`open_branch` 并按需切分支。

验证初始化状态：

```bash
"$COOL_BASH" "$COOL_STATE" check <name> open
```

运行阶段守卫，过渡 open → build：

```bash
"$COOL_BASH" "$COOL_GUARD" <change-name> open --apply
```

### 2. 轻量构建（preset build）

使用 tweak 默认值：`build_mode: direct`。跳过 Superpowers `brainstorming` 和 `writing-plans`。

继续或开始改动前，按 `cool/reference/dirty-worktree.md` 处理未提交改动。如果归因显示范围超出 tweak，按本文件"升级条件"处理。

**立即执行：** 按 tasks.md 逐个执行任务：

1. 读取 `openspec/changes/<name>/tasks.md`，获取未完成任务列表
2. 对每个未完成任务：
   - 按任务描述修改目标文件
   - 运行项目格式化工具（如 `mvn spotless:apply`、`npm run format`）
   - 运行相关测试确认通过
   - 将 tasks.md 中对应的 `- [ ]` 勾选为 `- [x]`
   - 提交代码，commit message 格式：`tweak: <简洁改动描述>`
3. 所有任务完成后，明确运行相关项目测试和构建命令
4. 运行阶段守卫，过渡 build → verify：

```bash
"$COOL_BASH" "$COOL_GUARD" <change-name> build --apply
```

状态自动更新为 `phase: verify`（tweak 的 `review_mode: skip`，直接进入 verify），`verify_result: pending`，然后进入验证。

### 3. 轻量验证（preset verify）

复用 `/cool-verify`。tweak 必须保持轻量验证条件：≤ 3 个任务、≤ 4 个文件、无 delta spec、无新能力。

**立即执行：** 使用 Skill 工具加载 `cool-verify` 技能。禁止跳过此步骤。

如果规模评估进入完整验证路径，停止 tweak，按升级条件处理阻塞确认。

验证通过后，按 `/cool-verify` 规则将 `.cool.yaml` `verify_result` 记录为 `pass`，归档前不得跳过此状态。验证通过后，仍需进入 `/cool-archive` 的最终归档确认；不要自动运行归档脚本。

### 4. 归档（preset archive）

复用 `/cool-archive`。归档前 `.cool.yaml` 必须满足 `verify_result: pass`，并等待 `/cool-archive` 的最终归档确认。

**立即执行：** 使用 Skill 工具加载 `cool-archive` 技能进行归档。禁止跳过此步骤。

---

## 连续执行模式

<IMPORTANT>
tweak 工作流是**一次性连续执行**。调用 `/cool-tweak` 后，agent 必须自动推进 tweak 各阶段，中途不得暂停等待用户输入。

例外：当 `.cool.yaml` 中 `auto_transition: false` 时，每次阶段守卫推进 `phase` 后，不自动调用下一个 skill。此时使用 `"$COOL_BASH" "$COOL_STATE" next <name>` 输出，按指示暂停等待手动继续。

以下情况也必须暂停等待用户确认：

1. 遇到升级条件（见"升级条件"节）。这是 recommend 模式决策点 `tweak-upgrade`（auto-after-review）。运行 `"$COOL_BASH" "$COOL_STATE" gate <name> tweak-upgrade` 并按其指令办：`PROCEED:` → 自动升级为完整 `/cool` 工作流（写入 `workflow: full`、`phase: design`，然后加载 `cool-design`）；`REVIEW:` → 用 `cool/reference/review-checklist.md` G3 跑复核前置（产物 = 升级决定；上游 = tasks + diff），分级 pass/minor/material——若判定升级信号为**误报**（count 被工作流产物或无关提交膨胀，真实范围仍在 tweak 内），返回 `material` 且 `ISSUES` 标 `false-positive`；若信号真实，`pass` → append `cool-state review-log <name> tweak-upgrade 1 pass`，重跑 gate 取得 `PROCEED:`；`BLOCK:`（manual 模式，或真实范围超出的 material 升级）→ 用平台用户输入机制暂停等待用户明确决定。误报场景 escalate 时，须在正常升级确认之外额外呈现"误报确认 → 继续当前级别"选项。`decision_mode: manual` 下 gate 返回 `BLOCK`，manual 暂停行为保留。
2. verify 阶段（cool-verify）的验证失败和分支处理决策
3. 最终归档确认（cool-archive 运行归档脚本前）

执行顺序：快速 open → 轻量构建 → 轻量验证 → 归档 → 完成

每个阶段完成后立即进入下一阶段。每个阶段内，仍须按上述要求调用对应的 Cool/OpenSpec/Superpowers skill；如果被调用的 skill 有自己的用户决策点，按该 skill 的规则执行。
</IMPORTANT>

---

## 升级条件

**满足任一条件**时升级为完整 `/cool` 工作流：

| 条件 | 说明 |
|------|------|
| 改动涉及 **5+ 个文件**（排除 openspec/Superpowers 工作流产物、`.cool/**`、根级 `.cool.yaml`/`.openspec.yaml`、`docs/guide/**` 同步文件，以及 en/zh SKILL.md 同步对；运行 `"$COOL_BASH" "$COOL_STATE" count-upgrade-files <name>` 取计数） | 超出小改动范围 |
| 需要跨模块协调 | 需要跨组件协调改动 |
| 需要新增 **5+** 个测试用例 | 改动复杂度上升 |
| 涉及配置项的新增或删除 | 超出值修改范围的配置变更 |
| 需要新增能力 | 超出局部优化 |
| 需要 delta spec | 影响了已有规格 |

满足升级条件时，运行 `"$COOL_BASH" "$COOL_STATE" gate <name> tweak-upgrade` 并按其指令办：`PROCEED:` → 自动升级为完整 `/cool` 工作流（写入 `workflow: full`、`phase: design`，然后加载 `cool-design`）；`REVIEW:` → 用 `cool/reference/review-checklist.md` G3 跑复核前置（产物 = 升级决定；上游 = tasks + diff）——若信号为**误报**（见 G3 rubric），返回 `material` 且 `ISSUES` 标 `false-positive`，escalate 时额外呈现"误报确认 → 继续当前级别"选项；若信号真实，`pass` → append `cool-state review-log <name> tweak-upgrade 1 pass`，重跑 gate 取得 `PROCEED:`；`BLOCK:`（manual 模式，或真实范围超出的 material 升级）→ 用平台用户输入机制暂停等待用户明确决定。不得直接进入 `/cool-design`，也不得自动补充 Design Doc。`decision_mode: manual` 下 gate 返回 `BLOCK`，manual 暂停行为保留。若当前平台没有结构化提问工具，则在对话中提出升级确认问题（适用时含误报选项）并停止流程，等待用户回复后才能继续。

用户确认升级后，**必须先更新 workflow 和 phase 字段**再进入完整流程：

```bash
"$COOL_BASH" "$COOL_STATE" set <name> workflow full
"$COOL_BASH" "$COOL_STATE" set <name> phase design
```

然后在当前 change 基础上补充 Design Doc：**立即使用 Skill 工具加载 `cool-design` 技能**，按完整工作流正常推进。

如果用户不确认升级，按原因分两路处理：
- **升级信号真实、用户仍拒绝升级** → 停止 tweak 并报告当前 change 已超出 tweak 范围。
- **升级信号为误报、用户选择"确认误报 → 继续当前级别"**（见上方"升级条件"节 `REVIEW:` 处理）→ 不停止、不升级，从中断处继续当前 tweak 工作流（回到 Step 2 轻量构建）。

---

## 退出条件

- 小改动已完成，测试通过
- Change 已归档
- 无新增能力、架构调整或接口变更
- **阶段守卫**：build → verify 前运行 `"$COOL_BASH" "$COOL_GUARD" <change-name> build --apply`；verify → archive 前按 `/cool-verify` 规则运行 `"$COOL_BASH" "$COOL_GUARD" <change-name> verify --apply`

## 自动衔接下一阶段

每次阶段守卫或状态转换推进 phase 后，运行：

```bash
"$COOL_BASH" "$COOL_STATE" next <name>
```

脚本根据 `phase`、`workflow`、`auto_transition` 输出确定性的下一步：
- `NEXT: auto` → 调用 `SKILL` 指向的 skill 继续 tweak 流程（`phase: build` 返回 `cool-tweak`，`verify` 返回 `cool-verify`，`archive` 返回 `cool-archive`）
- `NEXT: manual` → 不要调用下一 skill，按 `HINT` 提示用户手动运行 `/<SKILL>`
- `NEXT: done` → 流程已完成，无需继续
