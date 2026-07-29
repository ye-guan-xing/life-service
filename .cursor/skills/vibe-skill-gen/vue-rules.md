# Vue / Nuxt Scan Rules

Apply when source is `.vue` or imports `vue`, `vue-router`, `nuxt/*`.

## Component Name

Priority order:

1. `defineOptions({ name: 'LoginPage' })`
2. `<script> export default { name: 'LoginPage' }`
3. Filename without extension, PascalCase (`login.vue` → `Login`)

## Page Slug

| Context | page value |
|---------|------------|
| Nuxt `pages/login.vue` | login |
| Nuxt `pages/admin/users.vue` | admin-users |
| Nuxt dynamic `pages/users/[id].vue` | users-id |
| Vue Router view `views/Checkout.vue` | checkout |

## Nuxt Route Inference

| File path | inferred route |
|-----------|----------------|
| `pages/index.vue` | `/` |
| `pages/login.vue` | `/login` |
| `pages/users/[id].vue` | `/users/:id` |
| `pages/admin/index.vue` | `/admin` |

## Buttons

Scan template bindings:

| Pattern | handler extraction |
|---------|-------------------|
| `@click="handleSubmit"` | handleSubmit |
| `@click="submit"` | submit |
| `v-on:click="resetForm"` | resetForm |
| `@submit.prevent="onSubmit"` | onSubmit |
| `@keyup.enter="search"` | search |

Interactive elements:

- `<button>`
- `<input type="submit">`
- `<a @click="...">`
- `<el-button @click="...">` (Element Plus)
- `<v-btn @click="...">` (Vuetify)

Composition API: handler may be `const handleSubmit = () => ...` in `<script setup>`.

For each match record:

- `id`: from `data-skill-id` or derive from handler
- `selector`: `[data-skill-id=<id>]`
- `label`: inner text or `:aria-label`
- `element`: tag name
- `line`: template line number

### data-skill-id

```vue
<button data-skill-id="login" @click="handleLogin">Login</button>
```

If missing, add to pending list — do not auto-patch source.

## Routes

### Vue Router

| Pattern | fields |
|---------|--------|
| `router.push('/dashboard')` | to, trigger: navigate |
| `router.push({ name: 'UserDetail', params: { id } })` | to: named route, trigger: navigate |
| `router.replace('/login')` | to, trigger: redirect |
| `<router-link to="/home">` | to, trigger: link |
| `<RouterLink :to="{ path: '/cart' }">` | to, trigger: link |
| `useRouter().push(...)` | same as router.push |

Extract `from` from:

- Nuxt/Vue file path convention
- `useRoute().path` usage in same file
- `definePageMeta` route config (Nuxt)

### Nuxt

| Pattern | fields |
|---------|--------|
| `navigateTo('/success')` | to, trigger: navigate |
| `navigateTo({ path: '/users' })` | to, trigger: navigate |
| `<NuxtLink to="/about">` | to, trigger: link |
| `<NuxtLink :to="localePath('/contact')">` | resolve if literal inside |

## APIs

| Pattern | extraction |
|---------|------------|
| `$fetch('/api/users')` | GET default, url |
| `$fetch('/api/users', { method: 'POST', body })` | method, url |
| `useFetch('/api/products')` | GET, url |
| `useAsyncData('key', () => $fetch('/api/x'))` | parse callback |
| `axios.post('/api/login', payload)` | POST, url |
| `axios.get`, `.put`, `.patch`, `.delete` | method from call |
| `api.get('/orders')` (custom client) | method, url |

Nuxt server routes: if call targets `/api/*` and matching `server/api/*` file exists, note in `description`.

Record `handler` as enclosing function or composable name.

Infer schemas from TypeScript interfaces in `<script setup lang="ts">`.

## CLI Derivation

```
cli = <domain>:<page>:<action>
```

| Item | action source |
|------|---------------|
| `@click="handleLogin"` | login |
| `@click="resetPassword"` | reset-password |
| route to `/dashboard` | go-dashboard |
| api POST `/api/login` | login (or post-login if ambiguous) |

## Options API vs Composition API

Both supported. For Options API:

- Methods in `methods: { handleSubmit() {} }` map to template `@click="handleSubmit"`
- `this.$router.push(...)` counts as route

## Scan Order

1. Parse `.vue` SFC: `<template>`, `<script>`, `<script setup>`
2. Resolve component name and page slug
3. Collect buttons from template
4. Collect routes from template + script
5. Collect APIs from script
6. Build cli index
7. Skip output if steps 3–5 all empty

## Common False Positives — Skip

- `@click.stop` on layout wrappers with no action
- `$fetch` in comments
- Test files (`*.spec.ts`, `*.test.ts` colocated tests)
- Mock handlers in `__mocks__`

## Example Scan Result

Source: `pages/login.vue`

```vue
<script setup>
const router = useRouter()
const handleLogin = async () => {
  await $fetch('/api/login', { method: 'POST', body: form })
  router.push('/dashboard')
}
</script>
<template>
  <button data-skill-id="login" @click="handleLogin">Login</button>
  <button data-skill-id="reset" @click="resetPassword">Reset</button>
</template>
```

Produces:

- 2 buttons: `login` → `auth:login:login`, `reset` → `auth:login:reset-password`
- 1 route: `/login` → `/dashboard` → `auth:login:go-dashboard`
- 1 api: POST `/api/login` → `auth:login:login-api` (disambiguate if button shares name: use `post-login`)

When button and api actions collide, suffix api with `-api` or use verb-noun from URL.
