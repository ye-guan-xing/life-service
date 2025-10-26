const request = (url, method = 'GET', data = {}) => {
  return new Promise((resolve, reject) => {
    wx.request({
      url: 'http://localhost:8080/api' + url,
      method,
      data,
      success: (res) => {
        if (res.data.code === 200) {
          resolve(res.data.data)
        } else {
          reject(res.data.msg)
        }
      },
      fail: (err) => {
        reject('网络请求失败：' + err.errMsg)
      }
    })
  })
}

module.exports = request
