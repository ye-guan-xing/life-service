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
      this.setData({ orders });
    } catch (err) {
      wx.showToast({
        title: "加载失败",
        icon: "none",
      });
    }
  },

  // 格式化时间
  formatTime(timeString) {
    const date = new Date(timeString);
    return `${date.getFullYear()}-${(date.getMonth() + 1)
      .toString()
      .padStart(2, "0")}-${date
      .getDate()
      .toString()
      .padStart(2, "0")} ${date
      .getHours()
      .toString()
      .padStart(2, "0")}:${date.getMinutes().toString().padStart(2, "0")}`;
  },
});
