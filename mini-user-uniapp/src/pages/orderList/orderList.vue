<template>
  <view class="container">
    <view class="header">
      <text class="title">我的订单</text>
    </view>

    <view class="order-list">
      <view v-for="item in orders" :key="item.id" class="order-item">
        <view class="order-header">
          <text class="order-no">订单号: {{ item.id }}</text>
          <text class="order-status" :class="item.status === 0 ? 'pending' : 'completed'">
            {{ item.status === 0 ? '待支付' : '已完成' }}
          </text>
        </view>

        <view class="order-content">
          <view class="service-info">
            <text class="service-name">{{ item.service_name }}</text>
            <text class="merchant-name">{{ item.merchant_name }}</text>
          </view>
          <text class="service-price">¥{{ item.price }}</text>
        </view>

        <view class="order-footer">
          <text class="user-info">{{ item.user_name }} · {{ item.user_phone }}</text>
          <text class="order-time">{{ item.create_time_formatted }}</text>
        </view>
      </view>
    </view>

    <view v-if="orders.length === 0" class="empty-state">
      <text class="empty-text">暂无订单</text>
      <text class="empty-desc">去首页看看有什么服务吧</text>
    </view>
  </view>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { onLoad, onShow } from '@dcloudio/uni-app'
import request from '../../utils/request'
import type { Order } from '../../types'

const orders = ref<Order[]>([])

const formatOrder = (order: Order): Order => {
  const date = new Date(order.create_time)
  const pad = (n: number) => n.toString().padStart(2, '0')
  return {
    ...order,
    create_time_formatted: `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`
  }
}

const getOrders = async () => {
  try {
    const list = await request<Order[]>('/order/list')
    orders.value = list.map(formatOrder)
  } catch {
    uni.showToast({ title: '加载失败', icon: 'none' })
  }
}

onLoad(() => {
  getOrders()
})

onShow(() => {
  getOrders()
})
</script>

<style lang="scss">
.container {
  padding: 20rpx;
  background: #f5f5f5;
  min-height: 100vh;
}

.header {
  text-align: center;
  margin: 40rpx 0;
}

.title {
  font-size: 48rpx;
  font-weight: bold;
  color: #2c3e50;
}

.order-list {
  display: flex;
  flex-direction: column;
  gap: 20rpx;
}

.order-item {
  background: white;
  border-radius: 20rpx;
  padding: 30rpx;
  box-shadow: 0 4rpx 20rpx rgba(0, 0, 0, 0.1);
}

.order-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20rpx;
  padding-bottom: 20rpx;
  border-bottom: 1rpx solid #ecf0f1;
}

.order-no {
  font-size: 26rpx;
  color: #7f8c8d;
}

.order-status {
  font-size: 26rpx;
  font-weight: bold;
  padding: 8rpx 20rpx;
  border-radius: 20rpx;
}

.order-status.pending {
  background: #fff3cd;
  color: #856404;
}

.order-status.completed {
  background: #d4edda;
  color: #155724;
}

.order-content {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 20rpx;
}

.service-info {
  flex: 1;
}

.service-name {
  display: block;
  font-size: 32rpx;
  font-weight: bold;
  color: #2c3e50;
  margin-bottom: 10rpx;
}

.merchant-name {
  font-size: 26rpx;
  color: #7f8c8d;
}

.service-price {
  font-size: 36rpx;
  color: #e74c3c;
  font-weight: bold;
}

.order-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding-top: 20rpx;
  border-top: 1rpx solid #ecf0f1;
}

.user-info {
  font-size: 26rpx;
  color: #2c3e50;
}

.order-time {
  font-size: 24rpx;
  color: #95a5a6;
}

.empty-state {
  text-align: center;
  padding: 100rpx 0;
}

.empty-text {
  display: block;
  font-size: 32rpx;
  color: #bdc3c7;
  margin-bottom: 20rpx;
}

.empty-desc {
  display: block;
  font-size: 28rpx;
  color: #bdc3c7;
}
</style>
