# SQL 标准: 数学函数

> 参考资料:
> - [ISO/IEC 9075-2: SQL Foundation - Numeric Value Functions](https://www.iso.org/standard/76584.html)
> - [SQL:2016 - Numeric Value Expressions](https://www.iso.org/standard/63556.html)

## 基本数学函数

```sql
SELECT ABS(-42);                          -- 42 (绝对值)
SELECT CEIL(4.3);                         -- 5 (向上取整，CEILING 同义)
SELECT CEILING(4.3);                      -- 5
SELECT FLOOR(4.7);                        -- 4 (向下取整)
SELECT ROUND(3.14159, 2);                 -- 3.14 (四舍五入)
```

TRUNCATE 不在 SQL 标准中

## 取模运算

```sql
SELECT MOD(17, 5);                        -- 2 (取模)
```

% 运算符不在 SQL 标准中，但广泛支持

## 幂和根

```sql
SELECT POWER(2, 10);                      -- 1024 (幂运算)
SELECT SQRT(144);                         -- 12 (平方根)
SELECT EXP(1);                            -- 2.718... (e 的幂)
SELECT LN(2.718281828);                   -- ≈ 1.0 (自然对数)
SELECT LOG(100);                          -- 标准未明确定义底数
SELECT LOG10(1000);                       -- 3.0 (常用对数)
```

## 符号和常量

```sql
SELECT SIGN(-42);                         -- -1 (符号函数)
SELECT SIGN(0);                           -- 0
SELECT SIGN(42);                          -- 1
```

## 三角函数

```sql
SELECT SIN(0);                            -- 0 (正弦)
SELECT COS(0);                            -- 1 (余弦)
SELECT TAN(0);                            -- 0 (正切)
SELECT ASIN(1);                           -- π/2 (反正弦)
SELECT ACOS(1);                           -- 0 (反余弦)
SELECT ATAN(1);                           -- π/4 (反正切)
SELECT ATAN2(1, 1);                       -- π/4 (两参数反正切)
```

## GREATEST / LEAST

非 SQL 标准核心函数，但广泛支持
SELECT GREATEST(1, 5, 3);              -- 5
SELECT LEAST(1, 5, 3);                 -- 1

## 位运算 (SQL 标准未定义，各数据库自行实现)

常见运算符: & (AND), | (OR), ^ (XOR), ~ (NOT), << (左移), >> (右移)
常见函数: BIT_AND(), BIT_OR(), BIT_XOR()

- **注意：SQL 标准定义了 ABS, CEIL/CEILING, FLOOR, ROUND, MOD, POWER, SQRT, EXP, LN**
- **注意：三角函数在 SQL:2016 中标准化**
- **注意：LOG 的行为（底数）因实现而异**
- **注意：TRUNCATE, PI(), RAND() 不在 SQL 标准中**
- **注意：各数据库对标准的实现和扩展各有不同**
