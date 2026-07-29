# Decision Card — mini-user-taro

- **write_mode**: final-artifact
- **highest_risk_gap**: 两套框架(Taro/uni-app)在微信小程序+H5 双端下的请求层 baseURL 配置、路由 API、image/scroll-view 跨端兼容差异；以及原 mini-user 修 bug 后需保证原生小程序仍可正常运行。
- **next_action**: 创建 proposal/design/tasks → 进入 design 阶段做深度技术设计（目录结构、请求层抽象、跨端差异点、bug 修复方案）。
- **why_downstream_not_invent_what**: 源码 mini-user 已完整阅读（4 页面 + request 工具 + app 入口，功能/API/bug 均已定位）；用户已明确技术栈(Vue3+TypeScript)、目标端(微信小程序+H5)、范围(功能对等 + 修复明显 bug + 新建 mini-user-taro 与 mini-user-uniapp 两套多端版本)。design 阶段只决策 HOW，不再发明 WHAT。
