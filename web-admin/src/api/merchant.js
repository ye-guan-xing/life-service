import axios from "axios";

axios.defaults.baseURL = "http://localhost:8080";

export const merchantAPI = {
  addMerchant(merchant) {
    return axios.post("/api/merchant/add", merchant);
  },

  getMerchantList() {
    return axios.get("/api/merchant/list");
  },
  // 审核商家
  approveMerchant(id) {
    return axios.put(`/api/merchant/approve/${id}`);
  },
};

export default merchantAPI;
