# MaxCompute (ODPS): 数学函数

> 参考资料:
> - [1] MaxCompute SQL Reference - Mathematical Functions
>   https://help.aliyun.com/zh/maxcompute/user-guide/mathematical-functions


## 1. 基本数学函数


```sql
SELECT ABS(-42);                            -- 42（绝对值）
SELECT CEIL(4.3);                           -- 5（向上取整）
SELECT FLOOR(4.7);                          -- 4（向下取整）
SELECT ROUND(3.14159, 2);                   -- 3.14（四舍五入）
SELECT TRUNC(3.14159, 2);                   -- 3.14（截断，不四舍五入）
SELECT MOD(17, 5);                          -- 2（取模）
SELECT SIGN(-42);                           -- -1（符号函数）

```

 ROUND vs TRUNC:
   ROUND(3.145, 2) = 3.15（四舍五入）
   TRUNC(3.145, 2) = 3.14（直接截断）
   金融场景通常需要明确选择: 银行家舍入 vs 截断

## 2. 幂与对数


```sql
SELECT POWER(2, 10);                        -- 1024
SELECT POW(2, 10);                          -- 1024（POWER 别名）
SELECT SQRT(144);                           -- 12.0

SELECT EXP(1);                              -- 2.718...（e^1）
SELECT LN(EXP(1));                          -- 1.0（自然对数）
SELECT LOG(10, 1000);                       -- 3.0（以 10 为底）

```

 LOG 函数参数顺序:
   MaxCompute: LOG(base, value) — 底数在前
   MySQL:      LOG(value) / LOG(base, value)
   PostgreSQL: LN(value) / LOG(value)=LOG10 / LOG(base, value) 不支持
   BigQuery:   LOG(value, base) — 底数在后!
   对引擎开发者: LOG 的参数顺序是经典的不一致点

## 3. 三角函数


```sql
SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1);
SELECT ATAN2(1, 1);                         -- atan2(y, x)

```

 注意: 角度单位是弧度（radians），不是度数（degrees）
 对比: 有些引擎提供 DEGREES/RADIANS 转换函数

## 4. 比较函数


```sql
SELECT GREATEST(1, 5, 3);                   -- 5（最大值）
SELECT LEAST(1, 5, 3);                      -- 1（最小值）

```

 GREATEST/LEAST 是标量函数（同行多列比较）
 MAX/MIN 是聚合函数（多行同列比较）

## 5. 随机数


```sql
SELECT RAND();                              -- [0, 1) 均匀分布随机数
SELECT RAND(42);                            -- 带种子的随机数（可重复）

```

随机采样:

```sql
SELECT * FROM users WHERE RAND() < 0.01;    -- 约 1% 随机采样
```

 注意: 这种方式的采样率不精确
 更好的方式: TABLESAMPLE（如果支持）

## 6. 位运算


```sql
SELECT 5 & 3;                               -- 1（位与: 101 & 011 = 001）
SELECT 5 | 3;                               -- 7（位或: 101 | 011 = 111）
SELECT 5 ^ 3;                               -- 6（位异或: 101 ^ 011 = 110）
SELECT ~5;                                  -- -6（位取反）
SELECT SHIFTLEFT(1, 4);                     -- 16（左移 4 位）
SELECT SHIFTRIGHT(16, 2);                   -- 4（右移 2 位）
SELECT SHIFTRIGHTUNSIGNED(16, 2);           -- 4（无符号右移）

```

 设计分析: 位运算在数据处理中的用途
   位标志: 用一个 BIGINT 存储多个布尔值（如权限位图）
   哈希分桶: 自定义 hash 分布
   IP 地址处理: IPv4 → 整数的转换和运算
   对比: 大多数 SQL 引擎都支持位运算，语法基本一致

## 7. 其他数学函数


注意: MaxCompute 不提供 PI() 函数
替代: 使用 ACOS(-1) 或字面量 3.141592653589793


```sql
SELECT CBRT(27);                            -- 3.0（立方根，2.0+）
SELECT FACTORIAL(5);                        -- 120（阶乘，2.0+）
SELECT WIDTH_BUCKET(15, 0, 100, 10);        -- 2（等宽直方图分桶，2.0+）

```

 WIDTH_BUCKET 在数据分析中的价值:
   将连续值分配到等宽区间（直方图分析）
   对比: PostgreSQL 也有 WIDTH_BUCKET（SQL:2003 标准函数）

## 8. 数学函数在分布式环境中的注意事项


 RAND() 在分布式执行中:
   每个 Map/Reduce 任务有独立的随机种子
   相同的 RAND(seed) 在不同任务中产生不同的序列
   不适合需要全局确定性的场景

 浮点数精度:
   分布式求和的精度问题: 不同执行顺序可能产生不同结果
   SUM(0.1) 对 1000 万行: 结果可能不是精确的 1000000.0
   解决: 对精度敏感的场景使用 DECIMAL 类型而非 DOUBLE

## 9. 横向对比: 数学函数


 基本函数（ABS/CEIL/FLOOR/ROUND/MOD）:
   所有引擎均支持，语义基本一致

 LOG 参数顺序:
MaxCompute: LOG(base, value)  | BigQuery: LOG(value, base)
MySQL:      LOG(base, value)  | PostgreSQL: 不支持两参数 LOG

 PI:
MaxCompute: 无 PI()           | PostgreSQL: PI()
BigQuery:   ACOS(-1) 替代     | MySQL: PI()

 位运算:
MaxCompute: & | ^ ~ SHIFTLEFT/RIGHT  | PostgreSQL: & | # ~ << >>
BigQuery:   BIT_AND/OR/XOR           | MySQL: & | ^ ~ << >>

## 10. 对引擎开发者的启示


### 1. 数学函数是最标准化的函数族 — 差异主要在参数顺序和命名

### 2. LOG 的参数顺序不一致是经典问题 — 应与 SQL 标准对齐

### 3. RAND() 在分布式环境中的行为需要明确文档化

### 4. 浮点求和的精度问题在分布式场景中更严重 — 应支持 Kahan 求和

### 5. WIDTH_BUCKET 对数据分析很有价值 — 值得实现

### 6. PI() 是简单但常被遗忘的数学常量函数 — 应提供

