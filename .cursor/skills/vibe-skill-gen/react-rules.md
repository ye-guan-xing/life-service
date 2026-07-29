# React / Next.js Scan Rules

Apply when source is `.tsx`, `.jsx`, or imports `react` / `next/*`.

## Component Name

Priority order:

1. `export default function CheckoutPage`
2. `export const CheckoutPage = ...`
3. `function CheckoutPage` with default export
4. Filename without extension, PascalCase

## Page Slug

| Context | page value |
|---------|------------|
| Next.js App Router `app/checkout/page.tsx` | checkout |
| Next.js Pages Router `pages/checkout.tsx` | checkout |
| Next.js dynamic `app/users/[id]/page.tsx` | users-id |
| Generic `src/pages/Checkout.tsx` | checkout (from name, kebab-case) |

## Buttons

Scan JSX attributes:

| Pattern | handler extraction |
|---------|-------------------|
| `onClick={handleSubmit}` | `handleSubmit` |
| `onClick={() => foo()}` | `foo` |
| `onSubmit={onSubmit}` | `onSubmit` |
| `<form onSubmit={...}>` | form submit handler |

Interactive elements:

- `<button>`
- `<input type="submit">`
- `<a>` with onClick
- `<div role="button">` with onClick

For each match record:

- `id`: from `data-skill-id` or derive from handler
- `selector`: `[data-skill-id=<id>]` or tag + text fallback
- `label`: child text, `aria-label`, or `title`
- `element`: tag name
- `line`: source line number

### data-skill-id

```jsx
<button data-skill-id="submit" onClick={onSubmit}>Place Order</button>
```

If missing, add to pending list — do not auto-patch source.

## Routes

### React Router

| Pattern | fields |
|---------|--------|
| `navigate('/success')` | to: `/success`, trigger: navigate |
| `navigate('/users/' + id)` | to: `/users/:id`, trigger: navigate |
| `<Link to="/cart">` | to: `/cart`, trigger: link |
| `<NavLink to="/settings">` | to: `/settings`, trigger: link |
| `useNavigate()` variable calls | trace all `.push` / `.replace` / direct call |

Extract `from` from:

- Current file route if inferable from path
- `useLocation().pathname` usage
- Next.js file path convention

### Next.js

| Pattern | fields |
|---------|--------|
| `router.push('/success')` | to, trigger: navigate |
| `router.replace('/login')` | to, trigger: redirect |
| `<Link href="/about">` | to, trigger: link |
| `redirect('/home')` (server) | to, trigger: redirect |

App Router page path from file location when `to` is relative.

## APIs

| Pattern | extraction |
|---------|------------|
| `fetch('/api/orders', { method: 'POST' })` | method, url |
| `fetch(url, options)` | resolve url variable if literal |
| `axios.post('/api/orders', body)` | POST, url |
| `axios.get`, `.put`, `.patch`, `.delete` | method from call |
| `apiClient.post(...)` | treat as axios-like |
| `useSWR('/api/user', fetcher)` | GET, url from first arg |
| `useQuery({ queryKey: ['orders'], queryFn: () => fetch(...) })` | parse queryFn body |

Record `handler` as enclosing function name when call is inside one.

Infer `reqSchema` / `resSchema` from:

- Inline object literals in call
- TypeScript interfaces/types on same file referenced by handler
- JSDoc `@param` / `@returns` when present

## CLI Derivation

For each extracted item:

```
cli = <domain>:<page>:<action>
```

| Item | action source |
|------|---------------|
| button handler `handleSubmit` | submit |
| button handler `onResetPassword` | reset-password |
| route to `/success` | go-success |
| api POST `/api/orders` | place-order |

## Scan Order

1. Read full file
2. Resolve component name and page slug
3. Collect buttons (JSX tree)
4. Collect routes (navigate/Link/router)
5. Collect APIs (fetch/axios/hooks)
6. Build cli index
7. Skip output if steps 3–5 all empty

## Next.js App Router Route Inference

| File path | inferred route |
|-----------|----------------|
| `app/page.tsx` | `/` |
| `app/checkout/page.tsx` | `/checkout` |
| `app/blog/[slug]/page.tsx` | `/blog/[slug]` |
| `app/(shop)/cart/page.tsx` | `/cart` (ignore route groups) |

## Common False Positives — Skip

- `onClick` on non-interactive wrappers with no semantic action
- `fetch` inside comments or string literals
- Test files (`*.test.tsx`, `*.spec.tsx`)
- Storybook files (`*.stories.tsx`)

## Example Scan Result

Source: `src/pages/Checkout.tsx`

```tsx
export default function CheckoutPage() {
  const navigate = useNavigate();
  const onSubmit = async () => {
    await axios.post('/api/orders', { items });
    navigate('/success');
  };
  return (
    <button data-skill-id="submit" onClick={onSubmit}>Place Order</button>
  );
}
```

Produces:

- 1 button: `submit` → `cart:checkout:submit`
- 1 route: `/checkout` → `/success` → `cart:checkout:go-success`
- 1 api: POST `/api/orders` → `cart:checkout:place-order`
