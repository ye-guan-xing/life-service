const express = require("express");
const router = express.Router();
const serviceCtrl = require("../controllers/serviceCtrl");

// 获取服务列表
router.get("/list", serviceCtrl.getServices);

// 新增服务
router.post("/add", serviceCtrl.addService);

// 服务上架
router.put("/publish/:id", serviceCtrl.publishService);

router.put("/unpublish/:id", serviceCtrl.unpublishService);
module.exports = router;
