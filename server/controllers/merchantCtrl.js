const pool = require("../db");

//获取商家列表
exports.getMerchantList = async (req, res) => {
  try {
    //执行
    const [result] = await pool.execute(`SELECT * FROM merchants`);
    res.json({
      code: 200,
      message: "获取成功",
      data: result,
    });
    //报错
  } catch (err) {
    res.json({
      code: 500,
      message: "获取失败",
      error: err.message,
    });
  }
};

//新增
exports.addMerchant = async (req, res) => {
  //获取数据
  const { name, address, phone } = req.body;
  try {
    const [result] = await pool.execute(
      `INSERT INTO merchants (name,address,phone) VALUES(?,?,?)`,
      [name, address, phone]
    );
    res.json({
      code: 200,
      message: "添加成功",
      data: { id: result.insertId },
    });
    //报错
  } catch (err) {
    res.json({
      code: 500,
      message: "添加失败",
      data: err.message,
    });
    console.log(err);
  }
};

// 审核商家（更新状态）
exports.approveMerchant = async (req, res) => {
  const { id } = req.params;
  try {
    const [result] = await pool.execute(
      "UPDATE merchants SET status = 1 WHERE id = ?",
      [id]
    );
    if (result.affectedRows === 1) {
      res.json({
        code: 200,
        msg: "商家审核通过！",
      });
    } else {
      res.json({
        code: 404,
        msg: "商家不存在",
      });
    }
  } catch (err) {
    res.json({
      code: 500,
      msg: "服务器出错",
      error: err.message,
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
