# ksqlDB: 条件函数

## CASE WHEN

```sql
SELECT event_id,
    CASE
        WHEN amount > 1000 THEN 'high'
        WHEN amount > 100 THEN 'medium'
        ELSE 'low'
    END AS priority
FROM orders EMIT CHANGES;
```

## 简单 CASE

```sql
SELECT event_id,
    CASE event_type
        WHEN 'click' THEN 1
        WHEN 'view' THEN 2
        ELSE 0
    END AS type_code
FROM events EMIT CHANGES;
```

## IFNULL（NULL 替换）

```sql
SELECT IFNULL(username, 'unknown') FROM events EMIT CHANGES;
```

## COALESCE

```sql
SELECT COALESCE(phone, email, 'N/A') FROM events EMIT CHANGES;
```

## CAST 类型转换

```sql
SELECT CAST('123' AS INT) FROM events EMIT CHANGES;
SELECT CAST(amount AS VARCHAR) FROM orders EMIT CHANGES;
SELECT CAST('3.14' AS DOUBLE) FROM events EMIT CHANGES;
```

## 布尔表达式

```sql
SELECT event_id,
    amount > 1000 AS is_high_value
FROM orders EMIT CHANGES;
```

## 条件过滤

```sql
SELECT * FROM orders WHERE amount > 100 AND product IS NOT NULL EMIT CHANGES;
```

注意：支持 CASE WHEN 和 COALESCE
注意：IFNULL 是 COALESCE 的两参数简化版
注意：不支持 NULLIF
注意：不支持 GREATEST / LEAST
注意：不支持 DECODE
注意：不支持 NVL
