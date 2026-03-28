# Flink SQL: JOIN 连接查询

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Flink SQL - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
> - [Flink SQL - Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

```

LEFT JOIN
```sql
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;

```

RIGHT JOIN
```sql
SELECT u.username, o.amount
FROM users u
RIGHT JOIN orders o ON u.id = o.user_id;

```

FULL OUTER JOIN
```sql
SELECT u.username, o.amount
FROM users u
FULL OUTER JOIN orders o ON u.id = o.user_id;

```

CROSS JOIN
```sql
SELECT u.username, r.role_name
FROM users u
CROSS JOIN roles r;

```

SEMI JOIN
```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

ANTI JOIN
```sql
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

Temporal Join (join with a versioned/temporal table)
Lookup the dimension table as of the event's processing time
```sql
SELECT o.order_id, o.amount, u.username
FROM orders AS o
JOIN users FOR SYSTEM_TIME AS OF o.proc_time AS u
ON o.user_id = u.id;

```

Temporal join with event time (versioned table)
```sql
CREATE TABLE product_prices (
    product_id BIGINT,
    price      DECIMAL(10,2),
    update_time TIMESTAMP(3),
    WATERMARK FOR update_time AS update_time - INTERVAL '5' SECOND,
    PRIMARY KEY (product_id) NOT ENFORCED
) WITH (
    'connector' = 'kafka',
    'topic' = 'product-prices',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

SELECT o.order_id, o.product_id, p.price
FROM orders AS o
JOIN product_prices FOR SYSTEM_TIME AS OF o.order_time AS p
ON o.product_id = p.product_id;

```

Lookup Join (enrichment from external database)
```sql
CREATE TABLE dim_users (
    id       BIGINT,
    username STRING,
    email    STRING,
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'users',
    'lookup.cache.max-rows' = '5000',
    'lookup.cache.ttl' = '10min'
);

SELECT e.*, d.username, d.email
FROM events AS e
JOIN dim_users FOR SYSTEM_TIME AS OF e.proc_time AS d
ON e.user_id = d.id;

```

Lookup join with retry hints (Flink 1.16+)
```sql
SELECT /*+ LOOKUP('table'='dim_users', 'retry-predicate'='lookup_miss',
           'retry-strategy'='fixed_delay', 'fixed-delay'='10s', 'max-attempts'='3') */
    e.*, d.username
FROM events AS e
JOIN dim_users FOR SYSTEM_TIME AS OF e.proc_time AS d
ON e.user_id = d.id;

```

Interval Join (join events within a time window)
```sql
SELECT o.order_id, p.payment_id
FROM orders o
JOIN payments p
ON o.order_id = p.order_id
AND p.pay_time BETWEEN o.order_time AND o.order_time + INTERVAL '1' HOUR;

```

Interval join with more complex conditions
```sql
SELECT a.user_id, a.event_type, b.event_type
FROM click_events a
JOIN purchase_events b
ON a.user_id = b.user_id
AND b.event_time BETWEEN a.event_time AND a.event_time + INTERVAL '30' MINUTE;

```

Regular join with state TTL hint (Flink 1.17+)
Prevents unbounded state growth in streaming joins
```sql
SELECT /*+ STATE_TTL('u' = '1d', 'o' = '12h') */
    u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

```

CROSS JOIN with UNNEST (explode arrays)
```sql
SELECT user_id, tag
FROM user_events
CROSS JOIN UNNEST(tags) AS t(tag);

```

Note: Regular joins in streaming mode keep ALL state; use STATE_TTL to limit
Note: Temporal joins (FOR SYSTEM_TIME AS OF) are essential for stream enrichment
Note: Lookup joins query external systems in real-time (JDBC, HBase, etc.)
Note: Interval joins limit state by time bounds (efficient for streams)
Note: No LATERAL JOIN (use CROSS JOIN UNNEST or temporal joins)
Note: No NATURAL JOIN
Note: No ASOF JOIN (use interval joins or temporal joins)
Note: Join ordering and state management are critical for performance
