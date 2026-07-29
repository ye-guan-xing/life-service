---
name: cool-open
description: "Cool 阶段 1：开启。使用 /cool-open 调用。通过 OpenSpec 探索想法，确认需求澄清，然后创建 change 结构（proposal + design + tasks）。"
---

# Cool 阶段 1：开启（Open）

## 前置条件

- 无活跃 change，或用户希望创建新 change

## 步骤

### 0. 输出语言约束

传递给 OpenSpec 的所有提问和产物要求都必须包含输出语言约束：使用触发本次工作流的用户请求语言。恢复已有 change 且产物已有明确主语言时，除非用户明确要求切换，否则保持该语言。

### 1. 探索想法与需求澄清

**立即执行：** 使用 Skill 工具加载 `openspec-explore` 技能。禁止跳过此步骤。

技能加载后，按其指引探索问题空间，但不得把一次问答视为足够澄清。必须围绕下列内容继续提问、对齐并形成澄清摘要：
- 目标：用户真正要解决的问题和期望结果
- 非目标：本次明确不做的内容
- 范围边界：涉及/不涉及的模块、用户、平台或数据
- 关键未知项：仍不确定的假设、风险或依赖
- 验收场景草案：至少覆盖核心成功场景和关键边界场景

澄清摘要必须包含：目标、非目标、范围边界、关键未知项、验收场景草案。

### 1a. PRD 拆分预检（阻塞点）

当用户输入是大型 PRD、路线图、完整产品方案，或澄清摘要显示包含多个独立能力、模块、用户路径或里程碑时，必须在创建 OpenSpec artifacts 前评估是否需要拆分为多个 change。

拆分预检必须基于已澄清的信息，输出候选拆分清单。每个候选拆分项必须包含：
- 建议 change 名称
- 目标与范围边界
- 明确非目标
- 依赖关系或推荐执行顺序
- 对应的核心验收场景

满足任一条件时，应推荐拆分：
- PRD 包含多个可独立设计、构建、验证、归档的 capability
- 涉及多个模块或用户路径，且其中一部分可独立交付
- 存在明显分阶段里程碑
- 预计会产生多个 delta spec 或超过 3 个大任务
- 任一部分失败或延期不应阻塞其他部分进入后续阶段

#### recommend 模式决策闸门（scope-split-review）

当 `decision_mode: recommend` 且推荐拆分时，运行 gate 并按其指令办：

```bash
DM=$("$COOL_BASH" "$COOL_STATE" gate <name> scope-split-review)
```

- `BLOCK:`（manual 模式，或 material 升级）→ 走下方原阻塞拆分确认。
- `REVIEW:`（auto-after-review，尚未通过）→ 用 `cool/reference/review-checklist.md` 通用节复核（产物 = 候选拆分清单；上游 = 澄清摘要）。`subagent_dispatch: confirmed` 时派后台 subagent，否则主 agent 自检。分级与处理流程同 `open-review`，append `cool-state review-log <name> scope-split-review <round> <result> [issue]`；`pass` 时重跑 `cool-state gate <name> scope-split-review` 取得 `PROCEED:`。`material` 时升级用户（不自主决定拆分）。
- `PROCEED:`（auto-after-review 已通过）→ 按拆分决定推进（不询问）。

如推荐拆分，必须使用当前平台可用的用户输入/确认机制暂停并等待用户选择。

用户选择必须包含：
- 「创建多个 OpenSpec changes」— 按候选拆分逐个创建独立 change
- 「保持为一个 change」— 继续单 change 流程，并在 proposal/design/tasks 中记录不拆分原因
- 「调整拆分方案后继续」— 用户说明调整方向后，重新输出候选拆分清单并再次确认

每个被接受的拆分项都必须通过 `/cool-open` 创建独立 change，不得直接调用 `/opsx:new`。

不得在用户完成 PRD 拆分选择前创建 proposal.md、design.md 或 tasks.md。

批量拆分模式下，单个拆分项完成 open 阶段后不得自动流转到 `/cool-design`。拆分完毕后：`decision_mode: recommend` 下，agent 按拆分清单的「依赖关系或推荐执行顺序」字段自主选取首项 change 推进 `/cool-design`（不询问），其余拆分项保持 active，稍后通过 `/cool` 恢复；`decision_mode: manual`（或 gate 返回 `BLOCK:`）下，必须暂停询问用户开始哪一个 change，用户选择后只推进该 change 进入 `/cool-design`，其他 change 保持 active，稍后通过 `/cool` 恢复。

### 1b. 需求澄清完成确认（阻塞点）

**生成 Decision Card**（clarify-review gate 前）：写入 `openspec/changes/<name>/.cool/handoff/decision-card.md`，含四字段：

- `write_mode`：`final-artifact` / `ask-owner` / `checkpoint` / `route-out` — 必须与当前澄清状态一致（未完成澄清时 SHALL NOT 取 `final-artifact`，取 `ask-owner` 或 `checkpoint`）
- `highest_risk_gap`：当前最大未决风险
- `next_action`：下一步动作
- `why_downstream_not_invent_what`：为什么 design/build 不会凭空发明需求

Decision Card 是 run-local 产物——SHALL NOT 写入 `.cool.yaml`，不引入新 phase enum 或 progress file。它作为 `clarify-review` 与 `open-review` 的复核输入。`clarify-review` checklist（C4）核对 Decision Card 已生成且 `write_mode` 与澄清状态一致。

**recommend 模式决策闸门**：暂停前运行 gate：

```bash
DM=$("$COOL_BASH" "$COOL_STATE" gate <name> clarify-review)
```

- `BLOCK:`（manual 模式，或 material 升级）→ 执行下文原始阻塞确认（展示澄清摘要，暂停等用户）。
- `REVIEW:`（auto-after-review，尚未通过）→ 用 `cool/reference/review-checklist.md` 的 open 专节（C1-C4）做复核前置（产物 = 澄清摘要；上游 = 用户需求 / 探索笔记）。`subagent_dispatch: confirmed` 时派后台 subagent，否则主 agent 自检。按 `pass` / `minor` / `material` 分级：
  - `pass` → 写 `cool-state review-log <name> clarify-review <round> pass`，重跑 `cool-state gate <name> clarify-review` 取得 `PROCEED:`，自主推进到 artifact 创建（不暂停）。
  - `minor` → 内联修澄清摘要 1 次，再复核 1 次（round 2）；round 2 `pass` → 写 log，重跑 gate 取得 `PROCEED:` 后自主推进；否则升级用户。
  - `material` → 软阻塞：向用户展示澄清摘要与缺失项（不自主推进）。surface 前必须写 `cool-state review-log <name> clarify-review <round> material "<issue>"`（`decision=escalated-to-user`）。
- `PROCEED:`（auto-after-review 已通过）→ 自主推进到 artifact 创建（不暂停）。

创建 OpenSpec artifacts 前，必须使用当前平台可用的用户输入/确认机制暂停并等待用户确认需求澄清完成。若当前平台没有结构化提问工具，则在对话中展示澄清摘要并提出确认问题，停止流程，等待用户回复后才能继续。

暂停时必须展示澄清摘要：目标、非目标、范围边界、关键未知项、验收场景草案。

不得在用户确认需求澄清完成前创建 proposal.md、design.md 或 tasks.md，也不得使用 Skill 工具加载 `openspec-propose` 技能一次性生成全部 artifacts。

### 2. 创建 Change 结构 + 初始化状态

**立即执行：** 使用 Skill 工具加载 `openspec-new-change` 技能。禁止跳过此步骤。

完整 `/cool` 流程默认不得使用 Skill 工具加载 `openspec-propose` 技能；只有用户明确要求一次性生成提案和 artifacts 时才允许加载。

技能加载后，按其指引创建 change 骨架，但当 Step 1b 的已确认澄清摘要已存在于对话上下文时，覆盖其"STOP and wait for user direction"行为。具体如下：

1. 按技能指引执行 `openspec new change`、`openspec status`、`openspec instructions`
2. 在写任何 artifacts 之前初始化 `.cool.yaml` 并切到 feature 分支——保护分支不得承载 change 产物：

```bash
COOL_ENV="${COOL_ENV:-$(find . "$HOME"/.*/skills "$HOME/.config" "$HOME/.gemini" -path '*/cool/scripts/cool-env.sh' -type f -print -quit 2>/dev/null)}"
if [ -z "$COOL_ENV" ]; then echo "ERROR: cool-env.sh not found. Ensure the cool skill is installed." >&2; return 1; fi
. "$COOL_ENV"
if [ -z "$COOL_STATE" ] || [ -z "$COOL_GUARD" ]; then echo "ERROR: Cool scripts not found. Ensure the cool skill is installed." >&2; return 1; fi

"$COOL_BASH" "$COOL_STATE" init <name> full
```

随后判定当前分支并应用分支处理（在保护分支上是用户决策点）：
- 读取 `protected_branches`（默认 `main master`）。取 `CUR_BRANCH=$(git rev-parse --abbrev-ref HEAD)`。
- 若 `CUR_BRANCH` 是保护分支：**分支名确认**——这是 recommend 模式决策点 `branch-name`（auto）。推荐 `feature/YYYYMMDD/<change-name>`（前缀按 `workflow` 字段 `feature|hotfix|tweak`，日期取 `date +%Y%m%d`）。运行 `"$COOL_BASH" "$COOL_STATE" gate <name> branch-name` 并按其指令办：`PROCEED:` → 直接用推荐分支名（不询问）；`BLOCK:`（manual 模式）→ 用平台用户输入机制暂停等待用户确认或覆盖分支名，不得跳过。确认后（或 PROCEED）：`"$COOL_BASH" "$COOL_STATE" open-branch <name> --branch <NAME>`——记录 `base_branch=<CUR_BRANCH>`（保护父分支）和 `open_branch=<NAME>`，随后执行 `git checkout -b <NAME>`。
- 若 `CUR_BRANCH` 非保护分支（已在 feature 分支，如 `feature-1.1.0` 这类 per-need 分支）：沿用——`"$COOL_BASH" "$COOL_STATE" open-branch <name>`——记录 `base_branch=null` 和 `open_branch=<CUR_BRANCH>`，不切分支。

此步完成后工作分支为非保护 feature 分支；`base_branch` 和 `open_branch` 已记录。change 骨架（来自 `openspec new change`）和 `.cool.yaml` 随工作区跟随到该分支——保护分支上不提交任何产物。

3. 如果用户已确认澄清摘要（Step 1b），直接使用该摘要起草 proposal.md —— 不得再要求用户重新描述变更内容
4. 如果不存在澄清摘要（边缘情况），回退到技能的默认行为，询问用户

然后逐个补齐 design.md、tasks.md；每个文档都必须基于已确认的澄清摘要。

**命名与范围守卫**：change name 命名按 `decision_mode` 分流：
- `recommend`：agent 基于已确认澄清摘要的主题自主生成 kebab-case slug（与 `branch-name` 推荐名同源，不新增 slug 生成函数），按 `openspec new change <slug>` → `cool-state init <slug> full` → `cool-state set <slug> decision_mode recommend` → `cool-state gate <slug> change-name` 时序推进。`gate` 返回 `PROCEED:` 时自主用该名（不询问）；返回 `BLOCK:`（manual 模式）时暂停让用户确认或覆盖名称。slug 冲突（`openspec/changes/<slug>/` 目录已存在）属真异常，fallback 询问用户，不得自主覆盖或自动追加后缀。
- `manual`：change name 必须使用用户指定或通过当前平台可用的用户输入/确认机制确认的名称，不得自动生成或推断。

变更范围必须与用户描述一致，不得自行扩大或缩小。

确认以下产物已创建：

```
openspec/changes/<name>/
├── .openspec.yaml
├── .cool.yaml
├── proposal.md       # Why + What：问题、目标、范围
├── design.md         # How（高层）：架构决策、方案选型
└── tasks.md          # 任务清单（勾选框）
```

`.cool.yaml` 已在步骤 2 中（分支处理前）初始化，勿重复 init。

三个产物创建后，用 `cool-state abspath` 输出绝对路径告知用户：

```bash
ABS=$("$COOL_BASH" "$COOL_STATE" abspath openspec/changes/<name>/proposal.md)
echo "proposal.md 已写入：$ABS"
ABS=$("$COOL_BASH" "$COOL_STATE" abspath openspec/changes/<name>/design.md)
echo "design.md 已写入：$ABS"
ABS=$("$COOL_BASH" "$COOL_STATE" abspath openspec/changes/<name>/tasks.md)
echo "tasks.md 已写入：$ABS"
```

### 3. 入口状态验证

验证状态机已正确初始化：

```bash
"$COOL_BASH" "$COOL_STATE" check <name> open
```

验证通过后继续 Step 4。验证失败时脚本会输出具体失败原因。

**幂等性**：open 阶段所有操作可安全重复执行。如 `.cool.yaml` 已处于 `phase: open` 且三个产物文件均已存在，跳过已完成步骤，从第一个缺失步骤继续。

### 4. 内容完整性检查

确认三个文档内容完整：
- **proposal.md**：问题背景、目标、范围、非目标
- **design.md**：高层架构决策、方案选型、数据流
- **tasks.md**：任务列表，每个任务有明确描述

**文件存在性验证**：逐个确认三个文件路径存在且非空。任一文件缺失或为空时，不得进入 Step 5 或执行阶段守卫，必须回到创建步骤补充。

### 5. 用户审视确认（阻塞点）

#### recommend 模式决策闸门（open-review）

**更新 Decision Card**（open-review gate 前）：刷新 `openspec/changes/<name>/.cool/handoff/decision-card.md` 以反映当前产物状态——`write_mode` 应与产物是否定稿（`final-artifact`）或仍需 owner 输入（`ask-owner`/`checkpoint`）一致。Decision Card 与产物一同作为 open-review 的复核输入。

在下方的 manual 阻塞确认之前，当 `decision_mode: recommend` 时，运行 gate 并按其指令办：

```bash
DM=$("$COOL_BASH" "$COOL_STATE" gate <name> open-review)
```

- `BLOCK:`（manual 模式，或 material 升级）→ 走下方原阻塞确认流程。
- `REVIEW:`（auto-after-review，尚未通过）→ 进入复核：
  1. 读取 `.cool.yaml` 的 `subagent_dispatch`。`confirmed` → 派后台 subagent，prompt = proposal/design/tasks 产物原文 + 上游（澄清摘要）+ Decision Card（`.cool/handoff/decision-card.md`）+ `cool/reference/review-checklist.md` 通用节（G1-G4）与 open-review evidence 专节（E1-E2）；否则回退为主 agent 自检同一 checklist（通用 + evidence 节）。复核方 SHALL NOT 将 `user-stated` / `assumption` 当作 `confirmed` 通过。
  2. 按 rubric 分级：`pass` / `minor` / `material`。
  3. `pass` → 调 `cool-state review-log <name> open-review 1 pass [issue]`（设 `COOL_REVIEW_BY=subagent|self` 与派发路径一致），重跑 `cool-state gate <name> open-review` 取得 `PROCEED:`，然后 auto 推进（跳过下方 manual 阻塞确认）。`minor` → 内联修产物 1 次 → 再复核 1 次（round 2）；round 2 `pass` → `review-log ... 2 pass`，重跑 gate 取得 `PROCEED:` 后 auto 推进；round 2 仍非 pass → 升级用户（落入下方阻塞确认）。`material` → 软阻塞，surface 用户选择（调整产物 / 拆 change / 接受），**不自动大改**。
- `PROCEED:`（auto-after-review 已通过）→ auto 推进（不询问）。

三个文档创建完成且内容完整性检查通过后，**必须使用当前平台可用的用户输入/确认机制暂停并等待用户确认**。不得在用户确认前执行阶段守卫或自动流转。

用户确认问题必须以单选题形式呈现，包含以下摘要和选项：

**摘要内容**：
- **proposal.md**：问题背景、目标、范围
- **design.md**：高层架构决策、方案选型
- **tasks.md**：任务数量和关键任务描述

**选项**：
- 「确认，继续下一阶段」— 产物符合预期，执行阶段守卫流转
- 「需要调整」— 附带调整说明，修改后重新请求确认

用户选择「确认」后继续执行退出条件。用户选择「需要调整」时，按其说明修改对应文件，然后重新请求确认。

## 退出条件

- proposal.md、design.md、tasks.md 均已创建且内容完整
- **用户已确认** proposal、design、tasks 内容符合预期
- **阶段守卫**：运行 `"$COOL_BASH" "$COOL_GUARD" <change-name> open --apply`，全部 PASS 后由守卫推进到下一阶段

```bash
"$COOL_BASH" "$COOL_GUARD" <change-name> open --apply
```

完整流程会自动更新为 `phase: design`；hotfix/tweak preset 会自动更新为 `phase: build`。

## 自动衔接下一阶段

用户确认且阶段守卫推进 phase 后，运行：

```bash
"$COOL_BASH" "$COOL_STATE" next <change-name>
```

脚本根据 `phase`、`workflow`、`auto_transition` 输出确定性的下一步：
- `NEXT: auto` → 调用 `SKILL` 指向的 skill 进入下一阶段
- `NEXT: manual` → 不要调用下一 skill，按 `HINT` 提示用户手动运行 `/<SKILL>`
- `NEXT: done` → 流程已完成，无需继续
