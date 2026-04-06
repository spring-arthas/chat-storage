# Analyze Task — 需求理解与技术设计

在开始任何编码之前，完成需求理解和技术设计，并等待用户确认。

---

## 操作标记说明

| 标记 | 含义 |
|------|------|
| `[AI]` | Claude 执行 |
| `[USER]` | 等待用户确认后才能继续 |

---

## Step 1：读取任务上下文 `[AI]`

```bash
cat .trellis/tasks/$(cat .trellis/.current-task)/prd.md
cat .trellis/spec/backend/index.md
cat .trellis/spec/backend/api-module.md

