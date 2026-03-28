# TiDB: 缓慢变化维

> 参考资料:
> - [TiDB Documentation - INSERT ON DUPLICATE KEY UPDATE](https://docs.pingcap.com/tidb/stable/sql-statement-insert)
> - [TiDB Documentation - REPLACE INTO](https://docs.pingcap.com/tidb/stable/sql-statement-replace)
> - [TiDB Documentation - UPDATE](https://docs.pingcap.com/tidb/stable/sql-statement-update)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## 维度表结构


TiDB 高度兼容 MySQL DDL/DML
```sql
CREATE TABLE dim_customer (
    customer_key   INT AUTO_INCREMENT PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     TINYINT NOT NULL DEFAULT 1,
    created_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_customer_current (customer_id, is_current, effective_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE stg_customer (
    customer_id VARCHAR(20),
    name        VARCHAR(100),
    city        VARCHAR(100),
    tier        VARCHAR(20)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

```

## 插入样本数据


```sql
INSERT INTO stg_customer (customer_id, name, city, tier) VALUES
    ('C001', 'Alice', 'Shanghai', 'Gold'),
    ('C002', 'Bob', 'Beijing', 'Silver'),
    ('C003', 'Charlie', 'Shenzhen', 'Bronze');

```

## SCD Type 1: INSERT ... ON DUPLICATE KEY UPDATE


TiDB 完全兼容 MySQL 的 UPSERT 语法
```sql
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    city = VALUES(city),
    tier = VALUES(tier);

```

方法 2: UPDATE + JOIN
```sql
UPDATE dim_customer t
JOIN   stg_customer s ON t.customer_id = s.customer_id
SET    t.name = s.name, t.city = s.city, t.tier = s.tier
WHERE  t.is_current = 1;

```

方法 3: REPLACE INTO（注意: REPLACE 会触发 DELETE + INSERT）
对于有外键引用或触发器的表，REPLACE 可能有副作用
REPLACE INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer;

## SCD Type 2: UPDATE + INSERT（保留历史版本）


步骤 1: 标记已变化的记录为过期
```sql
UPDATE dim_customer t
JOIN   stg_customer s ON t.customer_id = s.customer_id
SET    t.expiry_date = DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY),
       t.is_current  = 0
WHERE  t.is_current = 1
  AND  (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier);

```

步骤 2: 插入新版本（变化的 + 新增的）
```sql
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', 1
FROM   stg_customer s
WHERE  EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE  d.customer_id = s.customer_id AND d.is_current = 0
      AND  d.expiry_date = DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY)
)
   OR NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);

```

## 验证查询


查看当前活跃维度记录
```sql
SELECT customer_key, customer_id, name, city, tier, effective_date, is_current
FROM   dim_customer
WHERE  is_current = 1
ORDER  BY customer_id;

```

查看某个客户的历史版本
```sql
SELECT customer_key, customer_id, name, city, tier, effective_date, expiry_date
FROM   dim_customer
WHERE  customer_id = 'C001'
ORDER  BY effective_date;

```

## TiDB 注意事项与最佳实践


## TiDB 高度兼容 MySQL 5.7 语法，包括 ON DUPLICATE KEY UPDATE

## TiDB 是分布式 HTAP 数据库，OLTP 和 OLAP 混合负载

   对于 SCD 查询，TiFlash 列存引擎可加速分析:
   ALTER TABLE dim_customer SET TIFLASH REPLICA 1;
## UPDATE 在 TiDB 中可能产生大量写放大（MVCC 机制）

   建议使用 INSERT ON DUPLICATE KEY UPDATE 代替分步 UPDATE + INSERT
## TiDB 的 AUTO_INCREMENT 在分布式环境下不保证严格递增

   建议使用 AUTO_ID_CACHE 或业务层生成代理键
## 大规模数据导入推荐使用 TiDB Lightning 或 LOAD DATA

## TiDB CDC (TiCDC) 可捕获维度表变更，辅助 SCD Type 2 增量处理

## TiDB 支持 Placement Rules，可将维度表放置在特定节点:

   ALTER TABLE dim_customer PLACEMENT POLICY=oltp_policy;
