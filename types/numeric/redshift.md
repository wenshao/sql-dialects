# Redshift: 数值类型

> 参考资料:
> - [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html)
> - [Redshift SQL Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html)
> - [Redshift Data Types](https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html)


SMALLINT: 2 字节，-32768 ~ 32767（别名 INT2）
INTEGER: 4 字节，-2^31 ~ 2^31-1（别名 INT, INT4）
BIGINT: 8 字节，-2^63 ~ 2^63-1（别名 INT8）

```sql
CREATE TABLE examples (
    small_val  SMALLINT,                     -- 2 字节整数
    int_val    INTEGER,                      -- 4 字节整数
    big_val    BIGINT                        -- 8 字节整数
);
```


定点数
DECIMAL(p, s) / NUMERIC(p, s): 最大精度 38
```sql
CREATE TABLE prices (
    price      DECIMAL(10, 2),               -- 10 位总精度，2 位小数
    rate       NUMERIC(5, 4)                 -- 5 位总精度，4 位小数
);
-- DECIMAL 和 NUMERIC 完全等价
```


浮点数
REAL / FLOAT4: 4 字节单精度 IEEE 754
DOUBLE PRECISION / FLOAT8 / FLOAT: 8 字节双精度 IEEE 754
```sql
CREATE TABLE measurements (
    value      REAL,                         -- 4 字节单精度
    result     DOUBLE PRECISION              -- 8 字节双精度
);
```


布尔
```sql
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);
```

值: TRUE / FALSE / NULL
别名: BOOL

自增
```sql
CREATE TABLE t (
    id BIGINT IDENTITY(1, 1)                 -- 起始值 1，步长 1
);
-- 或
CREATE TABLE t (
    id BIGINT IDENTITY(0, 2)                 -- 起始值 0，步长 2
);
```


DEFAULT IDENTITY（允许手动指定值）
```sql
CREATE TABLE t (
    id BIGINT DEFAULT IDENTITY(1, 1)
);
```


类型转换
```sql
SELECT CAST('123' AS INTEGER);
SELECT CAST('123.45' AS DECIMAL(10, 2));
SELECT '123'::INTEGER;                       -- :: 转换语法
SELECT 123::VARCHAR;
```


数值函数
```sql
SELECT ABS(-5);                              -- 5
SELECT CEIL(3.2);                            -- 4
SELECT FLOOR(3.8);                           -- 3
SELECT ROUND(3.567, 2);                      -- 3.57
SELECT TRUNC(3.567, 2);                      -- 3.56
SELECT MOD(10, 3);                           -- 1
SELECT POWER(2, 10);                         -- 1024
SELECT SQRT(144);                            -- 12
```


近似计数（HLL，高基数计数利器）
```sql
SELECT APPROXIMATE COUNT(DISTINCT user_id) FROM events;
```

使用 HyperLogLog 算法，比 COUNT(DISTINCT) 快得多
误差约 2%

HLL 函数（显式使用）
```sql
SELECT HLL(user_id) FROM events;
SELECT HLL_COMBINE(hll_sketch) FROM daily_sketches;
SELECT HLL_CARDINALITY(HLL(user_id)) FROM events;
```


注意：SMALLINT / INTEGER / BIGINT 有真正的存储大小区别
注意：选择合适的整数类型可以节省存储和提升查询性能
注意：没有 TINYINT 类型
注意：没有 UNSIGNED 类型
注意：IDENTITY 是唯一的自增方式（没有 SERIAL / SEQUENCE）
注意：APPROXIMATE COUNT(DISTINCT) 是 Redshift 特有的高效近似计数
注意：DECIMAL 最大精度 38 位
