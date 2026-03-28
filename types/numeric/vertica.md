# Vertica: 数值类型

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


整数
TINYINT / INT1:     1 字节，-128 ~ 127（Vertica 扩展）
SMALLINT / INT2:    2 字节，-32768 ~ 32767
INT / INTEGER / INT4: 4 字节，-2^31 ~ 2^31-1
BIGINT / INT8:      8 字节，-2^63 ~ 2^63-1
AUTO_INCREMENT:     自增整数

```sql
CREATE TABLE examples (
    id         AUTO_INCREMENT,
    small_val  SMALLINT,
    int_val    INT,
    big_val    BIGINT
);
```


浮点数
FLOAT / FLOAT4 / REAL:     4 字节，6 位精度（Vertica 内部为 FLOAT8）
DOUBLE PRECISION / FLOAT8: 8 字节，15 位精度
FLOAT(n):                  n <= 24 用 FLOAT, n >= 25 用 DOUBLE

定点数
NUMERIC(P, S) / DECIMAL(P, S): P 最大 1024，S 最大 P
NUMBER: NUMERIC 的别名
```sql
CREATE TABLE prices (
    price      NUMERIC(10, 2),            -- 精确到分
    value      DOUBLE PRECISION,          -- 浮点数
    rate       FLOAT                      -- 单精度
);
```


布尔
BOOLEAN / BOOL: TRUE / FALSE / NULL
```sql
CREATE TABLE t (
    active BOOLEAN DEFAULT TRUE
);
```


带编码的数值列
```sql
CREATE TABLE encoded_numbers (
    id         INT ENCODING DELTAVAL,     -- 适合递增数值
    value      DOUBLE PRECISION ENCODING AUTO,
    category   SMALLINT ENCODING RLE      -- 适合低基数
);
```


INTERVAL 类型
```sql
CREATE TABLE intervals (
    duration INTERVAL DAY TO SECOND
);
SELECT INTERVAL '3 days 4 hours 30 minutes';
```


类型转换
```sql
SELECT CAST('123' AS INT);
SELECT '123'::INT;                        -- 简写
SELECT TO_NUMBER('1,234.56', '9,999.99');
```


数学运算
```sql
SELECT 5 / 2;                            -- 整数除法 = 2
SELECT 5.0 / 2;                          -- 浮点除法 = 2.5
SELECT MOD(5, 2);                        -- 取模 = 1
SELECT POWER(2, 10);                     -- 幂运算 = 1024
SELECT SQRT(144);                        -- 平方根 = 12
```


数值函数
```sql
SELECT ABS(-5);
SELECT CEIL(1.3);
SELECT FLOOR(1.7);
SELECT ROUND(1.567, 2);
SELECT TRUNC(1.567, 2);
```


特殊值
```sql
SELECT 'NaN'::FLOAT;
SELECT 'Infinity'::FLOAT;
```


注意：Vertica 支持 AUTO_INCREMENT
注意：NUMERIC 精度最高 1024 位
注意：FLOAT 内部实际存储为 FLOAT8（双精度）
注意：列编码选择影响存储效率和查询性能
注意：支持 INTERVAL 类型
