const request = require('../../utils/request')

Page({
  data: {
    services: [],
    categories: ['全部', '家政', '维修', '保洁'],
    activeCategory: '全部',
    searchKeyword: ''
  },

  onLoad(options) {
    if (options.type) {
      this.setData({ activeCategory: options.type })
    }
    this.getServices()
  },

  // 获取服务列表
  async getServices() {
    const { activeCategory, searchKeyword } = this.data
    
    try {
      let category = activeCategory === '全部' ? '' : activeCategory
      let services = await request('/service/list', 'GET', { category })
      
      // 前端搜索过滤
      if (searchKeyword) {
        services = services.filter(service => 
          service.name.includes(searchKeyword) || 
          service.merchant_name.includes(searchKeyword)
        )
      }
      
      this.setData({ services })
    } catch (err) {
      wx.showToast({
        title: '加载失败',
        icon: 'none'
      })
    }
  },

  // 切换分类
  switchCategory(e) {
    const category = e.currentTarget.dataset.category
    this.setData({ 
      activeCategory: category,
      searchKeyword: ''
    })
    this.getServices()
  },

  // 搜索输入
  onSearchInput(e) {
    this.setData({ searchKeyword: e.detail.value })
  },

  // 执行搜索
  onSearch() {
    this.getServices()
  },

// 跳转到下单页面（修改后）
toOrderCreate(e) {
  const service = e.currentTarget.dataset.service
  wx.navigateTo({
    url: `/pages/orderCreate/orderCreate?service=${encodeURIComponent(JSON.stringify(service))}`
    })
  }
})
