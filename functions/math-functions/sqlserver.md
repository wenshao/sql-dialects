# SQL Server: 数学函数

> 参考资料:
> - [SQL Server T-SQL - Mathematical Functions](https://learn.microsoft.com/en-us/sql/t-sql/functions/mathematical-functions-transact-sql)

## 基本数学函数

```sql
SELECT ABS(-42);                -- 42
SELECT CEILING(4.3);            -- 5（向上取整，注意: 无 CEIL 别名）
SELECT FLOOR(4.7);              -- 4（向下取整）
SELECT ROUND(3.14159, 2);       -- 3.14
SELECT ROUND(3.14159, 2, 1);   -- 3.14（第 3 参数=1: 截断模式，不是四舍五入）
SELECT ROUND(3.14159, 0);       -- 3

-- SQL Server 独有函数:
SELECT SQUARE(12);              -- 144（平方，其他数据库用 POWER(12,2)）

-- 设计分析:
--   CEILING（不是 CEIL）: SQL Server 是唯一不支持 CEIL 缩写的主流数据库。
--   ROUND 的第 3 参数（截断模式）: 这是 SQL Server 独有的设计。
--     ROUND(3.14, 1)    → 3.1（四舍五入）
--     ROUND(3.14, 1, 1) → 3.1（截断）
--     ROUND(3.15, 1)    → 3.2（四舍五入）
--     ROUND(3.15, 1, 1) → 3.1（截断）
--   其他数据库使用 TRUNC/TRUNCATE 函数实现截断，SQL Server 没有 TRUNC。
--
-- 横向对比:
--   PostgreSQL: CEIL/CEILING, TRUNC(x, n)
--   MySQL:      CEIL/CEILING, TRUNCATE(x, n)
--   Oracle:     CEIL, TRUNC(x, n)
--   SQL Server: CEILING（无 CEIL）, ROUND(x, n, 1)（无 TRUNC）
```

## 取模运算

```sql
SELECT 17 % 5;                  -- 2（% 运算符）
-- SQL Server 没有 MOD() 函数（PostgreSQL/MySQL/Oracle 都有）
```

## 幂、根、指数、对数

```sql
SELECT POWER(2, 10);            -- 1024
SELECT SQRT(144);               -- 12
SELECT EXP(1);                  -- 2.718281828...
SELECT LOG(2.718281828);        -- ≈ 1.0（自然对数）
SELECT LOG(1024, 2);            -- 10（自定义底数，2012+）
SELECT LOG10(1000);             -- 3
```

## 符号和常量

```sql
SELECT SIGN(-42);               -- -1
SELECT SIGN(0);                 -- 0
SELECT SIGN(42);                -- 1
SELECT PI();                    -- 3.14159265358979
```

## 随机数

```sql
SELECT RAND();                  -- 0.0 到 1.0 之间（会话级种子）
SELECT RAND(42);                -- 可重复随机数（指定种子）

-- RAND() 在同一个 SELECT 中每行返回相同值（会话级种子，不是行级）
-- 行级随机数需要使用 CHECKSUM + NEWID 技巧:
SELECT ABS(CHECKSUM(NEWID())) % 100 + 1 AS random_1_to_100;
```

设计分析（对引擎开发者）:
  RAND() 是会话级随机——这意味着 SELECT RAND(), RAND() 返回相同值。
  这是一个常见的混淆点。其他数据库的 RANDOM()/RAND() 通常也是如此，
  但 PostgreSQL 的 random() 每次调用返回不同值。

对引擎开发者的启示:
  随机函数的"确定性"属性影响查询优化: 如果标记为确定性，
  优化器可能只求值一次并缓存结果。SQL Server 的 RAND 标记为非确定性，
  但在同一语句中只生成一个随机数（性能优化）。

## 三角函数

```sql
SELECT SIN(0), COS(0), TAN(PI()/4);
SELECT ASIN(1), ACOS(1), ATAN(1);
SELECT ATN2(1, 1);              -- π/4（注意: ATN2 不是 ATAN2！）
SELECT COT(1);                  -- 余切（SQL Server 独有函数）

SELECT DEGREES(PI());           -- 180
SELECT RADIANS(180.0);          -- π
```

ATN2 命名:
  SQL Server: ATN2（独有名称）
  其他数据库: ATAN2
  这是 T-SQL 与标准 SQL 命名差异的又一个例子。

## 位运算

```sql
SELECT 5 & 3;                   -- 1（AND）
SELECT 5 | 3;                   -- 7（OR）
SELECT 5 ^ 3;                   -- 6（XOR）——注意: ^ 是 XOR，不是幂！
SELECT ~5;                      -- -6（NOT）

-- POWER 是幂运算（不是 ^）: SELECT POWER(2, 10); → 1024
-- 这是 SQL Server 的重要注意事项: ^ 是 XOR，而非幂运算。
-- 横向对比:
--   PostgreSQL: ^ 是幂运算，# 是 XOR
--   MySQL:      ^ 是 XOR（同 SQL Server），POWER 是幂
--   Oracle:     POWER 是幂（无位运算符，使用 BITAND 函数）

-- SQL Server 无左移/右移运算符（<< >>），需要用 POWER 模拟:
SELECT 1 * POWER(2, 4);        -- 16（模拟左移 4 位）
```

## GREATEST / LEAST（2022+）

```sql
SELECT GREATEST(1, 5, 3, 9, 2);  -- 9
SELECT LEAST(1, 5, 3, 9, 2);    -- 1

-- 2022 之前需要模拟:
SELECT IIF(5 > 3, 5, 3);        -- 两值取大
SELECT (SELECT MAX(v) FROM (VALUES (1),(5),(3),(9),(2)) AS t(v)); -- 多值取大

-- 版本说明:
-- 2005+ : 基本数学函数, SQUARE, ATN2
-- 2012+ : LOG(x, base) 两参数版本
-- 2022+ : GREATEST, LEAST
-- 限制: 无 CEIL（用 CEILING）, 无 TRUNC（用 ROUND(x,n,1)）
-- 限制: 无 MOD()（用 % 运算符）, 无 ATAN2（用 ATN2）
-- 限制: ^ 是 XOR（幂用 POWER）, 无 << >> 运算符
```
