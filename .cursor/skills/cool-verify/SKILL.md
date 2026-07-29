---
name: cool-verify
description: "Cool 阶段 5：验证与收尾。使用 /cool-verify 调用。验证实现是否符合设计，处理开发分支。"
---

# Cool 阶段 5：验证与收尾（Verify）

## 前置条件

- 代码已提交（阶段 3/4 完成）
- tasks.md 全部任务已完成

## 步骤

### 0a. 输出语言约束

验证报告和分支处理说明必须使用触发本次工作流的用户请求语言。

### 0b. 入口状态验证（Entry Check）

执行入口验证：

```bash
COOL_ENV="${COOL_ENV:-$(find . "$HOME"/.*/skills "$HOME/.config" "$HOME/.gemini" -path '*/cool/scripts/cool-env.sh' -type f -print -quit 2>/dev/null)}"
if [ -z "$COOL_ENV" ]; then
  echo "ERROR: cool-env.sh not found. Ensure the cool skill is installed." >&2
  return 1
fi
. "$COOL_ENV"
"$COOL_BASH" "$COOL_STATE" check <change-name> verify
```

验证通过后继续 Step 1。验证失败时脚本会输出具体失败原因。

**幂等性**：所有 verify 阶段检查可以安全重试。如果 `verify_result` 已经是 `pass` 且 `branch_status` 是 `handled`，验证已完成——执行 guard 过渡即可。如果 `verify_result` 是 `pending`，从头开始验证。

### 1. 规模评估

执行规模评估：

```bash
"$COOL_BASH" "$COOL_STATE" scale <change-name>
```

脚本自动计算任务数、delta spec 数、改动文件数，判定轻量或完整验证模式，并设置 `verify_mode` 字段。判定规则（满足任一触发完整验证）：任务数 > 3，delta spec capability 数 > 1，改动文件数 > 4。变更文件数排除工作流产物（`openspec/**`、`docs/superpowers/**`、`.cool/**`、根级 `.cool.yaml`/`.openspec.yaml`、`docs/guide/**`、en/zh SKILL.md 同步对），经共享 helper `substantive_changed_files_list` 统一过滤——只有实质源码文件计入阈值。

验证开始前，按 `cool/reference/dirty-worktree.md` 协议处理未提交改动。verify 阶段特殊处理：

1. 如果未提交 diff 属于当前 change 且涉及实现、测试、tasks、delta spec 或 design doc 改动，不要在 verify 阶段直接修复或提交；报告失败并进入 Step 1b 验证失败决策阻塞点
2. 如果未提交 diff 只是 verify 阶段产物（如验证报告草稿、分支处理记录），可以继续并在 verify 阶段记录状态
3. 如果未提交 diff 显示有实现代码但 tasks.md 未勾选，视为 build 状态滞后；报告失败并进入 Step 1b，让用户决定是否回滚修复

仅在用户选择修复后，才允许回滚到 build 阶段：

```bash
# 仅在用户确认修复后执行
"$COOL_BASH" "$COOL_STATE" transition <change-name> verify-fail
```

注意：verify-fail 回滚到 build 时，`branch_status` 不会重置。如果第一次 verify 时分支处理已完成，重新 verify 时跳过分支处理步骤，保留已有的 `branch_status: handled`。

注意：如果 build 阶段每个任务都已提交，脚本基于工作区 diff 的文件计数可能低估改动规模。此时必须读取 plan 文件头部 `base-ref` 并用 commit 范围验证：

```bash
PLAN=$("$COOL_BASH" "$COOL_STATE" get <change-name> plan)
BASE_REF=$(grep '^base-ref:' "$PLAN" 2>/dev/null | head -1 | sed 's/^base-ref: *//')
git diff --stat "$BASE_REF"...HEAD
```

如果 commit 范围显示改动超过轻量阈值（> 4 个文件、跨模块协调、或 delta spec 跨越超过 1 个 capability），手动设置为完整验证：

```bash
"$COOL_BASH" "$COOL_STATE" set <change-name> verify_mode full
```

**覆盖机制**：如果 agent 或用户认为自动评估不合适，可随时覆盖：`"$COOL_BASH" "$COOL_STATE" set <change-name> verify_mode <light|full>`。

### 1b. 验证失败决策（阻塞点）

#### recommend 模式决策闸门（verify-drift-review）

当 `decision_mode: recommend` 且即将接受非 CRITICAL 偏差时，运行 gate 并按其指令办：

```bash
DM=$("$COOL_BASH" "$COOL_STATE" gate <name> verify-drift-review)
```

- `BLOCK:`（manual 模式，或 material 升级）→ 走下方原阻塞接受/修复确认。
- `REVIEW:`（auto-after-review，尚未通过）→ 用 `cool/reference/review-checklist.md` 的 **verify 专节** 复核（产物 = 偏差接受决定；上游 = 验证报告 + 受影响规格）。`subagent_dispatch: confirmed` 时派后台 subagent，否则主 agent 自检。分级 pass/minor/material：
  - `pass` → `cool-state review-log <name> verify-drift-review 1 pass [issue]`（设 `COOL_REVIEW_BY=subagent|self` 与派发路径一致），再运行 `cool-state gate <name> verify-drift-review` 取得 `PROCEED:`，然后自主接受并记录偏差。
  - `minor` → 内联补充接受理由 1 次 → 再复核 1 次（round 2）；round 2 `pass` → `review-log ... 2 pass`，重跑 gate 取得 `PROCEED:` 后自主接受；round 2 非 pass → 升级用户（落入阻塞）。
  - `material` → 软阻塞，surface 用户选择（修复 / 补 design / 接受），**不自动接受**。
- `PROCEED:`（auto-after-review 已通过）→ 自主接受并记录偏差（不询问）。

注：CRITICAL 失败仍走硬拦 `verify-critical`（gate 在任何模式下恒输出 `BLOCK:`），不进入本复核流程。

gate 返回 `BLOCK:`（manual 模式，或 material 升级）时，**必须使用平台用户输入机制暂停**等待用户决定修复还是接受偏差。gate 返回 `PROCEED:`（auto-after-review pass）时自主接受并记录偏差（不询问）。不得自动运行 `"$COOL_BASH" "$COOL_STATE" transition <change-name> verify-fail`，也不得自动调用 `/cool-build`。

暂停时必须列出：
- 失败项
- 是否 CRITICAL（构建失败、测试失败、安全问题、核心验收场景失败）
- 推荐处理方式

**不确定性原则**：严重程度不明确时，向下降级（SUGGESTION > WARNING > CRITICAL）。只有构建失败、测试失败和安全问题才用 CRITICAL；模糊或不确定的问题用 WARNING 或 SUGGESTION。

用户选择后，按以下方式继续：
- **全部修复**：运行 `"$COOL_BASH" "$COOL_STATE" transition <change-name> verify-fail`，然后调用 `/cool-build` 修复
- **逐项处理**：CRITICAL 失败必须修复；非 CRITICAL 失败可以选择接受偏差，但必须在验证报告中记录接受原因和影响范围。如果存在任何 CRITICAL 失败，不允许跳过修复直接接受全部偏差

**重试限制**：连续 3 次 verify-fail 后，第 4 次失败时 agent 不得自动选择继续修复。这是决策点 `verify-fail-limit`（任何模式下恒 block）——`"$COOL_BASH" "$COOL_STATE" gate <name> verify-fail-limit` 永远返回 `BLOCK: ask the user for verify-fail-limit.` 必须使用平台用户输入机制暂停，只提供两个选项："接受全部偏差并记录"或"继续修复"，让用户明确决定。调用 `cool-notify.sh verify-fail-limit`。

**CRITICAL 失败为硬拦点**：先查 `"$COOL_BASH" "$COOL_STATE" gate <name> verify-critical`；它永远返回 `BLOCK: ask the user for verify-critical.` 即使 recommend 模式也必须暂停。到达该阻塞点时调 `"$COOL_BASH" "$COOL_NOTIFY" verify-critical "Cool: verify CRITICAL 失败 — change=<name>"`。

### 2. 产物上下文加载（按需哈希读取）

验证需要读取 OpenSpec 产物时，先检查它们自 design 阶段以来是否有变化：

```bash
RECORDED_HASH=$("$COOL_BASH" "$COOL_STATE" get <change-name> handoff_hash)
CURRENT_HASH=$("$COOL_BASH" "$COOL_HANDOFF" <change-name> --hash-only 2>/dev/null || echo "")
```

- 如果 `RECORDED_HASH` = `CURRENT_HASH` 且两者均非空、非 `null`：OpenSpec 产物未变化。**tasks.md 不需要全文重新读取**（用 `grep -c '\- \[ \]' tasks.md` 确认完成数量）。proposal.md、design.md 和 delta spec 仍需读取用于对比检查。
- 如果 `RECORDED_HASH` 为空、为 `null` 或与 `CURRENT_HASH` 不同：产物已变化或 hash 从未记录。按正常方式全量读取所需文件。

**立即执行：** 使用 Skill 工具加载 Superpowers `verification-before-completion` 技能。禁止跳过此步骤。

技能加载后，按 `verify_mode` 分支执行：

### 2a. 轻量验证（小规模改动）

运行以下 5 项检查：

1. tasks.md 全部任务已完成 `[x]`
2. 改动文件与 tasks.md 描述匹配（`git diff --stat` / `git diff --cached --stat` / `git diff --stat <base-ref>...HEAD` 与 tasks 内容对比）
3. 构建通过（运行项目专用构建命令，如 `npm run build`、`mvn compile`、`cargo build` 等）
4. 相关测试通过
5. 无明显安全问题（无硬编码密钥，无新的不安全操作）

**通过标准**：5 项全部 OK，无 CRITICAL 问题。

**不通过时**：报告失败，进入 Step 1b 验证失败决策阻塞点。仅在用户确认修复后，执行以下命令记录失败并回滚到 build 阶段，然后调用 `/cool-build` 修复：

```bash
# 仅在用户确认修复后执行
"$COOL_BASH" "$COOL_STATE" transition <change-name> verify-fail
```

**报告格式**：简洁表格，列出 5 项检查结果 + PASS/FAIL。

**跳过的项目**（轻量验证不检查）：
- spec 场景覆盖率
- design doc 一致性深度对比
- 代码模式一致性建议
- delta spec 与 design doc 漂移检测

### 2b. 完整验证（大规模改动）

当规模评估结果为"大"时：

**前置检测（cool-openspec-profile-dep）：** 在加载 `openspec-verify-change` 之前，先确认该技能已安装。执行：

```bash
ls ~/.claude/skills/openspec-verify-change 2>/dev/null || ls .claude/skills/openspec-verify-change 2>/dev/null
```

若 `openspec-verify-change` 目录不存在（命令无输出/报错）：
- 输出以下修复指引并停止（不要继续加载该技能，不要自动执行 `openspec config` 或 `openspec update`）：
  - `openspec-verify-change 技能缺失 — 修复：cool init (重跑并在启用环节选 Yes)，或手动：直接写 openspec config.json 为 {profile:"custom",workflows:[...全量]} 后运行 openspec update <path>`
- 不得自动修改用户全局 openspec 配置。

若技能目录存在，继续下方加载 `openspec-verify-change`。

**立即执行：** 使用 Skill 工具加载 `openspec-verify-change` 技能。禁止跳过此步骤。

技能加载后，按其指引进行验证。检查项：
1. tasks.md 全部任务已完成（`[x]`）
2. 实现与 `openspec/changes/<name>/design.md` 高层设计决策一致
3. 实现与 Design Doc（`docs/superpowers/specs/` 下的技术设计文档）一致
4. 所有能力 spec 场景通过
5. proposal.md 目标已满足
6. delta spec 与 design doc 无矛盾（如 Build 阶段有增量 spec 修改，检查 design doc 是否有对应记录）
7. `docs/superpowers/specs/` 下的关联设计文档可定位（文件存在且与当前 change 相关）

验证不通过时：报告缺失项，进入 Step 1b 验证失败决策阻塞点。仅在用户确认修复后，执行以下命令记录失败并回滚到 build 阶段，然后调用 `/cool-build` 补充：

```bash
# 仅在用户确认修复后执行
"$COOL_BASH" "$COOL_STATE" transition <change-name> verify-fail
```

**Spec 漂移处理**（用户决策点）：
- 如果检查项 6 发现矛盾（delta spec 有内容但 design doc 未反映）：这是决策点 `spec-contradiction`（任何模式下恒 block）。运行 `"$COOL_BASH" "$COOL_STATE" gate <name> spec-contradiction` → 永远 `BLOCK: ask the user for spec-contradiction.` 必须使用平台用户输入机制暂停等待用户选择处理方式；不得自动选择。选项：
  - 选项 A：在 design doc 追加"实现偏差"节记录偏差原因。选项 A 是 verify 阶段允许写入的产物；写入后，不得因该 design doc 变更重新触发 Step 1b 脏工作区决策
  - 选项 B：用户选择 B 后，运行 `"$COOL_BASH" "$COOL_STATE" transition <change-name> verify-fail`，然后调用 `/cool-build`；`/cool-build` 的 Spec 增量更新规则会加载 Superpowers `brainstorming` 技能更新 Design Doc + delta spec
  - 选项 C：确认偏差可接受，继续验证（design doc 在归档时会标注为 `superseded-by-main-spec`）

### 3. 收尾（Superpowers）

**立即执行：** 使用 Skill 工具加载 Superpowers `finishing-a-development-branch` 技能。禁止跳过此步骤。

如果 Superpowers `finishing-a-development-branch` 技能不可用，停止流程并提示安装 Superpowers 技能，不要用普通对话替代。

技能加载后，按其指引完成收尾。

**决策闸门**：到达分支处理前，运行 gate：

```bash
DM=$("$COOL_BASH" "$COOL_STATE" gate <name> finishing-branch)
```

- `BLOCK:`（manual 模式）：**必须**用平台用户输入机制暂停等待用户选择。
- `PROCEED:`（auto，recommend 模式）：agent 自主按 `branch-recommend` 输出执行，不中断。

**推荐目标解析**：

```bash
"$COOL_BASH" "$COOL_STATE" branch-recommend <name>
# 输出:
#   target: <base_branch 或主干 或当前分支>
#   action: merge-local | pr | keep
```

**菜单**（基于 `branch-recommend` 与 `protected_branches`，主干永远只走 PR/MR，不本地合并）：
1. 合并回 `base_branch`（仅当 action=merge-local）
2. 推送并创建 PR/MR 到 `base_branch`（action=pr 且 target=base_branch）
3. 推送并创建 PR/MR 到主干（永远 PR，不本地 merge）
4. 保留分支
5. 丢弃（**硬拦**：`cool-state gate <name> discard` 永远返回 `BLOCK: ask the user for discard.`，必须人工确认；丢弃前调 `cool-notify.sh discard-confirm`）

manual 模式下呈现菜单等待用户选择——当 `action=keep`（即 `base_branch` 为 null：change 在 per-need feature 分支上，暂不应合并回）时高亮「4. 保留分支」；recommend 模式下 agent 选 1（若 merge-local）、4（若 keep），否则选 2/3。Superpowers `finishing-a-development-branch` 仅用于执行机械 git/清理步骤，不决定菜单。仅在用户完成选择（或 recommend 自主决定）且操作完成后，写 `branch_status: handled`。

**确认项**：
- 所有测试通过
- 无硬编码密钥或安全问题

### 4. 记录验证证据

验证报告必须保存到磁盘并记录在 `.cool.yaml`；分支处理完成后状态字段也必须写入。不要手动设置 `verify_result: pass`；使用 guard 自动过渡。

```bash
mkdir -p docs/superpowers/reports
# 将验证结论写入报告文件，例如：
# docs/superpowers/reports/YYYY-MM-DD-<change-name>-verify.md

"$COOL_BASH" "$COOL_STATE" set <change-name> verification_report docs/superpowers/reports/YYYY-MM-DD-<change-name>-verify.md
ABS=$("$COOL_BASH" "$COOL_STATE" abspath docs/superpowers/reports/YYYY-MM-DD-<change-name>-verify.md)
echo "验证报告已写入：$ABS"
"$COOL_BASH" "$COOL_STATE" set <change-name> branch_status handled
```

## 退出条件

- 验证报告通过
- 分支已处理
- `.cool.yaml` 中 `verification_report` 指向已存在的验证报告文件
- `.cool.yaml` 中 `branch_status: handled`
- **阶段守卫**：运行 `"$COOL_BASH" "$COOL_GUARD" <change-name> verify --apply`，全部 PASS 后通过 `cool-state transition verify-pass` 自动过渡到 `phase: archive`

验证和分支处理都完成后，运行守卫自动过渡：

```bash
"$COOL_BASH" "$COOL_GUARD" <change-name> verify --apply
```

状态文件自动更新为 `phase: archive`、`verify_result: pass`、`verified_at: YYYY-MM-DD`。

## 自动衔接下一阶段

验证和分支处理完成、守卫推进 phase 后，运行：

```bash
"$COOL_BASH" "$COOL_STATE" next <change-name>
```

脚本根据 `phase`、`workflow`、`auto_transition` 输出确定性的下一步：
- `NEXT: auto` → 调用 `SKILL` 指向的 skill 进入下一阶段
- `NEXT: manual` → 不要调用下一 skill，按 `HINT` 提示用户手动运行 `/<SKILL>`
- `NEXT: done` → 流程已完成，无需继续

注意：`cool-archive` 开始后，必须先执行归档前最终确认阻塞点，等待用户明确选择"确认归档"后才运行归档脚本。不得因为验证通过就自动归档。

## 上下文压缩恢复

verify 阶段可能触发上下文压缩。恢复时先运行：

```bash
"$COOL_BASH" "$COOL_STATE" check <change-name> verify --recover
```

脚本输出结构化恢复上下文（阶段、验证状态、分支状态、恢复动作）。按 Recovery action 判断下一步。
