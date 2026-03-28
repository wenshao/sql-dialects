# PolarDB: Math Functions

> 参考资料:
> - [PolarDB Documentation](https://www.alibabacloud.com/help/en/polardb/)
> - ============================================================
> - PolarDB for PostgreSQL
> - ============================================================
> - 基本数学函数

```sql
SELECT ABS(-42);                          -- 42
SELECT CEIL(4.3);                         -- 5
SELECT CEILING(4.3);                      -- 5
SELECT FLOOR(4.7);                        -- 4
SELECT ROUND(3.14159, 2);                 -- 3.14
SELECT TRUNC(3.14159, 2);                 -- 3.14
```

## 取模运算

```sql
SELECT MOD(17, 5);                        -- 2
```

## 幂、根、指数、对数

```sql
SELECT POWER(2, 10);                      -- 1024
SELECT SQRT(144);                         -- 12
SELECT CBRT(27);                          -- 3            (立方根)
SELECT EXP(1);                            -- 2.718281828...
SELECT LN(EXP(1));                        -- 1.0
SELECT LOG(100);                          -- 2            (以 10 为底)
```

## 符号、常量和随机数

```sql
SELECT SIGN(-42);                         -- -1
SELECT PI();                              -- 3.14159265358979
SELECT RANDOM();                          -- 0.0 到 1.0 之间
```

## 三角函数

```sql
SELECT SIN(0);                            -- 0
SELECT COS(0);                            -- 1
SELECT TAN(PI()/4);                       -- ≈ 1.0
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATAN2(1, 1);
SELECT DEGREES(PI());                     -- 180
SELECT RADIANS(180);                      -- π
```

## GREATEST / LEAST

```sql
SELECT GREATEST(1, 5, 3, 9, 2);          -- 9
SELECT LEAST(1, 5, 3, 9, 2);             -- 1
```

## 位运算

```sql
SELECT 5 & 3;                             -- 1 (AND)
SELECT 5 | 3;                             -- 7 (OR)
SELECT 5 # 3;                             -- 6 (XOR)
SELECT ~5;                                -- -6 (NOT)
```

## PolarDB for MySQL

SELECT ABS(-42);                       -- 42
SELECT CEIL(4.3);                      -- 5
SELECT FLOOR(4.7);                     -- 4
SELECT ROUND(3.14159, 2);              -- 3.14
SELECT TRUNCATE(3.14159, 2);           -- 3.14         (TRUNCATE 非 TRUNC)
SELECT MOD(17, 5);                     -- 2
SELECT POW(2, 10);                     -- 1024
SELECT SQRT(144);                      -- 12
SELECT EXP(1);                         -- 2.718281828...
SELECT LN(EXP(1));                     -- 1.0
SELECT LOG(EXP(1));                    -- 1.0          (以 e 为底！)
SELECT LOG2(1024);                     -- 10
SELECT LOG10(1000);                    -- 3
SELECT PI();                           -- 3.141593
SELECT RAND();                         -- 0.0 到 1.0 之间
SELECT RAND(42);                       -- 可重复随机数
注意：PolarDB 有 PostgreSQL 和 MySQL 两个版本，数学函数跟随对应引擎
注意：PostgreSQL 版 LOG(x) 以 10 为底；MySQL 版 LOG(x) 以 e 为底
注意：PostgreSQL 版用 TRUNC；MySQL 版用 TRUNCATE
注意：PostgreSQL 版用 RANDOM()；MySQL 版用 RAND()
注意：PostgreSQL 版支持 CBRT 立方根；MySQL 版不支持
