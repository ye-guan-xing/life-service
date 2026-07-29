---
name: cool-build
description: "Cool 阶段 3：计划与构建。使用 /cool-build 调用。创建实施计划并选择执行方式（子代理或直接执行）进行实现。"
---

# Cool 阶段 3：计划与构建（Build）

## 前置条件

- Design Doc 已创建（阶段 2 完成）
- 活跃 change 存在

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
"$COOL_BASH" "$COOL_STATE" check <name> build
```

验证通过后继续 Step 1。验证失败时脚本会输出具体失败原因。

**幂等性**：所有 build 阶段操作可以安全重试。读取 `.cool.yaml` `phase` 字段确认仍在 build，读取 plan 头部 `base-ref`，然后用 `grep -n '\- \[ \]' tasks.md | head -1` 找到第一个未勾选任务。已提交的任务不得重复提交。

### 1. 创建计划（子代理分载）

通过子代理创建实施计划，避免 planning skill 占用主 session 上下文。计划文件和执行反馈必须使用触发本次工作流的用户请求语言。

**子代理指令**：

你是实施计划专家。基于以下输入创建实施计划：

1. **立即执行：** 使用 Skill 工具加载 Superpowers `writing-plans` 技能。禁止跳过此步骤。加载后 ARGUMENTS 必须包含：`Language: 使用触发本次工作流的用户请求语言输出`
2. 读取 Design Doc（`docs/superpowers/specs/` 下的技术设计文档）
3. 读取 `openspec/changes/<name>/tasks.md`（任务边界）
4. 按技能指引创建计划

计划要求：
- 保存到 `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`
- 参考设计文档，拆解为可执行任务
- **计划文件头必须包含关联元数据**：

```yaml
---
change: <openspec-change-name>
design-doc: docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md
base-ref: <创建计划前的 git rev-parse HEAD>
---
```

`base-ref` 用于验证阶段计算完整实现范围内的提交改动。创建计划时记录当前 commit：

```bash
git rev-parse HEAD
```

记录 `base-ref` 后，在 plan 文件的 frontmatter `---` 结束符之后、任务分解之前，紧接着加入 **Source Coverage** 表。先在脑中完成任务分解草稿，再用确定的任务编号填写表格：

```markdown
## Source Coverage

| Scenario | Plan 任务 |
|----------|-----------|
| <来自 delta spec 的 Scenario 描述> | Task N |
```

读取 delta spec（`openspec/changes/<name>/specs/**/*.md`），将每条 `#### Scenario:` 条目映射到对应的 Plan 任务编号。如果一个 Scenario 跨越多个任务，用逗号分隔任务编号（例如 `Task 2, Task 3`）。如果 delta spec 没有 `#### Scenario:` 条目，写一行：`| （delta spec 未定义 Scenario）| — |`。

将计划写入文件后返回文件路径。

**执行子代理**：使用当前平台的子代理调度机制发送上述任务。

子代理完成后：
- 如果返回有效文件路径且文件存在，将其记录为 plan
- 如果子代理失败或返回无效路径，回退到在主 session 中内联加载 Superpowers `writing-plans` 技能（降级兜底）

### 2. 更新计划状态并提供 Plan-Ready 暂停点

#### recommend 模式决策闸门（plan-ready）

当 `decision_mode: recommend` 且 plan 就绪时，运行 gate 并按其指令办：

```bash
DM=$("$COOL_BASH" "$COOL_STATE" gate <name> plan-ready)
```

- `BLOCK:`（manual 模式，或 material 升级）→ 走原 plan-ready 阻塞选择（下方 A/B）。
- `REVIEW:`（auto-after-review，尚未通过）→ 用 `cool/reference/review-checklist.md` 通用节复核（产物 = plan；上游 = design doc + tasks.md）。`subagent_dispatch: confirmed` 时派后台 subagent，否则主 agent 自检。分级 pass/minor/material：
  - `pass` → `cool-state review-log <name> plan-ready 1 pass [issue]`（设 `COOL_REVIEW_BY=subagent|self` 与派发路径一致），再运行 `cool-state gate <name> plan-ready` 取得 `PROCEED:`，然后按规模自主选择执行方式（跳过 manual A/B 暂停）。
  - `minor` → 内联修 plan 1 次 → 再复核 1 次（round 2）；round 2 `pass` → `review-log ... 2 pass`，重跑 gate 取得 `PROCEED:` 后自主选择；round 2 非 pass → 升级用户（落入 A/B）。
  - `material` → 软阻塞，surface 用户选择（补 design / 拆 change / 接受），**不自动大改**。
- `PROCEED:`（auto-after-review 已通过）→ 按规模自主选择执行方式（跳过 manual A/B 暂停）。

记录 plan 路径：

```bash
"$COOL_BASH" "$COOL_STATE" set <name> plan docs/superpowers/plans/YYYY-MM-DD-feature.md
```

plan 写入后，用 `cool-state abspath` 输出绝对路径告知用户：

```bash
ABS=$("$COOL_BASH" "$COOL_STATE" abspath docs/superpowers/plans/YYYY-MM-DD-<feature>.md)
echo "实施计划已写入：$ABS"
```

无需手动更新 phase——guard 在退出条件满足时自动过渡。

计划记录后，立即提供一个用户决策点：

| 选项 | 行为 | 说明 |
|------|------|------|
| A | 继续执行 | 保持当前模型，进入 Step 3 选择工作区隔离和执行方式 |
| B | 暂停切换模型 | 记录 `build_pause: plan-ready`，停止本次 `/cool-build` 调用，用户稍后从 `/cool` 或 `/cool-build` 恢复 |

这是 recommend 模式决策点 `plan-ready`（auto-after-review）。运行 `"$COOL_BASH" "$COOL_STATE" gate <name> plan-ready` 并按其指令办：`PROCEED:` → 自动继续进入 Step 3（不询问，不写入 `build_pause`）；`REVIEW:` → 跑复核前置（产物 = plan；上游 = design doc + tasks.md），pass 后 append `cool-state review-log <name> plan-ready 1 pass`，重跑 gate 取得 `PROCEED:`；`BLOCK:` → 用平台用户输入机制暂停等待用户明确选择 A/B。不得把 pause 写入 `build_mode`。`decision_mode: manual` 下 gate 返回 `BLOCK`，manual 暂停行为保留。

用户选择继续时：

```bash
"$COOL_BASH" "$COOL_STATE" set <name> build_pause null
```

用户选择暂停时：

```bash
"$COOL_BASH" "$COOL_STATE" set <name> build_pause plan-ready
```

设置 `build_pause: plan-ready` 后停止当前调用，不选择 `isolation` 或 `build_mode`，不加载执行技能。

### 3. 选择工作流配置

如果恢复时 `build_pause: plan-ready` 且 `plan` 文件存在，不要重新运行 `writing-plans`。先告知用户工作流停在 plan-ready 暂停点；用户确认继续后，设置：

```bash
"$COOL_BASH" "$COOL_STATE" set <name> build_pause null
```

然后继续本步骤选择工作区隔离和执行方式。

计划已写入当前分支。开始执行前，**在单次交互中同时询问用户选择工作区隔离方式、执行方式和 TDD 模式**：

**工作区隔离**：

| 选项 | 方式 | 说明 |
|------|------|------|
| A | 创建分支 | 在当前 repo 创建新分支，简单快速 |
| B | 创建 Worktree | 隔离工作区，完全独立，适合并行开发 |

**推荐规则**：
- 改动 ≤ 3 个文件 → 推荐 A
- 需要并行开发，当前分支有未提交工作 → 推荐 B

**执行方式**：

| 选项 | 技能 | 适用场景 |
|------|------|---------|
| A | Superpowers `subagent-driven-development` | 任务相互独立、复杂度高、需要两阶段审查 |
| B | Superpowers `executing-plans` | 任务简单、无子代理环境、轻量快速 |

**推荐规则**：
- 任务数 ≥ 3 → 推荐 A
- 任务数 ≤ 2 且无跨模块依赖 → 推荐 B
- 来自 hotfix 路径 → 推荐 B

这是 recommend 模式决策点 `build-config`（auto-after-review）。运行 `"$COOL_BASH" "$COOL_STATE" gate <name> build-config` 并按其指令办：`PROCEED:` → 按规模自主选择 isolation/build_mode/tdd_mode（不询问）；`REVIEW:` → 跑复核前置（产物 = build-config 选择；上游 = plan + tasks.md），pass 后 append `cool-state review-log <name> build-config 1 pass`，重跑 gate 取得 `PROCEED:`；`BLOCK:` → 用平台用户输入机制暂停等待用户明确选择隔离方式、执行方式和 TDD 模式。`decision_mode: manual` 下所有点 gate 返回 `BLOCK`，manual 暂停行为保留。推荐规则仅供参考，不得代替用户确认。

用户选择后，更新 `isolation`、执行方式和 TDD 模式字段：

```bash
"$COOL_BASH" "$COOL_STATE" set <name> isolation <branch|worktree>
```

- 用户选择 `executing-plans`：运行 `"$COOL_BASH" "$COOL_STATE" set <name> subagent_dispatch null`，然后运行 `"$COOL_BASH" "$COOL_STATE" set <name> build_mode executing-plans`
- 用户选择 `subagent-driven-development`：先确认当前平台具备真实后台 subagent / Task / multi-agent 调度能力；确认后运行 `"$COOL_BASH" "$COOL_STATE" set <name> subagent_dispatch confirmed`，然后运行 `"$COOL_BASH" "$COOL_STATE" set <name> build_mode subagent-driven-development`
- 如无法确认真实后台调度能力，不得写入 `build_mode: subagent-driven-development`。这是 recommend 模式决策点 `subagent-dispatch`（auto）。运行 `"$COOL_BASH" "$COOL_STATE" gate <name> subagent-dispatch` 并按其指令办：`PROCEED:` → 自动降级到 `executing-plans`（不询问）；`BLOCK:` → 暂停等待用户选择 `executing-plans`。

**TDD 模式**：

| 选项 | 含义 | 适用场景 |
|------|------|---------|
| `tdd` | 每个任务先写失败测试，再实现 | 推荐。涉及业务逻辑、新功能、API 的改动 |
| `direct` | 直接实现，不强制 TDD 流程 | 不需要测试覆盖的改动，或用户选择跳过 TDD。hotfix/tweak preset 默认 `direct` |

运行 `"$COOL_BASH" "$COOL_STATE" set <name> tdd_mode <tdd|direct>`

`isolation` 是脚本强制约束。full workflow 初始化时可以暂时为 `null`，但只允许持续到本步骤前。如果仍为 `null`，`build → review/verify` 守卫和 `cool-state transition build-complete` 都会失败。

**执行隔离**：

- **branch**：先读 `.cool.yaml` 的 `open_branch`：
  - 若 `open_branch` 已记录（非 null）——/cool-open 已切到或沿用非保护 feature 分支——**复用当前分支**：跳过分支名确认、跳过 `git checkout -b`、跳过 `set base_branch`（已由 open-branch 记录）。向用户说明后进入「创建隔离后」。
  - 若 `open_branch` 为空/null（边缘：open 未切分支）——走下方原分支逻辑（仅此情况）。

  原分支逻辑（仅当 `open_branch` 为空时）：根据 workflow 类型和当前日期推荐分支名。这是 recommend 模式决策点 `branch-name`（auto）。运行 `"$COOL_BASH" "$COOL_STATE" gate <name> branch-name` 并按其指令办：`PROCEED:` → 直接使用推荐分支名（不询问）；`BLOCK:`（manual 模式）→ 用平台用户输入机制暂停等待用户确认或覆盖分支名。注：`open_branch` 已记录时整体跳过（复用当前分支）。gate 返回 `BLOCK:` 时不得跳过此步直接创建分支。

  分支命名约定：
  - 读 `.cool.yaml` 的 `workflow` 字段确定前缀
  - `workflow: full` → 推荐 `feature/YYYYMMDD/<change-name>`
  - `workflow: hotfix` → 推荐 `hotfix/YYYYMMDD/<change-name>`
  - `workflow: tweak` → 推荐 `tweak/YYYYMMDD/<change-name>`
  - 日期在运行时由 `date +%Y%m%d` 得出

  示例：change 名为 `fix-login-bug`、今天 2026-06-09 时，推荐 `feature/20260609/fix-login-bug`

  用户确认或提供自定义分支名后，**在 `git checkout -b` 之前**记录父分支（当前所在分支，如 `feature-build`），随后才切出新分支：

  ```bash
  BASE_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  "$COOL_BASH" "$COOL_STATE" set <name> base_branch "$BASE_BRANCH"
  "$COOL_BASH" "$COOL_STATE" set <name> open_branch <branch-name>
  git checkout -b <branch-name>
  ```

  worktree 模式同理：在 `git worktree add` 之前把主仓库当前分支名记到 `base_branch`（覆盖）。`base_branch` 供 verify 阶段优先合并回父分支使用。

- **worktree**：必须使用 Skill 工具加载 Superpowers `using-git-worktrees` 技能创建隔离工作区。不得用普通 shell 命令或原生工具绕过；技能不可用时停止流程并提示安装 Superpowers 技能。

创建隔离后，确认 plan 文件可访问（branch 方式天然可访问；worktree 方式需确认 plan 已提交）。如果 plan 文件尚未提交，先提交：

```bash
git add docs/superpowers/plans/YYYY-MM-DD-feature.md
git commit -m "chore: add implementation plan"
```

**执行计划**：必须按 `build_mode` 的实际运行时值处理执行。

- `build_mode: executing-plans`：**立即执行：** 使用 Skill 工具加载 Superpowers `executing-plans` 技能。禁止跳过此步骤。技能不可用时停止流程并提示安装对应 skill，不要用普通对话替代。技能加载后 ARGUMENTS 必须包含与 Step 1 相同的语言约束：`Language: 使用触发本次工作流的用户请求语言输出`。按计划执行。
- `build_mode: subagent-driven-development`：主窗口只做协调；不得在主窗口直接运行 `subagent-driven-development` 执行技能。必须使用已确认的真实后台 subagent / Task / multi-agent 调度能力将下一个未勾选任务派发到后台子代理。派发每个子代理时，prompt 必须明确要求：技能加载后 ARGUMENTS 包含与 Step 1 相同的语言约束；任务完成并验证后，立即在 `docs/superpowers/plans/<plan-file>.md` 中勾选对应计划任务；如果该计划任务映射到 `openspec/changes/<name>/tasks.md` 中的条目，也将对应 OpenSpec 任务从 `- [ ]` 改为 `- [x]`；如果计划新增了 OpenSpec 中不存在的步骤，只需勾选对应计划任务。不得只更新内置 Todo 或聊天中的清单。后台子代理自行加载 Superpowers `subagent-driven-development` 执行流程并遵循其指引进行实现、审查和提交。
- 如果当前平台没有真实后台子代理 / Task / multi-agent 调度能力，这是 recommend 模式决策点 `platform-capability`（auto）。能力降级时运行 `"$COOL_BASH" "$COOL_STATE" gate <name> platform-capability` 并按其指令办：`PROCEED:` → 自动记录降级路径（运行 `"$COOL_BASH" "$COOL_STATE" set <name> build_mode executing-plans`，然后按 `build_mode: executing-plans` 分支加载 Superpowers `executing-plans` 技能；不询问）；`BLOCK:` → 暂停等待用户选择主窗口执行。gate 返回 `PROCEED:` 或用户明确选择前不得继续执行任务。

执行开始后，按选择的分支完成：
- 按计划执行任务
- 勾选对应的 Superpowers 计划任务；如任务映射到 OpenSpec tasks.md，同时勾选对应 OpenSpec 任务（`- [ ]` → `- [x]`）
- 每个任务完成后提交代码

**TDD 模式执行约束**：

如果 `tdd_mode: tdd`：
- `build_mode: executing-plans`：加载执行技能并在执行第一个任务之前，**立即执行：** 使用 Skill 工具加载 Superpowers `test-driven-development` 技能一次。禁止跳过此步骤。技能加载后，从第一个未勾选任务开始，按已加载的 TDD 红绿重构循环执行每个任务。不得跳过失败测试验证阶段。后续任务不需要重新加载此技能；按已加载的流程继续。如果上下文压缩后恢复，重新运行本步骤加载 TDD 技能一次，然后从第一个未勾选任务继续。
- `build_mode: subagent-driven-development`：派发每个子代理时，必须在 prompt 中注入 TDD 强制约束：**"你必须遵循 TDD：对每个任务，先写一个失败测试，看到它失败，再写最小代码使其通过。没有失败测试不得写生产代码。"**。同一 prompt 还必须包含上述 OpenSpec tasks.md 和 Superpowers 计划持续勾选要求。不得依赖 implementer-prompt.md 的条件触发；必须在派发 prompt 中明确写出。

如果 `tdd_mode: direct`：按正常流程，不强制 TDD。

### 3b. 执行中调试（Debug Gate）

执行任务过程中，每当运行程序、测试、构建或手动验证时出现崩溃、异常行为、测试失败或构建失败，必须使用 Skill 工具加载 Superpowers `systematic-debugging` 技能。根因定位完成前，不得提出或实施源码修复。

按四阶段 `systematic-debugging` 流程处理：
- 首先复现并定位根因，读取完整错误信息，检查近期改动，追踪数据流
- 如果根因指向源码 bug，先添加一个能复现崩溃或异常行为的最小失败测试，再修改源码
- 修复后，运行该失败测试、相关测试以及项目构建/验证命令，确认全部通过
- 将测试、源码修复和 tasks.md 勾选保留在当前 change 内；不得通过启动独立的"写测试用例" change 来替代当前 change 的验证循环

### 4. Spec 增量更新

#### recommend 模式决策闸门（scope-split-review）

当 `decision_mode: recommend` 且检测到中改/大改或 50% 阈值拆分时，运行 gate 并按其指令办：

```bash
DM=$("$COOL_BASH" "$COOL_STATE" gate <name> scope-split-review)
```

- `BLOCK:`（manual 模式，或 material 升级）→ 走原阻塞确认。
- `REVIEW:`（auto-after-review，尚未通过）→ 用 `cool/reference/review-checklist.md` 通用节复核拆分/升级决定（产物 = 拟拆分/升级方案；上游 = 当前 design + tasks）。`subagent_dispatch: confirmed` 时派后台 subagent，否则主 agent 自检。按 pass/minor/material 处理；`pass` 时重跑 `cool-state gate <name> scope-split-review` 取得 `PROCEED:`；`material` 时升级用户（不自主拆分）。append `cool-state review-log <name> scope-split-review <round> <result> [issue]`（设 `COOL_REVIEW_BY` 与派发路径一致）。
- `PROCEED:`（auto-after-review 已通过）→ 按拆分/升级决定推进（不询问）。

实现过程中发现初始 spec 不完整时，按规模处理：

| 规模 | 触发条件 | 处理方式 |
|------|---------|---------|
| 小改 | 缺少验收场景、边界条件 | 直接编辑 delta spec + design.md，在 tasks.md 追加任务 |
| 中改 | 接口变更、新增组件、数据流变化 | **必须暂停等待用户明确确认**，然后必须使用 Skill 工具加载 Superpowers `brainstorming` 技能更新 Design Doc + delta spec；**Design Doc 和 delta spec 文件必须完全写入完成后，才能继续代码实现** — 禁止在 spec 更新过程中同时修改代码 |
| 大改 | 全新 capability 需求 | **必须暂停等待用户明确确认是否拆分**；用户确认后，通过 `/cool-open` 创建独立 change；**仅在新 change 的 open 阶段完成后，才能继续当前 change 的代码实现** — 禁止在新 change open 完成前为其范围写代码 |

**50% 阈值判断**：以 tasks.md 初始任务数为基准，如果新增任务超过该总数的一半，视为超出原有计划范围，**必须暂停等待用户决定是否拆分为新 change**。

创建独立 change 时，必须调用 `/cool-open`，不得直接调用 `/opsx:new`。

**用户选择必须包含**：
- 「拆分为新 change」— 通过 `/cool-open` 创建独立 change
- 「在当前 change 中继续」— 记录范围扩展决策，更新 tasks.md 和 delta spec，然后继续

**原则**：
- delta spec 是活文档，本阶段可随时修改
- 每次更新都应单独提交，commit message 说明变更原因
- 不要提前同步到 main spec，统一在归档时同步
- 小规模增量直接编辑 delta spec 时，在 commit message 中备注，便于归档时评估 design doc 漂移

### 5. 上下文管理

build 是最长的阶段，可能跨越多个任务。支持上下文压缩后恢复：

- **每个任务完成后**：立即勾选 Superpowers 计划中对应任务；如任务映射到 OpenSpec tasks.md，同时勾选对应 OpenSpec 任务；然后提交代码，使 `.cool.yaml` 和文件状态持久化。用 `grep -c '\- \[ \]' tasks.md` 检查剩余未勾选数量，无需重新读取整个文件
- **上下文压缩后**：先运行 `"$COOL_BASH" "$COOL_STATE" check <change-name> build --recover`——脚本输出结构化恢复上下文（isolation/build_mode 状态、plan 路径、任务进度、恢复动作）。按 Recovery action 判断下一步
- **长任务拆分**：如果单个任务的代码改动超过 200 行，考虑拆分为多个子任务和提交

## 退出条件

- tasks.md 全部勾选
- 代码已提交
- 项目专用构建/测试已明确运行并通过；不得仅依赖 guard 自动检测
- `isolation` 已写入 `branch` 或 `worktree`
- `build_mode` 已写入 `subagent-driven-development`、`executing-plans`，或带显式覆盖的 `direct`；如使用 `subagent-driven-development`，`subagent_dispatch` 必须是 `confirmed`
- `tdd_mode` 已写入 `tdd` 或 `direct`
- **阶段守卫**：运行 `"$COOL_BASH" "$COOL_GUARD" <change-name> build --apply`，全部 PASS 后守卫推进阶段（此步骤更新 `phase` 字段，与 `auto_transition` 无关）：
  - `review_mode: skip`（tweak）→ `phase: verify`
  - `review_mode: full/light` → `phase: review`

守卫优先读取项目命令配置：

```yaml
build_command: <构建命令>
verify_command: <验证命令>
```

配置可存放在 change 的 `.cool.yaml`，或仓库根目录的 `.cool.yaml` / `cool.yaml` / `.cool.yml` / `cool.yml`。
未配置命令时守卫才回退到 `npm run build`、Maven 或 Cargo 自动检测。命令失败时，守卫打印命令输出作为调试证据。

> **重要**：`finishing-a-development-branch` 是 build 阶段内的**中间步骤**，不是 build 阶段的终点。
> 分支处理（合并/PR/保留/丢弃）完成后，**必须回到 cool-build 主流程**，继续执行阶段守卫和 next 调用。
> 不得让 `finishing-a-development-branch` 的退出成为整个 build 阶段的终点。

退出前运行守卫自动过渡：

```bash
"$COOL_BASH" "$COOL_GUARD" <change-name> build --apply
```

状态文件自动更新：`review_mode: skip` → `phase: verify`；`review_mode: full/light` → `phase: review`。

## 自动衔接下一阶段

退出条件满足且守卫推进 phase 后，运行：

```bash
"$COOL_BASH" "$COOL_STATE" next <change-name>
```

脚本根据 `phase`、`workflow`、`auto_transition` 输出确定性的下一步：
- `NEXT: auto` → 调用 `SKILL` 指向的 skill 进入下一阶段
- `NEXT: manual` → 不要调用下一 skill，按 `HINT` 提示用户手动运行 `/<SKILL>`
- `NEXT: done` → 流程已完成，无需继续

> **扩展点：** `post-build` 与 `pre-review` hook 在 `cool-guard build --apply` transition 前触发。在 `.cool/config.yaml` 的 `extensions.hooks` 配置（见 cool SKILL.md § 阶段扩展点）。block 级 hook 会阻止 build→review 流转。
