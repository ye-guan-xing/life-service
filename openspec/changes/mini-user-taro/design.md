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
