# Derby: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [Apache Derby Reference Manual](https://db.apache.org/derby/docs/10.17/ref/)
> - [Apache Derby MERGE Statement (10.11+)](https://db.apache.org/derby/docs/10.17/ref/rrefsqljmerge.html)


## 维度表结构


```sql
CREATE TABLE dim_customer (
    customer_key   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT DATE('9999-12-31'),
    is_current     INT NOT NULL DEFAULT 1,
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

## SCD Type 1: UPDATE + INSERT（传统方式）


## Derby 不支持 UPSERT 语法，使用分步 UPDATE + INSERT

```sql
UPDATE dim_customer SET name = (SELECT s.name FROM stg_customer s WHERE s.customer_id = dim_customer.customer_id),
                        city = (SELECT s.city FROM stg_customer s WHERE s.customer_id = dim_customer.customer_id),
                        tier = (SELECT s.tier FROM stg_customer s WHERE s.customer_id = dim_customer.customer_id)
WHERE customer_id IN (SELECT customer_id FROM stg_customer) AND is_current = 1;

INSERT INTO dim_customer (customer_id, name, city, tier)
SELECT s.customer_id, s.name, s.city, s.tier FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id);
```

## SCD Type 2: 关闭旧记录 + 插入新记录


## Step 1: 关闭已变化的当前记录

```sql
UPDATE dim_customer SET expiry_date = CURRENT_DATE - 1 DAY, is_current = 0
WHERE is_current = 1 AND customer_id IN (
    SELECT s.customer_id FROM stg_customer s
    JOIN dim_customer d ON d.customer_id = s.customer_id AND d.is_current = 1
    WHERE s.name <> d.name OR s.city <> d.city OR s.tier <> d.tier
);
```

## Step 2: 插入新版本记录（包含新增客户）

```sql
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, DATE('9999-12-31'), 1
FROM stg_customer s
WHERE NOT EXISTS (SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = 1);
```

## SCD Type 2: 使用 MERGE（Derby 10.11+）


## Derby 10.11+ 支持 SQL 标准 MERGE 语句

可以用 MERGE 实现 SCD Type 1（直接覆盖）

```sql
MERGE INTO dim_customer AS d
USING stg_customer AS s
ON d.customer_id = s.customer_id AND d.is_current = 1
WHEN MATCHED THEN
    UPDATE SET name = s.name, city = s.city, tier = s.tier
WHEN NOT MATCHED THEN
    INSERT (customer_id, name, city, tier)
    VALUES (s.customer_id, s.name, s.city, s.tier);
```

## SCD Type 3: 新增列跟踪旧值


```sql
ALTER TABLE dim_customer ADD COLUMN prev_city VARCHAR(100);
ALTER TABLE dim_customer ADD COLUMN prev_tier VARCHAR(20);
```

## 更新时将旧值保存到 prev_* 列

```sql
UPDATE dim_customer SET prev_city = city, prev_tier = tier,
                        city = (SELECT s.city FROM stg_customer s WHERE s.customer_id = dim_customer.customer_id),
                        tier = (SELECT s.tier FROM stg_customer s WHERE s.customer_id = dim_customer.customer_id)
WHERE customer_id IN (SELECT customer_id FROM stg_customer) AND is_current = 1;
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

## 注意事项


## Derby 10.11+ 支持 MERGE，可用于 SCD Type 1

## Derby 不支持可写 CTE（WITH ... UPDATE ... INSERT），SCD Type 2 需分步执行

## Derby 不支持 UPSERT / ON CONFLICT / ON DUPLICATE KEY

## GENERATED ALWAYS AS IDENTITY 提供自增主键（Derby 10.7+）

## SCD Type 2 的两步操作不在同一事务中，建议手动 BEGIN / COMMIT 包裹
