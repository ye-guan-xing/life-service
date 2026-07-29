<template>
  <!-- <link rel="stylesheet" href=" ./css.css" /> -->
  <div class="merchant-page">
    <h2>🏪 商家管理</h2>

    <!-- 新增商家表单 -->
    <div class="add-form">
      <h3>➕ 新增商家</h3>
      <div class="form-group">
        <input v-model="newMerchant.name" placeholder="商家名称" class="input" :disabled="isSubmitting" />
        <input v-model="newMerchant.address" placeholder="商家地址" class="input" :disabled="isSubmitting" />
        <input v-model="newMerchant.phone" placeholder="联系电话" class="input" :disabled="isSubmitting" />
        <button @click="addMerchant" class="btn btn-primary" :disabled="isSubmitting">
          {{ isSubmitting ? "提交中..." : "添加商家" }}
        </button>
      </div>
    </div>

    <!-- 商家列表 -->
    <div class="merchant-list">
      <h3>📋 商家列表</h3>
      <!-- 加载状态 -->
      <div class="loading" v-if="isLoading">
        <span>加载中...</span>
      </div>

      <table class="table" v-else>
        <thead>
          <tr>
            <th>ID</th>
            <th>名称</th>
            <th>地址</th>
            <th>电话</th>
            <th>状态</th>
            <th>创建时间</th>
            <th>操作</th>
            <!-- 新增操作列，更清晰 -->
          </tr>
        </thead>
        <tbody>
          <!-- 空状态处理 -->
          <tr v-if="merchants.length === 0">
            <td colspan="7" class="empty-cell">暂无商家数据</td>
          </tr>

          <tr v-for="merchant in merchants" :key="merchant.id">
            <td>{{ merchant.id }}</td>
            <td>{{ merchant.name }}</td>
            <td>{{ merchant.address }}</td>
            <td>{{ merchant.phone }}</td>
            <td>
              <span :class="merchant.status === 0 ? 'status-pending' : 'status-approved'">
                {{ merchant.status === 0 ? "审核中" : "已通过" }}
              </span>
            </td>
            <td>{{ formatTime(merchant.create_time) }}</td>
            <td class="operation-cell">
              <!-- 审核按钮：只在"审核中"且非加载状态显示 -->
              <button
                class="approve-btn"
                @click="handleApprove(merchant.id)"
                v-if="merchant.status === 0 && !isLoading"
                :disabled="isApproving[merchant.id]"
              >
                {{ isApproving[merchant.id] ? "审核中..." : "审核通过" }}
              </button>
              <!-- 已通过状态提示 -->
              <span class="approved-text" v-else-if="merchant.status === 1"> 已审核 </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script>
import { ref, onMounted } from "vue";
import merchantAPI from "../../api/merchant";

export default {
  name: "MerchantView",
  setup() {
    // 商家列表数据
    const merchants = ref([]);
    // 新增商家表单数据
    const newMerchant = ref({
      name: "",
      address: "",
      phone: "",
    });
    // 加载状态（列表加载中）
    const isLoading = ref(false);
    // 提交状态（新增商家时）
    const isSubmitting = ref(false);
    // 审核状态（针对每个商家的单独加载状态，避免重复点击）
    const isApproving = ref({}); // 结构：{ 1: true, 2: false, ... }

    // 获取商家列表（封装为独立方法，便于复用）
    const getMerchants = async () => {
      try {
        isLoading.value = true; // 显示加载状态
        const response = await merchantAPI.getMerchantList();
        console.log(response.data);
        merchants.value = response.data.data || []; // 兼容空数据
      } catch (error) {
        alert("获取商家列表失败：" + (error.message || "网络错误"));
        console.error("商家列表加载失败：", error);
      } finally {
        isLoading.value = false; // 无论成功失败，关闭加载状态
      }
    };

    // 新增商家
    const addMerchant = async () => {
      // 表单验证
      if (!newMerchant.value.name.trim()) {
        alert("请输入商家名称！");
        return;
      }
      if (!newMerchant.value.address.trim()) {
        alert("请输入商家地址！");
        return;
      }
      if (!newMerchant.value.phone.trim()) {
        alert("请输入联系电话！");
        return;
      }
      // 简单手机号格式验证（11位数字）
      if (!/^\d{11}$/.test(newMerchant.value.phone)) {
        alert("请输入有效的11位手机号！");
        return;
      }

      try {
        isSubmitting.value = true; // 防止重复提交
        await merchantAPI.addMerchant(newMerchant.value);
        alert("商家添加成功！");

        // 清空表单
        newMerchant.value = { name: "", address: "", phone: "" };

        // 刷新列表
        getMerchants();
      } catch (error) {
        alert("添加商家失败：" + (error.message || "服务器错误"));
        console.error("新增商家失败：", error);
      } finally {
        isSubmitting.value = false; // 恢复提交状态
      }
    };

    // 审核商家（核心补充）
    const handleApprove = async (id) => {
      // 确认操作（避免误点）
      if (!confirm("确定要通过该商家的审核吗？")) {
        return;
      }

      try {
        // 标记当前商家正在审核中
        isApproving.value[id] = true;

        await merchantAPI.approveMerchant(id);
        alert("商家审核通过！");

        // 刷新列表
        getMerchants();
      } catch (error) {
        alert("审核失败：" + (error.message || "服务器错误"));
        console.error(`审核商家${id}失败：`, error);
      } finally {
        // 清除审核状态
        isApproving.value[id] = false;
      }
    };

    // 格式化时间（兼容空值）
    const formatTime = (timeString) => {
      if (!timeString) return "-";
      return new Date(timeString).toLocaleString();
    };

    // 页面加载时初始化数据
    onMounted(() => {
      getMerchants();
    });

    return {
      merchants,
      newMerchant,
      isLoading,
      isSubmitting,
      isApproving,
      addMerchant,
      handleApprove, // 导出审核方法（关键补充）
      formatTime,
    };
  },
};
</script>

<style scoped>
@import "./css.css";
</style>
