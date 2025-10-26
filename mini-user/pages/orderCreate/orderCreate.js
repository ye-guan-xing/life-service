const request = require("../../utils/request");

Page({
  data: {
    service: null,
    userInfo: {
      name: "",
      phone: "",
    },
  },

  onLoad(options) {
    if (options.service) {
      try {
        const serviceStr = decodeURIComponent(options.service);
        const service = JSON.parse(serviceStr);
        this.setData({ service });
      } catch (err) {
        // 3. 捕获解析错误，避免页面崩溃并提示用户
        console.error("服务信息解析失败：", err);
        wx.showToast({
          title: "服务信息错误",
          icon: "none",
          duration: 2000,
        });
        // 解析失败时返回上一页
        setTimeout(() => {
          wx.navigateBack();
        }, 2000);
      }
    } else {
      // 没有传递 service 参数时的提示
      wx.showToast({
        title: "未获取到服务信息",
        icon: "none",
        duration: 2000,
      });
      setTimeout(() => {
        wx.navigateBack();
      }, 2000);
    }
  },

  // 输入用户姓名
  onNameInput(e) {
    this.setData({
      "userInfo.name": e.detail.value,
    });
  },

  // 输入用户电话
  onPhoneInput(e) {
    this.setData({
      "userInfo.phone": e.detail.value,
    });
  },

  // 提交订单
  async submitOrder() {
    const { service, userInfo } = this.data;

    if (!userInfo.name.trim()) {
      wx.showToast({
        title: "请输入姓名",
        icon: "none",
      });
      return;
    }

    if (!userInfo.phone.trim()) {
      wx.showToast({
        title: "请输入手机号",
        icon: "none",
      });
      return;
    }

    // 简单的手机号验证
    const phoneRegex = /^1[3-9]\d{9}$/;
    if (!phoneRegex.test(userInfo.phone)) {
      wx.showToast({
        title: "请输入正确的手机号",
        icon: "none",
      });
      return;
    }

    try {
      wx.showLoading({
        title: "提交中...",
      });

      await request("/order/create", "POST", {
        service_id: service.id,
        user_name: userInfo.name,
        user_phone: userInfo.phone,
      });

      wx.hideLoading();

      wx.showToast({
        title: "订单创建成功！",
        icon: "success",
        duration: 2000,
      });

      // 跳转到订单列表
      setTimeout(() => {
        wx.navigateTo({
          url: "/pages/orderList/orderList",
        });
      }, 2000);
    } catch (err) {
      wx.hideLoading();
      wx.showToast({
        title: "订单创建失败",
        icon: "none",
      });
    }
  },
});
