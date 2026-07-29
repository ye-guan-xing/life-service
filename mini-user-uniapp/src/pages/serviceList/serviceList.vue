<template>
  <view class="container">
    <view class="search-box">
      <input
        class="search-input"
        placeholder="搜索服务或商家..."
        :value="searchKeyword"
        @input="onSearchInput"
      />
      <button class="search-btn" @tap="onSearch">搜索</button>
    </view>

    <scroll-view class="category-scroll" scroll-x>
      <view class="category-list">
        <view
          v-for="item in categories"
          :key="item"
          class="category-item"
          :class="{ active: activeCategory === item }"
          @tap="switchCategory(item)"
        >
          {{ item }}
        </view>
      </view>
    </scroll-view>

    <view class="service-list">
      <view
        v-for="item in services"
        :key="item.id"
        class="service-item"
        @tap="toOrderCreate(item)"
      >
        <image class="service-image" :src="item.image_url || '/static/default-service.png'" />
        <view class="service-content">
          <view class="service-header">
            <text class="service-name">{{ item.name }}</text>
            <text class="service-price">¥{{ item.price }}</text>
          </view>
          <view class="service-merchant">{{ item.merchant_name }}</view>
          <view class="service-footer">
            <text class="service-category">{{ item.category }}</text>
            <text class="service-stock">库存: {{ item.stock }}</text>
          </view>
        </view>
      </view>
    </view>

    <view v-if="services.length === 0" class="empty-state">
      <text class="empty-text">暂无服务</text>
    </view>
  </view>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import request from '../../utils/request'
import type { Service } from '../../types'

const services = ref<Service[]>([])
const categories = ['全部', '家政', '维修', '保洁']
const activeCategory = ref('全部')
const searchKeyword = ref('')

const getServices = async () => {
  const category = activeCategory.value === '全部' ? '' : activeCategory.value
  try {
    let list = await request<Service[]>('/service/list', 'GET', { category })
    if (searchKeyword.value) {
      list = list.filter(
        (s) => s.name.includes(searchKeyword.value) || s.merchant_name.includes(searchKeyword.value)
      )
    }
    services.value = list
  } catch {
    uni.showToast({ title: '加载失败', icon: 'none' })
  }
}

const switchCategory = (category: string) => {
  activeCategory.value = category
  searchKeyword.value = ''
  getServices()
}

const onSearchInput = (e: any) => {
  searchKeyword.value = e.detail.value
}

const onSearch = () => {
  getServices()
}

const toOrderCreate = (service: Service) => {
  uni.navigateTo({
    url: `/pages/orderCreate/orderCreate?service=${encodeURIComponent(JSON.stringify(service))}`
  })
}

onLoad((options) => {
  if (options && options.type) {
    activeCategory.value = options.type
  }
  getServices()
})
</script>

<style lang="scss">
.container {
  padding: 20rpx;
  background: #f5f5f5;
  min-height: 100vh;
}

.search-box {
  display: flex;
  gap: 20rpx;
  margin-bottom: 30rpx;
}

.search-input {
  flex: 1;
  background: white;
  padding: 20rpx;
  border-radius: 10rpx;
  font-size: 28rpx;
}

.search-btn {
  background: #3498db;
  color: white;
  border: none;
  border-radius: 10rpx;
  padding: 0 30rpx;
  font-size: 28rpx;
}

.category-scroll {
  white-space: nowrap;
  margin-bottom: 30rpx;
}

.category-list {
  display: inline-flex;
  gap: 20rpx;
}

.category-item {
  display: inline-block;
  padding: 15rpx 30rpx;
  background: white;
  border-radius: 30rpx;
  font-size: 28rpx;
  color: #666;
}

.category-item.active {
  background: #3498db;
  color: white;
}

.service-list {
  display: flex;
  flex-direction: column;
  gap: 20rpx;
}

.service-item {
  display: flex;
  background: white;
  border-radius: 20rpx;
  overflow: hidden;
  box-shadow: 0 4rpx 20rpx rgba(0, 0, 0, 0.1);
}

.service-image {
  width: 200rpx;
  height: 200rpx;
  background: #ecf0f1;
}

.service-content {
  flex: 1;
  padding: 30rpx;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}

.service-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 15rpx;
}

.service-name {
  font-size: 32rpx;
  font-weight: bold;
  color: #2c3e50;
  flex: 1;
  margin-right: 20rpx;
}

.service-price {
  font-size: 32rpx;
  color: #e74c3c;
  font-weight: bold;
}

.service-merchant {
  font-size: 26rpx;
  color: #7f8c8d;
  margin-bottom: 15rpx;
}

.service-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.service-category {
  font-size: 24rpx;
  color: #3498db;
  background: #ecf0f1;
  padding: 8rpx 20rpx;
  border-radius: 20rpx;
}

.service-stock {
  font-size: 24rpx;
  color: #95a5a6;
}

.empty-state {
  text-align: center;
  padding: 100rpx 0;
}

.empty-text {
  font-size: 32rpx;
  color: #bdc3c7;
}
</style>
