# Redshift: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [Amazon Redshift - MERGE (预览)](https://docs.aws.amazon.com/redshift/latest/dg/r_MERGE.html)
> - [Amazon Redshift - UPDATE with JOIN](https://docs.aws.amazon.com/redshift/latest/dg/r_UPDATE.html)


## SCD Type 1: UPDATE + INSERT（Redshift 传统方式）

步骤 1: 更新已存在的记录
```sql
UPDATE dim_customer
SET    name = s.name, city = s.city, tier = s.tier
FROM   stg_customer s
WHERE  dim_customer.customer_id = s.customer_id
  AND  dim_customer.is_current = TRUE;
```


步骤 2: 插入新记录
```sql
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT s.customer_id, s.name, s.city, s.tier
FROM   stg_customer s
LEFT JOIN dim_customer d ON d.customer_id = s.customer_id
WHERE  d.customer_id IS NULL;
```


## SCD Type 1: MERGE（Redshift 新版支持）

```sql
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED THEN UPDATE SET name = s.name, city = s.city, tier = s.tier
WHEN NOT MATCHED THEN INSERT VALUES (DEFAULT, s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', TRUE);
```


## SCD Type 2: DELETE + INSERT 模式（Redshift 推荐）

```sql
BEGIN;
-- 标记旧版本
UPDATE dim_customer SET expiry_date = CURRENT_DATE - 1, is_current = FALSE
FROM stg_customer s
WHERE dim_customer.customer_id = s.customer_id AND dim_customer.is_current = TRUE
  AND (dim_customer.name <> s.name OR dim_customer.city <> s.city);
```


插入新版本
```sql
INSERT INTO dim_customer SELECT DEFAULT, s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', TRUE
FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = TRUE);
COMMIT;
```
