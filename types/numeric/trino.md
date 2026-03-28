# Trino: 数值类型

> 参考资料:
> - [Trino - Data Types](https://trino.io/docs/current/language/types.html)
> - [Trino - Mathematical Functions](https://trino.io/docs/current/functions/math.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

```sql
CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    int_val    INTEGER,
    big_val    BIGINT
);

```

浮点数
REAL:             4 字节，单精度 IEEE 754
DOUBLE:           8 字节，双精度 IEEE 754
```sql
CREATE TABLE measurements (
    float_val  REAL,                      -- 单精度
    double_val DOUBLE                     -- 双精度
);

```

定点数
DECIMAL(p, s): p 最大 38，s 最大 p
```sql
CREATE TABLE prices (
    price      DECIMAL(10, 2),            -- 精确到分
    rate       DECIMAL(5, 4)              -- 如 1.2345
);

```

布尔
```sql
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);
```

值: TRUE / FALSE / NULL

类型转换
```sql
SELECT CAST('123' AS INTEGER);
SELECT TRY_CAST('abc' AS INTEGER);        -- 安全转换，失败返回 NULL
SELECT TYPEOF(123);                       -- 返回类型名

```

特殊数值
```sql
SELECT nan();                             -- NaN
SELECT infinity();                        -- 正无穷
SELECT -infinity();                       -- 负无穷
SELECT is_nan(nan());                     -- true
SELECT is_finite(1.0);                    -- true
SELECT is_infinite(infinity());           -- true

```

数学函数
```sql
SELECT ABS(-5);
SELECT MOD(10, 3);                        -- 1
SELECT ROUND(3.14159, 2);                 -- 3.14
SELECT TRUNCATE(3.14159, 2);              -- 3.14
SELECT CEIL(3.14);                        -- 4
SELECT FLOOR(3.14);                       -- 3
SELECT POWER(2, 10);                      -- 1024

```

**注意:** 没有 UNSIGNED 类型
**注意:** 没有自增类型（取决于 Connector）
**注意:** 没有 BIT 类型
**注意:** 整数溢出会报错
**注意:** 类型命名遵循 SQL 标准
