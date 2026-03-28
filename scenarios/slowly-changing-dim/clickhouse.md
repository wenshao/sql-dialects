# ClickHouse: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [1] ClickHouse - ReplacingMergeTree
>   https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree
> - [2] ClickHouse - VersionedCollapsingMergeTree
>   https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/versionedcollapsingmergetree


## 1. SCD Type 1: ReplacingMergeTree（天然支持）


ReplacingMergeTree 在后台 merge 时保留最新版本:

```sql
CREATE TABLE dim_customers (
    customer_id UInt64,
    name        String,
    address     String,
    city        String,
    version     UInt64
) ENGINE = ReplacingMergeTree(version)
ORDER BY customer_id;

```

"更新": 插入新版本行（INSERT-only 哲学）

```sql
INSERT INTO dim_customers VALUES (1, 'Alice', '123 Old St', 'NYC', 1);
INSERT INTO dim_customers VALUES (1, 'Alice', '456 New St', 'Boston', 2);
```

后台 merge 保留 version=2 的行

查询最新状态:

```sql
SELECT * FROM dim_customers FINAL WHERE customer_id = 1;
```

FINAL: 查询时执行 merge 逻辑（保证结果正确但有性能开销）

强制 merge:

```sql
OPTIMIZE TABLE dim_customers FINAL;

```

 设计分析:
   ReplacingMergeTree 是 ClickHouse 实现 SCD Type 1 的自然方案。
   不需要 UPDATE（INSERT 新版本行即可）。
   但代价是: 查询时需要 FINAL（或容忍短暂的数据冗余）。

## 2. SCD Type 2: 保留历史版本


```sql
CREATE TABLE dim_customers_v2 (
    customer_id UInt64,
    name        String,
    address     String,
    valid_from  DateTime DEFAULT now(),
    valid_to    DateTime DEFAULT toDateTime('9999-12-31 23:59:59'),
    is_current  UInt8 DEFAULT 1
) ENGINE = MergeTree()
ORDER BY (customer_id, valid_from);

```

SCD2 在 ClickHouse 中较复杂（因为没有 UPDATE）:
步骤 1: 插入"关闭"旧记录的 mutation

```sql
ALTER TABLE dim_customers_v2 UPDATE
    valid_to = now(), is_current = 0
WHERE customer_id = 1 AND is_current = 1;

```

步骤 2: 插入新记录

```sql
INSERT INTO dim_customers_v2 (customer_id, name, address)
VALUES (1, 'Alice', '456 New St');

```

 注意: mutation 是异步的! 需要 SETTINGS mutations_sync = 1 保证顺序。

## 3. SCD Type 2 的替代方案: 版本化表


更适合 ClickHouse 的方案: 直接保留所有版本

```sql
CREATE TABLE dim_customers_history (
    customer_id UInt64,
    name        String,
    address     String,
    version     UInt64,
    updated_at  DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (customer_id, version);

```

每次变更直接 INSERT:

```sql
INSERT INTO dim_customers_history VALUES (1, 'Alice', '123 Old St', 1, now());
INSERT INTO dim_customers_history VALUES (1, 'Alice', '456 New St', 2, now());

```

查询最新版本:

```sql
SELECT * FROM dim_customers_history
WHERE (customer_id, version) IN (
    SELECT customer_id, max(version) FROM dim_customers_history GROUP BY customer_id
);

```

或用 argMax:

```sql
SELECT customer_id, argMax(name, version), argMax(address, version)
FROM dim_customers_history GROUP BY customer_id;

```

## 4. 对比与引擎开发者启示

ClickHouse SCD 的实现:
Type 1: ReplacingMergeTree（最自然，INSERT 新版本）
Type 2: 版本化表 + argMax（比 mutation 更适合）

对比:
BigQuery: MERGE 语句（最适合 SCD）
PostgreSQL: MERGE 或 CTE + UPDATE + INSERT
SQLite: ON CONFLICT + 事务

对引擎开发者的启示:
INSERT-only 引擎的 SCD 实现与传统数据库不同:
不需要 UPDATE 旧记录，直接 INSERT 新版本。
ReplacingMergeTree（保留最新）+ 全历史表（保留所有版本）
是 INSERT-only 引擎的标准 SCD 模式。

