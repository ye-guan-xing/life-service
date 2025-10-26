<template>
  <div class="service-page">
    <h2>🛎️ 服务管理</h2>

    <!-- 新增服务表单 -->
    <div class="add-form">
      <h3>➕ 新增服务</h3>
      <div class="form-grid">
        <input v-model="newService.name" placeholder="服务名称" class="input" />
        <select v-model="newService.merchant_id" class="input">
          <option value="">选择商家</option>
          <option v-for="merchant in merchants" :key="merchant.id" :value="merchant.id">
            {{ merchant.name }}
          </option>
        </select>
        <input v-model="newService.price" type="number" placeholder="价格" class="input" />
        <select v-model="newService.category" class="input">
          <option value="">选择分类</option>
          <option value="家政">家政</option>
          <option value="维修">维修</option>
          <option value="保洁">保洁</option>
        </select>
        <input v-model="newService.stock" type="number" placeholder="库存" class="input" />
        <input v-model="newService.image_url" placeholder="图片URL" class="input" />
        <button @click="addService" class="btn btn-primary">添加服务</button>
      </div>
    </div>

    <!-- 服务列表 -->
    <div class="service-list">
      <h3>📋 服务列表</h3>
      <table class="table">
        <thead>
          <tr>
            <th>ID</th>
            <th>服务名称</th>
            <th>商家</th>
            <th>价格</th>
            <th>分类</th>
            <th>库存</th>
            <th>状态</th>
            <th>操作</th>
            <!-- 新增操作列 -->
          </tr>
        </thead>
        <tbody>
          <tr v-for="service in services" :key="service.id">
            <td>{{ service.id }}</td>
            <td>{{ service.name }}</td>
            <td>{{ service.merchant_name }}</td>
            <td>¥{{ service.price }}</td>
            <td>{{ service.category }}</td>
            <td>{{ service.stock }}</td>
            <td>
              <span :class="service.status === 0 ? 'status-off' : 'status-on'">
                {{ service.status === 0 ? "下架" : "上架" }}
              </span>
            </td>
            <td>
              <!-- 上架按钮（下架状态时显示） -->
              <button v-if="service.status === 0" class="btn btn-publish" @click="handlePublish(service.id)">
                上架
              </button>
              <!-- 下架按钮（上架状态时显示） -->
              <button v-else class="btn btn-unpublish" @click="handleUnpublish(service.id)">下架</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script>
import { ref, onMounted } from "vue";
import serviceAPI from "../../api/service";
import merchantAPI from "../../api/merchant";

export default {
  name: "ServiceView",
  setup() {
    const services = ref([]);
    const merchants = ref([]);
    const newService = ref({
      name: "",
      merchant_id: "",
      price: "",
      category: "",
      stock: "",
      image_url: "",
    });

    // 获取服务列表
    const getServices = async () => {
      try {
        const response = await serviceAPI.getServices();
        services.value = response.data.data;
      } catch (error) {
        alert("获取服务列表失败！");
        console.error(error);
      }
    };

    // 获取商家列表
    const getMerchants = async () => {
      try {
        const response = await merchantAPI.getMerchantList();
        merchants.value = response.data.data;
      } catch (error) {
        alert("获取商家列表失败！");
        console.error(error);
      }
    };

    // 新增服务
    const addService = async () => {
      if (!newService.value.name || !newService.value.merchant_id || !newService.value.price) {
        alert("请填写完整信息！");
        return;
      }

      try {
        await serviceAPI.addService(newService.value);
        alert("服务添加成功！");
        newService.value = { name: "", merchant_id: "", price: "", category: "", stock: "", image_url: "" };
        getServices();
      } catch (error) {
        alert("添加服务失败！");
        console.error(error);
      }
    };

    // 上架服务（状态更新为1）
    const handlePublish = async (id) => {
      try {
        await serviceAPI.publishService(id);
        alert("服务上架成功！");
        getServices(); // 刷新列表
      } catch (error) {
        alert("上架失败！");
        console.error(error);
      }
    };

    // 下架服务（状态更新为0）
    const handleUnpublish = async (id) => {
      try {
        await serviceAPI.unpublishService(id);
        alert("服务下架成功！");
        getServices(); // 刷新列表
      } catch (error) {
        alert("下架失败！");
        console.error(error);
      }
    };

    onMounted(() => {
      getServices();
      getMerchants();
    });

    return {
      services,
      merchants,
      newService,
      addService,
      handlePublish, // 导出上架方法
      handleUnpublish, // 导出下架方法
    };
  },
};
</script>

<style scoped>
.service-page {
  padding: 20px;
  max-width: 1200px;
  margin: 0 auto;
}

.add-form {
  margin: 30px 0;
  padding: 20px;
  border: 1px solid #e1e1e1;
  border-radius: 8px;
  background: #f9f9f9;
}

.form-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 10px;
  align-items: end;
}

.input {
  padding: 8px 12px;
  border: 1px solid #ccc;
  border-radius: 4px;
  width: 100%;
}

.btn {
  padding: 8px 16px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
}

.btn-primary {
  background: #4caf50;
  color: white;
  grid-column: 1 / -1;
  justify-self: start;
}

.btn-primary:hover {
  background: #45a049;
}

/* 上架按钮样式 */
.btn-publish {
  background: #2196f3;
  color: white;
}

.btn-publish:hover {
  background: #0b7dda;
}

/* 下架按钮样式 */
.btn-unpublish {
  background: #ff9800;
  color: white;
}

.btn-unpublish:hover {
  background: #e68900;
}

.service-list {
  margin-top: 30px;
}

.table {
  width: 100%;
  border-collapse: collapse;
  margin-top: 10px;
  background: white;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
}

.table th,
.table td {
  border: 1px solid #ddd;
  padding: 12px;
  text-align: left;
}

.table th {
  background: #f5f5f5;
  font-weight: bold;
}

.status-on {
  color: #4caf50;
  font-weight: bold;
}

.status-off {
  color: #f44336;
  font-weight: bold;
}
</style>
