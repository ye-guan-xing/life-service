const pool = require("../db");

//创建定单
exports.createOrder = async (req, res) => {
  const { service_id, user_name, user_phone } = req.body;
  try {
    const [result] = await pool.execute(
      `INSERT INTO orders (service_id,user_name,user_phone) VALUES(?,?,?)`,
      [service_id, user_name, user_phone]
    );
    res.json({
      code: 200,
      message: "创建定单成功",
      data: { id: result.insertId },
    });
  } catch (err) {
    res.json({
      code: 500,
      message: "创建定单失败",
      error: err.message,
    });
  }
};

// WHERE 1=1
// 这是一个 “技巧性写法”，方便后续动态添加条件。
// 比如后面有 if (status !== undefined) 时，
// 会拼接 AND o.status = ?。如果没有 1=1，初始的 WHERE 子句是空的
// 第一次添加条件时需要写 WHERE o.status = ?，第二次添加才写 AND ...，代码里就要判断 “是不是第一个条件”，很麻烦。
// 有了 1=1 后，不管后面加多少条件，直接用 AND ... 拼接就行
// （比如 WHERE 1=1 AND o.status=? AND o.user_id=?），简化了动态条件的拼接逻辑。

//stayus 0:待处理 1:处理中 2:完成

//获取定单列表
exports.getOrders = async (req, res) => {
  const { status } = req.query;
  try {
    let sql = `SELECT o.*,
    s.name AS server_name,
    m.name AS merchant_name
    FROM orders AS o
    LEFT JOIN services AS s ON o.service_id = s.id 
    LEFT JOIN merchants AS m ON s.merchant_id = m.id
    WHERE 1=1`;
    let params = [];

    if (status !== undefined) {
      sql += ` AND o.status=?`;
      params.push(status);
    }
    //加一个空格
    sql += ` ORDER BY o.create_time DESC`;

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
