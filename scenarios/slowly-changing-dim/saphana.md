# SAP HANA: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [SAP HANA SQL Reference - MERGE / UPSERT](https://help.sap.com/docs/HANA_CLOUD/c1d3f60099654ecfb3fe36ac93c121bb/)
> - [SAP HANA - System-Versioned Tables](https://help.sap.com/docs/HANA_CLOUD/c1d3f60099654ecfb3fe36ac93c121bb/)


## SCD Type 1: UPSERT / MERGE

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

## SCD Type 2: 两步操作

```sql
MERGE INTO dim_customer AS t USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = 1
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city)
    THEN UPDATE SET t.expiry_date = ADD_DAYS(CURRENT_DATE, -1), t.is_current = 0;

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', 1
FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = 1);
```

## SAP HANA 系统版本化表

CREATE TABLE dim_temporal (
customer_id NVARCHAR(20) PRIMARY KEY,
name NVARCHAR(100),
valid_from TIMESTAMP NOT NULL GENERATED ALWAYS AS ROW START,
valid_to TIMESTAMP NOT NULL GENERATED ALWAYS AS ROW END,
PERIOD FOR SYSTEM_TIME (valid_from, valid_to)
) WITH SYSTEM VERSIONING;
