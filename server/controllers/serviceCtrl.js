const pool = require("../db");
// 关联 merchants 表的本质是通过数据库的关联查询能力，
// 一次性整合 “服务” 和 “商家” 的关联数据，
// 既满足了前端展示 “服务所属商家” 的业务需求
// 即使右表（merchants）中没有匹配的记录
// （比如商家被删除，但服务记录未清理），左表（services）的记录依然会被返回（此时商家名称为 NULL）
exports.getServices = async (req, res) => {
  const { category } = req.query;
  let sql = `
    SELECT s.*,m.name AS merchant_name
    FROM services AS s
    LEFT JOIN merchants AS m ON s.merchant_id = m.id
    where 1=1
    `;
  let params = [];
  // 根据前端传递的分类参数（category）
  // 动态为 SQL 查询添加 “服务分类” 筛选条件，实现 “按分类筛选服务列表” 的功能，同时兼顾灵活性和安全性。
  if (category && category !== "all") {
    sql += ` AND s.category=?`;
    params.push(category);
  }
  try {
    const [row] = await pool.execute(sql, params);
    res.json({
      code: 200,
      message: "获取成功",
      data: row,
    });
  } catch (err) {
    res.json({
      code: 500,
      message: "获取失败",
      error: err.message,
    });
  }
};

//新增
exports.addService = async (req, res) => {
  const { merchant_id, name, price, category, image_url, stock } = req.body;
  try {
    const [result] = await pool.execute(
      `INSERT INTO services (name,price,category, image_url,merchant_id,stock) VALUES(?,?,?,?,?,?)`,
      [name, price, category, image_url, merchant_id, stock]
    );
    res.json({
      code: 200,
      message: "新增服务成功",
      data: { id: result.insertId },
    });
  } catch (err) {
    res.json({
      code: 500,
      message: "新增服务失败",
      data: err.message,
    });
  }
};

// 服务上架（更新状态为“上架”）
exports.publishService = async (req, res) => {
  const { id } = req.params;
  try {
    const [result] = await pool.execute(
      "UPDATE services SET status = 1 WHERE id = ?",
      [id]
    );
    if (result.affectedRows === 1) {
      res.json({ code: 200, msg: "服务上架成功！" });
    } else {
      res.json({ code: 404, msg: "服务不存在" });
    }
  } catch (err) {
    res.json({ code: 500, msg: "服务器出错", error: err.message });
  }
};

// 服务下架（更新状态为“下架”）
exports.unpublishService = async (req, res) => {
  const { id } = req.params;
  try {
    const [result] = await pool.execute(
      "UPDATE services SET status = 0 WHERE id = ?",
      [id]
    );
    if (result.affectedRows === 1) {
      res.json({ code: 200, msg: "服务下架成功！" });
    } else {
      res.json({ code: 404, msg: "服务不存在" });
    }
  } catch (err) {
    res.json({ code: 500, msg: "服务器出错", error: err.message });
  }
};
