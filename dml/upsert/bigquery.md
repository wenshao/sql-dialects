# BigQuery: UPSERT（通过 MERGE 实现）

> 参考资料:
> - [1] BigQuery SQL Reference - MERGE
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#merge_statement
> - [2] BigQuery Documentation - DML Best Practices
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax


## 1. BigQuery 没有专用 UPSERT 语法


 BigQuery 不支持:
   INSERT ... ON CONFLICT（SQLite/PostgreSQL）
   INSERT ... ON DUPLICATE KEY UPDATE（MySQL）
   REPLACE INTO（MySQL/SQLite）

 原因: BigQuery 没有 UNIQUE 约束，因此不存在"冲突"的概念。
 PRIMARY KEY 是 NOT ENFORCED 的，可以有重复值。
 → 没有冲突检测机制 → 没有冲突处理语法

 替代方案: MERGE 语句（SQL:2003 标准）

## 2. MERGE: BigQuery 的 UPSERT 实现


基本 UPSERT（匹配则更新，不匹配则插入）

```sql
MERGE INTO myproject.mydataset.users AS t
USING (SELECT 'alice' AS username, 'alice@e.com' AS email, 25 AS age) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

```

批量 UPSERT（从 staging 表）

```sql
MERGE INTO myproject.mydataset.users AS t
USING myproject.mydataset.staging_users AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

```

带条件的 UPSERT

```sql
MERGE INTO myproject.mydataset.users AS t
USING myproject.mydataset.staging_users AS s
ON t.username = s.username
WHEN MATCHED AND s.age > t.age THEN
    UPDATE SET age = s.age               -- 只更新更大的年龄值
WHEN MATCHED AND s.age <= t.age THEN
    DELETE                               -- 如果新值更小则删除
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

```

INSERT IF NOT EXISTS

```sql
MERGE INTO myproject.mydataset.users AS t
USING (SELECT 'alice' AS username, 'alice@e.com' AS email, 25 AS age) AS s
ON t.username = s.username
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

```

## 3. MERGE 的高级用法


使用 UNNEST 批量 UPSERT（不需要 staging 表）

```sql
MERGE INTO myproject.mydataset.users AS t
USING UNNEST([
    STRUCT('alice' AS username, 'a@e.com' AS email, 25 AS age),
    STRUCT('bob' AS username, 'b@e.com' AS email, 30 AS age)
]) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

```

CTE + MERGE

```sql
WITH new_data AS (
    SELECT username, email, MAX(age) AS age
    FROM myproject.mydataset.raw_users
    GROUP BY username, email
)
MERGE INTO myproject.mydataset.users AS t
USING new_data AS s
ON t.username = s.username
WHEN MATCHED THEN UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN INSERT ROW;    -- INSERT ROW = 插入所有列

```

## 4. MERGE 的内部机制与成本


 MERGE 在 BigQuery 中是单个 DML 操作（消耗 1 次 DML 配额）。
 内部流程:
   (1) 扫描目标表 (t) 和源数据 (s)
   (2) 按 ON 条件 JOIN
   (3) 对匹配行执行 UPDATE（COW 重写）
   (4) 对不匹配行执行 INSERT（创建新存储文件）
   (5) 原子提交

 成本考虑:
   MERGE 扫描目标表全表（除非有分区条件）
   大表 MERGE 可能很昂贵（按扫描量计费）
   优化: 在 ON 条件中包含分区列，减少扫描范围

## 5. SCD (Slowly Changing Dimension) 模式


BigQuery 的 MERGE 适合实现 SCD Type 1（直接覆盖）:

```sql
MERGE INTO myproject.mydataset.dim_customers AS t
USING myproject.mydataset.stg_customers AS s
ON t.customer_id = s.customer_id
WHEN MATCHED THEN
    UPDATE SET name = s.name, address = s.address, updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, address, created_at, updated_at)
    VALUES (s.customer_id, s.name, s.address, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());

```

## 6. 对比与引擎开发者启示

BigQuery UPSERT/MERGE 的设计:
(1) 无 UNIQUE 约束 → 无冲突检测 → 无 ON CONFLICT 语法
(2) MERGE 是唯一的 UPSERT 方案 → 标准 SQL，功能最完整
(3) 单次 DML 配额 → 比 DELETE + INSERT 更经济
(4) UNNEST 批量 → 不需要 staging 表即可多行 UPSERT

对比:
MySQL:      ON DUPLICATE KEY UPDATE（最简洁但非标准）
PostgreSQL: ON CONFLICT DO UPDATE（简洁且标准化）
SQLite:     ON CONFLICT DO UPDATE（与 PostgreSQL 相同）
ClickHouse: 无 UPSERT（用 ReplacingMergeTree 最终一致去重）
BigQuery:   MERGE（最标准但最冗长）

对引擎开发者的启示:
MERGE 是最通用的 UPSERT 方案，但语法冗长。
ON CONFLICT DO UPDATE 更简洁但需要 UNIQUE 约束支持。
如果引擎不支持 UNIQUE 约束（如 BigQuery/ClickHouse），
MERGE 是唯一合理的选择。

