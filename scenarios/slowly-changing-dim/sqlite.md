# SQLite: 缓慢变化维度

> 参考资料:
> - [SQLite Documentation - UPSERT](https://www.sqlite.org/lang_UPSERT.html)

## SCD Type 1: 直接覆盖（最常用）

当维度数据变化时，直接用新值覆盖旧值:
```sql
CREATE TABLE dim_customers (
    customer_id INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    address     TEXT,
    city        TEXT,
    updated_at  TEXT DEFAULT (datetime('now'))
);
```

使用 UPSERT（ON CONFLICT）:
```sql
INSERT INTO dim_customers (customer_id, name, address, city)
VALUES (1, 'Alice Smith', '123 New St', 'Boston')
ON CONFLICT (customer_id) DO UPDATE SET
    name = EXCLUDED.name,
    address = EXCLUDED.address,
    city = EXCLUDED.city,
    updated_at = datetime('now');
```

## SCD Type 2: 保留历史版本

```sql
CREATE TABLE dim_customers_v2 (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id  INTEGER NOT NULL,
    name         TEXT NOT NULL,
    address      TEXT,
    valid_from   TEXT NOT NULL DEFAULT (datetime('now')),
    valid_to     TEXT DEFAULT '9999-12-31',
    is_current   INTEGER DEFAULT 1 CHECK (is_current IN (0, 1))
);
CREATE INDEX idx_cust_current ON dim_customers_v2(customer_id, is_current);
```

更新步骤（需要两步操作，用事务保证原子性）:
```sql
BEGIN;
-- 步骤 1: 关闭旧记录
UPDATE dim_customers_v2
SET valid_to = datetime('now'), is_current = 0
WHERE customer_id = 1 AND is_current = 1;
```

步骤 2: 插入新记录
```sql
INSERT INTO dim_customers_v2 (customer_id, name, address, valid_from, is_current)
VALUES (1, 'Alice Smith', '456 New St', datetime('now'), 1);
COMMIT;
```

查询当前状态:
```sql
SELECT * FROM dim_customers_v2 WHERE customer_id = 1 AND is_current = 1;
```

查询历史状态（时间点查询）:
```sql
SELECT * FROM dim_customers_v2
WHERE customer_id = 1
  AND '2024-06-15' BETWEEN valid_from AND valid_to;
```

## SCD Type 2 的触发器自动化

使用 INSTEAD OF 触发器在视图上实现自动 SCD2:
```sql
CREATE VIEW dim_customers_current AS
SELECT customer_id, name, address FROM dim_customers_v2 WHERE is_current = 1;

CREATE TRIGGER trg_scd2_update
INSTEAD OF UPDATE ON dim_customers_current
BEGIN
    UPDATE dim_customers_v2 SET valid_to = datetime('now'), is_current = 0
    WHERE customer_id = OLD.customer_id AND is_current = 1;
    INSERT INTO dim_customers_v2 (customer_id, name, address) VALUES (NEW.customer_id, NEW.name, NEW.address);
END;
```

## 对比与引擎开发者启示

SQLite SCD 的实现:
  Type 1: ON CONFLICT DO UPDATE（最简洁）
  Type 2: 事务中 UPDATE + INSERT（两步操作）
  自动化: INSTEAD OF 触发器

对比:
  MySQL:      没有 MERGE，用 INSERT ON DUPLICATE KEY UPDATE (Type1)
  PostgreSQL: MERGE (15+) 或 CTE + UPDATE + INSERT
  ClickHouse: ReplacingMergeTree（Type1 天然支持）
  BigQuery:   MERGE 语句（最适合 SCD）

对引擎开发者的启示:
  SCD Type 2 是数仓的核心需求。
  MERGE 语句是实现 SCD2 最简洁的方案。
  SQLite 没有 MERGE，需要事务+两步操作（更复杂但可行）。
