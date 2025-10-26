const express = require('express');
const cors = require('cors');
const app = express();

app.use(express.json())
app.use(cors())

const merchantRouder = require('./routes/merchant');
const customerRouder = require('./routes/service');
const orderRouder = require('./routes/order');
app.use('/api/merchant',merchantRouder);
app.use('/api/service',customerRouder);
app.use('/api/order',orderRouder);

app.listen(8080,()=>{
    console.log('服务器启动成功！')
    console.log('http://localhost:8080')
})