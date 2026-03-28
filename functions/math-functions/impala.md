# Apache Impala: 数学函数

> 参考资料:
> - [Impala Mathematical Functions](https://impala.apache.org/docs/build/html/topics/impala_math_functions.html)
> - [Impala SQL Reference - Built-in Functions](https://impala.apache.org/docs/build/html/topics/impala_builtin_functions.html)


## 基础算术

```sql
SELECT ABS(-42);                             -- 42           绝对值
SELECT CEIL(4.3);                            -- 5            向上取整
SELECT CEILING(4.3);                         -- 5            向上取整（CEIL 同义）
SELECT FLOOR(4.7);                           -- 4            向下取整
SELECT ROUND(3.14159, 2);                    -- 3.14         四舍五入到小数点后 2 位
SELECT ROUND(3.14159);                       -- 3            四舍五入到整数
SELECT TRUNCATE(3.14159, 2);                 -- 3.14         截断（注意：非 TRUNC）
SELECT MOD(17, 5);                           -- 2            整数取模
SELECT 17 % 5;                               -- 2            取模运算符
SELECT FMOD(17.5, 5.0);                      -- 2.5          浮点取模（Impala 特有）
SELECT POWER(2, 10);                         -- 1024         幂运算
SELECT POW(2, 10);                           -- 1024         幂运算（POWER 缩写）
SELECT SQRT(144);                            -- 12           平方根
SELECT SIGN(-42);                            -- -1           符号函数
SELECT SIGN(0);                              -- 0
SELECT SIGN(42);                             -- 1
```


注意：Impala 支持 FMOD 用于浮点数取模，返回浮点结果
注意：TRUNCATE 函数名（不是 TRUNC）
注意：无 CBRT（立方根）函数

## 三角函数（弧度）

```sql
SELECT SIN(0);                               -- 0            正弦
SELECT COS(0);                               -- 1            余弦
SELECT TAN(0);                               -- 0            正切
SELECT ASIN(1);                              -- π/2          反正弦
SELECT ACOS(1);                              -- 0            反余弦
SELECT ATAN(1);                              -- π/4          反正切
SELECT ATAN2(1, 1);                          -- π/4          双参数反正切
SELECT COT(1);                               -- 0.6420...    余切
```


双曲函数
```sql
SELECT SINH(1);                              -- 1.1752...    双曲正弦
SELECT COSH(1);                              -- 1.5430...    双曲余弦
SELECT TANH(1);                              -- 0.7615...    双曲正切
```


弧度角度转换
```sql
SELECT DEGREES(PI());                        -- 180          弧度转角度
SELECT RADIANS(180);                         -- π            角度转弧度
```


## 对数 / 指数

```sql
SELECT EXP(1);                               -- 2.718281...  e 的指定次幂
SELECT LN(EXP(1));                           -- ≈ 1.0        自然对数
SELECT LOG(EXP(1));                          -- ≈ 1.0        自然对数（LN 的同义词）
SELECT LOG2(1024);                           -- 10           以 2 为底的对数
SELECT LOG10(1000);                          -- 3            以 10 为底的对数
```


注意：Impala 中 LOG(x) 等同于 LN(x)，即自然对数（以 e 为底）
区别于 PostgreSQL/Vertica 中 LOG(x) 以 10 为底
注意：支持 LOG2 函数（以 2 为底）

## 其他函数

```sql
SELECT PI();                                 -- 3.141593     圆周率常量
```


随机数
```sql
SELECT RAND();                               -- 0~1 之间随机浮点数
SELECT RAND(42);                             -- 可重复随机数（给定种子）
```


GREATEST / LEAST
```sql
SELECT GREATEST(1, 5, 3, 9, 2);             -- 9            取最大值
SELECT LEAST(1, 5, 3, 9, 2);                -- 1            取最小值
```


正数/负数判断
```sql
SELECT POSITIVE(42);                         -- 42           返回正数值（Impala 特有）
SELECT NEGATIVE(-42);                        -- 42           返回负数值（Impala 特有）
```


精度控制
```sql
SELECT PRECISION(3.14159);                   -- 精度信息（Impala 特有）
SELECT SCALE(3.14159);                       -- 小数位数（Impala 特有）
```


位运算（函数形式，非运算符）
```sql
SELECT BITAND(5, 3);                         -- 1            按位与
SELECT BITOR(5, 3);                          -- 7            按位或
SELECT BITXOR(5, 3);                         -- 6            按位异或
SELECT BITNOT(5);                            -- -6           按位取反
SELECT SHIFTLEFT(1, 4);                      -- 16           左移位
SELECT SHIFTRIGHT(16, 2);                    -- 4            右移位
SELECT SHIFTRIGHTUNSIGNED(16, 2);            -- 4            无符号右移
```


版本说明：
Impala 2.x+ : 基本数学函数
Impala 3.x+ : FMOD, 双曲函数，增强精度
Impala 4.x+ : 完整数学函数支持
注意：Impala 位运算使用函数形式（BITAND/BITOR/BITXOR/BITNOT）
而非运算符形式（&, |, ^, ~）
注意：SHIFTLEFT/SHIFTRIGHT/SHIFTRIGHTUNSIGNED 为 Impala 特有移位函数
注意：POSITIVE/NEGATIVE 是 Impala 特有的辅助函数
注意：LOG(x) 是自然对数（以 e 为底），等同于 LN(x)
限制：无 CBRT（立方根）函数
