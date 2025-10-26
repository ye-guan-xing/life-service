// web-admin/vue.config.js
module.exports = {
  devServer: {
    port: 8081, // 前端开发端口（自定义，避免和后端冲突）
    open: true, // 启动后自动打开浏览器（可选）
    proxy: {
      // 后续解决跨域用（提前配置，下文会讲）
      "/api": {
        target: "http://localhost:8080", // 后端接口地址（后端端口）
        changeOrigin: true, // 开启跨域代理
        pathRewrite: { "^/api": "" }, // 可选：如果后端接口没有 /api 前缀，就去掉这个重写
      },
    },
  },
};
