# TDSQL: Math Functions

> 参考资料:
> - [TDSQL Documentation](https://cloud.tencent.com/document/product/557)


## 基本数学函数

```sql
SELECT ABS(-42);                          -- 42
SELECT CEIL(4.3);                         -- 5            (CEILING 同义)
SELECT CEILING(4.3);                      -- 5
SELECT FLOOR(4.7);                        -- 4
SELECT ROUND(3.14159, 2);                 -- 3.14
SELECT ROUND(3.14159);                    -- 3
SELECT TRUNCATE(3.14159, 2);              -- 3.14
```

## 取模运算

```sql
SELECT MOD(17, 5);                        -- 2
SELECT 17 % 5;                            -- 2
SELECT 17 MOD 5;                          -- 2            (关键字形式)
```

## 幂、根、指数、对数

```sql
SELECT POWER(2, 10);                      -- 1024         (POW 同义)
SELECT POW(2, 10);                        -- 1024
SELECT SQRT(144);                         -- 12
SELECT EXP(1);                            -- 2.718281828...
SELECT LN(2.718281828);                   -- ≈ 1.0
SELECT LOG(2.718281828);                  -- ≈ 1.0        (以 e 为底)
SELECT LOG2(1024);                        -- 10           (以 2 为底)
SELECT LOG10(1000);                       -- 3
```

## 符号、常量和随机数

```sql
SELECT SIGN(-42);                         -- -1
SELECT SIGN(0);                           -- 0
SELECT SIGN(42);                          -- 1
SELECT PI();                              -- 3.141593
SELECT RAND();                            -- 0.0 到 1.0 之间
SELECT RAND(42);                          -- 可重复的随机数（给定种子）
SELECT FLOOR(RAND() * 100 + 1);          -- 1 到 100 的随机整数
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
SELECT COT(1);                            -- 0.6420...    (余切)
```

## GREATEST / LEAST

```sql
SELECT GREATEST(1, 5, 3, 9, 2);          -- 9
SELECT LEAST(1, 5, 3, 9, 2);             -- 1
```

## 位运算

```sql
SELECT 5 & 3;                             -- 1            (AND)
SELECT 5 | 3;                             -- 7            (OR)
SELECT 5 ^ 3;                             -- 6            (XOR)
SELECT ~5;                                -- 64位 NOT
SELECT 1 << 4;                            -- 16           (左移)
SELECT 16 >> 2;                           -- 4            (右移)
```

## 进制转换

```sql
SELECT CONV(255, 10, 16);                 -- 'FF'
SELECT CONV('FF', 16, 10);               -- '255'
```

注意：TDSQL 完全兼容 MySQL 数学函数
注意：LOG(x) 以 e 为底（与 MySQL 一致）
注意：^ 是 XOR 运算符（幂运算用 POW/POWER）
注意：TRUNCATE 而非 TRUNC
限制：无立方根函数
限制：无 GCD/LCM
