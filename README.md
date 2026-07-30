# 全域生活服务平台

## 项目介绍

一个完整的生活服务平台，包含 Web 管理后台和微信小程序用户端。小程序提供三套实现方案（Taro / uni-app / 原生），按需选用。

## 技术栈

- 后端：Node.js + Express 5 + MySQL 8.0（mysql2）
- Web 管理后台：Vue 3 + Vue Router + Vite
- 小程序：Taro / uni-app / 微信原生（三选一）
- 工具：DataGrip

## 启动步骤

### 后端

1. cd server
2. npm install
3. 修改 db/index.js 中的数据库密码
4. npm run dev

### Web 管理后台

1. cd web-admin
2. npm install
3. npm run dev

### 小程序

> Taro 依赖体积大、安装慢，建议先切国内镜像：
> `npm config set registry https://registry.npmmirror.com`

- Taro：cd mini-user-taro && npm install && npm run dev:weapp，用微信开发者工具打开 dist
- uni-app：
  - CLI：cd mini-user-uniapp && npm install && npm run dev:mp-weixin，用微信开发者工具打开 dist/dev/mp-weixin
  - HBuilderX：用 HBuilderX 打开 mini-user-uniapp，运行 → 运行到小程序模拟器 → 微信开发者工具

- 原生：微信开发者工具直接打开 mini-user-wx，点击预览
