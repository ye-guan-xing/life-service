import axios from "axios";
export const orderAPI = {
  getOrders(status) {
    const params = status != undefined ? { status: status } : {};
    return axios.get("/api/order/list", { params });
  },
  createOrder: (data) => {
    return axios.post("/api/order/add", data);
  },
};

export default orderAPI;
