# Brainstorm Summary

- Change: mini-user-taro
- Date: 2026-07-29

## 确认的技术方案

两套独立工程（mini-user-taro / mini-user-uniapp），不共享 monorepo（YAGNI，4 页面应用抽象成本 > 收益）。各工程结构对称：`src/{app入口, pages/{index,serviceList,orderCreate,orderList}, utils/request.ts}`。

- Taro 版：Taro 4.x + Vue3 + TS + Sass，`app.ts`/`app.config.ts`/`app.scss`，页面 `.vue` + `.config.ts`
- uni-app 版：uni-app + Vue3 + TS + Sass，`main.ts`/`App.vue`/`pages.json`/`manifest.json`，页面 `.vue`
- 请求层 `request.ts`：`BASE_URL`+`TIMEOUT` 常量，封装 `Taro.request`/`uni.request`，响应 `{code,data,msg}` 约定
- 页面迁移：`Page({data,onLoad,setData})` → `<script setup lang="ts">` + `ref/reactive` + `onLoad/onShow`；`wx.*`→`Taro.*`/`uni.*`；`wx:for/wx:if`→`v-for/v-if`；`bindtap`→`@tap`
- 路由传参沿用 `encodeURIComponent(JSON.stringify(service))`

## 关键取舍与风险

- 取舍：不做跨框架代码共享（构建工具链差异大，共享抽象不划算）
- 风险1：H5 端 `image` 默认图路径需放入各工程 `src/` 静态目录
- 风险2：`scroll-view` 横向滚动 H5 下需 `white-space:nowrap` + `display:inline-block`
- 风险3：Taro 与 uni-app 页面生命周期钩子来源不同（`@tarojs/taro` vs `@dcloudio/uni-app`）

## 测试策略

不引入单元测试框架（对齐原项目 YAGNI）。手动验证：微信开发者工具跑通 4 页面流转；H5 `npm run dev:h5`(Taro) / `npm run dev:h5`(uni-app) 浏览器验证。验收点：3 个 bug 修复后行为正确 + 双端功能对等原版。

## Spec Patch

无（OpenSpec delta spec 验收场景已覆盖；本次为纯迁移 + bug 修复，不新增能力规格）。

## bug 修复方案（原 mini-user + 两版同步）

1. index 补 `toOrderCreate`：取 `dataset.service` → 跳转 orderCreate 传 service
2. orderList：`getOrders` 后 `map` 出 `create_time_formatted`，模板渲染该字段，删模板内方法调用
3. request：抽 `BASE_URL`+`timeout`+统一错误处理
