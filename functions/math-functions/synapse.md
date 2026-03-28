# Azure Synapse Analytics: 数学函数

> 参考资料:
> - [Azure Synapse Analytics - Mathematical Functions (T-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/functions/mathematical-functions-transact-sql)
> - [Synapse SQL Pool - Supported T-SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/develop-tsql-language-elements)


## 基础算术

```sql
SELECT ABS(-42);                             -- 42           绝对值
SELECT CEILING(4.3);                         -- 5            向上取整（注意：无 CEIL，仅 CEILING）
SELECT FLOOR(4.7);                           -- 4            向下取整
SELECT ROUND(3.14159, 2);                    -- 3.14         四舍五入到小数点后 2 位
SELECT ROUND(3.14159, 2, 1);                 -- 3.14         第三参数非 0 时为截断模式（不四舍五入）
SELECT ROUND(3.14559, 2, 0);                 -- 3.15         第三参数为 0 时正常四舍五入
SELECT 17 % 5;                               -- 2            取模运算符（无 MOD 函数）
SELECT POWER(2, 10);                         -- 1024         幂运算（无 POW 缩写）
SELECT SQRT(144);                            -- 12           平方根
SELECT SQUARE(12);                           -- 144          平方（Synapse/SQL Server 特有）
SELECT SIGN(-42);                            -- -1           符号函数
SELECT SIGN(0);                              -- 0
SELECT SIGN(42);                             -- 1
```


注意：Synapse 无 CEIL 函数，必须使用 CEILING
注意：无 CBRT（立方根）函数
注意：ROUND 第三参数控制截断行为，是 SQL Server/Synapse 特有扩展

## 对数 / 指数

```sql
SELECT EXP(1);                               -- 2.718281...  e 的指定次幂
SELECT LOG(EXP(1));                          -- ≈ 1.0        自然对数（SQL Server 2012+ / Synapse）
SELECT LOG(1024, 2);                         -- 10           自定义底数对数（第二参数为底数）
SELECT LOG10(1000);                          -- 3            以 10 为底的对数
```


注意：LOG() 在 SQL Server 2012 之前等同于 LOG10()
从 SQL Server 2012 起 LOG(x) 为自然对数，LOG(x, base) 支持自定义底数
注意：无 LOG2 函数，可用 LOG(x, 2) 替代
注意：无 LN 函数，使用 LOG()

## 三角函数（弧度）

```sql
SELECT SIN(0);                               -- 0            正弦
SELECT COS(0);                               -- 1            余弦
SELECT TAN(0);                               -- 0            正切
SELECT ASIN(1);                              -- π/2          反正弦
SELECT ACOS(1);                              -- 0            反余弦
SELECT ATAN(1);                              -- π/4          反正切
SELECT ATN2(1, 1);                           -- π/4          双参数反正切（注意：ATN2 而非 ATAN2）
SELECT COT(1);                               -- 0.6420...    余切
```


弧度角度转换
```sql
SELECT DEGREES(PI());                        -- 180          弧度转角度
SELECT RADIANS(180.0);                       -- 3.141593     角度转弧度
```


注意：双参数反正切函数名为 ATN2（不是 ATAN2），与 SQL Server 一致
注意：无 SINH/COSH/TANH 双曲函数

## 其他函数

```sql
SELECT PI();                                 -- 3.141593     圆周率常量
SELECT RAND();                               -- 0~1 之间随机浮点数
SELECT RAND(42);                             -- 可重复随机数（给定种子）
```


GREATEST / LEAST
注意：Synapse Dedicated SQL Pool 不支持 GREATEST/LEAST
Serverless SQL Pool 在较新版本中可能支持
替代方案：
```sql
SELECT MAX(v) FROM (VALUES (1), (5), (3), (9), (2)) AS T(v);  -- 模拟 GREATEST
SELECT MIN(v) FROM (VALUES (1), (5), (3), (9), (2)) AS T(v);  -- 模拟 LEAST
```


位运算符
```sql
SELECT 5 & 3;                               -- 1            按位与 (AND)
SELECT 5 | 3;                               -- 7            按位或 (OR)
SELECT 5 ^ 3;                               -- 6            按位异或 (XOR)
SELECT ~5;                                   -- -6           按位取反 (NOT)
```


版本说明：
Synapse Dedicated SQL Pool : 基于 SQL Server T-SQL，部分函数受限
Synapse Serverless SQL Pool: 支持更多 T-SQL 函数
注意：^ 是 XOR 运算符（不是幂运算，幂用 POWER）
注意：无 TRUNCATE/TRUNC 函数，可用 ROUND(x, d, 1) 截断模式替代
注意：MOD 运算使用 % 运算符，无 MOD() 函数
限制：无 CBRT、LN、LOG2 函数
限制：无 GREATEST/LEAST（Dedicated SQL Pool）
限制：无 DEGREES/RADIANS 在某些旧版本中
