<template>
  <div class="order-page">
    <h2>📦 订单管理</h2>

    <!-- 筛选条件 -->
    <div class="filter-section">
      <h3>筛选条件</h3>
      <div class="filter-group">
        <label> <input type="radio" v-model="filterStatus" value="" /> 全部订单 </label>
        <label> <input type="radio" v-model="filterStatus" value="0" /> 待支付 </label>
        <label> <input type="radio" v-model="filterStatus" value="1" /> 已完成 </label>
      </div>
    </div>

    <!-- 订单列表 -->
    <div class="order-list">
      <h3>订单列表</h3>
      <table class="table">
        <thead>
          <tr>
            <th>订单ID</th>
            <th>服务名称</th>
            <th>商家</th>
            <th>用户姓名</th>
            <th>用户电话</th>
            <th>价格</th>
            <th>状态</th>
            <th>下单时间</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="order in orders" :key="order.id">
            <td>{{ order.id }}</td>
            <td>{{ order.service_name }}</td>
            <td>{{ order.merchant_name }}</td>
            <td>{{ order.user_name }}</td>
            <td>{{ order.user_phone }}</td>
            <td>¥{{ order.price }}</td>
            <td>
              <span :class="order.status === 0 ? 'status-pending' : 'status-completed'">
                {{ order.status === 0 ? "待支付" : "已完成" }}
              </span>
            </td>
            <td>{{ formatTime(order.create_time) }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script>
import { ref, onMounted, watch } from "vue";
import orderAPI from "../../api/order";

export default {
  name: "OrderView",
  setup() {
    const orders = ref([]);
    const filterStatus = ref("");

    // 获取订单列表
    const getOrders = async (status = "") => {
      try {
        const response = await orderAPI.getOrders(status);
        orders.value = response.data.data;
      } catch (error) {
        alert("获取订单列表失败！");
        console.error(error);
      }
    };

    // 格式化时间
    const formatTime = (timeString) => {
      return new Date(timeString).toLocaleString();
    };

    // 监听筛选条件变化
    watch(filterStatus, (newStatus) => {
      getOrders(newStatus);
    });

    // 页面加载时获取数据
    onMounted(() => {
      getOrders();
    });

    return {
      orders,
      filterStatus,
      formatTime,
    };
  },
};
</script>

<style scoped>
@import "./css.css";
</style>
