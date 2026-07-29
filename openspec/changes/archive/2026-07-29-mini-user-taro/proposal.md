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
