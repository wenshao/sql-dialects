# DB2: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [IBM DB2 Documentation - MERGE](https://www.ibm.com/docs/en/db2/11.5?topic=statements-merge)
> - [IBM DB2 Documentation - Temporal Tables](https://www.ibm.com/docs/en/db2/11.5?topic=tables-temporal)
> - ============================================================
> - SCD Type 1: MERGE
> - ============================================================

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

## SCD Type 2: 两步 MERGE

```sql
MERGE INTO dim_customer AS t USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = 1
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city)
    THEN UPDATE SET t.expiry_date = CURRENT DATE - 1 DAY, t.is_current = 0;

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT DATE, '9999-12-31', 1
FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = 1);
```

## DB2 时态表（System-period temporal）

```sql
CREATE TABLE dim_customer_temporal (
    customer_id VARCHAR(20) NOT NULL PRIMARY KEY,
    name        VARCHAR(100),
    city        VARCHAR(100),
    sys_start   TIMESTAMP(12) GENERATED ALWAYS AS ROW BEGIN NOT NULL,
    sys_end     TIMESTAMP(12) GENERATED ALWAYS AS ROW END NOT NULL,
    ts_id       TIMESTAMP(12) GENERATED ALWAYS AS TRANSACTION START ID,
    PERIOD SYSTEM_TIME (sys_start, sys_end)
);
CREATE TABLE dim_customer_history LIKE dim_customer_temporal;
ALTER TABLE dim_customer_temporal ADD VERSIONING USE HISTORY TABLE dim_customer_history;
```

## 查询时态数据

```sql
SELECT * FROM dim_customer_temporal FOR SYSTEM_TIME AS OF '2024-06-01-00.00.00';
```
