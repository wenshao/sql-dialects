# Materialize: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [Materialize Documentation - SQL Reference](https://materialize.com/docs/sql/)
> - [Materialize Documentation - INSERT](https://materialize.com/docs/sql/insert/)
> - [Materialize Documentation - Subsources and Sources](https://materialize.com/docs/sql/create-source/)
> - [Materialize - Incremental Computation](https://materialize.com/docs/overview/what-is-materialize/)
> - ============================================================
> - 1. 维度表结构
> - ============================================================
> - Materialize 兼容 PostgreSQL 语法

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
    UNIQUE (customer_id, is_current, effective_date)
);

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


## Materialize 支持 PostgreSQL 风格的 UPSERT

```sql
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON CONFLICT (customer_id)
DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city,
              tier = EXCLUDED.tier;
```

## 方法 2: UPDATE + INSERT 分步操作

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


## 步骤 1: 检测变化并标记当前行为过期

```sql
UPDATE dim_customer AS t
SET    expiry_date = CURRENT_DATE - INTERVAL '1 day', is_current = FALSE
FROM   stg_customer AS s
WHERE  t.customer_id = s.customer_id AND t.is_current = TRUE
  AND  (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier);
```

## 步骤 2: 插入新版本（变化的 + 新增的）

```sql
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = TRUE
);
```

## Materialize 特色: 实时物化视图（增量计算 SCD）


## Materialize 核心优势: 物化视图自动增量维护

创建当前版本视图（实时维护，无需手动刷新）

```sql
CREATE VIEW v_current_customer AS
SELECT customer_key, customer_id, name, city, tier
FROM   dim_customer
WHERE  is_current = TRUE;
```

创建订阅: 实时推送变更到下游
SUBSCRIBE TO (SELECT * FROM v_current_customer);
从 Kafka Source 直接创建维度物化视图
CREATE SOURCE customer_source FROM KAFKA BROKER 'localhost:9092' TOPIC 'customers'
FORMAT JSON;
CREATE MATERIALIZED VIEW mv_customer AS
SELECT data->>'customer_id' AS customer_id,
data->>'name'        AS name,
data->>'city'        AS city
FROM   customer_source;

## 验证查询


## 查看当前活跃维度记录

```sql
SELECT customer_key, customer_id, name, city, tier, effective_date, is_current
FROM   dim_customer
WHERE  is_current = TRUE
ORDER  BY customer_id;
```

## 查看某个客户的历史版本

```sql
SELECT customer_key, customer_id, name, city, tier, effective_date, expiry_date
FROM   dim_customer
WHERE  customer_id = 'C001'
ORDER  BY effective_date;
```

## Materialize 注意事项与最佳实践


## Materialize 是流式数据库，核心优势是物化视图的增量维护

## 支持从 Kafka/PostgreSQL/MySQL 等外部 Source 导入数据

## SUBSCRIBE 提供实时变更推送（CDC 输出）

## Materialize 不支持可写 CTE，SCD Type 2 必须分步执行

## 对于流式 SCD Type 2，建议在 Materialize 之外处理版本化逻辑

## Materialize 的 INDEX 可加速维度表的点查找

## CREATE INDEX idx_customer_id ON dim_customer (customer_id, is_current);

7. 适合实时数仓场景，与传统批处理 SCD 模式有本质区别
