const mysql = require('mysql2/promise');

const pool=mysql.createPool({
    host:'localhost',
    user:'root',
    password:'123456',
    database:'life_server',
    port:3306
});

console.log('数据库连接成功！')
module.exports=pool;