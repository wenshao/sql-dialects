# TDengine: 数值类型

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)
> - 整数
> - TINYINT: 1 字节，-128 ~ 127
> - SMALLINT: 2 字节，-32768 ~ 32767
> - INT: 4 字节，-2^31 ~ 2^31-1
> - BIGINT: 8 字节，-2^63 ~ 2^63-1
> - 无符号整数（3.0+）
> - TINYINT UNSIGNED: 1 字节，0 ~ 255
> - SMALLINT UNSIGNED: 2 字节，0 ~ 65535
> - INT UNSIGNED: 4 字节，0 ~ 2^32-1
> - BIGINT UNSIGNED: 8 字节，0 ~ 2^64-1

```sql
CREATE STABLE sensors (
    ts          TIMESTAMP,
    v_tinyint   TINYINT,
    v_smallint  SMALLINT,
    v_int       INT,
    v_bigint    BIGINT,
    v_utinyint  TINYINT UNSIGNED,
    v_usmallint SMALLINT UNSIGNED,
    v_uint      INT UNSIGNED,
    v_ubigint   BIGINT UNSIGNED
) TAGS (
    device_id   INT,
    group_id    SMALLINT
);
```

浮点数
FLOAT: 4 字节，6~7 位有效数字
DOUBLE: 8 字节，15~16 位有效数字

```sql
CREATE STABLE measurements (
    ts          TIMESTAMP,
    temperature FLOAT,
    pressure    DOUBLE
) TAGS (
    sensor_id   INT
);
```

## 布尔

BOOL: 1 字节，TRUE/FALSE

```sql
CREATE STABLE status (
    ts     TIMESTAMP,
    active BOOL
) TAGS (
    id     INT
);
```

## 不支持的数值类型


不支持 DECIMAL / NUMERIC（定点数）
不支持 SERIAL / AUTO_INCREMENT
不支持 MONEY 类型
精确计算需要在应用层处理或使用 BIGINT 存储（乘以倍数）
例如：金额用分（cents）存储为 BIGINT

## 数学函数


```sql
SELECT ABS(-5);
SELECT CEIL(3.14);               -- 4
SELECT FLOOR(3.14);              -- 3
SELECT ROUND(3.14159);           -- 3
SELECT SQRT(144);                -- 12
SELECT POW(2, 10);               -- 1024
SELECT LOG(100);                 -- ~4.605 (natural log)
SELECT MOD(10, 3);               -- 1
```

注意：TDengine 支持有符号和无符号整数
注意：不支持 DECIMAL/NUMERIC 精确数值类型
注意：浮点数使用 FLOAT 或 DOUBLE
注意：标签列也支持数值类型
注意：无自增类型，时间戳是唯一标识
