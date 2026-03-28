# Snowflake: 数学函数

> 参考资料:
> - [1] Snowflake SQL Reference - Numeric Functions
>   https://docs.snowflake.com/en/sql-reference/functions-numeric


## 1. 基本数学函数


```sql
SELECT ABS(-42);                        -- 42
SELECT CEIL(4.3);                       -- 5
SELECT FLOOR(4.7);                      -- 4
SELECT ROUND(3.14159, 2);              -- 3.14
SELECT TRUNCATE(3.14159, 2);           -- 3.14 (截断，不四舍五入)
SELECT MOD(17, 5);                      -- 2
SELECT 17 % 5;                          -- 2 (运算符形式)
SELECT SIGN(-42);                       -- -1

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 DIV0 / DIV0NULL: 安全除法（Snowflake 独有）

```sql
SELECT DIV0(10, 0);                     -- 0 (除以零返回 0)
SELECT DIV0NULL(10, 0);                 -- NULL (除以零返回 NULL)

```

 传统 SQL: 10 / 0 → 报错（DIVISION_BY_ZERO）
 Snowflake: DIV0(10, 0) → 0（静默处理）
 这对 ETL 数据清洗非常有价值（脏数据中的零除数不会终止管道）

 对比:
   PostgreSQL: 无原生安全除法（需要 NULLIF: a / NULLIF(b, 0)）
   MySQL:      无原生安全除法（同上）
   BigQuery:   IEEE_DIVIDE(a, b) 返回 Inf/NaN（IEEE 754 语义）
   Oracle:     无原生安全除法
   SQL Server: 无原生安全除法

 对引擎开发者的启示:
   安全除法是高频需求。NULLIF(b, 0) 变通方案虽然可行，
   但专用函数更清晰。推荐引擎提供 DIV0/SAFE_DIVIDE 等内置函数。

## 3. 幂与对数


```sql
SELECT POWER(2, 10);                    -- 1024
SELECT POW(2, 10);                      -- 1024 (别名)
SELECT SQRT(144);                       -- 12
SELECT CBRT(27);                        -- 3
SELECT EXP(1);                          -- 2.71828...
SELECT LN(EXP(1));                      -- 1 (自然对数)
SELECT LOG(10, 1000);                   -- 3 (以 10 为底)
SELECT PI();                            -- 3.14159...

```

 LOG(base, x): Snowflake 的底数在前参数在后
对比: PostgreSQL LOG(base, x) 一致 | MySQL LOG(x) 或 LOG(base, x)

## 4. 随机数


```sql
SELECT RANDOM();                        -- 全范围整数随机数
SELECT UNIFORM(1, 100, RANDOM());       -- 1-100 均匀分布
SELECT NORMAL(0, 1, RANDOM());          -- 正态分布 (均值0, 标准差1)

```

 UNIFORM / NORMAL 需要 RANDOM() 作为种子参数
 这是 Snowflake 独特的设计（大多数数据库的随机函数不需要种子参数）
 好处: 传入固定种子可以生成可重复的随机数

 对比:
   PostgreSQL: random()（0-1 浮点数）, setseed() 设置种子
   MySQL:      RAND() 或 RAND(seed)
   BigQuery:   RAND()
   Oracle:     DBMS_RANDOM.VALUE

## 5. 三角函数


```sql
SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1);
SELECT ATAN2(1, 1);
SELECT COT(1);
SELECT DEGREES(PI()); SELECT RADIANS(180);
SELECT SINH(1); SELECT COSH(1); SELECT TANH(1);

```

## 6. 位运算


```sql
SELECT BITAND(5, 3);                    -- 1 (101 & 011 = 001)
SELECT BITOR(5, 3);                     -- 7 (101 | 011 = 111)
SELECT BITXOR(5, 3);                    -- 6 (101 ^ 011 = 110)
SELECT BITNOT(5);                       -- -6 (按位取反)
SELECT BITSHIFTLEFT(1, 4);             -- 16 (1 << 4)
SELECT BITSHIFTRIGHT(16, 2);           -- 4 (16 >> 2)

```

对比: PostgreSQL 使用 & | # ~ << >> 运算符
 Snowflake 使用函数形式（更明确但更冗长）

## 7. 其他数学函数


```sql
SELECT GREATEST(1, 5, 3);              -- 5
SELECT LEAST(1, 5, 3);                  -- 1
SELECT FACTORIAL(5);                    -- 120
SELECT SQUARE(5);                       -- 25
SELECT HAVERSINE(40.7, -74.0, 51.5, -0.1); -- 地球球面距离(度)
SELECT WIDTH_BUCKET(42, 0, 100, 10);   -- 5 (分桶)

```

 HAVERSINE: 计算两个经纬度坐标之间的球面距离
 这对地理分析场景有价值，大多数数据库需要自定义函数实现
对比: PostgreSQL PostGIS ST_Distance | BigQuery ST_DISTANCE

## 横向对比: 数学函数亮点

| 函数         | Snowflake    | BigQuery     | PostgreSQL  | MySQL |
|------|------|------|------|------|
| 安全除法     | DIV0/DIV0NULL| IEEE_DIVIDE  | 无(NULLIF)  | 无(NULLIF) |
| 均匀随机     | UNIFORM      | RAND         | random()    | RAND() |
| 正态分布     | NORMAL       | 无           | 无          | 无 |
| 球面距离     | HAVERSINE    | ST_DISTANCE  | PostGIS     | 自定义 |
| 分桶         | WIDTH_BUCKET | 不支持       | 支持        | 不支持 |
| 位运算       | 函数形式     | 运算符+函数  | 运算符      | 运算符 |

