const request = require("../../utils/request");

Page({
  data: {
    orders: [],
  },

  onLoad() {
    this.getOrders();
  },

  onShow() {
    this.getOrders();
  },

  // 获取订单列表
  async getOrders() {
    try {
      const orders = await request("/order/list");
      this.setData({ orders: orders.map(this.formatOrder) });
    } catch (err) {
      wx.showToast({
        title: "加载失败",
        icon: "none",
      });
    }
  },

  // 格式化订单时间
  formatOrder(order) {
    const date = new Date(order.create_time);
    const pad = (n) => n.toString().padStart(2, "0");
    return {
      ...order,
      create_time_formatted: `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`,
    };
  },
});
