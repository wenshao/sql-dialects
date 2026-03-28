# 人大金仓 (KingbaseES): 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [KingbaseES 文档 - SQL 语言参考](https://help.kingbase.com.cn/)
> - [KingbaseES 文档 - INSERT ON CONFLICT](https://help.kingbase.com.cn/v8/developer/sql-reference/insert.html)
> - [KingbaseES - PostgreSQL 兼容性](https://help.kingbase.com.cn/v8/developer/compatibility.html)
> - [Kimball Group - SCD Types](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/)


## 维度表结构


## KingbaseES 高度兼容 PostgreSQL DDL/DML

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


## KingbaseES 完全兼容 PostgreSQL 的 UPSERT 语法

```sql
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON CONFLICT (customer_id)
DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city,
              tier = EXCLUDED.tier, updated_at = NOW();
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

## KingbaseES 注意事项与最佳实践


## KingbaseES 高度兼容 PostgreSQL 语法，包括 ON CONFLICT、CTE 等

## 支持 Oracle 兼容模式（通过 kingbase.conf 配置）

## KingbaseES 支持可写 CTE（WITH ... DML ... RETURNING），

理论上可以使用 PostgreSQL 风格的单语句 SCD Type 2 方案
4. 需验证 RETURNING + INSERT 组合在 KingbaseES 中的兼容性
5. 建议为大维度表创建合适的索引:
CREATE INDEX idx_customer_current ON dim_customer (customer_id, is_current);
6. KingbaseES 支持 PL/SQL 和 PL/pgSQL 存储过程
7. 国产数据库信创场景首选，兼容性和性能均经过大规模验证
