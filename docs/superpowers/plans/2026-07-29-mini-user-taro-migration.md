---
change: mini-user-taro
design-doc: docs/superpowers/specs/2026-07-29-mini-user-taro-migration-design.md
base-ref: 56da8b92a35ee21f0b2330602090514717b694d7
archived-with: 2026-07-29-mini-user-taro
---

## Source Coverage

| Scenario | Plan 任务 |
|----------|-----------|
| （delta spec 未定义 Scenario）| — |

## 任务分解

### Task A：原 mini-user bug 修复
- A1. `mini-user/pages/index/index.js` 补 `toOrderCreate`（跳转 orderCreate 传 service）
- A2. `mini-user/pages/orderList/orderList.js` 预计算 `create_time_formatted`；`orderList.wxml` 模板改用该字段
- A3. `mini-user/utils/request.js` 抽 `BASE_URL`+`timeout`+统一错误处理
- 提交：`fix(mini-user): repair 3 obvious bugs (index nav, orderList time, request layer)`

### Task B：mini-user-taro 工程搭建
- B1. `npx @tarojs/cli init` 初始化 `mini-user-taro`（Vue3 + TS + Sass），双端配置
- B2. 配置 `app.config.ts`（pages 路由、window 导航栏对齐原版 #2c3e50 / 生活服务平台）
- B3. 迁移 `app.scss`（对齐原 `app.wxss`）
- 提交：`feat(mini-user-taro): scaffold Taro project (Vue3+TS+Sass, weapp+h5)`

### Task C：mini-user-taro 请求层
- C1. `src/utils/request.ts`（BASE_URL、TIMEOUT、Taro.request 封装、统一错误处理）
- 提交：`feat(mini-user-taro): add request util`

### Task D：mini-user-taro 4 页面迁移
- D1. index（分类 + 推荐 + 底部导航，含 toOrderCreate）
- D2. serviceList（搜索 + 分类筛选 + 列表 + 跳转）
- D3. orderCreate（服务信息 + 表单 + 校验 + 提交）
- D4. orderList（列表 + 时间预处理 + 空状态）
- 提交：`feat(mini-user-taro): migrate 4 pages`

### Task E：mini-user-uniapp 工程搭建
- E1. 初始化 `mini-user-uniapp`（Vue3 + TS + Sass，vue3/vite 模板）
- E2. 配置 `pages.json`/`manifest.json`（路由、导航栏对齐原版）
- E3. 全局样式
- 提交：`feat(mini-user-uniapp): scaffold uni-app project (Vue3+TS+Sass, weapp+h5)`

### Task F：mini-user-uniapp 请求层
- F1. `src/utils/request.ts`（uni.request 封装）
- 提交：`feat(mini-user-uniapp): add request util`

### Task G：mini-user-uniapp 4 页面迁移
- G1. index / G2. serviceList / G3. orderCreate / G4. orderList
- 提交：`feat(mini-user-uniapp): migrate 4 pages`

### Task H：验证
- H1. 微信开发者工具跑通两版 4 页面流转
- H2. H5 端 `npm run dev:h5` 浏览器验证
- H3. 原 mini-user 修 bug 后仍可运行
- 提交：`test: manual verification notes`

## 执行约束
- tdd_mode: direct（UI 迁移 + 无测试框架，手动验证）
- 每任务完成 → 勾选 tasks.md 对应项 → git commit
