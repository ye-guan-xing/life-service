const BASE_URL = "http://localhost:8080/api";
const TIMEOUT = 10000;

const request = (url, method = "GET", data = {}) => {
  return new Promise((resolve, reject) => {
    wx.request({
      url: BASE_URL + url,
      method,
      data,
      timeout: TIMEOUT,
      success: (res) => {
        if (res.data.code === 200) {
          resolve(res.data.data);
        } else {
          reject(res.data.msg);
        }
      },
      fail: (err) => {
        reject("网络请求失败：" + err.errMsg);
      },
    });
  });
};

module.exports = request;
