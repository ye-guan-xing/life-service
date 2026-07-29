import axios from "axios";

export const serviceAPI = {
  getServices: (category = "") => {
    const params = {
      ...(category ? { category } : {}),
      t: Date.now(),
    };
    return axios.get("/api/service/list", { params });
  },
  addService: (data) => {
    return axios.post("/api/service/add", data);
  },
  publishService: (id) => {
    axios.put(`/api/service/publish/${id}`);
  },
  unpublishService: (id) => {
    axios.put(`/api/service/unpublish/${id}`);
  },
};

export default serviceAPI;
