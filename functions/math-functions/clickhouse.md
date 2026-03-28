# ClickHouse: Math Functions

> 参考资料:
> - [1] ClickHouse Documentation - Mathematical Functions
>   https://clickhouse.com/docs/en/sql-reference/functions/math-functions


## 基本数学函数

```sql
SELECT abs(-42);                          -- 42
SELECT ceil(4.3);                         -- 5            (ceiling 同义)
SELECT ceiling(4.3);                      -- 5
SELECT floor(4.7);                        -- 4
SELECT round(3.14159, 2);                 -- 3.14
SELECT roundBankers(2.5);                 -- 2            (银行家舍入)
SELECT trunc(3.14159, 2);                 -- 3.14         (truncate 同义)

```

取模

```sql
SELECT 17 % 5;                            -- 2
SELECT modulo(17, 5);                     -- 2
SELECT moduloOrZero(17, 0);              -- 0            (安全取模)

```

幂、根、对数

```sql
SELECT power(2, 10);                      -- 1024         (pow 同义)
SELECT pow(2, 10);                        -- 1024
SELECT sqrt(144);                         -- 12
SELECT cbrt(27);                          -- 3            (立方根)
SELECT exp(1);                            -- 2.718...
SELECT exp2(10);                          -- 1024         (2^x)
SELECT exp10(3);                          -- 1000         (10^x)
SELECT ln(exp(1));                        -- 1.0
SELECT log(exp(1));                       -- 1.0          (自然对数)
SELECT log2(1024);                        -- 10
SELECT log10(1000);                       -- 3

SELECT sign(-42);                         -- -1
SELECT pi();                              -- 3.14159...
SELECT e();                               -- 2.71828...

```

随机数

```sql
SELECT rand();                            -- 随机 UInt32
SELECT rand64();                          -- 随机 UInt64
SELECT randNormal(0, 1);                  -- 正态分布
SELECT randUniform(0, 100);               -- 均匀分布
SELECT randExponential(1);                -- 指数分布

```

三角函数

```sql
SELECT sin(0); SELECT cos(0); SELECT tan(0);
SELECT asin(1); SELECT acos(1); SELECT atan(1);
SELECT atan2(1, 1);
SELECT sinh(1); SELECT cosh(1); SELECT tanh(1);
SELECT asinh(1); SELECT acosh(1); SELECT atanh(0.5);
SELECT hypot(3, 4);                       -- 5            (斜边)
SELECT degrees(pi());                     -- 180
SELECT radians(180);                      -- π

```

GREATEST / LEAST

```sql
SELECT greatest(1, 5, 3);                -- 5
SELECT least(1, 5, 3);                   -- 1

```

位运算

```sql
SELECT bitAnd(5, 3);                      -- 1
SELECT bitOr(5, 3);                       -- 7
SELECT bitXor(5, 3);                      -- 6
SELECT bitNot(5);                         -- (按类型取反)
SELECT bitShiftLeft(1, 4);               -- 16
SELECT bitShiftRight(16, 2);             -- 4
SELECT bitCount(7);                       -- 3
SELECT bitRotateLeft(1, 2);              -- 4
SELECT bitRotateRight(16, 2);            -- 4

```

其他

```sql
SELECT intDiv(17, 5);                     -- 3            (整除)
SELECT gcd(12, 18);                       -- 6
SELECT lcm(12, 18);                       -- 36

```

注意：ClickHouse 函数名大小写不敏感
注意：提供丰富的随机分布函数（正态、均匀、指数等）
注意：e() 返回欧拉数
注意：提供 exp2, exp10 快捷函数
限制：位运算使用函数而非运算符

