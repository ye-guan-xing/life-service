---
cool_change: mini-user-taro
role: technical-design
canonical_spec: openspec
archived-with: 2026-07-29-mini-user-taro
status: final
---

# Design Doc: mini-user → Taro / uni-app 多端迁移

## 1. 背景与目标

将原生微信小程序 `mini-user`（WXML/WXSS/JS，仅微信端）迁移为两套多端实现，目标端均为**微信小程序 + H5**：

- `mini-user-taro`：Taro 4.x + Vue3 + TypeScript + Sass
- `mini-user-uniapp`：uni-app + Vue3 + TypeScript + Sass

功能与原版对等，并同步修复原 `mini-user` 的 3 个明显 bug。不新增业务功能、不引入状态管理库、不改后端、不删原目录。

## 2. 总体架构

### 2.1 两套独立工程（不共享 monorepo）

Taro 与 uni-app 构建工具链差异大（Taro: `@tarojs/cli` + `config/`；uni-app: `pages.json`/`manifest.json` + vite）。4 页面应用共享代码的抽象成本 > 收益，YAGNI。两套工程各自完整，逻辑结构对齐原 `mini-user`。

### 2.2 目录结构（对称）

```
mini-user-taro/                mini-user-uniapp/
├── src/                       ├── src/
│   ├── app.ts                 │   ├── main.ts
│   ├── app.config.ts          │   ├── App.vue
│   ├── app.scss               │   ├── pages.json
│   ├── pages/                 │   ├── pages/
│   │   ├── index/             │   │   ├── index/
│   │   │   ├── index.vue      │   │   │   └── index.vue
│   │   │   └── index.config.ts│   │   ├── serviceList/
│   │   ├── serviceList/       │   │   ├── orderCreate/
│   │   ├── orderCreate/       │   │   └── orderList/
│   │   └── orderList/         │   └── utils/
│   └── utils/request.ts       │       └── request.ts
├── config/index.ts            ├── manifest.json
├── project.config.json        ├── tsconfig.json
├── tsconfig.json              └── package.json
└── package.json
```

## 3. 请求层设计

`src/utils/request.ts`（两版结构一致，仅底层 API 不同）：

```ts
const BASE_URL = 'http://localhost:8080/api'
const TIMEOUT = 10000

type ApiResponse<T> = { code: number; data: T; msg: string }

function request<T>(url: string, method: 'GET' | 'POST' = 'GET', data: Record<string, unknown> = {}): Promise<T> {
  return new Promise((resolve, reject) => {
    Taro.request({  // uni-app 版为 uni.request
      url: BASE_URL + url, method, data, timeout: TIMEOUT,
      success: (res) => {
        const body = res.data as ApiResponse<T>
        if (body.code === 200) resolve(body.data)
        else reject(body.msg)
      },
      fail: (err) => reject('网络请求失败：' + err.errMsg)
    })
  })
}
export default request
```

统一约定：`code===200` → resolve(data)；否则 reject(msg)；网络失败 reject 带语义文案。`BASE_URL` 抽常量便于环境切换。

## 4. 页面迁移映射

| 原生 | Taro / uni-app |
|------|----------------|
| `Page({ data, onLoad, setData })` | `<script setup lang="ts">` + `ref()`/`reactive()` + `onLoad(options)` 钩子 |
| `this.setData({ key: val })` | `key.value = val`（ref）/ `state.key = val`（reactive） |
| `wx.request` | `Taro.request` / `uni.request`（封装于 request.ts） |
| `wx.showToast` / `wx.showLoading` / `wx.hideLoading` | `Taro.*` / `uni.*` |
| `wx.navigateTo` | `Taro.navigateTo` / `uni.navigateTo` |
| `wx:for` / `wx:if` | `v-for` / `v-if` |
| `bindtap` | `@tap`（小程序）/ `@click`（H5）→ 统一用 `@tap` |
| `bindinput` / `e.detail.value` | `@input` / `e.detail.value`（Taro/uni-app 保持 detail 结构） |

**页面生命周期钩子来源差异**：
- Taro：从 `@tarojs/taro` 导入 `onLoad`、`onShow`（页面级组合式 API）
- uni-app：从 `@dcloudio/uni-app` 导入 `onLoad`、`onShow`

**路由传参**：沿用原版 `encodeURIComponent(JSON.stringify(service))`，`onLoad(options)` 中 `JSON.parse(decodeURIComponent(options.service))`。

## 5. 各页面设计

### 5.1 index
- 分类网格（家政/维修/保洁）→ `@tap` 跳 serviceList 带 `type`
- 推荐服务（`/service/list` 前 4 条）→ **补 `toOrderCreate`**（原 bug 修复）：`@tap` 跳 orderCreate 传 service
- 底部导航：全部服务 / 我的订单

### 5.2 serviceList
- 搜索框（`@input` 更新 keyword，`@tap` 触发搜索）
- 分类横向滚动（`scroll-view scroll-x`）+ active 高亮
- 服务列表 → `@tap` 跳 orderCreate 传 service
- 空状态

### 5.3 orderCreate
- 服务信息卡片（`service` 来自路由参数）
- 表单：姓名 + 手机号（`@input`）
- 校验：非空 + 手机号正则 `/^1[3-9]\d{9}$/`
- 提交：`request('/order/create','POST',{service_id,user_name,user_phone})` → toast → 跳 orderList

### 5.4 orderList
- `onLoad` + `onShow` 调 `/order/list`
- **时间格式化预处理**（原 bug 修复）：`getOrders` 后 `map` 出 `create_time_formatted`，模板渲染该字段
- 状态显示（status===0 待支付 / 已完成）
- 空状态

## 6. bug 修复方案（原 mini-user + 两版同步）

| # | 位置 | 修复 |
|---|------|------|
| 1 | index | 补 `toOrderCreate`：`dataset.service` → 跳转 orderCreate 并传 service（原生版 `wx.navigateTo`；两版用框架 API） |
| 2 | orderList | `getOrders` 中 `map` 预计算 `create_time_formatted`，模板改用该字段，删除模板内方法调用 |
| 3 | request | 抽 `BASE_URL`+`timeout`，统一错误处理（code≠200 reject(msg)，网络失败 reject 文案） |

原 `mini-user` 修复后须保证原生小程序仍可运行（不改框架，仅修上述 3 处）。

## 7. 跨端差异处理

| 差异点 | 处理 |
|--------|------|
| H5 路由 | Taro browser history / uni-app history 模式，框架路由 API 屏蔽 |
| `image` 默认图 `/images/default-service.png` | 各工程 `src/` 下放静态图，引用相对路径 |
| `scroll-view` 横向滚动 H5 | 样式保证 `white-space: nowrap` + 子项 `display: inline-block` |
| `@tap` vs `@click` | 统一 `@tap`，Taro/uni-app 双端均支持 |

## 8. 测试策略

不引入单元测试框架（对齐原项目 YAGNI）。手动验证：

1. **微信小程序端**（微信开发者工具）：两版 4 页面流转与原版一致
2. **H5 端**：Taro `npm run dev:h5`、uni-app `npm run dev:h5` 浏览器验证路由/请求/样式
3. **原 mini-user**：修 bug 后微信开发者工具确认仍可运行
4. **验收点**：3 个 bug 修复后行为正确 + 双端功能对等

## 9. 数据流

```
页面 onLoad → request.ts(url, method, data)
  → Taro.request/uni.request → 后端 localhost:8080/api
  → success: {code,data,msg} → code===200 ? resolve(data) : reject(msg)
  → 响应式状态更新 → 模板渲染
用户操作 → 校验 → request POST → 成功 toast → navigateTo 下一页
```

## 10. 非目标

- 不新增业务功能/新页面
- 不引入状态管理库
- 不改后端
- 不删除原 `mini-user` 目录
- 不做 UI 重设计
