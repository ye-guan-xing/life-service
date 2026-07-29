<template>
  <view class="container">
    <view class="header">
      <text class="title">生活服务平台</text>
      <text class="subtitle">便捷生活，一键送达</text>
    </view>

    <view class="category-section">
      <view class="section-title">服务分类</view>
      <view class="category-grid">
        <view
          v-for="item in categories"
          :key="item.type"
          class="category-item"
          @tap="toServiceList(item.type)"
        >
          <text class="category-icon">{{ item.icon }}</text>
          <text class="category-name">{{ item.name }}</text>
        </view>
      </view>
    </view>

    <view class="recommend-section">
      <view class="section-header">
        <text class="section-title">推荐服务</text>
        <text class="more" @tap="toServiceList('')">查看更多</text>
      </view>
      <view class="service-grid">
        <view
          v-for="item in services"
          :key="item.id"
          class="service-card"
          @tap="toOrderCreate(item)"
        >
          <image class="service-image" :src="item.image_url || '/images/default-service.png'" />
          <view class="service-info">
            <text class="service-name">{{ item.name }}</text>
            <text class="service-merchant">{{ item.merchant_name }}</text>
            <view class="service-bottom">
              <text class="service-price">¥{{ item.price }}</text>
              <text class="service-category">{{ item.category }}</text>
            </view>
          </view>
        </view>
      </view>
    </view>

    <view class="bottom-nav">
      <view class="nav-item" @tap="toServiceList('')">
        <text class="nav-icon">🔍</text>
        <text class="nav-text">全部服务</text>
      </view>
      <view class="nav-item" @tap="toOrderList">
        <text class="nav-icon">📦</text>
        <text class="nav-text">我的订单</text>
      </view>
    </view>
  </view>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import Taro from '@tarojs/taro'
import request from '../../utils/request'
import type { Service } from '../../types'

const services = ref<Service[]>([])
const categories = [
  { name: '家政', icon: '🏠', type: '家政' },
  { name: '维修', icon: '🔧', type: '维修' },
  { name: '保洁', icon: '✨', type: '保洁' }
]

const getServices = async () => {
  try {
    const list = await request<Service[]>('/service/list')
    services.value = list.slice(0, 4)
  } catch {
    Taro.showToast({ title: '加载失败', icon: 'none' })
  }
}

const toServiceList = (type: string) => {
  Taro.navigateTo({ url: `/pages/serviceList/serviceList?type=${type}` })
}

const toOrderList = () => {
  Taro.navigateTo({ url: '/pages/orderList/orderList' })
}

const toOrderCreate = (service: Service) => {
  Taro.navigateTo({
    url: `/pages/orderCreate/orderCreate?service=${encodeURIComponent(JSON.stringify(service))}`
  })
}

Taro.useLoad(() => {
  getServices()
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
  margin: 40rpx 0 60rpx;
}

.title {
  display: block;
  font-size: 48rpx;
  font-weight: bold;
  color: #2c3e50;
  margin-bottom: 10rpx;
}

.subtitle {
  display: block;
  font-size: 28rpx;
  color: #7f8c8d;
}

.category-section {
  margin-bottom: 40rpx;
}

.section-title {
  font-size: 36rpx;
  font-weight: bold;
  color: #2c3e50;
  margin-bottom: 30rpx;
  display: block;
}

.category-grid {
  display: flex;
  justify-content: space-around;
  background: white;
  padding: 30rpx;
  border-radius: 20rpx;
  box-shadow: 0 4rpx 20rpx rgba(0, 0, 0, 0.1);
}

.category-item {
  display: flex;
  flex-direction: column;
  align-items: center;
}

.category-icon {
  font-size: 60rpx;
  margin-bottom: 15rpx;
}

.category-name {
  font-size: 28rpx;
  color: #2c3e50;
}

.recommend-section {
  margin-bottom: 100rpx;
}

.section-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 30rpx;
}

.more {
  font-size: 28rpx;
  color: #3498db;
}

.service-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20rpx;
}

.service-card {
  background: white;
  border-radius: 20rpx;
  overflow: hidden;
  box-shadow: 0 4rpx 20rpx rgba(0, 0, 0, 0.1);
}

.service-image {
  width: 100%;
  height: 200rpx;
  background: #ecf0f1;
}

.service-info {
  padding: 20rpx;
}

.service-name {
  display: block;
  font-size: 30rpx;
  font-weight: bold;
  color: #2c3e50;
  margin-bottom: 10rpx;
}

.service-merchant {
  display: block;
  font-size: 24rpx;
  color: #7f8c8d;
  margin-bottom: 15rpx;
}

.service-bottom {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.service-price {
  color: #e74c3c;
  font-size: 28rpx;
  font-weight: bold;
}

.service-category {
  font-size: 24rpx;
  color: #3498db;
  background: #ecf0f1;
  padding: 5rpx 15rpx;
  border-radius: 20rpx;
}

.bottom-nav {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  background: white;
  display: flex;
  padding: 20rpx;
  box-shadow: 0 -2rpx 20rpx rgba(0, 0, 0, 0.1);
}

.nav-item {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.nav-icon {
  font-size: 40rpx;
  margin-bottom: 10rpx;
}

.nav-text {
  font-size: 24rpx;
  color: #2c3e50;
}
</style>
