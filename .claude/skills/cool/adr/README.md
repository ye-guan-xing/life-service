# ADR — 架构决策记录

> 跨 change、难逆的决策：记**为什么**这么选，不记做了什么（那归 design.md）
> 也不记怎么做（那归 spec.md / SKILL.md）。

## 准入过滤（三重过滤）

一个决策值得写 ADR，仅当**同时**满足：

1. **难以逆转** —— 逆转需重构多个 change 或破坏既有用户项目。
2. **缺上下文会令人惊讶** —— 读者冷遇到该决策会问"为什么"，因为理由从代码看不明显。
3. **真有权衡** —— 至少有一个可行替代方案因具体理由被拒绝。

单 change 的 `assumption`（如钩子挂载点选择）**不**自动升格为 ADR——只有跨 change、难逆的架构决策才升格。

## 文件命名

`NNNN-<kebab-slug>.md`，从 0001 起，单调递增，不复用。位于本目录（en）与 `assets/skills-zh/cool/adr/`（zh）。en/zh 须同步。

## 写作格式

每个 ADR 遵循：

1. **约束（Constraints）** —— 起作用的力（技术、历史、user-stated）。
2. **选项（Options）** —— 考虑过的可行替代方案。
3. **拒绝理由（Rejected reasons）** —— 每个未选方案为何被拒。
4. **决策（Decision）** —— 选了什么。
5. **不变量（Invariants）** —— 决策成立须保持为真的条件；什么会迫使重开本 ADR。

## 与 design.md 证据级别的关系

design.md 的证据级别（`confirmed-source` / `user-stated` / `assumption` / `source-candidate`）声明**单 change** 可信度。ADR 声明**跨 change** 决策。两者是不同层级，不互相折叠。archive 时，cool-archive 脚本扫描 design 决策表，软提示将满足三重过滤的决策升格为 ADR——升格非自动。

## L1 与 L2

- **L1**（本目录 `assets/skills/cool/adr/`）：cool-flow 工具自身设计决策，随 skill 分发（en/zh）。
- **L2**（用户项目根 `adr/`）：用户项目决策，由 cool-design domain-modeling 纪律在首次出现满足三重过滤的决策时惰性创建。
