# ksqlDB: Math Functions

> 参考资料:
> - [ksqlDB Function Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/scalar-functions/)
> - ============================================================
> - 基本数学函数
> - ============================================================

```sql
SELECT ABS(-42);                          -- 42
SELECT CEIL(4.3);                         -- 5
SELECT FLOOR(4.7);                        -- 4
SELECT ROUND(3.14159);                    -- 3            (仅整数舍入)
```

## 幂、根、指数、对数

```sql
SELECT SQRT(144);                         -- 12
SELECT EXP(1);                            -- 2.718281828...
SELECT LN(EXP(1));                        -- 1.0
```

## 符号和随机数

```sql
SELECT SIGN(-42);                         -- -1
SELECT SIGN(0);                           -- 0
SELECT SIGN(42);                          -- 1
SELECT RANDOM();                          -- 0.0 到 1.0 之间的随机数
```

## GREATEST / LEAST (通过 CASE 模拟)

## ksqlDB 不支持 GREATEST/LEAST，需要用 CASE 表达式:

SELECT CASE WHEN a > b THEN a ELSE b END AS max_val FROM stream;

## 流处理中的数学应用示例

CREATE STREAM sensor_readings (
sensor_id VARCHAR KEY,
temperature DOUBLE,
humidity DOUBLE
) WITH (KAFKA_TOPIC='readings', VALUE_FORMAT='JSON');
流处理中使用数学函数
SELECT sensor_id,
ABS(temperature) AS abs_temp,
ROUND(temperature) AS rounded_temp,
CEIL(humidity) AS ceil_humidity,
SQRT(temperature * temperature + humidity * humidity) AS magnitude
FROM sensor_readings
EMIT CHANGES;
注意：ksqlDB 数学函数非常有限，面向流处理场景
注意：ROUND 仅支持整数舍入，不支持指定小数位
限制：无三角函数（SIN, COS, TAN 等）
限制：无 POWER, LOG, LOG2, LOG10, MOD 等
限制：无 PI() 常量
限制：无 GREATEST/LEAST（需 CASE 模拟）
限制：无位运算
限制：无 DEGREES/RADIANS 转换
