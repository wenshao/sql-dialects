# Firebird: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [Firebird Documentation - UPDATE OR INSERT](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html)
> - [Firebird Documentation - MERGE (Firebird 3.0+)](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html)


## SCD Type 1: MERGE（Firebird 3.0+）

```sql
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = 1
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city)
    THEN UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier);
```

## SCD Type 1: UPDATE OR INSERT（Firebird 特色语法）

```sql
UPDATE OR INSERT INTO dim_customer (customer_id, name, city, tier)
VALUES ('C001', 'Alice', 'Shenzhen', 'Gold')
MATCHING (customer_id);
```

## SCD Type 2: UPDATE + INSERT

```sql
UPDATE dim_customer t SET t.expiry_date = CURRENT_DATE - 1, t.is_current = 0
WHERE t.is_current = 1
  AND EXISTS (SELECT 1 FROM stg_customer s WHERE s.customer_id = t.customer_id
              AND (s.name <> t.name OR s.city <> t.city));

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', 1
FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = 1);
```
