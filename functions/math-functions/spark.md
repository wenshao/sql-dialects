# Spark SQL: 数学函数 (Math Functions)

> 参考资料:
> - [1] Spark SQL - Built-in Math Functions
>   https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html#math-functions


## 1. 基本数学函数

```sql
SELECT ABS(-42);                                         -- 42
SELECT CEIL(4.3);                                        -- 5
SELECT CEILING(4.3);                                     -- 5 (别名)
SELECT FLOOR(4.7);                                       -- 4
SELECT ROUND(3.14159, 2);                                -- 3.14
SELECT BROUND(2.5);                                      -- 2 (银行家舍入)
SELECT MOD(17, 5);                                       -- 2
SELECT 17 % 5;                                           -- 2

```

 设计分析: BROUND（Banker's Rounding）
   BROUND 使用"四舍六入五留双"规则: 当恰好在 .5 时，取最近的偶数
   BROUND(2.5) = 2, BROUND(3.5) = 4, BROUND(4.5) = 4
   这减少了统计学上的系统性偏差（标准 ROUND 总是向上进位导致均值偏高）
   Python 的 round() 默认也使用银行家舍入
   MySQL/PostgreSQL 的 ROUND 使用传统"四舍五入"
   对引擎开发者: 提供两种舍入模式（ROUND + BROUND）是最佳做法

## 2. 幂运算与对数

```sql
SELECT POWER(2, 10);                                     -- 1024
SELECT POW(2, 10);                                       -- 别名
SELECT SQRT(144);                                        -- 12
SELECT CBRT(27);                                         -- 3
SELECT EXP(1);                                           -- e^1 = 2.718...
SELECT LN(EXP(1));                                       -- 1.0
SELECT LOG(EXP(1));                                      -- 1.0 (自然对数)
SELECT LOG(10, 1000);                                    -- 3.0 (以 10 为底)
SELECT LOG2(1024);                                       -- 10
SELECT LOG10(1000);                                      -- 3

```

## 3. 符号与常数

```sql
SELECT SIGN(-42);                                        -- -1
SELECT SIGNUM(-42);                                      -- -1.0 (别名)
SELECT PI();                                             -- 3.14159...
SELECT E();                                              -- 2.71828... (欧拉数)

```

## 4. 随机数

```sql
SELECT RAND();                                           -- [0, 1) 均匀分布
SELECT RAND(42);                                         -- 固定种子（可重现）
SELECT RANDN();                                          -- 标准正态分布 N(0,1)
SELECT RANDN(42);                                        -- 固定种子正态分布

```

 RANDN 是 Spark 独有的——大多数 SQL 引擎只提供均匀分布随机数
 正态分布随机数在统计模拟和测试数据生成中非常有用

## 5. 三角函数

```sql
SELECT SIN(0), COS(0), TAN(0);
SELECT ASIN(1), ACOS(1), ATAN(1), ATAN2(1, 1);
SELECT DEGREES(PI());                                    -- 180
SELECT RADIANS(180);                                     -- PI
SELECT SINH(1), COSH(1), TANH(1);

```

## 6. 比较函数

```sql
SELECT GREATEST(1, 5, 3);                                -- 5
SELECT LEAST(1, 5, 3);                                   -- 1
```

 注意: 任何参数为 NULL 则返回 NULL（Spark 行为）

## 7. 位运算

```sql
SELECT 5 & 3;                                            -- 1 (AND)
SELECT 5 | 3;                                            -- 7 (OR)
SELECT 5 ^ 3;                                            -- 6 (XOR)
SELECT ~5;                                               -- -6 (NOT)
SELECT SHIFTLEFT(1, 4);                                  -- 16
SELECT SHIFTRIGHT(16, 2);                                -- 4
SELECT SHIFTRIGHTUNSIGNED(16, 2);                        -- 4 (无符号右移)
SELECT BIT_COUNT(7);                                     -- 3

```

 对比:
MySQL:      位运算符完全一致（& | ^ ~ << >>）
   PostgreSQL: 类似但用 # 代替 ^（^ 在 PG 中是幂运算!）
   Spark:      ^ 是 XOR（与 MySQL 一致，与 PostgreSQL 不同）

## 8. 进制与编码转换

```sql
SELECT CONV(255, 10, 16);                                -- 'FF' (十进制转十六进制)
SELECT BIN(255);                                         -- '11111111'
SELECT HEX(255);                                         -- 'FF'
SELECT UNHEX('FF');                                      -- binary

```

## 9. 其他函数

```sql
SELECT FACTORIAL(5);                                     -- 120
SELECT WIDTH_BUCKET(42, 0, 100, 10);                     -- 5 (分桶)

```

 WIDTH_BUCKET 将值分到等宽桶中:
 WIDTH_BUCKET(value, low, high, num_buckets)
 将 [low, high) 等分为 num_buckets 个桶，返回 value 所在的桶号
 这是 SQL 标准函数，在直方图生成和数据分布分析中非常有用

## 10. try_* 安全数学函数

```sql
SELECT try_divide(10, 0);                                -- NULL (Spark 3.2+)
SELECT try_add(2147483647, 1);                           -- NULL (INT 溢出)
SELECT try_subtract(-2147483648, 1);                     -- NULL
SELECT try_multiply(2147483647, 2);                      -- NULL

```

## 11. 版本演进

Spark 2.0: 基本数学函数（继承 Hive）
Spark 3.0: E() 常数, 更多位运算函数
Spark 3.2: try_divide, try_add, try_subtract, try_multiply
Spark 3.4: 数学函数增强

限制:
数学函数与 Hive 兼容（函数名、参数顺序一致）
BROUND 是 Spark/Hive 特色（银行家舍入）
RANDN 提供正态分布随机数（大多数引擎不支持）
无 TRUNC 数字截断（用 FLOOR/CAST 替代）

