---
name: cool
description: "Cool — OpenSpec + Superpowers 双星开发工作流。输入 /cool 自动检测当前阶段并分派到子命令。六个阶段：open → design → build → review → verify → archive。"
---

# Cool — OpenSpec + Superpowers 双星开发工作流

OpenSpec 与 Superpowers 如双星系统围绕同一目标运转。

```
OpenSpec 负责 WHAT  — 大纲、提案、spec 生命周期、归档
Superpowers 负责 HOW — 技术设计、计划、执行、收尾
```

> **领域语言单源**：术语定义（change / phase / gate / decision_mode / review mode / hotfix / tweak / decision point / auto-after-review / agent-assess / context-compaction / finishing-branch 等）与主导词单源在 `CONTEXT.md`。本文件只定义引用这些术语的行为规则，不重复定义。

**核心原则：brainstorming 必不可跳过。每次变更都必须经过深度设计（hotfix 和 tweak preset 除外）。**

---

## 决策核心

agent 做决策只需读本节，参考附录按需查阅。

### `/cool --recommend` 自主模式

`/cool --recommend` 临时启用自主模式：解析后写 per-change `decision_mode: recommend`（持久化，抗上下文压缩；每个新 change 默认 `manual`）。可重复带 flag 或用 `cool-state set <name> decision_mode manual` 关闭。

若 `/cool` 调用参数含 `--recommend`：识别或创建 change 后，运行

```bash
"$COOL_BASH" "$COOL_STATE" set <name> decision_mode recommend
```

将 per-change `decision_mode` 写为 `recommend`，后续 `cool-state gate <name> <point>` 据此判定 PROCEED/REVIEW/BLOCK。

自主模式下，**可逆决策点** agent 自主推进；**不可逆硬拦点**（archive 执行 / 丢弃工作 / verify CRITICAL / 连续 3 次失败 / spec-contradiction）仍必须人工确认——由 `cool-state gate <name> <point>` 输出 `BLOCK:` 强制，与 decision_mode 无关。`context-compaction` 在 recommend 下属 **agent 自评档**（agent 自评上下文余量，见决策点分级表）；manual 下仍返回 `block`。

决策点分级见附录「决策点分级表」。

### 过程内提问规则（recommend 模式）

`decision_mode: recommend` 下，design/open/build 全阶段的过程内提问遵循 HOW/WHAT 分层：

- **HOW 层**（技术实现选择，同时满足①非 WHAT 层②有明显推荐项③可逆）：agent SHALL 自主选推荐项，记录理由，单向告知（"假设 X，若冲突请纠正"），SHALL NOT 抛二选一提问。
- **WHAT 层**（影响目标/范围/验收且无法从上下文推断的真未知）：agent SHALL 暂停提问。
- **HOW/WHAT 模糊**：SHALL 按 WHAT 处理（保守提问）。
- 本规则仅约束过程内提问，SHALL NOT 替代既有阶段级 gate 复核点（clarify-review / open-review / design-review 等），SHALL NOT 新增 gate 命名点（微观选择无法穷举命名）。

### 输出语言规则

以触发本次工作流的用户请求语言作为默认输出语言。恢复已有 change 时，如果现有产物有明确主语言，除非用户明确要求切换，否则保持该语言。

### 阶段自动检测

**Step 0: 活跃 Change 发现与意图判定**

1. 先做 Preset 检测；命中 hotfix/tweak 时直接调用对应 preset skill，不进入普通 open 分支
2. 未命中 preset 时，运行 `openspec list --json` 获取所有活跃 change

**Preset 检测优先级最高**：
- 用户明确描述为 bug fix / 热修复 + 满足 hotfix 条件 → 直接 `/cool-hotfix`
- 用户明确描述为文案/配置/文档/prompt 小调整 + 满足 tweak 条件 → 直接 `/cool-tweak`
- 未命中 preset → 按下表处理

| 活跃 change | 用户输入 | 行为 |
|-------------|---------|------|
| 无 | 非 preset 输入 | → 调用 `/cool-open` |
| 恰好 1 个 | `/cool <描述>` | → **询问**：继续该变更 or 创建新变更 |
| 多个 | `/cool <描述>` | → **询问**：继续现有变更 or 创建新变更；若选继续 → 列出清单让用户选择 |
| 恰好 1 个 | `/cool`（无描述） | → 自动选中，进入 Step 1 |
| 多个 | `/cool`（无描述） | → 列出清单让用户选择 |

**recommend 模式意图判定**：`decision_mode: recommend` 下，上表两条「询问」（恰好 1 个 / 多个 + 描述）并非无条件。先运行 `"$COOL_BASH" "$COOL_STATE" gate <name> intent`：
- `PROCEED:` → 按推荐自主决策并记录：若现有 change 处于 `verify-pass`/`archive` 待归档，或新描述主题与活跃 change 不同 → 新建；若主题与在进行的 change 相同 → 继续。记录决策后推进（不询问）。
- `BLOCK:`（manual 模式）→ 按上表询问。

<IMPORTANT>
当用户选择「创建新变更」时，**必须调用 `/cool-open`**（禁止直接调用 `/opsx:new`）。
`/cool-open` 负责完整双初始化：OpenSpec artifacts（由内部 `/opsx:new` 创建）+ `.cool.yaml` 状态文件。
直接调用 `/opsx:new` 会缺失 `.cool.yaml`，导致后续阶段判定失败。
</IMPORTANT>

**Step 1: 读取 `.cool.yaml` 状态元数据**

优先读取 `openspec/changes/<name>/.cool.yaml`。不存在时回退到 `openspec status --change "<name>" --json`、`tasks.md` 和 `docs/superpowers/` 文件检查。

**断点恢复规则**：
- 每次恢复上下文时，先重新执行 Step 0 和 Step 1，不依赖对话历史判断阶段
- 只要存在 active change 且工作区有未提交改动，必须按 `cool/reference/dirty-worktree.md` 协议处理
- 若 `phase: build`，先检查 `build_pause`、`plan`、`build_mode` 和 `isolation`：
  - 若 `build_pause: plan-ready` 但 `isolation` 和 `build_mode` 已经设置，则视为 stale pause：先输出 `[COOL] 检测到 stale pause（build_pause=plan-ready 但 isolation/build_mode 已设置），自动清除并继续`，再运行 `"$COOL_BASH" "$COOL_STATE" set <name> build_pause null`，然后读取 tasks.md 的下一个未勾选任务并按 `build_mode` 恢复执行
  - 若 `build_pause: plan-ready` 且 plan 文件存在，但 `isolation` 或 `build_mode` 尚未设置，回到 `/cool-build` 的 plan-ready 恢复点，提示用户继续选择隔离方式和执行方式，不重新生成 plan
  - 若 `build_pause: plan-ready` 但 plan 文件缺失，回到 `/cool-build` 处理状态损坏或重新生成 plan
  - 若 `build_mode`、`isolation` 或 `tdd_mode` 未设置，回到 `/cool-build` 对应步骤补充后再执行
  - 若均已设置，读取 tasks.md 的下一个未勾选任务，并按 `build_mode` 恢复执行：
    - 若 `build_mode: subagent-driven-development`，不得在主窗口直接执行任务；必须回到 `/cool-build` 的后台 subagent 调度规则，由主窗口只做协调
    - 其他执行方式按 `/cool-build` 的对应规则继续
- 若 `phase: verify` 且 `verify_result: fail`，进入验证失败决策阻塞点：暂停并询问用户修复或接受偏差；用户选择修复后才运行 `"$COOL_BASH" "$COOL_STATE" transition <name> verify-fail` 并调用 `/cool-build`
- 若 `phase: open` 但 proposal/design/tasks 已完整，先运行 `"$COOL_BASH" "$COOL_GUARD" <change-name> open --apply` 修正状态，再继续判定
- 若 `phase: archive`，只允许调用 `/cool-archive`；`/cool-archive` 必须先等待归档前最终确认，归档成功后 change 会移动到 archive 目录，不再对原活跃目录运行 guard

**Step 2: 阶段判定**（按顺序，命中即停）

1. `archived: true` 或 change 已移入 archive → 流程已完成
2. `verify_result: pass` 且 `archived` 不是 `true` → `/cool-archive`（先进行归档前最终确认）
3. `verify_result: fail` → 进入验证失败决策阻塞点（暂停询问修复或接受偏差；用户选择修复后才 `verify-fail` 并 `/cool-build`）
4. `phase: verify` 或 tasks.md 全部勾选 → `/cool-verify`
5. `review_result: fail` → 询问修复 → `/cool-build`
6. `phase: review` → `/cool-review`
7. `phase: build` 或已有 Design Doc 但计划/执行未完成 → 优先按 workflow 路由：`hotfix` → `/cool-hotfix`，`tweak` → `/cool-tweak`，`full` → `/cool-build`
8. `phase: design` 或有 change 但无 Design Doc → `/cool-design`
9. `phase: open` 或有活跃 change 但 `.cool.yaml` 缺失 → `/cool-open`
10. 无活跃 change → `/cool-open`

如果元数据与文件状态冲突，以文件状态为准，修正 `.cool.yaml` 后继续。

### 预设升级条件

**hotfix → full**（满足任一即升级）：
- 改动涉及 **3+ 文件**
- 涉及架构变更（新模块、新接口、新依赖）
- 涉及数据库 schema 变更
- 修复引入新的 public API
- 修复范围超出单一函数/模块

**tweak → full**（满足任一即升级）：
- 改动涉及 **5+ 文件**
- 涉及多个模块的协调修改
- 需要新增测试用例 **5+**
- 涉及配置项的新增或删除（非值修改）
- 需要新增 capability
- 需要 delta spec（影响了已有规格）

### 错误处理速查

| 场景 | 处理方式 |
|------|---------|
| `openspec list --json` 失败 | 检查 openspec 是否已安装，提示 `openspec init` |
| 子 skill 不可用 | 停止流程，提示安装或启用对应 skill |
| `.cool.yaml` 格式异常或缺失 | 以文件状态为准，用 `"$COOL_BASH" "$COOL_STATE" set` 修正后继续 |
| 构建/测试失败 | 返回 build 阶段修复，不进入 verify |
| change 目录结构不完整 | 按 `cool-open` 产物要求补齐 |

### 阶段衔接

<IMPORTANT>
单次 `/cool` 调用从检测到的阶段开始，退出条件满足后进入下一阶段。

流转链：open → design → build → [review] → verify → archive

build 完成后，根据 `.cool.yaml` 的 `review_mode` 字段：
- `review_mode: skip`（tweak）→ 自动衔接 `/cool-verify`
- `review_mode: full`（full workflow）→ 自动衔接 `/cool-review`（两阶段审查）
- `review_mode: light`（hotfix）→ 自动衔接 `/cool-review`（仅规格合规审查）

**连续执行要求**：从检测到的阶段开始，agent 自动推进后续阶段。但**自动推进仅适用于没有用户决策的衔接点**。遇到用户决策点时，**必须使用当前平台可用的用户输入/确认机制暂停并等待用户明确回复**，不得用推荐规则、默认值或历史偏好代替用户确认，也不得仅输出文字提示后继续执行。

**阶段推进与自动衔接的区分**：每个子 skill 退出前都会运行阶段守卫 `--apply` 推进 `.cool.yaml` 的 `phase` 字段——这一步**始终发生**，与 `auto_transition` 无关。之后子 skill 运行 `"$COOL_BASH" "$COOL_STATE" next <name>` 解析下一步：`auto_transition` 不为 `false` 时输出 `NEXT: auto`（自动调用下一 skill），为 `false` 时输出 `NEXT: manual`（不调用下一 skill，提示用户手动运行）。因此 `auto_transition` **只控制是否自动调用下一个 skill，不影响 phase 推进**。无论 `auto_transition` 取何值，下方的用户决策点都必须阻塞等待。

**决策点是阻塞点**：只要到达下列任一节点，当前 `/cool` 调用必须停住。`decision_mode: recommend` 下，auto / auto-after-review 点运行 `cool-state gate <name> <point>` 并按其指令办（PROCEED/REVIEW/BLOCK）；只有 `BLOCK:`（或 manual 模式）才暂停等待用户明确输入。硬拦点无论何种模式都必须暂停。若当前平台没有结构化提问工具，则必须在对话中提出明确选项并停止流程，等待用户回复后才能继续。

`decision_mode: manual` 下，所有决策点都阻塞等待用户明确输入。`decision_mode: recommend` 下，仅硬拦点无条件暂停：`archive`、`discard`、`verify-critical`、`verify-fail-limit`、`spec-contradiction`；`context-compaction` 为 agent-assess（agent 自评，可询问）。其余点按下方决策点分级表的档位自动推进——该表是完整决策点集合与档位的单源，本节不再重列。

agent 不应跳过这些决策点；其他明确无歧义的阶段衔接必须从检测到的阶段起继续推进所有后续阶段。到达决策点时，**禁止跳过用户确认或自动选择——必须通过当前平台可用的用户输入/确认机制明确获取用户选择后才能继续**（manual 模式或 gate 返回 `BLOCK:` 时）。

**红旗清单** — 以下想法出现时立即停止并检查：

| Agent 心理 | 实际风险 |
|-----------|---------|
| "用户应该会同意这个方案" | 不能替用户决策，必须等待用户明确选择 |
| "这只是个小改动，不需要确认" | 决策点无大小之分，阻塞点必须等待 |
| "用户之前选过 A，这次也选 A" | 历史偏好不能替代当前确认 |
| "我已经解释了方案，用户没反对" | 没反对 ≠ 同意，必须用工具获取明确选择 |
| "流程走到这里应该没问题了" | 验证不通过 ≠ 通过，检查 verify_result |
</IMPORTANT>

---

## 子命令速查

| 命令 | 阶段 | 归属 | 产物 |
|------|------|------|------|
| `/cool-open` | 1. 开启 | OpenSpec | proposal.md、design.md、tasks.md |
| `/cool-design` | 2. 深度设计 | Superpowers | Design Doc、delta spec |
| `/cool-build` | 3. 计划与构建 | Superpowers | 实施计划、代码提交 |
| `/cool-review` | 4. 代码审查 | Cool | 审查报告、规格合规验证 |
| `/cool-verify` | 5. 验证与收尾 | Both | 验证报告、分支处理 |
| `/cool-archive` | 6. 归档 | OpenSpec | delta→main spec 同步、design doc 标注、归档 |
| `/cool-hotfix` | 预设路径 | Both | 快速修复（跳过 brainstorming） |
| `/cool-tweak` | 预设路径 | Both | 小改动（跳过 brainstorming 和完整 plan） |

```
/cool
  ↓ 自动检测
/cool-open ──→ /cool-design ──→ /cool-build ──→ /cool-review ──→ /cool-verify ──→ /cool-archive
  (OpenSpec)      (Superpowers)     (Superpowers)     (Cool)          (Both)          (OpenSpec)

/cool-hotfix（预设路径，跳过 brainstorming）
  open ──→ build ──→ review(light) ──→ verify ──→ archive
    ↑ 如触发升级条件 → 阻塞确认升级 → 补充 Design Doc → 回到完整流程

/cool-tweak（预设路径，跳过 brainstorming 和完整 plan）
  open ──→ lightweight build ──→ verify ──→ archive
    ↑ 如触发升级条件 → 阻塞确认升级 → 补充 Design Doc → 回到完整流程
```

---

## 参考附录

### 配置体系（优先级与归属）

```
优先级高 → 低：
  1. CLI flag（/cool --recommend）— 写入 per-change decision_mode 字段，等同 per-change
  2. per-change .cool.yaml 字段
  3. 环境变量（COOL_*）
  4. 项目级 .cool/config.yaml               团队/项目默认
  5. 内置默认
```

`build_command` / `verify_command` 由 guard 按此顺序解析：per-change `.cool.yaml` → `COOL_BUILD_COMMAND` / `COOL_VERIFY_COMMAND` 环境变量 → `.cool/config.yaml` → 构建清单自动探测（`package.json` / `pom.xml` / `Cargo.toml`）→ 失败并输出诊断。项目级配置文件**仅** `.cool/config.yaml`；根目录 `.cool.yaml` / `cool.yaml` / `.cool.yml` / `cool.yml` **不再读取**（迁移：把根目录 `cool.yaml` 内容并入 `.cool/config.yaml`）。

`.cool/config.yaml` 键（手编此文件；团队/项目默认值）：

| 键 | 类型 | 默认 | 说明 |
|----|------|------|------|
| `auto_transition` | bool | true | 阶段推进后是否自动调下一 skill（不影响 phase 推进、不跳过决策点） |
| `context_compression` | off\|beta | off | 上下文压缩实验开关；beta 下 design 生成 spec-context.json 并由 guard 校验 |
| `decision_mode` | manual\|recommend | manual | 决策点自主模式 |
| `protected_branches` | list | [main, master] | 禁止本地 merge、只允许 PR/MR 的分支 |
| `notify` | on\|off | on | 硬拦截点通知开关 |
| `notify_command` | string | — | 自定义通知命令（可用 %s 占位消息） |
| `build_command` | string | — | guard 构建命令 |
| `verify_command` | string | — | verify 验证命令 |
| `level_detection.exclude_globs` | 列表（嵌套） | — | 追加到内置级别判定排除集的 glob 模式，供 `count-upgrade-files` / `cmd_scale` 使用（见 `cool-state.sh` 的 `substantive_changed_files_list`）。内置排除集已含 `openspec/**`、`docs/superpowers/**`、`.cool/**`、根级 `.cool.yaml`/`.openspec.yaml`、`docs/guide/**`、en/zh SKILL.md 同步对、构建产物（`dist/**`、`build/**`、`out/**`）、机器生成文件（`*.lock`、`*-lock.json`、`*-lock.yaml`、`*.min.js`、`*.min.css`、`*.map`） |

环境变量（会话级覆盖，不提交到仓库）：

| 环境变量 | 覆盖键 | 说明 |
|----|------|------|
| `COOL_DECISION_MODE` | `decision_mode` | |
| `COOL_AUTO_TRANSITION` | `auto_transition` | |
| `COOL_CONTEXT_COMPRESSION` | `context_compression` | |
| `COOL_BUILD_COMMAND` | `build_command` | guard 构建覆盖 |
| `COOL_VERIFY_COMMAND` | `verify_command` | verify 覆盖（否则回落到 build） |
| `COOL_SKIP_BUILD` | — | `1` 跳过 build/verify 检查（逃生口） |
| `COOL_REVIEW_BY` | — | review 归属（self/subagent） |

#### 用户配置 vs AI/cool 流程状态

两类读者各管各的文件，不要混用：

| 读者 | 文件/通道 | 修改方式 | 示例 |
|------|----------|---------|------|
| **用户**（团队/项目） | `.cool/config.yaml` | 手编、提交到仓库 | `build_command`、`verify_command`、`decision_mode`、`protected_branches`、`notify`、`auto_transition` |
| **用户**（会话） | `COOL_*` 环境变量、`/cool --recommend` flag | shell / 入口 flag | `COOL_BUILD_COMMAND`、`COOL_DECISION_MODE` |
| **AI / cool 流程**（状态） | per-change `openspec/changes/<name>/.cool.yaml` | 仅 `cool-state set`，禁止手编 | `phase`、`workflow`、`branch_status`、`verify_result`、`review_result`、各 `*_mode`、各 `*_report`、`handoff_*`、`base_ref`、`open_branch` |

少数键（`build_command`、`verify_command`、`decision_mode`、`auto_transition`、`context_compression`）可同时出现在 `.cool/config.yaml`（用户默认）与 per-change `.cool.yaml`（机器写入的覆盖）。由上面的优先级顺序裁决谁生效。

### .cool.yaml 字段说明

```yaml
workflow: full
phase: build
design_doc: docs/superpowers/specs/YYYY-MM-DD-topic-design.md
plan: docs/superpowers/plans/YYYY-MM-DD-feature.md
base_ref: a1b2c3d4e5f6...
build_mode: subagent-driven-development
build_pause: null
subagent_dispatch: confirmed
tdd_mode: tdd
isolation: branch
review_mode: full
review_result: pending
review_report: null
review_fail_count: 0
verify_mode: light
verify_result: pending
verification_report: null
branch_status: pending
created_at: 2026-06-10
verified_at: null
archived: false
```

| 字段 | 含义 |
|------|------|
| `workflow` | `full`、`hotfix` 或 `tweak` |
| `phase` | 当前阶段：`open`、`design`、`build`、`review`、`verify`、`archive`（init 统一设为 `open`，guard 负责过渡） |
| `design_doc` | 关联的 Superpowers Design Doc 路径，可为空 |
| `plan` | 关联的 Superpowers Plan 路径，可为空 |
| `base_ref` | init 时记录的 git commit SHA，用于 scale 评估 |
| `build_mode` | 已选择的执行方式，可为空 |
| `build_pause` | build 阶段内部暂停点。`null` 表示无暂停，`plan-ready` 表示 plan 已生成等待选择执行方式 |
| `subagent_dispatch` | `null` 或 `confirmed`。使用 subagent-driven-development 前必须确认平台支持 |
| `tdd_mode` | `tdd` 或 `direct`。full workflow 离开 build 阶段前必须已选择 |
| `isolation` | `branch` 或 `worktree`，工作区隔离方式 |
| `review_mode` | `full`（两阶段审查）、`light`（仅规格合规）、`skip`（跳过 review） |
| `review_result` | `pending`、`pass` 或 `fail` |
| `review_report` | 审查报告文件路径，review-pass 的强制前提 |
| `review_fail_count` | 连续 review-fail 计数，review-pass 时归零 |
| `verify_mode` | `light` 或 `full`，可为空 |
| `auto_transition` | `true` 或 `false`。只控制是否自动调用下一个 skill，不影响 phase 推进、不跳过决策点 |
| `verify_result` | `pending`、`pass` 或 `fail` |
| `verification_report` | 验证报告文件路径，verify 通过前必须指向已存在文件 |
| `branch_status` | `pending` 或 `handled`，分支处理完成后设为 `handled` |
| `created_at` | change 创建日期（init 时自动写入），格式 `YYYY-MM-DD` |
| `verified_at` | 验证通过时间，可为空 |
| `archived` | change 是否已归档 |
| `decision_mode` | `manual`（默认）或 `recommend`。控制决策点是否自主推进；硬拦点不受影响 |
| `base_branch` | 由 open-branch 在从保护分支切出时记录的父分支（保护父分支，如 main）；/cool-open 沿用非保护分支时为 null。worktree 模式覆盖为当前分支。供 verify 优先合并回 |
| `open_branch` | /cool-open 切到或沿用的 feature 分支（必非保护）。供 guard 校验工作分支、build isolation:branch 复用 |

可选字段：

| 字段 | 含义 |
|------|------|
| `direct_override` | `true`/`false`。full workflow 如需使用 `build_mode: direct`，必须显式设为 `true` |
| `build_command` | 项目构建命令。guard 优先运行该命令，失败时打印命令输出 |
| `verify_command` | 项目验证命令。verify guard 优先运行该命令，未配置时回退到构建命令 |
| `context_compression` | `off` 或 `beta`。beta 下 design 生成 spec-context.json 并由 guard 校验结构 |

状态机硬约束：
- `build → review/verify` 前，`isolation` 必须是 `branch` 或 `worktree`
- `build → review/verify` 前，`build_mode` 必须已选择
- `build_mode: subagent-driven-development` 必须同时有 `subagent_dispatch: confirmed`
- full workflow 离开 build 阶段前 `tdd_mode` 必须已选择为 `tdd` 或 `direct`
- `build_mode: direct` 默认只允许 `hotfix` / `tweak`；full workflow 需要 `direct_override: true`
- `build_pause` 不是执行方式，不得写入 `build_mode`

### 决策点分级表（decision_mode: recommend 下）

`decision_mode: recommend` 下，决策点分四档。`cool-state gate <name> <point>` 据此输出 `PROCEED:` / `REVIEW:` / `ASSESS:` / `BLOCK:`：

- **直接自主推进（无复核）** — 机械/可逆点：gate 输出 `PROCEED:`。
- **复核后自主推进** — 产物质量点：gate 输出 `REVIEW:` 直到复核前置通过，然后 `PROCEED:`。
- **agent 自评** — 能力限制点：gate 输出 `ASSESS:`；agent 自评后决定 PROCEED 或 BLOCK（问用户）。
- **硬拦** — 不可逆点：gate 任何模式下永远输出 `BLOCK:`；必须暂停等人工确认。

| 决策点 | 行为 | 复核前置 | 理由 |
|--------|------|---------|------|
| intent：继续现有 vs 新建 change | 按推荐自主决策（待归档或主题不同 → 新建；主题与进行中相同 → 继续） | - | 可逆（机械） |
| open 阶段分支名确认（`branch-name`） | 自主用推荐名（feature/YYYYMMDD/<change>） | - | 可逆（机械） |
| open change 名称命名（`change-name`） | 自主用澄清摘要派生的 kebab-case slug | - | 可逆（机械） |
| open 需求澄清完成确认（`clarify-review`） | 澄清摘要复核后自主推进 | auto-after-review | 可逆（产物质量） |
| open proposal/design/tasks 审视（`open-review`） | 自主通过 | auto-after-review | 可逆（产物质量） |
| brainstorming 方案确认（`design-review`） | 自主选推荐方案 | auto-after-review | 可逆（产物质量） |
| build plan-ready（`plan-ready`） | 自主推进 | auto-after-review | 可逆（产物质量） |
| build 隔离/执行/TDD（`build-config`） | 自主按规模选 | auto-after-review | 可逆（产物质量） |
| verify 非临界偏差（`verify-drift-review`） | 自主接受并记录 | auto-after-review | 可逆（产物质量） |
| finishing-branch 选择（`finishing-branch`） | 自主按 branch-recommend | - | 可逆（机械） |
| hotfix/tweak→full 升级（`tweak-upgrade` / `hotfix-upgrade`） | 复核后自主推进 | auto-after-review | 可逆（产物质量） |
| 范围扩张/PRD 拆分（`scope-split-review`） | 自主决策并记录 | auto-after-review | 可逆（产物质量） |
| 子代理调度降级（`subagent-dispatch`） | 自主回退 | - | 可逆（机械） |
| 平台能力降级（`platform-capability`） | 自主记录降级路径 | - | 可逆（机械） |
| **design 手动压缩**（`context-compaction`） | **agent 自评** — agent 自评上下文余量：充足→继续；紧张+无程序化压缩→问用户 | agent-assess | 能力限制（非不可逆） |
| **archive 归档脚本执行**（`archive`） | **硬拦** | 不可逆 |
| **丢弃工作**（`discard`） | **硬拦** | 不可逆 |
| **verify CRITICAL 失败**（`verify-critical`） | **硬拦** | 不可逆 |
| **连续 3 次 verify-fail**（`verify-fail-limit`） | **硬拦** | 不可逆 |
| **Spec 漂移处理**（`spec-contradiction`） | **硬拦** | 不可逆 |

硬拦点由 `cool-state gate <name> <point>` 永远输出 `BLOCK:` 强制，point ∈ {archive, discard, verify-critical, verify-fail-limit, spec-contradiction}。`context-compaction` 在 recommend 下返回 `ASSESS:`（agent 自评，见 agent 自评档），manual 下返回 `BLOCK:`。机械点（`intent` / `change-name` / `branch-name` / `finishing-branch` / `subagent-dispatch` / `platform-capability`）返回 `PROCEED:`；产物质量点（`clarify-review` / `open-review` / `design-review` / `plan-ready` / `build-config` / `scope-split-review` / `verify-drift-review` / `tweak-upgrade` / `hotfix-upgrade`）返回 `REVIEW:` 直到复核通过，然后 `PROCEED:`。未知/未审计的点 fall through 到 `block`（保守——宁可询问，也不静默自主推进）。`decision_mode: manual` 下所有点返回 `BLOCK:`。

### 产物质量点复核流程

当 `cool-state gate <name> <point>` 输出 `REVIEW:`（产物质量点：`clarify-review` / `open-review` / `design-review` / `plan-ready` / `build-config` / `scope-split-review` / `verify-drift-review` / `tweak-upgrade` / `hotfix-upgrade`）时，子 skill 在自主推进前必须先做一次复核：

1. 检查 `.cool.yaml` 的 `subagent_dispatch`：`confirmed` → 派后台 subagent（prompt = 产物原文 + 上游规格 + `cool/reference/review-checklist.md` 对应节）；否则回退为主 agent 自检同一 checklist。日志标注 `review:subagent` 或 `review:self`。
2. 按 `review-checklist.md` 的 rubric 分级：`pass` / `minor` / `material`。
3. `pass` → 写复核日志，重跑 `cool-state gate <name> <point>` 取得 `PROCEED:`，然后 auto 推进。`minor` → 内联修产物 1 次 → 再复核 1 次（round 2）；round 2 `pass` → 写 log，重跑 gate 取得 `PROCEED:` 后 auto 推进，否则升级用户。`material` → 软阻塞，surface 用户选择（补 design / 拆 change / 接受），**不自动大改**。
4. **每次**复核结果（pass / minor / material，含 round 2 非 pass 升级）都必须通过 `cool-state review-log <name> <point> <round> <result> [issue]`（设 `COOL_REVIEW_BY=subagent|self` 与派发路径一致）append 到 `openspec/changes/<name>/.cool/handoff/review-log.md`。material 与 round 2 非 pass 在 surface 用户前必须记录（`result=material|minor`、`decision=escalated-to-user`）。轮次追踪用日志 `round` 字段（恢复时 grep 自最近 pass/escalated 后的条目计数），不写入 `.cool.yaml`。

派发与分级逻辑由各子 skill 实现；主 `cool/SKILL.md` 只定义分级表与本流程。manual 模式不受影响（gate 输出 `BLOCK:`）。

#### `gate` 输出值

- `BLOCK:` — manual 模式或硬拦点；必须暂停问用户。
- `PROCEED:` — recommend 模式，机械/可逆点，或 auto-after-review 已通过；不询问直接自主推进。
- `REVIEW:` — recommend 模式，产物质量点尚未复核/通过；先做复核（见「产物质量点复核流程」），`pass` 后重跑 gate 取得 `PROCEED:`。现有只判 block 的调用者不受影响（硬拦点不会输出 `REVIEW:`）。
- `ASSESS:` — recommend 模式，agent 自评档（当前为 `context-compaction`）；agent 自评上下文余量后决定 PROCEED（不询问继续）或 BLOCK（问用户手动压缩）。manual 模式下该点输出 `BLOCK:`。

### 脚本定位

Cool 脚本随 skill 包分发在 `cool/scripts/` 下。**不硬编码路径** — 定位一次，缓存到环境变量：

```bash
COOL_ENV="${COOL_ENV:-$(find . "$HOME"/.*/skills "$HOME/.config" "$HOME/.gemini" -path '*/cool/scripts/cool-env.sh' -type f -print -quit 2>/dev/null)}"
if [ -z "$COOL_ENV" ]; then
  echo "ERROR: cool-env.sh not found. Ensure the cool skill is installed." >&2
  return 1
fi
. "$COOL_ENV"

if [ -z "$COOL_GUARD" ] || [ -z "$COOL_STATE" ] || [ -z "$COOL_HANDOFF" ] || [ -z "$COOL_ARCHIVE" ]; then
  echo "ERROR: Cool scripts not found. Ensure the cool skill is installed." >&2
  echo "Expected path pattern: */cool/scripts/cool-*.sh under project or platform skill directories" >&2
  return 1
fi
```

**自动状态更新**：guard 支持 `--apply` 参数，验证通过后自动更新 `.cool.yaml` 状态字段：

```bash
"$COOL_BASH" "$COOL_GUARD" <change-name> <phase> --apply
```

**解析下一步**：阶段守卫推进 phase 后，用 `next` 子命令解析是否自动调用下一个 skill：

```bash
"$COOL_BASH" "$COOL_STATE" next <change-name>
```

输出 `NEXT: auto|manual|done` + `SKILL: <skill-name>`（`done` 时省略）+ `HINT`（仅 `manual` 时）。

**归档脚本**：一键完成归档全部步骤：

```bash
"$COOL_BASH" "$COOL_ARCHIVE" <change-name>
```

### 阶段扩展点

cool-flow 可在阶段边界挂载外部 CLI（opt-in，未配置时零行为变化）。

**Hook 触发模型：**
- `post-<current>` 与 `pre-<next>` 都在 `cool-guard <current> --apply` 的 transition 前触发；任一 block → 不 transition。
- `post-archive` 在 `cool-archive.sh` 归档完成末尾触发（archive 已终态，block 仅记日志）。
- `cool-state next` 不改。

**配置（`.cool/config.yaml`）：**
```yaml
extensions:
  enabled: true                     # false/缺省 = no-op
  default-timeout: 30
  default-on-failure: warn          # block | warn
  hooks:
    - phase: build
      slot: post
      command: cool-api-mock
      args: --name,{change},--mode,incremental
      env: LOG_LEVEL=debug;MODE=incremental   # KEY=val;KEY=val，导出给子进程
      on-failure: block
      timeout: 60
```

**状态契约：** env（`COOL_CHANGE`/`COOL_PHASE`/`COOL_PHASE_SLOT`/`COOL_CHANGE_DIR`/`COOL_PROJECT_DIR`/`COOL_HOOK_INDEX`/`COOL_PREV_HOOK_OUTPUT`）+ stdin JSON 入参（含 `cool_yaml` 透传）；exit code（0=pass / 非0=fail / 124=超时，runner 强制）+ 可选 stdout JSON 出参（落盘 `.cool/extensions/<phase>-<slot>-<index>.json`，同 slot 上一 hook 的 stdout 路径经 `COOL_PREV_HOOK_OUTPUT` 传给下一 hook）。runner 只据 exit code 决定 transition，不解析 stdout 作控制流。

**降级：** `cool-extension.sh` 不存在/不可执行 → guard/archive 跳过且不阻断既有流程（向后兼容）。guard transition 前自动跑 `validate`，配置畸形 fail-fast。用 `cool-extension.sh validate <change>` 手动校验。

> 第三方 CLI 开发规范（幂等、工作目录、超时与子进程、信任边界等）见 `docs/guide/extensions.md`。

### 文件结构

```
openspec/                              # OpenSpec — WHAT
├── config.yaml
├── changes/
│   ├── <name>/                        # 活跃 change
│   │   ├── .openspec.yaml
│   │   ├── .cool.yaml
│   │   ├── proposal.md                # Why + What
│   │   ├── design.md                  # 高层架构决策
│   │   ├── specs/<capability>/spec.md # Delta 能力规格
│   │   ├── review-report.md           # 审查报告（review 阶段生成）
│   │   ├── .cool/handoff/             # 脚本生成的阶段交接包
│   │   └── tasks.md                   # 任务清单
│   └── archive/YYYY-MM-DD-<name>/     # 已归档
└── specs/<capability>/spec.md         # 主 specs（归档时按 OpenSpec delta 语义合并）

docs/superpowers/                      # Superpowers — HOW
├── specs/YYYY-MM-DD-<topic>-design.md # 设计文档（技术 RFC，归档时标注状态）
└── plans/YYYY-MM-DD-<feature>.md      # 实施计划（文件头含 change 关联元数据）
```

### 最佳实践

1. **brainstorming 不可跳过** — 每次变更必须经过深度设计（hotfix 和 tweak 除外）
2. **delta spec 是活文档** — 阶段 3 期间可自由修改，归档时同步
3. **交接包由脚本生成** — OpenSpec → Superpowers 的上下文必须通过 `cool-handoff.sh` 生成 compact 可追溯摘录，并由 guard 校验 source/hash/mode
4. **保持 tasks.md 同步** — 完成一个勾一个
5. **频繁提交** — 每个任务一次提交，message 体现设计意图
6. **先验证再确认归档** — `/cool-verify` 通过后进入 `/cool-archive`，但运行归档脚本前必须等待用户最终确认
7. **增量更新分级** — 小编辑、中重 brainstorming、大新 change
8. **Plan 必须关联 change** — 文件头包含 `change:` 和 `design-doc:` 元数据
9. **归档闭环** — design doc 和 plan 必须标注 `archived-with` 状态
10. **修改已有功能** — 直接 open 新 change 即可
11. **Preset 有上限** — hotfix/tweak 满足升级条件时及时切换到完整流程
