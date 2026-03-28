# ksqlDB: 数值类型

> 参考资料:
> - [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - [ksqlDB API Reference](https://docs.ksqldb.io/en/latest/developer-guide/api/)


INT / INTEGER: 4 字节，-2^31 ~ 2^31-1
BIGINT: 8 字节，-2^63 ~ 2^63-1
DOUBLE: 8 字节浮点数
DECIMAL(p,s): 精确数值

```sql
CREATE STREAM orders (
    order_id   INT KEY,
    user_id    INT,
    quantity   INT,
    amount     DOUBLE,
    tax        DECIMAL(10,2),
    total      BIGINT
) WITH (
    KAFKA_TOPIC = 'orders_topic',
    VALUE_FORMAT = 'JSON'
);
```

## BOOLEAN

```sql
CREATE TABLE settings (
    key     VARCHAR PRIMARY KEY,
    enabled BOOLEAN
) WITH (
    KAFKA_TOPIC = 'settings_topic',
    VALUE_FORMAT = 'JSON'
);
```

## 类型转换


```sql
SELECT CAST('123' AS INT) FROM orders EMIT CHANGES;
SELECT CAST(123 AS DOUBLE) FROM orders EMIT CHANGES;
SELECT CAST(amount AS DECIMAL(10,2)) FROM orders EMIT CHANGES;
SELECT CAST(amount AS VARCHAR) FROM orders EMIT CHANGES;
```

## 算术运算


```sql
SELECT order_id,
    amount * quantity AS subtotal,
    amount * quantity * 0.1 AS tax_amount,
    amount * quantity * 1.1 AS total
FROM orders EMIT CHANGES;
```

## 聚合运算

```sql
CREATE TABLE order_stats AS
SELECT user_id,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS avg_amount,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount
FROM orders
GROUP BY user_id
EMIT CHANGES;
```

## 数学函数


```sql
SELECT ABS(-5) FROM orders EMIT CHANGES;
SELECT CEIL(3.14) FROM orders EMIT CHANGES;
SELECT FLOOR(3.14) FROM orders EMIT CHANGES;
SELECT ROUND(3.14159) FROM orders EMIT CHANGES;
```

## 不支持的数值类型


不支持 SMALLINT / TINYINT
不支持 FLOAT（使用 DOUBLE）
不支持 NUMERIC（使用 DECIMAL）
不支持 SERIAL / AUTO_INCREMENT
注意：INT 和 BIGINT 是主要的整数类型
注意：DOUBLE 是唯一的浮点类型
注意：DECIMAL 用于精确数值
注意：不支持 NaN 和 Infinity 特殊值
