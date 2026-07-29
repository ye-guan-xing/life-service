const request = require('../../utils/request')

Page({
  data: {
    services: [],
    categories: [
      { name: '家政', icon: '🏠', type: '家政' },
      { name: '维修', icon: '🔧', type: '维修' },
      { name: '保洁', icon: '✨', type: '保洁' }
    ]
  },

  onLoad() {
    this.getServices()
  },

  // 获取推荐服务
  async getServices() {
    try {
      const services = await request('/service/list')
      // 只取前4个作为推荐
      this.setData({ 
        services: services.slice(0, 4) 
      })
    } catch (err) {
      wx.showToast({
        title: '加载失败',
        icon: 'none'
      })
    }
  },

  // 跳转到服务列表
  toServiceList(e) {
    const type = e.currentTarget.dataset.type
    wx.navigateTo({
      url: `/pages/serviceList/serviceList?type=${type}`
    })
  },

  // 跳转到订单列表
  toOrderList() {
    wx.navigateTo({
      url: '/pages/orderList/orderList'
    })
  }
})
