# Spanner: 缓慢变化维

> 参考资料:
> - [Cloud Spanner - DML (INSERT, UPDATE, DELETE)](https://cloud.google.com/spanner/docs/reference/standard-sql/dml-syntax)
> - [Cloud Spanner - Schema and Data Model](https://cloud.google.com/spanner/docs/schema-and-data-model)
> - [Cloud Spanner - Query Syntax](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## 维度表结构


Spanner 不支持 SERIAL/AUTO_INCREMENT，使用 STRING(GENERATE_UUID()) 或 INT64 作为主键
```sql
CREATE TABLE dim_customer (
    customer_key   STRING(36) NOT NULL,
    customer_id    STRING(20) NOT NULL,
    name           STRING(100),
    city           STRING(100),
    tier           STRING(20),
    effective_date DATE NOT NULL,
    expiry_date    DATE NOT NULL,
    is_current     BOOL NOT NULL,
) PRIMARY KEY (customer_key);

```

辅助索引：按业务键快速查找当前记录
```sql
CREATE INDEX idx_customer_current ON dim_customer (customer_id, is_current);

```

源数据临时表（Spanner 不支持真正的临时表，使用普通表模拟）
```sql
CREATE TABLE stg_customer (
    customer_id STRING(20) NOT NULL,
    name        STRING(100),
    city        STRING(100),
    tier        STRING(20)
) PRIMARY KEY (customer_id);

```

## 插入样本数据


```sql
INSERT INTO stg_customer (customer_id, name, city, tier) VALUES
    ('C001', 'Alice', 'Shanghai', 'Gold'),
    ('C002', 'Bob', 'Beijing', 'Silver'),
    ('C003', 'Charlie', 'Shenzhen', 'Bronze');

```

## SCD Type 1: INSERT OR UPDATE（Spanner 特有语法）


Spanner 不支持 MERGE，使用 INSERT OR UPDATE 实现幂等写入
INSERT OR UPDATE: 存在则更新，不存在则插入
```sql
INSERT OR UPDATE INTO dim_customer (customer_key, customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT GENERATE_UUID(), customer_id, name, city, tier, CURRENT_DATE(), DATE '9999-12-31', TRUE
FROM   stg_customer;

```

方法 2: 分步 UPDATE + INSERT
先更新已存在的记录
```sql
UPDATE dim_customer
SET    name = s.name, city = s.city, tier = s.tier
FROM   stg_customer s
WHERE  dim_customer.customer_id = s.customer_id
  AND  dim_customer.is_current = TRUE;

```

再插入新记录
```sql
INSERT INTO dim_customer (customer_key, customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT GENERATE_UUID(), s.customer_id, s.name, s.city, s.tier, CURRENT_DATE(), DATE '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);

```

## SCD Type 2: UPDATE + INSERT（保留历史版本）


步骤 1: 检测变化并标记当前行为过期
```sql
UPDATE dim_customer
SET    expiry_date = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY),
       is_current  = FALSE
WHERE  is_current = TRUE
  AND  customer_id IN (
    SELECT s.customer_id
    FROM   stg_customer s
    JOIN   dim_customer d ON s.customer_id = d.customer_id AND d.is_current = TRUE
    WHERE  s.name != d.name OR s.city != d.city OR s.tier != d.tier
);

```

步骤 2: 插入新版本（变化的 + 新增的）
```sql
INSERT INTO dim_customer (customer_key, customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT GENERATE_UUID(), s.customer_id, s.name, s.city, s.tier,
       CURRENT_DATE(), DATE '9999-12-31', TRUE
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

## Spanner 注意事项与最佳实践


## Spanner 不支持 SERIAL 自增列，使用 GENERATE_UUID() 生成主键

## INSERT OR UPDATE 是 Spanner 特有的 DML 扩展，适合幂等写入

## Spanner 不支持 MERGE 语句，SCD Type 2 必须分步执行

## 单次 DML 语句的变异上限为 20,000 行，大规模更新需分批处理

## Spanner 没有真正的临时表，stg_customer 需手动清理

## 建议在 customer_id + is_current 上创建二级索引加速查找

## 对于大规模 ETL，推荐使用 Dataflow 而非 DML 直接写入

## Spanner 日期函数使用 CURRENT_DATE() 和 DATE_SUB()（带括号）
