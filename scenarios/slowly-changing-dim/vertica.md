# Vertica: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [Vertica Documentation - MERGE](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/MERGE.htm)
> - [Vertica Documentation - UPDATE](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/UPDATE.htm)
> - [Vertica Documentation - INSERT](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/INSERT.htm)
> - [Vertica Documentation - Projections](https://www.vertica.com/docs/latest/HTML/Content/Authoring/AnalyzingData/Projections.htm)


## 1. 维度表结构


Vertica 使用 AUTO_INCREMENT 或 IDENTITY 生成代理键
```sql
CREATE TABLE dim_customer (
    customer_key   IDENTITY(1,1) PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at     TIMESTAMP DEFAULT NOW()
);
```


创建优化投影（Vertica 的物理存储结构）
```sql
CREATE PROJECTION dim_customer_prj AS
SELECT customer_key, customer_id, name, city, tier,
       effective_date, expiry_date, is_current
FROM   dim_customer
ORDER  BY customer_id, is_current, effective_date
SEGMENTED BY HASH(customer_id) ALL NODES;

CREATE TABLE stg_customer (
    customer_id VARCHAR(20),
    name        VARCHAR(100),
    city        VARCHAR(100),
    tier        VARCHAR(20)
);
```


## 2. 插入样本数据


```sql
INSERT INTO stg_customer (customer_id, name, city, tier) VALUES
    ('C001', 'Alice', 'Shanghai', 'Gold'),
    ('C002', 'Bob', 'Beijing', 'Silver'),
    ('C003', 'Charlie', 'Shenzhen', 'Bronze');
```


## 3. SCD Type 1: MERGE INTO


Vertica 的 MERGE 是高性能实现，利用列存和投影优化
```sql
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier, effective_date, expiry_date, is_current)
         VALUES (s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, DATE '9999-12-31', TRUE);
```


方法 2: UPDATE + INSERT（分步操作，更精确控制）
```sql
UPDATE dim_customer t
SET    name = s.name, city = s.city, tier = s.tier
FROM   stg_customer s
WHERE  t.customer_id = s.customer_id AND t.is_current = TRUE;

INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, DATE '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);
```


## 4. SCD Type 2: 两步操作（保留历史版本）


步骤 1: 检测变化并标记当前行为过期
```sql
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET expiry_date = CURRENT_DATE - 1, is_current = FALSE;
```


步骤 2: 插入新版本（变化的 + 新增的）
```sql
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE, DATE '9999-12-31', TRUE
FROM   stg_customer s
WHERE  NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id AND d.is_current = TRUE
);

COMMIT;
```


## 5. 验证查询


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


Vertica 高性能分析查询: 统计每个客户等级的维度变化次数
```sql
SELECT tier,
       COUNT(*) AS version_count,
       MIN(effective_date) AS first_seen,
       MAX(effective_date) AS last_seen
FROM   dim_customer
GROUP  BY tier
ORDER  BY version_count DESC;
```


## 6. Vertica 注意事项与最佳实践


1. Vertica 的 MERGE 性能优秀，充分利用列存和向量执行引擎
2. 投影 (Projection) 是 Vertica 的核心物理存储结构
创建投影时可指定排序键和分布策略
3. UPDATE/DELETE 在 Vertica 中会产生删除向量 (Delete Vector)
大量更新后需要执行 PURGE 或 REBUILD 清理:
SELECT PURGE_TABLE('dim_customer');
4. 大规模数据加载推荐使用 COPY 命令（比 INSERT 快 10x+）
5. 分区策略建议: ALTER TABLE dim_customer PARTITION BY effective_date;
6. Vertica 不支持可写 CTE，SCD Type 2 必须分步执行
7. IDENTITY 列在 Vertica 中不一定严格递增（分布式中可能有间隔）
8. 建议对投影使用 SEGMENTED BY HASH(customer_id) 确保数据均匀分布
