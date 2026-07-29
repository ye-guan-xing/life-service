# Cool Design Handoff

- Change: mini-user-taro
- Phase: design
- Mode: compact
- Context hash: 53387154445f4557eb164fdaedb597e2f5bb137e9a1f72018f9391a6b182d16c

Generated-by: cool-handoff.sh

OpenSpec remains the canonical capability spec. This handoff is a deterministic, source-traceable context pack, not an agent-authored summary.

## openspec/changes/mini-user-taro/proposal.md

- Source: openspec/changes/mini-user-taro/proposal.md
- Lines: 1-41
- SHA256: 2082e0292ae4a5700a520e6b78af6c70927ee25bfa97a7daad3f771d31cbb7e1

```md
# Proposal: mini-user-taro

## Why

现有 `mini-user` 是原生微信小程序（WXML/WXSS/JS），只能在微信端运行，且存在若干明显 bug（推荐服务点击无响应、订单列表时间格式化失效、请求层硬编码地址无错误处理）。需要将其迁移到跨端框架，一次开发同时产出微信小程序与 H5，并顺带修复原项目缺陷。

## What

将 `mini-user` 的 4 个页面（index / serviceList / orderCreate / orderList）+ request 工具 + app 入口，迁移为两套独立的多端实现，并修复原项目明显 bug：

1. **`mini-user-taro`**：基于 Taro 4.x + Vue3 + TypeScript + Sass，目标端微信小程序 + H5。
2. **`mini-user-uniapp`**：基于 uni-app + Vue3 + TypeScript + Sass，目标端微信小程序 + H5，功能与 Taro 版对等。
3. **原 `mini-user` 修复**：同步修复下列明显 bug，保证原生小程序仍可运行。

### 修复的明显 bug

| # | 位置 | 问题 | 修复方向 |
|---|------|------|---------|
| 1 | `pages/index/index.wxml` + `index.js` | 推荐服务卡片绑定 `toOrderCreate`，但 `index.js` 未定义该方法 → 点击无响应 | 补全 `toOrderCreate`，跳转 orderCreate 并传递 service |
| 2 | `pages/orderList/orderList.wxml` | `{{formatTime(item.create_time)}}` 在 WXML 模板中调用方法不生效 → 时间不显示 | 数据预处理：`getOrders` 中计算 `create_time_formatted`，模板直接渲染 |
| 3 | `utils/request.js` | 硬编码 `http://localhost:8080/api`，无超时、无错误码细分 | 抽出可配置 baseURL，统一超时与错误处理 |

## Scope

- 涉及模块：4 页面 + request 工具 + app 入口配置
- 平台：微信小程序 + H5
- 沿用后端 API（`localhost:8080/api`，`/service/list`、`/order/create`、`/order/list`），仅前端迁移
- 保持原视觉与交互，不重设计 UI

## Non-goals

- 不新增业务功能或新页面
- 不引入状态管理库（保持简单模块化）
- 不改动后端
- 不删除原 `mini-user` 目录（保留并在其上修 bug）

## Impact

- 新增目录 `mini-user-taro/`、`mini-user-uniapp/`（两套完整 Taro / uni-app 工程）
- 修改 `mini-user/pages/index/index.js`、`mini-user/pages/orderList/orderList.{js,wxml}`、`mini-user/utils/request.js`
- 不影响 `server/`、`web-admin/`
```

## openspec/changes/mini-user-taro/design.md

- Source: openspec/changes/mini-user-taro/design.md
- Lines: 1-76
- SHA256: ec04cfa566f133c6d46cf68d940c183ea2e2924695e303892c3e91710f82cbe8

```md
# Design: mini-user-taro

> 高层架构决策。深度技术设计在 design 阶段的 Design Doc 中展开。

## 方案选型

| 维度 | Taro 版 | uni-app 版 |
|------|---------|-----------|
| 框架 | Taro 4.x | uni-app (Vue3) |
| UI 语法 | Vue3 SFC + JSX 无关 | Vue3 SFC |
| 语言 | TypeScript | TypeScript |
| 样式 | Sass | Sass |
| 目标端 | 微信小程序 + H5 | 微信小程序 + H5 |
| 状态 | 简单模块（无 Pinia/Redux） | 简单模块（无 Pinia） |

两版均以「最小改写」为原则：逻辑结构对齐原 `mini-user`，仅替换框架 API。

## 目录结构（两版对称）

```
mini-user-taro/                 mini-user-uniapp/
├── src/                        ├── src/
│   ├── app.ts                  │   ├── main.ts
│   ├── app.config.ts           │   ├── pages.json
│   ├── app.scss                │   ├── App.vue
│   ├── pages/                  │   ├── pages/
│   │   ├── index/              │   │   ├── index/
│   │   ├── serviceList/        │   │   ├── serviceList/
│   │   ├── orderCreate/        │   │   ├── orderCreate/
│   │   └── orderList/          │   │   └── orderList/
│   └── utils/                  │   └── utils/
│       └── request.ts          │       └── request.ts
├── config/ (Taro)              ├── manifest.json (uni-app)
├── project.config.json         ├── pages.json
├── tsconfig.json               ├── tsconfig.json
└── package.json                └── package.json
```

## 关键映射

| 原生 API | Taro | uni-app |
|----------|------|---------|
| `wx.request` | `Taro.request` | `uni.request` |
| `wx.showToast` | `Taro.showToast` | `uni.showToast` |
| `wx.navigateTo` | `Taro.navigateTo` | `uni.navigateTo` |
| `wx.showLoading/hideLoading` | `Taro.*` | `uni.*` |
| Page `onLoad/onShow` | Vue3 `onLoad`/`onShow` 生命周期 | Vue3 `onLoad`/`onShow` |
| `this.setData` | 响应式 `ref`/`reactive` | 响应式 `ref`/`reactive` |
| `wx:for` / `wx:if` | `v-for` / `v-if` | `v-for` / `v-if` |

## 请求层抽象

`utils/request.ts` 统一封装：
- `BASE_URL` 抽为常量（默认 `http://localhost:8080/api`），便于环境切换
- 统一 `timeout`（默认 10s）
- 响应约定 `{code, data, msg}`：`code===200` resolve(data)，否则 reject(msg)
- 网络失败 reject 带语义文案

## bug 修复方案（原 mini-user + 两版同步）

1. **index 跳转缺失**：`index.js` 补 `toOrderCreate(e)`，取 `dataset.service`，`wx.navigateTo` 到 orderCreate 并 `encodeURIComponent(JSON.stringify(service))`。两版用框架等价 API。
2. **orderList 时间格式化**：`getOrders` 取数后 `map` 预计算 `create_time_formatted`，模板渲染该字段；删除模板内的方法调用。两版同理。
3. **request 硬编码**：抽出 `BASE_URL` 与 `timeout`，统一错误处理。两版同理。

## 数据流

```
页面 onLoad → request.ts 调 /api/* → resolve(data) → 响应式状态更新 → 模板渲染
用户操作 → 校验 → request.ts POST → 成功 toast → 跳转
```

## 跨端差异点（design 阶段细化）

- H5 路由：Taro 用 browser history，uni-app H5 用 history 模式，均由框架路由 API 屏蔽
- `image` 默认图：`/images/default-service.png` 两版均需放入对应 static 目录
- `scroll-view` 横向滚动：双端均支持，样式需保证 H5 下 `white-space: nowrap`
```

## openspec/changes/mini-user-taro/tasks.md

- Source: openspec/changes/mini-user-taro/tasks.md
- Lines: 1-47
- SHA256: c0d4221ad571f267af00b444ddb7cfd7b66eeb2e229b521fbaacbaaa81846822

```md
# Tasks: mini-user-taro

## A. 原 mini-user bug 修复

- [ ] A1. `mini-user/pages/index/index.js` 补 `toOrderCreate` 方法，跳转 orderCreate 并传 service
- [ ] A2. `mini-user/pages/orderList/orderList.js` getOrders 中预计算 `create_time_formatted`；`orderList.wxml` 模板改用该字段
- [ ] A3. `mini-user/utils/request.js` 抽出 `BASE_URL` + `timeout`，统一错误处理

## B. mini-user-taro 工程搭建

- [ ] B1. 用 Taro CLI 初始化 `mini-user-taro`（Vue3 + TS + Sass），配置微信小程序 + H5 双端
- [ ] B2. 配置 `app.config.ts`（pages 路由、window 导航栏样式对齐原版）
- [ ] B3. 迁移全局样式 `app.scss`（对齐原 `app.wxss`）

## C. mini-user-taro 请求层

- [ ] C1. 实现 `src/utils/request.ts`（BASE_URL、timeout、统一错误处理）

## D. mini-user-taro 页面迁移

- [ ] D1. index 页（分类 + 推荐服务 + 底部导航，含 toOrderCreate）
- [ ] D2. serviceList 页（搜索 + 分类筛选 + 列表 + 跳转下单）
- [ ] D3. orderCreate 页（服务信息 + 表单 + 校验 + 提交）
- [ ] D4. orderList 页（列表 + 时间格式化预处理 + 空状态）

## E. mini-user-uniapp 工程搭建

- [ ] E1. 初始化 `mini-user-uniapp`（Vue3 + TS + Sass），配置微信小程序 + H5
- [ ] E2. 配置 `pages.json`、`manifest.json`（路由、导航栏样式对齐原版）
- [ ] E3. 迁移全局样式 `App.vue` / 全局 scss

## F. mini-user-uniapp 请求层

- [ ] F1. 实现 `src/utils/request.ts`（uni.request 封装）

## G. mini-user-uniapp 页面迁移

- [ ] G1. index 页
- [ ] G2. serviceList 页
- [ ] G3. orderCreate 页
- [ ] G4. orderList 页

## H. 验证

- [ ] H1. 微信小程序端：两版 4 页面流转与原版一致
- [ ] H2. H5 端：两版 4 页面可运行，路由/请求/样式正常
- [ ] H3. 原 mini-user 修 bug 后原生小程序仍可运行
```

