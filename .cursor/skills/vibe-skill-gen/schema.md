# .skill.json Schema

Single-component skill definition. One file per component, co-located with source.

## Root Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| version | number | yes | Schema version, currently `1` |
| component | string | yes | PascalCase component name |
| framework | `"react"` \| `"vue"` | yes | Detected framework |
| source | string | yes | Relative path to source file |
| domain | string | yes | Feature domain for CLI prefix |
| page | string | yes | Page slug (kebab-case) |
| runtime | boolean | no | When true, emit `.skill.ts` |
| updatedAt | string | yes | ISO 8601 timestamp |
| buttons | Button[] | yes | Click/submit bindings |
| routes | Route[] | yes | Navigation entries |
| apis | Api[] | yes | HTTP/API calls |
| cli | CliEntry[] | yes | Flat CLI command index |

Empty arrays are valid. Do not write file if all three of `buttons`, `routes`, `apis` are empty.

## Button

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string | yes | Unique within component |
| selector | string | yes | CSS selector, prefer `[data-skill-id=<id>]` |
| cli | string | yes | CLI command name |
| handler | string | yes | Function/handler name in source |
| label | string | no | Visible text or aria-label |
| element | string | no | Tag hint (`button`, `a`, `form`) |
| line | number | no | Source line for traceability |
| manual | boolean | no | When true, never auto-overwrite |

```json
{
  "id": "submit",
  "selector": "[data-skill-id=submit]",
  "cli": "cart:checkout:submit",
  "handler": "onSubmit",
  "label": "Place Order",
  "element": "button",
  "line": 42
}
```

## Route

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string | yes | Unique within component |
| from | string | no | Current route path |
| to | string | yes | Target route path |
| cli | string | yes | CLI command name |
| trigger | string | no | How navigation fires (`link`, `navigate`, `redirect`) |
| line | number | no | Source line |
| manual | boolean | no | When true, never auto-overwrite |

```json
{
  "id": "checkout-to-success",
  "from": "/checkout",
  "to": "/success",
  "cli": "cart:checkout:go-success",
  "trigger": "navigate",
  "line": 58
}
```

## Api

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string | yes | Unique within component |
| method | string | yes | HTTP method (GET, POST, PUT, PATCH, DELETE) |
| url | string | yes | Request URL or path |
| cli | string | yes | CLI command name |
| handler | string | no | Wrapper function name |
| reqSchema | object | no | Request body/query shape |
| resSchema | object | no | Response shape |
| line | number | no | Source line |
| manual | boolean | no | When true, never auto-overwrite |

```json
{
  "id": "place-order",
  "method": "POST",
  "url": "/api/orders",
  "cli": "cart:checkout:place-order",
  "handler": "submitOrder",
  "reqSchema": { "items": "array", "addressId": "string" },
  "resSchema": { "orderId": "string" },
  "line": 31
}
```

## CliEntry

Flat index linking CLI name to skill item.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | yes | CLI command (`domain:page:action`) |
| type | `"button"` \| `"route"` \| `"api"` | yes | Target category |
| ref | string | yes | Dot path: `buttons.submit`, `routes.checkout-to-success`, `apis.place-order` |
| description | string | no | Human-readable summary |
| manual | boolean | no | When true, never auto-overwrite |

```json
{
  "name": "cart:checkout:submit",
  "type": "button",
  "ref": "buttons.submit",
  "description": "Click submit button on checkout page"
}
```

## Registry Wrapper (`.cursor/skills-registry/<slug>.json`)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| version | number | yes | Always `1` |
| slug | string | yes | Registry key |
| updatedAt | string | yes | ISO 8601 |
| components | SkillRoot[] | yes | Array of `.skill.json` objects |

## Full Example

```json
{
  "version": 1,
  "component": "CheckoutPage",
  "framework": "react",
  "source": "src/pages/Checkout.tsx",
  "domain": "cart",
  "page": "checkout",
  "runtime": false,
  "updatedAt": "2026-05-19T12:00:00.000Z",
  "buttons": [
    {
      "id": "submit",
      "selector": "[data-skill-id=submit]",
      "cli": "cart:checkout:submit",
      "handler": "onSubmit",
      "label": "Place Order",
      "element": "button",
      "line": 42
    }
  ],
  "routes": [
    {
      "id": "checkout-to-success",
      "from": "/checkout",
      "to": "/success",
      "cli": "cart:checkout:go-success",
      "trigger": "navigate",
      "line": 58
    }
  ],
  "apis": [
    {
      "id": "place-order",
      "method": "POST",
      "url": "/api/orders",
      "cli": "cart:checkout:place-order",
      "handler": "submitOrder",
      "reqSchema": { "items": "array", "addressId": "string" },
      "resSchema": { "orderId": "string" },
      "line": 31
    }
  ],
  "cli": [
    {
      "name": "cart:checkout:submit",
      "type": "button",
      "ref": "buttons.submit",
      "description": "Submit checkout form"
    },
    {
      "name": "cart:checkout:go-success",
      "type": "route",
      "ref": "routes.checkout-to-success",
      "description": "Navigate to success page"
    },
    {
      "name": "cart:checkout:place-order",
      "type": "api",
      "ref": "apis.place-order",
      "description": "POST /api/orders"
    }
  ]
}
```

## Manual Override Example

```json
{
  "id": "submit",
  "selector": "[data-testid=checkout-submit]",
  "cli": "cart:checkout:submit",
  "handler": "onSubmit",
  "manual": true
}
```

When `manual: true`, preserve entire object on rescan. Other fields on the same object are also frozen.

## Merge Algorithm

1. Load existing `.skill.json` if present
2. Scan source → produce candidate object
3. For each array (`buttons`, `routes`, `apis`, `cli`):
   - Keep items with `manual: true` unchanged
   - Update non-manual items matched by `id`
   - Append new ids from scan
   - Drop non-manual items absent from scan
4. Rebuild `cli` array from buttons/routes/apis unless individual cli entries are `manual: true`
5. Set `updatedAt` to now
