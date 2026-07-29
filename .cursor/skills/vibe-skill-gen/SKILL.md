---
name: vibe-skill-gen
description: Scans Vibe Coding React/Vue source and generates CLI/button/route/API skill assets into .skill.json, syncs to .cursor/skills-registry/, optionally emits .skill.ts and Markdown registry README. Use when the user mentions Vibe Coding, CLI controlling GUI, generating Skills, scanning components/pages, refreshing skills-registry, or AI operating web pages without CV.
---

# Vibe Skill Gen

Scan React/Vue business code and produce the four-piece skill set: CLI commands, button clicks, route jumps, API calls.

## When to Use

- User asks to scan a page/component for Skills
- User asks to generate or refresh `.skill.json`
- User asks to sync `.cursor/skills-registry/`
- User asks to generate `.skill.ts` for runtime CLI control
- User finishes Vibe Coding a UI module and wants skill assets auto-generated

## Quick Workflow

Copy and track:

```
Task Progress:
- [ ] Step 1: Detect framework (react | vue)
- [ ] Step 2: Scan source for buttons, routes, APIs
- [ ] Step 3: Build schema payload
- [ ] Step 4: Write/merge <ComponentName>.skill.json (same directory as source)
- [ ] Step 5: Sync to .cursor/skills-registry/<slug>.json
- [ ] Step 6: Generate .skill.ts if runtime flag present
- [ ] Step 7: Regenerate .cursor/skills-registry/README.md
```

### Step 1: Detect Framework

| Signal | Framework |
|--------|-----------|
| `.tsx`, `.jsx`, imports from `react`, `next/*` | react |
| `.vue`, `<script setup>`, imports from `vue`, `vue-router`, `nuxt/*` | vue |

- React rules: [react-rules.md](react-rules.md)
- Vue rules: [vue-rules.md](vue-rules.md)

### Step 2: Scan Source

Extract four categories:

1. **buttons** — click/submit handlers bound to interactive elements
2. **routes** — navigation targets (Link, router.push, navigateTo, file-path routes)
3. **apis** — fetch/axios/$fetch/useFetch/useQuery calls
4. **cli** — derived from buttons/routes/apis using naming rules below

### Step 3: Build Payload

Follow [schema.md](schema.md). Use [templates.md](templates.md) for output shape.

Skip file generation if all four arrays would be empty.

### Step 4: Write Local `.skill.json`

Path: same directory as source, named `<ComponentName>.skill.json`.

Merge rules when file exists:

- Match items by `id`
- Never overwrite any item or field where `"manual": true`
- Add new scanned items; remove items only when source no longer contains them AND item is not `manual: true`
- Bump `updatedAt` (ISO 8601)

### Step 5: Sync Registry

Path: `.cursor/skills-registry/<slug>.json`

Slug priority:

1. Primary route path → kebab-case (e.g. `/checkout` → `checkout`)
2. Else source path relative to `src/` without extension (e.g. `pages/Checkout.tsx` → `pages-checkout`)

Registry file wraps one or more component skills:

```json
{
  "version": 1,
  "slug": "checkout",
  "updatedAt": "2026-05-19T00:00:00.000Z",
  "components": [ /* skill objects from .skill.json */ ]
}
```

When multiple components share a slug, merge `components` array by `source` path. Deduplicate `routes` by `from+to`, `apis` by `method+url`, `cli` by `name`.

### Step 6: Generate `.skill.ts` (Optional)

Generate only when ANY of:

- Source file top comment contains `@skill:runtime`
- Local `.skill.json` has `"runtime": true`

Output: same directory, `<ComponentName>.skill.ts`. Template in [templates.md](templates.md).

### Step 7: Regenerate Registry README

Path: `.cursor/skills-registry/README.md`

Auto-generated from all registry JSON files. Template in [templates.md](templates.md). Do not hand-edit; regenerate on every sync.

## Naming Rules

### CLI Format

`<domain>:<page>:<action>`

| Part | Rule |
|------|------|
| domain | Top-level feature area (cart, auth, admin) — infer from folder or route |
| page | Current page slug (kebab-case) |
| action | Handler or intent (submit, go-success, place-order) |

Examples:

- `cart:checkout:submit`
- `auth:login:reset-password`
- `admin:users:delete-user`

### Button ID

1. Prefer `data-skill-id` on element
2. Else derive from handler name in camelCase → kebab-case (`handleSubmit` → `submit`)
3. If ambiguous, list candidates and ask user before writing source

### Route ID

`<from-slug>-to-<to-slug>` or `to-<target>` when `from` unknown

### API ID

`<verb>-<resource>` from method + URL last segment (`POST /api/orders` → `post-orders`)

## Domain Inference

| Source hint | domain |
|-------------|--------|
| `src/features/cart/*` | cart |
| `pages/login.vue` | auth |
| Route `/admin/users` | admin |
| No hint | use page slug as domain |

## data-skill-id Policy

When scanned button lacks `data-skill-id`:

1. Output a **pending list** in response (element line, suggested id, suggested selector)
2. Do NOT modify source unless user explicitly approves
3. After approval, add only `data-skill-id="<id>"` — no other business logic changes

## Prohibited Actions

- Do not refactor business code
- Do not add tests
- Do not write project README or docs outside `.cursor/skills-registry/README.md`
- Do not use computer vision or screen reading
- Do not overwrite `manual: true` entries

## Full Registry Refresh

When user asks to refresh entire registry:

1. Glob all `**/*.skill.json` under project (exclude `node_modules`, `.cursor/skills-registry`)
2. Rebuild each registry slug from local files
3. Remove registry entries whose source file no longer exists
4. Regenerate README

## Additional Resources

- Schema: [schema.md](schema.md)
- React scan rules: [react-rules.md](react-rules.md)
- Vue scan rules: [vue-rules.md](vue-rules.md)
- Output templates: [templates.md](templates.md)
