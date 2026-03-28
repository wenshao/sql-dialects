# KingbaseES: Math Functions

> 参考资料:
> - [KingbaseES SQL 参考手册](https://help.kingbase.com.cn/)
> - ============================================================
> - 基本数学函数（兼容 PostgreSQL/Oracle）
> - ============================================================

```sql
SELECT ABS(-42);                          -- 42
SELECT CEIL(4.3);                         -- 5
SELECT CEILING(4.3);                      -- 5
SELECT FLOOR(4.7);                        -- 4
SELECT ROUND(3.14159, 2);                 -- 3.14
SELECT ROUND(3.14159);                    -- 3
SELECT TRUNC(3.14159, 2);                 -- 3.14
SELECT TRUNC(3.14159);                    -- 3
```

## 取模运算

```sql
SELECT MOD(17, 5);                        -- 2
```

## 幂、根、指数、对数

```sql
SELECT POWER(2, 10);                      -- 1024
SELECT SQRT(144);                         -- 12
SELECT CBRT(27);                          -- 3            (立方根，PostgreSQL 模式)
SELECT EXP(1);                            -- 2.718281828...
SELECT LN(2.718281828);                   -- ≈ 1.0
SELECT LOG(100);                          -- 2            (以 10 为底，PostgreSQL 模式)
```

## 符号、常量和随机数

```sql
SELECT SIGN(-42);                         -- -1
SELECT SIGN(0);                           -- 0
SELECT SIGN(42);                          -- 1
SELECT PI();                              -- 3.14159265358979
SELECT RANDOM();                          -- 0.0 到 1.0 之间
```

## 三角函数（弧度）

```sql
SELECT SIN(0);                            -- 0
SELECT COS(0);                            -- 1
SELECT TAN(PI()/4);                       -- ≈ 1.0
SELECT ASIN(1);                           -- π/2
SELECT ACOS(1);                           -- 0
SELECT ATAN(1);                           -- π/4
SELECT ATAN2(1, 1);                       -- π/4
SELECT DEGREES(PI());                     -- 180
SELECT RADIANS(180);                      -- π
```

## GREATEST / LEAST

```sql
SELECT GREATEST(1, 5, 3, 9, 2);          -- 9
SELECT LEAST(1, 5, 3, 9, 2);             -- 1
```

## 位运算（PostgreSQL 模式）

```sql
SELECT 5 & 3;                             -- 1            (AND)
SELECT 5 | 3;                             -- 7            (OR)
SELECT ~5;                                -- -6           (NOT)
SELECT 1 << 4;                            -- 16           (左移)
SELECT 16 >> 2;                           -- 4            (右移)
```

注意：KingbaseES 兼容 PostgreSQL 和 Oracle 数学函数
注意：具体支持取决于兼容模式（PG 模式 / Oracle 模式）
注意：Oracle 模式下 LOG 行为可能不同
注意：Oracle 模式额外支持 REMAINDER 等函数
