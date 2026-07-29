---
name: cool-archive
description: "Cool 阶段 6：归档。使用 /cool-archive 调用。按 OpenSpec 语义将 delta spec 合并到 main spec，归档变更。"
---

# Cool 阶段 6：归档（Archive）

## 前置条件

- 验证通过（阶段 5 完成）
- 分支已处理
- `openspec/changes/<name>/.cool.yaml` 中 `verify_result: pass`

## 步骤

### 0. 输出语言约束

归档摘要和生命周期闭环说明必须使用触发本次工作流的用户请求语言。

### 0. 入口状态验证（Entry Check）

执行入口验证：

```bash
COOL_ENV="${COOL_ENV:-$(find . "$HOME"/.*/skills "$HOME/.config" "$HOME/.gemini" -path '*/cool/scripts/cool-env.sh' -type f -print -quit 2>/dev/null)}"
if [ -z "$COOL_ENV" ]; then
  echo "ERROR: cool-env.sh not found. Ensure the cool skill is installed." >&2
  return 1
fi
. "$COOL_ENV"
"$COOL_BASH" "$COOL_STATE" check <name> archive
```

验证通过后继续 Step 1。验证失败时脚本会输出具体失败原因。

### 1. 归档前最终确认（阻塞点）

入口验证通过后，**必须使用当前平台可用的用户输入/确认机制暂停并等待用户确认是否立即归档**。不得在用户确认前运行 `"$COOL_BASH" "$COOL_ARCHIVE" "<change-name>"`。若当前平台没有结构化提问工具，则在对话中提出同等单选问题并停止流程，等待用户回复后才能继续。

确认前向用户展示简要摘要：
- change 名称
- 验证报告路径和结果
- 分支处理状态
- 本次归档将执行的不可逆操作：按 OpenSpec delta 语义将 delta spec 合并到 main spec、标注 design doc / plan、将 change 移动到归档目录

用户确认问题必须以单选题形式呈现，包含以下选项：
- 「确认归档」— 立即运行归档脚本，完成 spec 合并和 change 移动
- 「需要调整或重新验证」— 不归档；运行 `"$COOL_BASH" "$COOL_STATE" transition <change-name> archive-reopen` 回到 `phase: verify`，然后调用 `/cool-verify`。如果验证确认需要修复，按 `/cool-verify` 的验证失败决策流程回到 `/cool-build`
- 「暂不归档」— 不归档；保持当前 `phase: archive` 状态，等待用户稍后再次调用 `/cool-archive`

仅在用户选择「确认归档」后才继续 Step 2。用户选择「需要调整或重新验证」后，必须先运行 `archive-reopen` 状态转换；不要手动编辑 `.cool.yaml`。

归档是不可逆硬拦点：`"$COOL_BASH" "$COOL_STATE" gate <name> archive` 在任何 decision_mode 下都永远返回 `BLOCK: ask the user for archive.`。即使 recommend 模式也必须暂停等待用户明确确认。

确认后调用归档脚本前，先通知用户并设置闸门环境变量：

```bash
"$COOL_BASH" "$COOL_NOTIFY" archive-confirm "Cool: 归档前最终确认 — change=<name>"
# 用户明确确认后:
COOL_ARCHIVE_CONFIRMED=1 "$COOL_BASH" "$COOL_ARCHIVE" <name>
```

未设 `COOL_ARCHIVE_CONFIRMED=1` 时 `cool-archive.sh` 会拒绝执行。

### 2. 执行归档

运行归档脚本，自动完成所有步骤：

```bash
"$COOL_BASH" "$COOL_ARCHIVE" "<change-name>"
```

脚本自动执行：
1. 入口状态校验（phase=archive、verify_result=pass、archived=false）
2. Design doc frontmatter 标注（archived-with、status）
3. Plan frontmatter 标注（archived-with）
4. OpenSpec 归档，按 delta 合并语义将 delta spec 同步到 main spec，并将 change 移动到归档目录
5. 防止 delta-only 节标题泄漏到 main spec 的守卫检查
6. 通过 `cool-state transition <archive-name> archived` 更新 `archived: true`

脚本返回非零退出码时，报告错误并停止。
脚本返回零退出码时，归档完成。
摘要中的 `X/Y steps succeeded` 统计实际执行的步骤数，不重复计算 delta spec 同步或文档标注。

脚本调用 OpenSpec archive 将 `ADDED/MODIFIED/REMOVED/RENAMED` delta 语义合并到 main specs，然后验证 main specs 不含 delta-only 节标题。

使用 `--dry-run` 标志可以预览而不实际执行。

### 3. 生命周期闭环

Spec 生命周期在此完成：
```
brainstorming → delta spec → 实现 → 验证 → main spec 合并 → design doc 标注 → 归档
```

## 退出条件

- 归档脚本执行成功（exit code 0）
- 归档目录 `openspec/changes/archive/YYYY-MM-DD-<change-name>/` 已存在
- 已归档的 `.cool.yaml` 包含 `archived: true`

归档脚本将 `openspec/changes/<name>/` 移动到 `openspec/changes/archive/YYYY-MM-DD-<name>/`。

> **警告**：归档成功后，**不要**对旧的活跃 change 名运行 `"$COOL_BASH" "$COOL_GUARD" <change-name> archive`；活跃目录已不存在。这样做会导致 guard 报错"change directory not found"。归档完整性由脚本退出码和归档目录状态判定。

## 完成

Cool 工作流已完成。如需开始新工作，调用 `/cool` 或 `/cool-open`。

## 上下文压缩恢复

archive 阶段执行过程中可能触发上下文压缩。恢复时先运行：

```bash
"$COOL_BASH" "$COOL_STATE" check <change-name> archive --recover
```

脚本输出结构化恢复上下文（归档状态、已完成步骤）。按 Recovery action 判断下一步。如果 `archived: true` 且归档目录已存在，归档已完成——无需再次运行归档操作。

> **扩展点：** `post-archive` hook 在 `cool-archive.sh` 末尾触发（非阻断，archive 已终态）。在 `.cool/config.yaml` 的 `extensions.hooks` 配置（见 cool SKILL.md § 阶段扩展点）。
