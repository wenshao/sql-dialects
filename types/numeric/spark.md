# Spark SQL: 数值类型 (Numeric Types)

> 参考资料:
> - [1] Spark SQL - Data Types
>   https://spark.apache.org/docs/latest/sql-ref-datatypes.html


## 1. 整数类型

TINYINT / BYTE:   1 byte,  -128 ~ 127
SMALLINT / SHORT: 2 bytes, -32,768 ~ 32,767
INT / INTEGER:    4 bytes, -2^31 ~ 2^31-1
BIGINT / LONG:    8 bytes, -2^63 ~ 2^63-1


```sql
CREATE TABLE examples (
    tiny_val  TINYINT,
    small_val SMALLINT,
    int_val   INT,
    big_val   BIGINT
) USING PARQUET;

```

 无 UNSIGNED 整数类型（Spark 基于 JVM，使用 Java 的有符号整数）
 无 HUGEINT / 128-bit 整数（对比: DuckDB 支持 HUGEINT）

## 2. 浮点类型

FLOAT / REAL:   4 bytes, ~6 位有效数字（IEEE 754 单精度）
DOUBLE:         8 bytes, ~15 位有效数字（IEEE 754 双精度）


```sql
CREATE TABLE measurements (
    temperature FLOAT,
    precise_val DOUBLE
) USING PARQUET;

```

特殊值

```sql
SELECT DOUBLE('NaN');                                    -- Not a Number
SELECT DOUBLE('Infinity');                               -- 正无穷
SELECT DOUBLE('-Infinity');                              -- 负无穷

```

 浮点精度陷阱:
   SELECT 0.1 + 0.2 = 0.3;  -- false! (浮点精度问题)
   金融计算必须使用 DECIMAL

## 3. DECIMAL (精确数值)

DECIMAL(p, s) / DEC(p, s) / NUMERIC(p, s)
p: 总位数（最大 38），s: 小数位数


```sql
CREATE TABLE prices (
    price   DECIMAL(10, 2),                      -- 最大 99999999.99
    rate    DECIMAL(5, 4),                       -- 最大 9.9999
    any_num DECIMAL                              -- 默认 DECIMAL(10, 0)
) USING PARQUET;

```

 DECIMAL 的精度规则:
   加法: DECIMAL(p1,s1) + DECIMAL(p2,s2) -> DECIMAL(max(s1,s2)+max(p1-s1,p2-s2)+1, max(s1,s2))
   乘法: DECIMAL(p1,s1) * DECIMAL(p2,s2) -> DECIMAL(p1+p2+1, s1+s2)
   除法: 复杂规则，可能导致精度损失

 对比:
   MySQL:      DECIMAL(65, 30) — 最大精度 65 位
   PostgreSQL: NUMERIC(1000, ...) — 任意精度
   Oracle:     NUMBER — 最大 38 位（与 Spark 相同）
   BigQuery:   NUMERIC(38, 9) / BIGNUMERIC(76, 38)
   Spark:      DECIMAL(38, *) — 最大 38 位（受 JVM long 限制）

## 4. BOOLEAN

```sql
CREATE TABLE flags (active BOOLEAN) USING PARQUET;
```

 值: TRUE / FALSE / NULL

## 5. 数值字面量（Spark 特色后缀语法）

```sql
SELECT 42;                                               -- INT
SELECT 42L;                                              -- BIGINT (L 后缀)
SELECT 42S;                                              -- SMALLINT (S 后缀)
SELECT 42Y;                                              -- TINYINT (Y 后缀)
SELECT 3.14;                                             -- DECIMAL
SELECT 3.14D;                                            -- DOUBLE (D 后缀)
SELECT 3.14F;                                            -- FLOAT (F 后缀)
SELECT 3.14BD;                                           -- DECIMAL (BD 后缀, 3.0+)
SELECT 1e10;                                             -- DOUBLE (科学计数法)
SELECT 0xFF;                                             -- INT (十六进制)

```

 数值后缀是 Spark/Scala 特色语法:
   大多数 SQL 引擎不支持 L/S/Y/D/F/BD 后缀
   迁移到其他引擎时需要改为 CAST

## 6. 类型转换与安全转换

```sql
SELECT CAST('123' AS INT);
SELECT INT('123');                                       -- 函数式（Spark 特色）
SELECT DOUBLE('3.14');
SELECT TRY_CAST('abc' AS INT);                           -- NULL (3.0+)

```

## 7. 类型提升规则

 TINYINT -> SMALLINT -> INT -> BIGINT -> DECIMAL -> FLOAT -> DOUBLE
 混合运算自动向上提升:
   INT + BIGINT -> BIGINT
   INT + DOUBLE -> DOUBLE
   DECIMAL + DOUBLE -> DOUBLE (注意: DECIMAL 到 DOUBLE 可能损失精度!)

## 8. 溢出处理

ANSI=false (3.x 默认): 溢出静默回绕
SELECT CAST(300 AS TINYINT);  -- 44 (300 mod 256 = 44)
ANSI=true (4.0 默认): 溢出抛出异常
SELECT CAST(300 AS TINYINT);  -- ARITHMETIC_OVERFLOW 异常

try_* 安全函数:

```sql
SELECT try_add(2147483647, 1);                           -- NULL (不抛异常)
SELECT try_multiply(2147483647, 2);                      -- NULL

```

自增替代:

```sql
SELECT monotonically_increasing_id() AS id, username FROM users;

```

## 9. 版本演进

Spark 2.0: 基本数值类型（继承 Hive/JVM 类型体系）
Spark 3.0: ANSI 模式溢出检测, BD 后缀, try_* 函数
Spark 3.4: 类型提升规则改进
Spark 4.0: ANSI 模式默认开启

限制:
无 UNSIGNED 整数类型
DECIMAL 最大精度 38 位（受 JVM 限制）
无 MONEY 类型（用 DECIMAL 处理货币）
无 HUGEINT（128-bit 整数）
数值后缀（L/S/Y/D/F/BD）是 Spark 特有的非标准语法
JVM 浮点: 使用 IEEE 754 标准，与 C/C++ 引擎行为一致

