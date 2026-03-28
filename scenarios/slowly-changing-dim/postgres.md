# PostgreSQL: 缓慢变化维度

> 参考资料:
> - [PostgreSQL Documentation - INSERT ... ON CONFLICT](https://www.postgresql.org/docs/current/sql-insert.html#SQL-ON-CONFLICT)
> - [PostgreSQL Documentation - MERGE (15+)](https://www.postgresql.org/docs/15/sql-merge.html)

## 维度表结构

```sql
CREATE TABLE dim_customer (
    customer_key   SERIAL PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100), city VARCHAR(100), tier VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     BOOLEAN NOT NULL DEFAULT TRUE
);
```

## SCD Type 1: 直接覆盖（不保留历史）

```sql
INSERT ... ON CONFLICT (9.5+)
```

```sql
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON CONFLICT (customer_id)
DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city,
              tier = EXCLUDED.tier, updated_at = NOW();
```

```sql
MERGE (15+)
```

```sql
MERGE INTO dim_customer AS t USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city)
    THEN UPDATE SET name = s.name, city = s.city
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier) VALUES (s.customer_id, s.name, s.city, s.tier);
```

## SCD Type 2: 可写 CTE 版本化（保留历史，PostgreSQL 最佳方式）

使用 PostgreSQL 独有的可写 CTE，单语句原子完成:
```sql
WITH changed AS (
    UPDATE dim_customer AS t
    SET expiry_date = CURRENT_DATE - 1, is_current = FALSE
    FROM stg_customer AS s
    WHERE t.customer_id = s.customer_id AND t.is_current = TRUE
      AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    RETURNING t.customer_id
)
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE
FROM stg_customer s
WHERE s.customer_id IN (SELECT customer_id FROM changed)
   OR NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id);
```

设计分析: 可写 CTE 的优势
  UPDATE + INSERT 在单语句中原子完成（无需两步操作）。
  RETURNING 将更新的行传递给后续 INSERT。
  这是 PostgreSQL 独有的能力——其他数据库需要两个语句或存储过程。

## 横向对比与对引擎开发者的启示

### SCD Type 2 实现方式

  PostgreSQL: 可写 CTE（单语句原子操作）— 最简洁
  MySQL:      两条 SQL（UPDATE + INSERT）— 需要事务包裹
  Oracle:     MERGE（SQL:2003，但不支持同一行多个动作）
  SQL Server: MERGE + OUTPUT（可以，但 MERGE 有已知 bug）

### PostgreSQL 的优势

  (a) 可写 CTE 让 SCD Type 2 成为单语句操作
  (b) RETURNING 传递中间结果，无需临时表
  (c) DDL 事务性保证了 schema 变更的安全性

对引擎开发者:
  可写 CTE（DML in WITH + RETURNING）是 PostgreSQL 最独特的特性之一。
  它将多步骤的 ETL 操作压缩为单语句，减少事务复杂度。
  新引擎如果支持 RETURNING + 可写 CTE，将极大简化数据仓库 ETL。
