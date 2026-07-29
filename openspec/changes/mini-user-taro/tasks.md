# Tasks: mini-user-taro

## A. 原 mini-user bug 修复

- [x] A1. `mini-user/pages/index/index.js` 补 `toOrderCreate` 方法，跳转 orderCreate 并传 service
- [x] A2. `mini-user/pages/orderList/orderList.js` getOrders 中预计算 `create_time_formatted`；`orderList.wxml` 模板改用该字段
- [x] A3. `mini-user/utils/request.js` 抽出 `BASE_URL` + `timeout`，统一错误处理

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
