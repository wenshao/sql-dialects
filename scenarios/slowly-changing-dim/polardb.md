# PolarDB: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [PolarDB MySQL 版文档 - INSERT ON DUPLICATE KEY UPDATE](https://help.aliyun.com/document_detail/172538.html)
> - [PolarDB MySQL 版文档 - DML](https://help.aliyun.com/document_detail/176116.html)
> - [PolarDB PostgreSQL 版文档 - INSERT ON CONFLICT](https://help.aliyun.com/document_detail/455098.html)
> - [Kimball Group - SCD Types](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/)


## 维度表结构


## PolarDB MySQL 版兼容 MySQL DDL/DML

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

## SCD Type 1: INSERT ... ON DUPLICATE KEY UPDATE


## PolarDB MySQL 版兼容 MySQL UPSERT 语法

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

## 方法 3: INSERT ... SET（仅插入不存在的记录）

```sql
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, '9999-12-31', 1
FROM   stg_customer s
LEFT JOIN dim_customer t ON t.customer_id = s.customer_id
WHERE  t.customer_id IS NULL;
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

## PolarDB 注意事项与最佳实践


## PolarDB 有 MySQL 版和 PostgreSQL 版两个引擎:

MySQL 版: 兼容 MySQL 语法（本文示例）
PostgreSQL 版: 兼容 PostgreSQL 语法（支持 ON CONFLICT）
2. PolarDB MySQL 版基于共享存储架构，读写分离自动实现
3. 利用 PolarDB 的并行查询加速大维度表扫描:
SET max_parallel_degree = 4;
4. 建议为大维度表使用分区表，按 effective_date 范围分区
5. PolarDB 支持 Binlog CDC，可集成 DataWorks/Flink 实现 SCD 自动化
6. ON DUPLICATE KEY UPDATE 性能优于 REPLACE INTO（避免 DELETE 开销）
7. 在阿里云生态中，推荐使用 DataWorks 数据集成处理 SCD 逻辑
