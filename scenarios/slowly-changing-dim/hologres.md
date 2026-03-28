# Hologres: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [Hologres Documentation - INSERT ON CONFLICT (UPSERT)](https://help.aliyun.com/document_detail/130408.html)
> - [Hologres Documentation - Table Types](https://help.aliyun.com/document_detail/176116.html)
> - [Hologres Documentation - DML](https://help.aliyun.com/document_detail/181551.html)
> - [Hologres - PostgreSQL Compatibility](https://help.aliyun.com/document_detail/193895.html)
> - ============================================================
> - 1. 维度表结构
> - ============================================================
> - Hologres 兼容 PostgreSQL DDL/DML，支持 ON CONFLICT UPSERT

```sql
CREATE TABLE dim_customer (
    customer_key   BIGINT NOT NULL,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at     TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (customer_key)
);
```

## Hologres 使用 Distribution Key 控制数据分布

```sql
CALL SET_TABLE_PROPERTY('dim_customer', 'distribution_key', 'customer_id');
CALL SET_TABLE_PROPERTY('dim_customer', 'clustering_key', 'customer_id,is_current');

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


## Hologres 的 ON CONFLICT 通过主键判断冲突

```sql
INSERT INTO dim_customer (customer_key, customer_id, name, city, tier)
SELECT nextval('customer_key_seq'), customer_id, name, city, tier FROM stg_customer
ON CONFLICT (customer_key)
DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city,
              tier = EXCLUDED.tier, updated_at = NOW();
```

## 方法 2: 分步 UPDATE + INSERT

```sql
UPDATE dim_customer t
SET    name = s.name, city = s.city, tier = s.tier
FROM   stg_customer s
WHERE  t.customer_id = s.customer_id AND t.is_current = TRUE;

INSERT INTO dim_customer (customer_key, customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT nextval('customer_key_seq'), s.customer_id, s.name, s.city, s.tier,
       CURRENT_DATE, '9999-12-31', TRUE
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
INSERT INTO dim_customer (customer_key, customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT nextval('customer_key_seq'), s.customer_id, s.name, s.city, s.tier,
       CURRENT_DATE, '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = TRUE
);
```

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

## Hologres 注意事项与最佳实践


## Hologres 兼容 PostgreSQL 协议，支持 ON CONFLICT UPSERT

## Hologres 使用 CALL SET_TABLE_PROPERTY 设置分布键和聚簇键

## distribution_key 建议设置为 customer_id，确保同一客户在同一 shard

## Hologres 支持 Fixed Plan 优化路径，加速单行 UPSERT

需要设置: SET hg_experimental_enable_fixed_dispatcher_for_update = ON;
5. 大规模数据导入推荐使用 COPY FROM 或 DataWorks 数据集成
6. Hologres 不支持可写 CTE，SCD Type 2 必须分步执行
7. Hologres 的 UPDATE 操作会产生新的存储版本，建议定期 VACUUM
8. 与 MaxCompute/DataWorks 深度集成，适合阿里云数仓场景
