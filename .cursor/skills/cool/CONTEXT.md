# CONTEXT.md — cool-flow 领域语言

> cool-flow 工具术语单源。纯术语——禁实现细节/方案/行为契约（那些归
> design.md / spec.md / proposal.md）。SKILL.md 与 rules/cool-phase-guard.md
> 改引用本文件，不重复定义。

## Terms

### change
- **Definition:** 流经 cool 六个阶段（open → design → build → review → verify → archive）的工作单元，锚定于 `openspec/changes/<name>/`。
- **Relationships:** 由 proposal.md + design.md + tasks.md + spec delta 组成；按 `phase` 推进；由 `gate` 把关。
- **Avoid:** 勿与"feature"混淆（一个 change 可含多个 feature 或无 feature）。勿用"change"指代 git commit。

### phase
- **Definition:** cool 生命周期六阶段之一：open、design、build、review、verify、archive。
- **Relationships:** 每个 `change` 按序推进；阶段转换由 `cool-guard <name> <phase> --apply` 守卫。
- **Avoid:** cool 语境中勿用"stage"作同义词（"stage"保留给非 cool 语境以避免歧义）。

### gate
- **Definition:** 机制 `cool-state gate <change> <point>`，返回 `PROCEED` / `REVIEW` / `ASSESS` / `BLOCK`，控制决策点能否自动推进。
- **Relationships:** 每个 gate 有 `decision_mode`（manual / recommend）与档（auto / auto-after-review / agent-assess / block）；见 `decision point`。
- **Avoid:** 勿与"阶段转换"混淆——gate 在阶段内部；阶段转换是退出守卫，非 gate。

### review mode
- **Definition:** `.cool.yaml` 字段（`review_mode: full | light | skip`），控制 build 后走哪条 review 路径。
- **Relationships:** full → cool-review 两阶段；light → cool-review 仅规格合规；skip → 直入 cool-verify（tweak）。
- **Avoid:** 勿与 `decision_mode` 混淆（不同轴：谁决策，而非如何审查）。

### decision_mode
- **Definition:** `.cool.yaml` 字段（`decision_mode: manual | recommend`），控制 gate 是否阻塞等人工确认或自动推进。
- **Relationships:** recommend 下 auto / auto-after-review 档自动通过；block 档仍阻塞；agent-assess 档让 agent 自评并允许询问。
- **Avoid:** 勿与 `review mode` 混淆。

### hotfix
- **Definition:** 高紧急修复的工作流类型：open → design(light) → build → review(light) → verify → archive，`review_mode: light`。
- **Avoid:** 非紧急改动勿用——用 `full` 工作流。

### tweak
- **Definition:** 琐碎改动的工作流类型：open → build → verify → archive，`review_mode: skip`，无 design 阶段。
- **Avoid:** 改动触及行为契约时勿用——经 scope-split-review 升级为 `full`。

### decision point
- **Definition:** 命名的决策检查点（如 clarify-review、design-review、plan-ready、build-config、scope-split-review、verify-drift-review、finishing-branch、archive）。
- **Relationships:** 每个决策点映射到一个 `gate` 档（auto / auto-after-review / agent-assess / block），受 `decision_mode` 约束。
- **Avoid:** 未在此处与 SKILL.md Grading Table 登记前，勿引入新决策点名称。

### auto-after-review
- **Definition:** gate 档：仅在前置 predecision review 通过后自动推进；通过前阻塞（返回 REVIEW）。
- **Relationships:** recommend 下用于 design-review / plan-ready / build-config / scope-split-review / verify-drift-review / clarify-review / open-review。
- **Avoid:** 勿等同于纯 `auto`——review 通过是前置条件。

### agent-assess
- **Definition:** 为 context-compaction 引入的 gate 档：agent 自评并输出 `ASSESS:`（非 auto，因决策钩子 auto 档会 `exit 2` 阻止 AskUserQuestion）。
- **Relationships:** 仅 recommend 下的 context-compaction gate。
- **Avoid:** 勿用于其他 gate——它是专用的。

### context-compaction
- **Definition:** brainstorm-summary 定稿与 Design Doc 创建之间的主动压缩 gate；recommend 下 agent 自评（agent-assess 档）。
- **Avoid:** 宿主平台无法程序化压缩时勿程序化触发——暂停并提示用户。

### finishing-branch
- **Definition:** verify 阶段处理开发分支（merge / ff / discard）的决策点。
- **Relationships:** recommend 下非 discard 路径为 auto 档；discard 恒 block。
- **Avoid:** 勿自动 discard——discard 恒 block。

### design-doc
- **Definition:** 技术设计产物，位于 `docs/superpowers/specs/YYYY-MM-DD-<change>-design.md`，full 工作流必需，hotfix/tweak 可选。
- **Relationships:** design 阶段创建；frontmatter 关联当前 change（`cool_change` / `role: technical-design` / `canonical_spec: openspec`）。
- **Avoid:** 勿与 `design.md`（`openspec/changes/<name>/` 内的 OpenSpec change 级设计产物）混淆。

### plan-ready
- **Definition:** build 阶段决策点，执行前确认实施计划。
- **Relationships:** recommend 下为 auto-after-review 档。

### build-config
- **Definition:** build 阶段决策点，选择构建配置（isolation / 执行方式 / TDD 模式）。
- **Relationships:** recommend 下为 auto-after-review 档。

### scope-split-review
- **Definition:** 拆分 change 范围的决策点（hotfix/tweak → full 升级，或拆为多个 change）。
- **Relationships:** recommend 下为 auto-after-review 档；也可在 open 出现。

### verify-drift-review
- **Definition:** verify 阶段处理非临界验证失败（spec 与实现漂移）的决策点。
- **Relationships:** recommend 下为 auto-after-review 档。

### clarify-review
- **Definition:** open 阶段确认需求澄清完成的决策点。
- **Relationships:** manual 下 gate 返回 BLOCK；recommend 下为 auto-after-review。

### open-review
- **Definition:** open 阶段产物复核决策点（证据分层、反 launder）。
- **Relationships:** recommend 下为 auto-after-review 档。

### design-review
- **Definition:** design 阶段确认 brainstorming 设计方案的决策点。
- **Relationships:** recommend 下为 auto-after-review 档；通过后触发 context-compaction gate。

## Leading Words

> 主导词锚定一个行为区，标志可预测性词汇（RES-030）。提炼为本节作单源；
> SKILL.md 改引用而非重定义。

- **binary star** — 锚定 OpenSpec + Superpowers 双星架构区。
- **decision core** — 锚定 gate/决策点区。
- **gate** — 锚定阶段转换控制区。
- **phase** — 锚定六阶段生命周期区。
- **single source** — 锚定术语/ADR 去重区。
- **honest boundary** — 锚定"guard 只做机械可检测"区。

## Flagged Ambiguities

- **change vs feature：** change 是 cool 工作流单元；feature 是面向用户的能力。一个 change 可交付多个 feature 或纯基础设施。cool 语境优先用"change"。
- **design.md vs design-doc：** design.md 是 change 级（`openspec/changes/<name>/` 内）；design-doc 是 `docs/superpowers/specs/` 下的技术设计。勿将任一简称为"设计"而不加限定。
- **gate vs decision point：** decision point 是命名检查点；gate 是执行其档位的机制（`cool-state gate`）。散文中可宽松互换，但 spec/SKILL.md 中优先精确。
