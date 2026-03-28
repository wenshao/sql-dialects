# TDSQL: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [TDSQL 文档 - SQL 兼容性](https://cloud.tencent.com/document/product/557)
> - [TDSQL 文档 - DML 语句](https://cloud.tencent.com/document/product/557/104712)
> - [TDSQL - MySQL 兼容性](https://cloud.tencent.com/document/product/557/11204)
> - [Kimball Group - SCD Types](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/)


## 维度表结构


## TDSQL 兼容 MySQL DDL/DML（Percona 分支）

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
```

TDSQL 分布式版本建议指定分片键
shardkey 用于水平分片，确保同一 customer_id 的记录在同一分片
CREATE TABLE dim_customer ( ... ) shardkey=customer_id;

```sql
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


## TDSQL 兼容 MySQL 的 UPSERT 语法

```sql
INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT customer_id, name, city, tier FROM stg_customer
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    city = VALUES(city),
    tier = VALUES(tier);
```

## 方法 2: UPDATE + JOIN

```sql
UPDATE dim_customer t
JOIN   stg_customer s ON t.customer_id = s.customer_id
SET    t.name = s.name, t.city = s.city, t.tier = s.tier
WHERE  t.is_current = 1;
```

## 方法 3: INSERT IGNORE + UPDATE（安全插入后更新）

```sql
INSERT IGNORE INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', 1
FROM   stg_customer s;
```

## SCD Type 2: UPDATE + INSERT（保留历史版本）


## 步骤 1: 标记已变化的记录为过期

```sql
UPDATE dim_customer t
JOIN   stg_customer s ON t.customer_id = s.customer_id
SET    t.expiry_date = DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY),
       t.is_current  = 0
WHERE  t.is_current = 1
  AND  (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier);
```

## 步骤 2: 插入新版本（变化的 + 新增的）

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


## 查看当前活跃维度记录

```sql
SELECT customer_key, customer_id, name, city, tier, effective_date, is_current
FROM   dim_customer
WHERE  is_current = 1
ORDER  BY customer_id;
```

## 查看某个客户的历史版本

```sql
SELECT customer_key, customer_id, name, city, tier, effective_date, expiry_date
FROM   dim_customer
WHERE  customer_id = 'C001'
ORDER  BY effective_date;
```

## TDSQL 注意事项与最佳实践


## TDSQL 高度兼容 MySQL 语法（基于 Percona 分支）

## TDSQL 分布式版本使用 shardkey 进行水平分片

shardkey 必须包含在所有 DML 条件中，避免跨分片操作
3. 分布式模式下的 JOIN 要求关联键相同或在同一分片组
4. ON DUPLICATE KEY UPDATE 在分布式模式下需要唯一键包含 shardkey
5. TDSQL 支持强同步复制，保证数据一致性
6. 大规模 ETL 推荐使用 Data Migration (DM) 工具
7. 建议使用 TDSQL 的 Binlog 订阅功能实现增量 ETL
8. 在腾讯云生态中，推荐使用数据集成服务处理 SCD 逻辑
