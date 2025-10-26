const express = require('express');
const router = express.Router();
const orderCtrl = require('../controllers/orderCtrl');

// 创建订单
router.post('/create', orderCtrl.createOrder);

// 获取订单列表
router.get('/list', orderCtrl.getOrders);

module.exports = router;
