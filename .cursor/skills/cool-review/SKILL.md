---
name: cool-review
description: "Cool 阶段 4：代码审查。执行两阶段审查（规格合规 + 代码质量），子代理隔离执行。使用 /cool-review 调用。"
---

# Cool 阶段 4：代码审查（Review）

## 前置条件

- build 阶段已完成，`.cool.yaml` 的 `phase` 为 `review`
- `review_mode` 为 `full` 或 `light`（`skip` 不会进入本阶段）

## 步骤

### 0. 入口状态验证

```bash
COOL_ENV="${COOL_ENV:-$(find . "$HOME"/.*/skills "$HOME/.config" "$HOME/.gemini" -path '*/cool/scripts/cool-env.sh' -type f -print -quit 2>/dev/null)}"
if [ -z "$COOL_ENV" ]; then
  echo "ERROR: cool-env.sh not found. Ensure the cool skill is installed." >&2
  return 1
fi
. "$COOL_ENV"

if [ -z "$COOL_STATE" ] || [ -z "$COOL_GUARD" ]; then
  echo "ERROR: Cool scripts not found." >&2
  return 1
fi

"$COOL_BASH" "$COOL_STATE" check <change-name> review
```

验证通过后读取 `review_mode` 和连续失败计数：

```bash
REVIEW_MODE=$("$COOL_BASH" "$COOL_STATE" get <change-name> review_mode)
REVIEW_FAIL_COUNT=$("$COOL_BASH" "$COOL_STATE" get <change-name> review_fail_count 2>/dev/null || echo "0")
[ "$REVIEW_FAIL_COUNT" = "null" ] && REVIEW_FAIL_COUNT=0
```

### 1. 加载审查上下文

读取以下文件作为审查输入：
- `openspec/changes/<name>/specs/**/*.md`（delta spec，审查基准）
- `openspec/changes/<name>/proposal.md`（范围约束，了解本次变更的目标和非目标）
- `git diff <base_ref>..HEAD`（实际改动）

```bash
BASE_REF=$("$COOL_BASH" "$COOL_STATE" get <change-name> base_ref)
git diff "$BASE_REF"..HEAD --stat
```

### 2. Phase 1：规格合规审查（full + light 均执行）

**平台检测**：

检测当前平台是否支持 Agent 工具派发真实子代理：
- 若支持：派发隔离子代理，审查视角完全独立
- 若不支持：在主窗口顺序执行，在报告中注明 `non-isolated`

**子代理 Prompt（规格合规审查）**：

```
你是代码审查者，审查任务是检查代码实现是否符合规格要求。
你不能看到主会话历史，只依据以下材料做判断。

## 审查基准（Delta Spec）
<粘贴 openspec/changes/<name>/specs/ 下所有 spec.md 的完整内容>

## 实际改动（Git Diff）
<粘贴 git diff base_ref..HEAD 的完整输出>

## 审查任务
逐条核查每个 Requirement 的每个 Scenario：
1. 代码实现是否满足该 Scenario 的 WHEN/THEN 条件？
2. 是否有遗漏的 Scenario 完全未实现？

## 输出格式
按以下 JSON schema 返回结果，不要输出其他内容：
{
  "phase": "compliance",
  "findings": [
    {
      "requirement": "Requirement 名称",
      "scenario": "Scenario 名称",
      "level": "CRITICAL | WARNING | SUGGESTION",
      "detail": "具体问题描述",
      "evidence": "file:line 或代码片段"
    }
  ],
  "summary": "一句话总结"
}

CRITICAL 定义：Scenario 完全未实现，或实现与 THEN 条件明确矛盾。
WARNING 定义：Scenario 部分实现，边界条件缺失，但核心逻辑存在。
SUGGESTION 定义：实现可改进但不影响合规性的建议。
```

### 3. Phase 1 结果判定

```
有 CRITICAL findings → 记录结果，跳过 Phase 2，进入 Step 5（失败处理）
无 CRITICAL + review_mode=full  → 执行 Phase 2（Step 4）
无 CRITICAL + review_mode=light → 跳过 Phase 2，进入 Step 5（通过路径）
```

### 4. Phase 2：代码质量审查（review_mode=full 时执行）

**子代理 Prompt（代码质量审查）**：

```
你是代码审查者，审查任务是评估代码质量。
你不能看到主会话历史，只依据以下材料做判断。

## 实际改动
<粘贴 git diff base_ref..HEAD 的完整输出>

## 审查维度
1. 代码质量：命名清晰度、结构合理性、重复代码、复杂度
2. 测试覆盖：关键路径是否有测试，测试是否真正验证行为（而非只是 mock）
3. 安全隐患：注入风险、越权访问、敏感信息泄露
4. 性能问题：明显的性能瓶颈、资源泄漏、不必要的重复计算

## 输出格式
按以下 JSON schema 返回结果，不要输出其他内容：
{
  "phase": "quality",
  "findings": [
    {
      "dimension": "quality | testing | security | performance",
      "level": "CRITICAL | WARNING | SUGGESTION",
      "detail": "具体问题描述",
      "evidence": "file:line 或代码片段"
    }
  ],
  "summary": "一句话总结"
}

CRITICAL 定义：安全漏洞、构建失败、测试失败、数据丢失风险。
WARNING 定义：测试覆盖不足、明显性能问题、代码结构严重问题。
SUGGESTION 定义：可读性改进、风格建议、重构机会。
```

### 5. 生成合并审查报告

将两阶段结果合并写入报告文件：

```bash
REPORT_PATH="openspec/changes/<name>/review-report.md"
```

报告格式：

```markdown
# 审查报告

- Change: <name>
- 日期: YYYY-MM-DD
- review_mode: full | light
- 执行模式: isolated | non-isolated

## Phase 1：规格合规审查

### CRITICAL
<!-- 无则写"无" -->

### WARNING
<!-- 无则写"无" -->

### SUGGESTION
<!-- 无则写"无" -->

## Phase 2：代码质量审查

<!-- review_mode=light 时写"本次为 light 模式，跳过代码质量审查" -->

### CRITICAL
<!-- 无则写"无" -->

### WARNING
<!-- 无则写"无" -->

### SUGGESTION
<!-- 无则写"无" -->

## 偏差记录

<!-- 用户选择接受偏差时，在此填写接受原因和影响范围 -->
```

报告写入后更新状态：

```bash
"$COOL_BASH" "$COOL_STATE" set <change-name> review_report "$REPORT_PATH"
ABS=$("$COOL_BASH" "$COOL_STATE" abspath "$REPORT_PATH")
echo "审查报告已写入：$ABS"
```

### 6. 结果决策（阻塞点）

**判断是否有 CRITICAL findings（来自任一阶段）：**

**无 CRITICAL 时**：

```bash
"$COOL_BASH" "$COOL_STATE" transition <change-name> review-pass
```

进入 Step 7。

**有 CRITICAL 时**：

必须使用当前平台可用的用户输入/确认机制暂停，展示所有 CRITICAL 问题清单，提供两个选项：

- **「修复」**：执行 `"$COOL_BASH" "$COOL_STATE" transition <change-name> review-fail`，然后调用 `/cool-build` 进行修复
- **「接受偏差」**：在报告的"偏差记录"节填写接受原因和影响范围，然后执行 `"$COOL_BASH" "$COOL_STATE" transition <change-name> review-pass`

**连续失败限制**：

连续失败限制仅在**本次审查存在 CRITICAL 问题**（即即将触发「修复」路径）且 `REVIEW_FAIL_COUNT >= 3` 时生效。若本次审查通过（无 CRITICAL），无论 fail_count 为何值，均正常执行 `review-pass`，不触发强制暂停。

```bash
# 仅当本次有 CRITICAL 且已连续失败 3 次时触发
if [ "$(本次是否有 CRITICAL)" = "true" ] && [ "$REVIEW_FAIL_COUNT" -ge 3 ]; then
  # 强制暂停：不得自动选择，必须等待用户明确回复
  # 仅提供「接受所有偏差」或「继续修复」两个选项
fi
```

### 7. 阶段守卫退出

```bash
"$COOL_BASH" "$COOL_GUARD" <change-name> review --apply
```

全部 PASS 后 `phase` 推进到 `verify`，`review_result` 更新为 `pass`。

## 退出条件

- `review_report` 已写入且文件存在
- `review_result: pass`（通过 `review-pass` 转换或接受偏差后设置）
- **阶段守卫**：`"$COOL_BASH" "$COOL_GUARD" <change-name> review --apply` 全部 PASS

退出前必须使用 `--apply`：

```bash
"$COOL_BASH" "$COOL_GUARD" <change-name> review --apply
```

## 自动衔接下一阶段

守卫推进 phase 后，运行：

```bash
"$COOL_BASH" "$COOL_STATE" next <change-name>
```

- `NEXT: auto` → 自动调用 `/cool-verify`
- `NEXT: manual` → 提示用户手动运行 `/cool-verify`

> **扩展点：** `post-review` 与 `pre-verify` hook 在 `cool-guard review --apply` transition 前触发。在 `.cool/config.yaml` 的 `extensions.hooks` 配置（见 cool SKILL.md § 阶段扩展点）。
