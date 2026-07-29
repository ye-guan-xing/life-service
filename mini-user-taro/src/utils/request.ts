import Taro from '@tarojs/taro'

const BASE_URL = 'http://localhost:8080/api'
const TIMEOUT = 10000

type ApiResponse<T> = { code: number; data: T; msg: string }

function request<T = unknown>(url: string, method: 'GET' | 'POST' = 'GET', data: Record<string, unknown> = {}): Promise<T> {
  return new Promise((resolve, reject) => {
    Taro.request({
      url: BASE_URL + url,
      method,
      data,
      timeout: TIMEOUT,
      success: (res) => {
        const body = res.data as ApiResponse<T>
        if (body.code === 200) {
          resolve(body.data)
        } else {
          reject(body.msg)
        }
      },
      fail: (err) => {
        reject('网络请求失败：' + err.errMsg)
      }
    })
  })
}

export default request
