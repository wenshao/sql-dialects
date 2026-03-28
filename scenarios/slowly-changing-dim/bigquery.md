# BigQuery: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [1] BigQuery SQL Reference - MERGE
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#merge_statement


## 1. SCD Type 1: MERGE 直接覆盖（最简洁的方案）


```sql
MERGE INTO myproject.mydataset.dim_customers AS t
USING myproject.mydataset.stg_customers AS s
ON t.customer_id = s.customer_id
WHEN MATCHED THEN
    UPDATE SET
        name = s.name,
        address = s.address,
        city = s.city,
        updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, address, city, updated_at)
    VALUES (s.customer_id, s.name, s.address, s.city, CURRENT_TIMESTAMP());

```

 MERGE 是 BigQuery 实现 SCD 的最佳工具:
 单个语句完成 UPDATE（已存在）+ INSERT（不存在）
 原子操作（消耗 1 次 DML 配额）

## 2. SCD Type 2: MERGE + 条件分支


```sql
CREATE TABLE myproject.mydataset.dim_customers_v2 (
    surrogate_key STRING NOT NULL DEFAULT GENERATE_UUID(),
    customer_id   INT64 NOT NULL,
    name          STRING,
    address       STRING,
    valid_from    TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    valid_to      TIMESTAMP DEFAULT TIMESTAMP '9999-12-31',
    is_current    BOOL DEFAULT TRUE
);

```

SCD2 MERGE（检测变更 + 关闭旧记录 + 插入新记录）:

```sql
MERGE INTO myproject.mydataset.dim_customers_v2 AS t
USING myproject.mydataset.stg_customers AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
```

有变更时: 关闭旧记录

```sql
WHEN MATCHED AND (t.name != s.name OR t.address != s.address) THEN
    UPDATE SET valid_to = CURRENT_TIMESTAMP(), is_current = FALSE
```

无变更时: 不做任何操作

```sql
WHEN MATCHED THEN
    UPDATE SET name = t.name  -- no-op（保持不变）
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, address)
    VALUES (s.customer_id, s.name, s.address);

```

第二步: 插入新版本行（MERGE 只能对 target 的每行做一个操作）

```sql
INSERT INTO myproject.mydataset.dim_customers_v2 (customer_id, name, address)
SELECT s.customer_id, s.name, s.address
FROM myproject.mydataset.stg_customers s
JOIN myproject.mydataset.dim_customers_v2 t
  ON s.customer_id = t.customer_id
WHERE t.valid_to = CURRENT_TIMESTAMP()   -- 刚被关闭的记录
  AND t.is_current = FALSE;

```

## 3. 时间旅行辅助 SCD 调试


BigQuery 的时间旅行可以查看 SCD 变更前的状态:

```sql
SELECT * FROM myproject.mydataset.dim_customers_v2
FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
WHERE customer_id = 1;

```

## 4. 对比与引擎开发者启示

BigQuery SCD 的实现:
- **Type 1**: MERGE（单语句，最简洁）
- **Type 2**: MERGE + INSERT（两步，因为 MERGE 不能对一行做两个操作）
- **时间旅行**: 辅助 SCD 调试和恢复

对比:
- **SQLite**: ON CONFLICT DO UPDATE (Type1) + 事务 (Type2)
- **ClickHouse**: ReplacingMergeTree (Type1) + 版本化表 (Type2)
- **PostgreSQL**: MERGE (15+) 或 CTE + UPDATE + INSERT

对引擎开发者的启示:
MERGE 是 SCD 实现的最佳语法选择。
但 SCD Type 2 需要"对一行做两个操作"（关闭旧 + 插入新），
- MERGE 不支持这种模式 → 需要两步操作。
如果设计引擎，考虑在 MERGE 中支持"一行触发多个操作"的语义。
