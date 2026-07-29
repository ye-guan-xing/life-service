// 1. 导入创建路由的工具

import { createRouter, createWebHistory } from "vue-router";
// createRouter：用来创建路由实例（相当于“接待员”本身）
// createWebHistory：路由模式（用无#号的URL，比如 http://localhost:8080/service，更美观）

// 2. 导入需要跳转的页面组件（“房间”本身）
import Merchant from "../views/Merchant/index.vue";
import Service from "../views/Service/index.vue";
import Order from "../views/Order/index.vue";

// 3. 定义“地址→页面”的对应规则（“房间号→房间”的对照表）

const routes = [
  {
    path: "/",
    redirect: "/merchant", // 核心：访问 "/" 时自动跳转到 "/merchant"
  },
  {
    path: "/merchant", // 地址：网站根路径（http://localhost:8080/）
    component: Merchant, // 对应页面：商家管理页
    name: "商家管理", // 给这个路由起个名字（方便后续引用，可选）
  },
  {
    path: "/service", // 地址：/service（http://localhost:8080/service）
    name: "服务管理",
    component: Service, // 对应页面：服务管理页
  },
  {
    path: "/order", // 地址：/order（http://localhost:8080/order）
    name: "订单管理",
    component: Order, // 对应页面：订单管理页
  },
];

// 4. 创建路由实例（初始化“接待员”，告诉他规则和工作模式）
const router = createRouter({
  history: createWebHistory(), // 用无#号的URL模式
  routes, // 刚才定义的“地址→页面”规则
});

// 5. 导出路由实例，让整个项目能用（把“接待员”安排到酒店工作）
export default router;
