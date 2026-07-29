import { createApp } from "vue";
import App from "./App.vue";
import router from "./router"; // 如果有路由

createApp(App)
  .use(router) // 如果有路由
  .mount("#app");
