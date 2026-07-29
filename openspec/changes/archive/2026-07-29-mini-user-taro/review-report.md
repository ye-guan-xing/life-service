# 审查报告

- Change: mini-user-taro
- 日期: 2026-07-29
- review_mode: full
- 执行模式: isolated（双子代理并行）

## Phase 1：规格合规审查

### CRITICAL
无

### WARNING
- **request 错误码处理为最低满足**：三处 request 仅按 `code===200` 二分（resolve data / reject msg），未对 401/500 等细分；`BASE_URL` 抽为模块顶常量但未做环境化配置。proposal 的 bug#3 修复方向为"抽为可配置 baseURL + 统一错误处理"，当前属最低满足（统一错误处理已做，环境化未做）。evidence: `mini-user/utils/request.js`, `mini-user-taro/src/utils/request.ts:3-27`, `mini-user-uniapp/src/utils/request.ts:1-26`

### SUGGESTION
- Bug1/Bug2 三处（原项目/Taro/uni-app）均正确修复，功能对等。
- 4 页面逻辑、字段、交互与原版一致，无功能缺失。
- orderList onLoad+onShow 双触发 getOrders（沿用原版行为，对等迁移非回归）。
- 下单成功 navigateTo 跳 orderList（沿用原版，页面栈叠加风险可后续优化）。
- Taro `app.ts` 存在未使用的 `createApp` 导入（不影响构建）。
- 注：子代理将原目录误记为 `mini-user-wx`，实际为 `mini-user`，不影响结论。

## Phase 2：代码质量审查

### CRITICAL
无

### WARNING
- **安全**：`BASE_URL` 硬编码 `http://localhost:8080/api`，HTTP 非 HTTPS，真机/生产不可用。沿用原版，部署时需改为 HTTPS 域名。evidence: `mini-user-taro/src/utils/request.ts:3`, `mini-user-uniapp/src/utils/request.ts:1`
- **安全**：orderList 完整展示 `user_phone` 未脱敏。沿用原版行为。evidence: `*/pages/orderList/orderList.vue:25`
- **性能**：orderList useLoad+useDidShow 双触发首屏重复请求。沿用原版。evidence: `*/pages/orderList/orderList.vue:64-70`
- **质量**：URL query 传递整个 Service 对象（JSON.stringify+encodeURIComponent），小程序 URL 长度有限。沿用原版传参方式。evidence: `*/pages/index/index.vue:93`

### SUGGESTION
- orderCreate `service.value!.id` 非空断言，建议 submitOrder 内显式判空。
- index `toServiceList` 中文 type 未 encodeURIComponent，H5 端可能乱码。
- request.ts `res.data as ApiResponse<T>` 无运行时校验。
- 输入事件参数标注为 `any`，丢失类型安全。
- App.vue/app.ts 保留 console.log 启动日志。
- Taro 与 uni-app 页面代码高度重复，可抽共享业务模块（类型/校验/格式化）。
- serviceList 搜索为前端全量 filter，数据量大时应改后端过滤。
- 关键路径（request 错误分支、手机号校验）建议补手测用例清单。

## 偏差记录

接受以下偏差（均为沿用原版 `mini-user` 的既有行为，本次范围为对等迁移 + 3 bug 修复，改这些会超出非目标"不新增功能"）：

1. request 错误码仅二分 + BASE_URL 非环境化：bug#3 修复方向"统一错误处理"已满足，"可配置 baseURL"以模块顶常量最低满足；HTTPS/域名属部署期事项，与原版一致。
2. 手机号未脱敏：原版订单列表即完整展示手机号，对等迁移保留。
3. orderList 双请求、URL 传整对象、navigateTo 栈叠加：均为原版既有行为，对等保留。

上述偏差不影响本次合规性（无 CRITICAL），仅作后续优化备忘。
