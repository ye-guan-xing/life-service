---
name: cool-hotfix
description: "Cool 预设路径：Bug 修复 / 热修复。跳过 brainstorming，直接 open → build → review(light) → verify → archive。适用于不涉及新能力设计的行为修复场景。"
---

# Cool 预设路径：Hotfix

快速 bug 修复工作流：open → build → review(light) → verify → archive。跳过 brainstorming 和完整计划，适用于不涉及新能力设计的行为修复场景。

**适用条件**（全部满足）：
1. 修复现有功能的 bug，无新增能力
2. 无接口变更或架构调整
3. 改动范围可预期（通常 ≤ 2 个文件）

**不适用**：如果修复过程中发现需要架构调整，应升级为完整 `/cool` 工作流。

---

## 流程（预设工作流，5 个步骤）

### 0. 输出语言约束

精简的 OpenSpec 产物必须使用触发本次工作流的用户请求语言。

执行链：open → build → 根因确认 → review(light) → verify → archive。hotfix 为每个阶段提供默认决策：精简 open、直接 build、根因确认、按规模验证，以及验证通过后的最终归档确认。

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

复用 Cool open 能力创建 change，但使用 hotfix 默认值：不执行 `openspec-explore` 长时间探索，直接进入精简 change 创建。

**立即执行：** 使用 Skill 工具加载 `openspec-new-change` 技能。禁止跳过此步骤。

技能加载后，按其指引创建精简产物：
- `proposal.md` — 问题描述 + 根因分析 + 修复目标（无需方案对比）
- `design.md` — 修复方案（一个即可，无需多方案对比）
- `tasks.md` — 修复任务列表
- **无需 delta spec**（除非修复改变了现有 spec 验收场景）

初始化 Cool 状态文件：

```bash
"$COOL_BASH" "$COOL_STATE" init <name> hotfix
```

写任何 artifacts 前先切到 feature 分支——保护分支不得承载 change 产物（同 `/cool-open` step 2 规则）。读取 `protected_branches`；当前分支是保护分支时，用平台用户输入机制确认分支名（推荐 `hotfix/YYYYMMDD/<name>`）后 `"$COOL_BASH" "$COOL_STATE" open-branch <name> --branch <NAME>`；否则 `"$COOL_BASH" "$COOL_STATE" open-branch <name>` 沿用当前分支。`open-branch` 记录 `base_branch`/`open_branch` 并按需切分支。

验证初始化状态：

```bash
"$COOL_BASH" "$COOL_STATE" check <name> open
```

运行阶段守卫，过渡 open → build：

```bash
"$COOL_BASH" "$COOL_GUARD" <change-name> open --apply
```

检查 `auto_transition` 决定是否继续：

```bash
"$COOL_BASH" "$COOL_STATE" next <name>
```

- `NEXT: auto` → 继续 Step 2
- `NEXT: manual` → 暂停，按 `HINT` 提示用户手动运行 `/<SKILL>`

### 2. 直接构建（preset build）

使用 hotfix 默认值：`build_mode: direct`。跳过 Superpowers `brainstorming` 和 `writing-plans`（除非任务数 > 3；如超过 3 个任务，转到 `/cool-build` 的计划和执行方式选择——注意这不触发完整工作流升级，只是切换执行方式）。

继续或开始改动前，按 `cool/reference/dirty-worktree.md` 处理未提交改动。如果归因显示修复范围超出 hotfix，按本文件"升级条件"处理。

**立即执行：** 按 tasks.md 逐个执行任务：

1. 读取 `openspec/changes/<name>/tasks.md`，获取未完成任务列表
2. 对每个未完成任务：
   - 按任务描述修改代码
   - 运行项目格式化工具（如 `mvn spotless:apply`、`npm run format`）
   - 运行相关测试确认通过
   - 将 tasks.md 中对应的 `- [ ]` 勾选为 `- [x]`
   - 提交代码，commit message 格式：`fix: <简洁修复描述>`
3. 所有任务完成后，明确运行相关项目测试和构建命令

**如果修复影响现有 spec 验收场景**：
- 在 `openspec/changes/<name>/specs/<capability>/spec.md` 创建 delta spec
- 只包含 `## MODIFIED Requirements` 节

hotfix 执行过程中，每当运行程序、测试、构建或手动验证时出现崩溃、异常行为、测试失败或构建失败，必须使用 Skill 工具加载 Superpowers `systematic-debugging` 技能。根因定位完成前，不得提出或实施源码修复。

按四阶段 `systematic-debugging` 流程处理：
- 首先复现并定位根因，读取完整错误信息，检查近期改动，追踪数据流
- 如果根因指向源码 bug，先添加一个能复现崩溃或异常行为的最小失败测试，再修改源码
- 修复后，运行该失败测试、相关测试以及项目构建/验证命令，确认全部通过
- 将测试、源码修复和 tasks.md 勾选保留在当前 change 内；不得通过启动独立的"写测试用例" change 来替代当前 change 的验证循环

### 3. 根因消除确认

**在运行 build guard 前执行**，确保修复确实消除了根因：

1. 读取 proposal.md 中的 bug 描述和根因
2. 搜索并验证问题代码已不再存在
3. 如果根因未消除，回到 Step 2 继续修复（仍在 build 阶段，无需状态转换）

**升级条件**：
- 根因确认发现深层架构问题 → 停止 hotfix，按"升级条件"处理
- 修复需要额外接口变更 → 停止 hotfix，按"升级条件"处理

根因确认已消除后，运行阶段守卫过渡 build → review：

```bash
"$COOL_BASH" "$COOL_GUARD" <change-name> build --apply
```

状态自动更新为 `phase: review`，`review_result: pending`，然后进入审查。

### 4. 规格合规审查（preset review - light）

复用 `/cool-review`，使用 `review_mode: light`（仅 Phase 1 规格合规审查）。

**立即执行：** 使用 Skill 工具加载 `cool-review` 技能。禁止跳过此步骤。

hotfix 的 `review_mode` 初始化为 `light`，`cool-review` 会自动执行规格合规审查，跳过代码质量审查。

审查通过后，按 `/cool-review` 规则记录 `.cool.yaml` `review_result` 为 `pass`，进入验证。

### 5. 验证（preset verify）

复用 `/cool-verify`，由 cool-verify 的规模评估决定轻量或完整验证。

**立即执行：** 使用 Skill 工具加载 `cool-verify` 技能。禁止跳过此步骤。

无 delta spec 的小规模 hotfix 通常满足轻量验证条件（≤ 3 个任务、≤ 2 个文件），cool-verify 的规模评估会选择轻量验证路径（5 项快速检查）。如果 hotfix 创建了 delta spec，按 cool-verify 的规模评估规则进入完整验证路径。

验证通过后，按 `/cool-verify` 规则将 `.cool.yaml` `verify_result` 记录为 `pass`，归档前不得跳过此状态。验证通过后，仍需进入 `/cool-archive` 的最终归档确认；不要自动运行归档脚本。

### 6. 归档（preset archive）

复用 `/cool-archive`。归档前 `.cool.yaml` 必须满足 `verify_result: pass`，并等待 `/cool-archive` 的最终归档确认。

**立即执行：** 使用 Skill 工具加载 `cool-archive` 技能进行归档。禁止跳过此步骤。
如果有 delta spec，按 cool-archive 规则同步到 main spec，并处理关联 Design Doc 和 Plan 的归档标注。

---

## 连续执行模式

<IMPORTANT>
hotfix 工作流是**一次性连续执行**。调用 `/cool-hotfix` 后，agent 必须自动推进 hotfix 各步骤，中途不得暂停等待用户输入。

例外：当 `.cool.yaml` 中 `auto_transition: false` 时，每次阶段守卫推进 `phase` 后，不自动调用下一个 skill。此时使用 `"$COOL_BASH" "$COOL_STATE" next <name>` 输出，按指示暂停等待手动继续。

以下情况也必须暂停等待用户确认：

1. 遇到升级条件（见"升级条件"节）。这是 recommend 模式决策点 `hotfix-upgrade`（auto-after-review）。运行 `"$COOL_BASH" "$COOL_STATE" gate <name> hotfix-upgrade` 并按其指令办：`PROCEED:` → 自动升级为完整 `/cool` 工作流（写入 `workflow: full`、`phase: design`，然后加载 `cool-design`）；`REVIEW:` → 用 `cool/reference/review-checklist.md` G3 跑复核前置（产物 = 升级决定；上游 = tasks + diff），分级 pass/minor/material——若判定升级信号为**误报**（count 被工作流产物或无关提交膨胀，真实范围仍在 hotfix 内），返回 `material` 且 `ISSUES` 标 `false-positive`；若信号真实，`pass` → append `cool-state review-log <name> hotfix-upgrade 1 pass`，重跑 gate 取得 `PROCEED:`；`BLOCK:`（manual 模式，或真实范围超出的 material 升级）→ 用平台用户输入机制暂停等待用户明确决定。误报场景 escalate 时，须在正常升级确认之外额外呈现"误报确认 → 继续当前级别"选项。`decision_mode: manual` 下 gate 返回 `BLOCK`，manual 暂停行为保留。
2. 任务数超过 3 个时转到 `/cool-build` 的工作区隔离和执行方式选择
3. verify 阶段（cool-verify）的验证失败和分支处理决策
4. 最终归档确认（cool-archive 运行归档脚本前）

执行顺序：快速 open → 直接 build → 根因确认 → review(light) → 验证 → 归档 → 完成

每步完成后立即进入下一步。每个阶段内，仍须按上述要求调用对应的 Cool/OpenSpec/Superpowers skill；如果被调用的 skill 有自己的用户决策点，按该 skill 的规则执行。
</IMPORTANT>

---

## 升级条件

**满足任一条件**时升级为完整 `/cool` 工作流：

| 条件 | 说明 |
|------|------|
| 改动涉及 **3+ 个文件**（排除 openspec/Superpowers 工作流产物、`.cool/**`、根级 `.cool.yaml`/`.openspec.yaml`、`docs/guide/**` 同步文件，以及 en/zh SKILL.md 同步对；运行 `"$COOL_BASH" "$COOL_STATE" count-upgrade-files <name>` 取计数） | 超出单点修复范围 |
| 涉及架构变更 | 新模块、新接口、新依赖 |
| 涉及数据库 schema 变更 | 结构性调整 |
| 引入新的 public API | 修复创建了新的外部接口 |
| 修复范围超出单一函数/模块 | 需要协调多处改动 |

满足升级条件时，运行 `"$COOL_BASH" "$COOL_STATE" gate <name> hotfix-upgrade` 并按其指令办：`PROCEED:` → 自动升级为完整 `/cool` 工作流（写入 `workflow: full`、`phase: design`，然后加载 `cool-design`）；`REVIEW:` → 用 `cool/reference/review-checklist.md` G3 跑复核前置（产物 = 升级决定；上游 = tasks + diff）——若信号为**误报**（见 G3 rubric），返回 `material` 且 `ISSUES` 标 `false-positive`，escalate 时额外呈现"误报确认 → 继续当前级别"选项；若信号真实，`pass` → append `cool-state review-log <name> hotfix-upgrade 1 pass`，重跑 gate 取得 `PROCEED:`；`BLOCK:`（manual 模式，或真实范围超出的 material 升级）→ 用平台用户输入机制暂停等待用户明确决定。不得直接进入 `/cool-design`，也不得自动补充 Design Doc。`decision_mode: manual` 下 gate 返回 `BLOCK`，manual 暂停行为保留。若当前平台没有结构化提问工具，则在对话中提出升级确认问题（适用时含误报选项）并停止流程，等待用户回复后才能继续。

用户确认升级后，**必须先更新 workflow 和 phase 字段**再进入完整流程：

```bash
"$COOL_BASH" "$COOL_STATE" set <name> workflow full
"$COOL_BASH" "$COOL_STATE" set <name> phase design
```

然后在当前 change 基础上补充 Design Doc：**立即使用 Skill 工具加载 `cool-design` 技能**，按完整工作流正常推进。

如果用户不确认升级，按原因分两路处理：
- **升级信号真实、用户仍拒绝升级** → 停止 hotfix 并报告当前 change 已超出 hotfix 范围。
- **升级信号为误报、用户选择"确认误报 → 继续当前级别"**（见上方"升级条件"节 `REVIEW:` 处理）→ 不停止、不升级，从中断处继续当前 hotfix 工作流（回到 Step 3 根因确认 / Step 4 构建，取决于中断时所处步骤）。

---

## 退出条件

- Bug 已修复，测试通过
- Change 已归档
- 如有 spec 变更，已同步到 main spec
- **阶段守卫**：build → review 前运行 `"$COOL_BASH" "$COOL_GUARD" <change-name> build --apply`；review → verify 前按 `/cool-review` 规则运行 review 守卫；verify → archive 前按 `/cool-verify` 规则运行 `"$COOL_BASH" "$COOL_GUARD" <change-name> verify --apply`

## 自动衔接下一阶段

每次阶段守卫或状态转换推进 phase 后，运行：

```bash
"$COOL_BASH" "$COOL_STATE" next <name>
```

脚本根据 `phase`、`workflow`、`auto_transition` 输出确定性的下一步：
- `NEXT: auto` → 调用 `SKILL` 指向的 skill 继续 hotfix 流程（`phase: build` 返回 `cool-hotfix`，`review` 返回 `cool-review`，`verify` 返回 `cool-verify`，`archive` 返回 `cool-archive`）
- `NEXT: manual` → 不要调用下一 skill，按 `HINT` 提示用户手动运行 `/<SKILL>`
- `NEXT: done` → 流程已完成，无需继续
