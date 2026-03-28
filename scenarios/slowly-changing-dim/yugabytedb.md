# YugabyteDB: 缓慢变化维

> 参考资料:
> - [YugabyteDB Documentation - YSQL (PostgreSQL Compatibility)](https://docs.yugabyte.com/latest/api/ysql/)
> - [YugabyteDB Documentation - INSERT ON CONFLICT](https://docs.yugabyte.com/latest/api/ysql/commands/insert/)
> - [YugabyteDB Documentation - UPDATE](https://docs.yugabyte.com/latest/api/ysql/commands/update/)
> - [YugabyteDB Documentation - Transactions](https://docs.yugabyte.com/latest/explore/acid-transactions/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## 维度表结构


YugabyteDB YSQL API 完全兼容 PostgreSQL DDL/DML
```sql
CREATE TABLE dim_customer (
    customer_key   SERIAL PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at     TIMESTAMP DEFAULT NOW(),
    UNIQUE (customer_id, is_current, effective_date)
);

```

建议创建二级索引加速业务键查找
```sql
CREATE INDEX idx_customer_current ON dim_customer (customer_id, is_current);

CREATE TABLE stg_customer (
    customer_id VARCHAR(20),
    name        VARCHAR(100),
    city        VARCHAR(100),
    tier        VARCHAR(20)
);

```

## 插入样本数据


```sql
INSERT INTO stg_customer (customer_id, name, city, tier) VALUES
    ('C001', 'Alice', 'Shanghai', 'Gold'),
    ('C002', 'Bob', 'Beijing', 'Silver'),
    ('C003', 'Charlie', 'Shenzhen', 'Bronze');

```

## SCD Type 1: INSERT ... ON CONFLICT（PostgreSQL 兼容）


YugabyteDB 完全兼容 PostgreSQL UPSERT 语法
```sql
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON CONFLICT (customer_id)
DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city,
              tier = EXCLUDED.tier, updated_at = NOW();

```

方法 2: UPDATE + INSERT 分步操作
```sql
UPDATE dim_customer t
SET    name = s.name, city = s.city, tier = s.tier
FROM   stg_customer s
WHERE  t.customer_id = s.customer_id AND t.is_current = TRUE;

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);

```

## SCD Type 2: UPDATE + INSERT（保留历史版本）


步骤 1: 检测变化并标记当前行为过期
```sql
UPDATE dim_customer AS t
SET    expiry_date = CURRENT_DATE - INTERVAL '1 day', is_current = FALSE
FROM   stg_customer AS s
WHERE  t.customer_id = s.customer_id AND t.is_current = TRUE
  AND  (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier);

```

步骤 2: 插入新版本（变化的 + 新增的）
```sql
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = TRUE
);

```

## 验证查询


查看当前活跃维度记录
```sql
SELECT customer_key, customer_id, name, city, tier, effective_date, is_current
FROM   dim_customer
WHERE  is_current = TRUE
ORDER  BY customer_id;

```

查看某个客户的历史版本
```sql
SELECT customer_key, customer_id, name, city, tier, effective_date, expiry_date
FROM   dim_customer
WHERE  customer_id = 'C001'
ORDER  BY effective_date;

```

## YugabyteDB 注意事项与最佳实践


## YugabyteDB YSQL API 完全兼容 PostgreSQL 语法

## 分布式架构下，主键和唯一键自动作为分片键 (Tablet)

   建议将 customer_id 纳入主键或显式指定分片
## SERIAL 在分布式环境中使用缓存分配，可能不严格递增

## YugabyteDB 不支持可写 CTE，SCD Type 2 必须分步执行

## ON CONFLICT 在分布式环境下性能良好（基于 DocDB 乐观并发）

## 建议将高频查询的维度表设置为 COLOCATED（同一 Tablet Group）:

   CREATE TABLE dim_customer (...) WITH (colocated = true);
## YugabyteDB 支持 CDC (Change Data Capture)，可辅助 SCD 增量处理

## 地域分布部署可实现低延迟读取:

   CREATE TABLE dim_customer (...) WITH (placement = 'cloud.region.zone');
