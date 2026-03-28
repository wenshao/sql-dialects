# SQLite: 数学函数

> 参考资料:
> - [SQLite Documentation - Built-in Mathematical SQL Functions](https://www.sqlite.org/lang_mathfunc.html)
> - [SQLite Documentation - Core Functions](https://www.sqlite.org/lang_corefunc.html)

## 基本数学函数

```sql
SELECT ABS(-42);                          -- 42
SELECT CEIL(4.3);                         -- 5            -- 3.35.0+
SELECT CEILING(4.3);                      -- 5            -- 3.35.0+
SELECT FLOOR(4.7);                        -- 4            -- 3.35.0+
SELECT ROUND(3.14159, 2);                 -- 3.14
SELECT ROUND(3.14159);                    -- 3
SELECT TRUNC(3.14159);                    -- 3            -- 3.35.0+
```

## 取模运算

```sql
SELECT 17 % 5;                            -- 2            (运算符)
-- 无 MOD() 函数
```

## 幂、根、指数、对数                                   -- 3.35.0+

```sql
SELECT POWER(2, 10);                      -- 1024
SELECT SQRT(144);                         -- 12.0
SELECT EXP(1);                            -- 2.718281828...
SELECT LN(2.718281828);                   -- ≈ 1.0
SELECT LOG(100);                          -- 2.0          (以 10 为底)
SELECT LOG(2, 1024);                      -- 10           (自定义底数)
SELECT LOG2(1024);                        -- 10
SELECT LOG10(1000);                       -- 3.0
```

## 符号和常量                                           -- 3.35.0+

```sql
SELECT SIGN(-42);                         -- -1
SELECT SIGN(0);                           -- 0
SELECT SIGN(42);                          -- 1
SELECT PI();                              -- 3.14159265358979
```

## 随机数

```sql
SELECT RANDOM();                          -- 随机整数（-9223372036854775808 到 +9223372036854775807）
SELECT ABS(RANDOM() % 100) + 1;          -- 1 到 100 的随机整数
```

## 三角函数（弧度）                                     -- 3.35.0+

```sql
SELECT SIN(0);                            -- 0
SELECT COS(0);                            -- 1.0
SELECT TAN(PI()/4);                       -- ≈ 1.0
SELECT ASIN(1);                           -- π/2
SELECT ACOS(1);                           -- 0
SELECT ATAN(1);                           -- π/4
SELECT ATAN2(1, 1);                       -- π/4

-- 弧度角度转换
SELECT DEGREES(PI());                     -- 180
SELECT RADIANS(180);                      -- π

-- 双曲函数                                             -- 3.35.0+
SELECT SINH(1);                           -- 1.1752...
SELECT COSH(1);                           -- 1.5430...
SELECT TANH(1);                           -- 0.7615...
SELECT ASINH(1);                          -- 0.8813...
SELECT ACOSH(1);                          -- 0
SELECT ATANH(0.5);                        -- 0.5493...
```

## GREATEST / LEAST（替代方案）

```sql
SELECT MAX(1, 5, 3);                      -- 5            (MIN/MAX 不支持多参数)
-- 使用 CASE 或子查询模拟
```

## 位运算

```sql
SELECT 5 & 3;                             -- 1            (AND)
SELECT 5 | 3;                             -- 7            (OR)
SELECT ~5;                                -- -6           (NOT)
SELECT 1 << 4;                            -- 16           (左移)
SELECT 16 >> 2;                           -- 4            (右移)
-- 无 XOR 运算符（使用 (a | b) - (a & b) 模拟）

-- 版本说明：
--   SQLite 全版本   : ABS, ROUND, RANDOM, 位运算
--   SQLite 3.35.0+  : 数学函数扩展（需编译时启用 -DSQLITE_ENABLE_MATH_FUNCTIONS）
-- 注意：数学函数需要编译时启用（默认在大多数发行版中已启用）
-- 注意：RANDOM() 返回整数而非 0-1 浮点数
-- 注意：无 MOD() 函数，使用 % 运算符
-- 限制：GREATEST/LEAST 不可用
-- 限制：无 XOR 运算符
-- 限制：3.35.0 之前数学函数非常有限
```
