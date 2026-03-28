# Spark SQL: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [1] Delta Lake - MERGE INTO
>   https://docs.delta.io/latest/delta-update.html#upsert-into-a-table-using-merge
> - [2] Apache Iceberg - MERGE INTO
>   https://iceberg.apache.org/docs/latest/spark-writes/#merge-into


## 1. SCD Type 1: 覆盖更新（Delta Lake MERGE）


SCD1: 新数据直接覆盖旧数据，不保留历史

```sql
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier);

```

 SCD1 的 Delta Lake 优势:
   即使覆盖了旧值，通过 Time Travel 仍可以查看历史状态
   SELECT * FROM dim_customer VERSION AS OF 5;

## 2. SCD Type 2: 保留完整历史（两步 MERGE）


SCD2 表结构:
dim_customer(customer_id, name, city, tier,
effective_date DATE, expiry_date DATE, is_current BOOLEAN)

步骤 1: 识别变更记录

```sql
CREATE OR REPLACE TEMPORARY VIEW staged_updates AS
```

已存在但发生变化的记录

```sql
SELECT s.customer_id, s.name, s.city, s.tier, TRUE AS is_new_version
FROM stg_customer s
JOIN dim_customer t ON s.customer_id = t.customer_id AND t.is_current = TRUE
WHERE s.name <> t.name OR s.city <> t.city OR s.tier <> t.tier
UNION ALL
```

全新记录

```sql
SELECT customer_id, name, city, tier, FALSE
FROM stg_customer
WHERE customer_id NOT IN (SELECT customer_id FROM dim_customer);

```

步骤 2: MERGE 关闭旧版本 + 插入新版本

```sql
MERGE INTO dim_customer AS t
USING (
    -- 新版本记录
    SELECT customer_id, name, city, tier,
           current_date() AS effective_date,
           DATE '9999-12-31' AS expiry_date,
           TRUE AS is_current,
           TRUE AS is_new_version
    FROM staged_updates WHERE is_new_version = TRUE
    UNION ALL
    -- 新记录
    SELECT customer_id, name, city, tier,
           current_date(), DATE '9999-12-31', TRUE, FALSE
    FROM staged_updates WHERE is_new_version = FALSE
) AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE AND s.is_new_version = TRUE
WHEN MATCHED THEN
    UPDATE SET t.expiry_date = DATE_SUB(current_date(), 1), t.is_current = FALSE
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, city, tier, effective_date, expiry_date, is_current)
    VALUES (s.customer_id, s.name, s.city, s.tier, s.effective_date, s.expiry_date, TRUE);

```

 SCD2 的设计挑战:
   传统数据库: 单次 MERGE 可以同时关闭旧行+插入新行
   Spark/Delta: MERGE 不能对同一行同时 UPDATE 和 INSERT（需要两步）
   Databricks: 通过 WHEN NOT MATCHED BY SOURCE 简化了部分场景

## 3. SCD Type 2 简化: Delta Lake Time Travel 替代


 Delta Lake 的 Time Travel 天然提供了"表级 SCD":
   不需要 effective_date/expiry_date/is_current 列
   直接查询任意历史时间点的数据
 SELECT * FROM dim_customer VERSION AS OF 5;
 SELECT * FROM dim_customer TIMESTAMP AS OF '2024-06-01';

 这是否能替代 SCD2？
   可以: 如果只需要"在某个时间点查看表的快照"
   不能: 如果需要"追踪单个实体的变化历史"（如一个客户从 A 市搬到 B 市的时间线）
   SCD2 提供行级历史，Time Travel 提供表级历史

## 4. SCD Type 3: 保留有限历史（前值列）


SCD3 在表中添加"前值"列:
dim_customer(customer_id, city, prev_city, city_change_date)


```sql
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id
WHEN MATCHED AND t.city <> s.city THEN
    UPDATE SET
        t.prev_city = t.city,
        t.city = s.city,
        t.city_change_date = current_date()
WHEN NOT MATCHED THEN
    INSERT (customer_id, city, prev_city, city_change_date)
    VALUES (s.customer_id, s.city, NULL, NULL);

```

## 5. 对比各引擎的 SCD 实现


 Oracle:   MERGE INTO 最成熟，单次 MERGE 可同时更新+插入
 SQL Server: MERGE + OUTPUT 可以捕获变更行
 PostgreSQL: INSERT ... ON CONFLICT + 触发器 或 MERGE (15+)
 Spark:     MERGE INTO (Delta Lake)，SCD2 需要两步操作
 Hive:      Hive ACID + MERGE (3.0+)，性能较差

## 6. 版本演进

Delta 0.3: MERGE INTO 基本支持
Delta 1.0: MERGE + Time Travel (SCD 替代方案)
Spark 3.4: WHEN NOT MATCHED BY SOURCE (简化部分 SCD 场景)
Iceberg:   MERGE INTO 支持 (Spark 3.0+)

限制:
MERGE 不能对同一行同时 UPDATE 和 INSERT（SCD2 需要两步）
需要 Delta Lake 或 Iceberg（原生 Spark 表无法实现 SCD）
大维度表的 SCD2 MERGE 可能涉及大量文件重写

