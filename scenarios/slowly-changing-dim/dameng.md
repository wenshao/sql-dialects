# 达梦 (DM): 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [达梦数据库 SQL 参考手册 - MERGE INTO](https://eco.dameng.com/document/dm/zh-cn/sql-dev/)
> - [达梦数据库 SQL 参考手册 - 数据类型](https://eco.dameng.com/document/dm/zh-cn/sql-dev/)
> - [达梦数据库 兼容 Oracle 模式 MERGE 语法](https://eco.dameng.com/document/dm/zh-cn/pm/sql-reference/)
> - ============================================================
> - 1. 维度表结构
> - ============================================================
> - 达梦兼容 Oracle 数据类型: VARCHAR2, NUMBER, DATE, CLOB 等

```sql
CREATE TABLE dim_customer (
    customer_key   INT IDENTITY(1,1) PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT SYSDATE,
    expiry_date    DATE NOT NULL DEFAULT DATE '9999-12-31',
    is_current     CHAR(1) NOT NULL DEFAULT 'Y',
    CHECK (is_current IN ('Y', 'N'))
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

## SCD Type 1: MERGE INTO（兼容 Oracle 语法）


## 达梦的 MERGE 语法与 Oracle 高度兼容

```sql
MERGE INTO dim_customer t
USING stg_customer s
ON (t.customer_id = s.customer_id AND t.is_current = 'Y')
WHEN MATCHED THEN
    UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
    WHERE t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, city, tier, effective_date, expiry_date, is_current)
    VALUES (s.customer_id, s.name, s.city, s.tier, SYSDATE, DATE '9999-12-31', 'Y');
```

## 方法 2: UPDATE + INSERT 分步操作

```sql
UPDATE dim_customer t
SET    t.name = (SELECT s.name FROM stg_customer s WHERE s.customer_id = t.customer_id),
       t.city = (SELECT s.city FROM stg_customer s WHERE s.customer_id = t.customer_id)
WHERE  t.is_current = 'Y'
  AND  EXISTS (SELECT 1 FROM stg_customer s WHERE s.customer_id = t.customer_id);

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, SYSDATE, 'Y'
FROM   stg_customer s
WHERE  NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id);
```

## SCD Type 2: 两步操作（保留历史版本）


## 步骤 1: 标记已变化的记录为过期

```sql
MERGE INTO dim_customer t
USING stg_customer s
ON (t.customer_id = s.customer_id AND t.is_current = 'Y')
WHEN MATCHED THEN
    UPDATE SET t.expiry_date = SYSDATE - 1, t.is_current = 'N'
    WHERE t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier;
```

## 步骤 2: 插入新版本（变化的 + 新增的）

```sql
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, SYSDATE, DATE '9999-12-31', 'Y'
FROM   stg_customer s
WHERE  EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE  d.customer_id = s.customer_id AND d.is_current = 'N'
      AND  d.expiry_date = SYSDATE - 1
)
   OR NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);

COMMIT;
```

## 验证查询


## 查看当前活跃维度记录

```sql
SELECT customer_key, customer_id, name, city, tier, effective_date, is_current
FROM   dim_customer
WHERE  is_current = 'Y'
ORDER  BY customer_id;
```

## 查看某个客户的历史版本

```sql
SELECT customer_key, customer_id, name, city, tier, effective_date, expiry_date
FROM   dim_customer
WHERE  customer_id = 'C001'
ORDER  BY effective_date;
```

## 达梦注意事项与最佳实践


## 达梦 MERGE 语法高度兼容 Oracle，适合从 Oracle 迁移的项目

## is_current 使用 CHAR(1) 而非 BOOLEAN，这是 Oracle 风格惯例

## SYSDATE 是达梦的当前时间函数（兼容 Oracle），也可用 CURRENT_DATE

## 达梦 IDENTITY 语法: INT IDENTITY(1,1) 类似 SQL Server

## 达梦支持 SQL:2003 MERGE 标准，可在 WHEN MATCHED 中添加条件过滤

## 在达梦集群部署中，建议使用哈希分区优化大维度表的查询

## 达梦支持事务内 DDL 操作，可在同一事务中修改表结构和数据
