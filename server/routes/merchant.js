const express = require('express');
const router = express.Router();

//引入控制器
const merchantCtrl = require('../controllers/merchantCtrl');

//发送到/add，用什么文件的什么方法处理
router.post('/add',merchantCtrl.addMerchant);

router.get('/list',merchantCtrl.getMerchantList);

// 审核商家
router.put('/approve/:id', merchantCtrl.approveMerchant);

//导出让add.js使用
module.exports = router;