// 引入我们创建的连接池
const pool = require('./index.js');
// 执行一条简单的 SQL：查询 MySQL 数据库的版本（不需要创建表，通用测试）
pool.query('SELECT VERSION() AS version', (err, results) => {
  // 回调函数：SQL 执行完成后会触发这个函数
  if (err) {
    console.error('数据库操作失败：', err.message);
    return; 
  }
  console.log('数据库连接成功！MySQL 版本是：', results[0].version);
});

// 测试完成后，关闭连接池
// pool.end();