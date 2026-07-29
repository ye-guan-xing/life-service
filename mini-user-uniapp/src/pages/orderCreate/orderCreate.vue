<template>
  <view class="container">
    <view v-if="service" class="service-card">
      <view class="card-title">服务信息</view>
      <view class="service-info">
        <image class="service-image" :src="service.image_url || '/static/default-service.png'" />
        <view class="service-details">
          <text class="service-name">{{ service.name }}</text>
          <text class="service-merchant">{{ service.merchant_name }}</text>
          <text class="service-price">¥{{ service.price }}</text>
        </view>
      </view>
    </view>

    <view class="form-card">
      <view class="card-title">填写订单信息</view>
      <view class="form-item">
        <text class="form-label">姓名</text>
        <input class="form-input" placeholder="请输入您的姓名" :value="userInfo.name" @input="onNameInput" />
      </view>
      <view class="form-item">
        <text class="form-label">手机号</text>
        <input class="form-input" placeholder="请输入您的手机号" type="number" :value="userInfo.phone" @input="onPhoneInput" />
      </view>
    </view>

    <view class="submit-section">
      <view class="price-display">
        <text class="price-label">总计：</text>
        <text class="price-amount">¥{{ service ? service.price : '0' }}</text>
      </view>
      <button class="submit-btn" @tap="submitOrder">立即下单</button>
    </view>
  </view>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import request from '../../utils/request'
import type { Service } from '../../types'

const service = ref<Service | null>(null)
const userInfo = reactive({ name: '', phone: '' })

const onNameInput = (e: any) => {
  userInfo.name = e.detail.value
}

const onPhoneInput = (e: any) => {
  userInfo.phone = e.detail.value
}

const submitOrder = async () => {
  if (!userInfo.name.trim()) {
    uni.showToast({ title: '请输入姓名', icon: 'none' })
    return
  }
  if (!userInfo.phone.trim()) {
    uni.showToast({ title: '请输入手机号', icon: 'none' })
    return
  }
  const phoneRegex = /^1[3-9]\d{9}$/
  if (!phoneRegex.test(userInfo.phone)) {
    uni.showToast({ title: '请输入正确的手机号', icon: 'none' })
    return
  }

  try {
    uni.showLoading({ title: '提交中...' })
    await request('/order/create', 'POST', {
      service_id: service.value!.id,
      user_name: userInfo.name,
      user_phone: userInfo.phone
    })
    uni.hideLoading()
    uni.showToast({ title: '订单创建成功！', icon: 'success', duration: 2000 })
    setTimeout(() => {
      uni.navigateTo({ url: '/pages/orderList/orderList' })
    }, 2000)
  } catch {
    uni.hideLoading()
    uni.showToast({ title: '订单创建失败', icon: 'none' })
  }
}

onLoad((options) => {
  if (options && options.service) {
    try {
      service.value = JSON.parse(decodeURIComponent(options.service))
    } catch (err) {
      console.error('服务信息解析失败：', err)
      uni.showToast({ title: '服务信息错误', icon: 'none', duration: 2000 })
      setTimeout(() => uni.navigateBack(), 2000)
    }
  } else {
    uni.showToast({ title: '未获取到服务信息', icon: 'none', duration: 2000 })
    setTimeout(() => uni.navigateBack(), 2000)
  }
})
</script>

<style lang="scss">
.container {
  padding: 20rpx;
  background: #f5f5f5;
  min-height: 100vh;
  padding-bottom: 200rpx;
}

.service-card,
.form-card {
  background: white;
  border-radius: 20rpx;
  padding: 30rpx;
  margin-bottom: 20rpx;
  box-shadow: 0 4rpx 20rpx rgba(0, 0, 0, 0.1);
}

.card-title {
  font-size: 32rpx;
  font-weight: bold;
  color: #2c3e50;
  margin-bottom: 30rpx;
}

.service-info {
  display: flex;
  gap: 30rpx;
}

.service-image {
  width: 120rpx;
  height: 120rpx;
  border-radius: 10rpx;
  background: #ecf0f1;
}

.service-details {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}

.service-name {
  font-size: 32rpx;
  font-weight: bold;
  color: #2c3e50;
}

.service-merchant {
  font-size: 26rpx;
  color: #7f8c8d;
}

.service-price {
  font-size: 36rpx;
  color: #e74c3c;
  font-weight: bold;
}

.form-item {
  display: flex;
  align-items: center;
  padding: 30rpx 0;
  border-bottom: 1rpx solid #ecf0f1;
}

.form-item:last-child {
  border-bottom: none;
}

.form-label {
  font-size: 30rpx;
  color: #2c3e50;
  width: 150rpx;
}

.form-input {
  flex: 1;
  font-size: 30rpx;
  color: #2c3e50;
}

.submit-section {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  background: white;
  padding: 30rpx;
  display: flex;
  align-items: center;
  justify-content: space-between;
  box-shadow: 0 -2rpx 20rpx rgba(0, 0, 0, 0.1);
}

.price-display {
  display: flex;
  align-items: baseline;
}

.price-label {
  font-size: 28rpx;
  color: #2c3e50;
  margin-right: 10rpx;
}

.price-amount {
  font-size: 40rpx;
  color: #e74c3c;
  font-weight: bold;
}

.submit-btn {
  background: #e74c3c;
  color: white;
  border: none;
  border-radius: 50rpx;
  padding: 25rpx 60rpx;
  font-size: 32rpx;
  font-weight: bold;
}
</style>
