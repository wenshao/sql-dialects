# Snowflake: 缓慢变化维度 (SCD)

> 参考资料:
> - [1] Snowflake SQL Reference - MERGE
>   https://docs.snowflake.com/en/sql-reference/sql/merge
> - [2] Snowflake - Streams (CDC)
>   https://docs.snowflake.com/en/user-guide/streams


## 维度表与暂存表

```sql
CREATE OR REPLACE TABLE dim_customer (
    customer_key   NUMBER AUTOINCREMENT,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CURRENT_DATE(),
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE OR REPLACE TABLE stg_customer (
    customer_id VARCHAR(20), name VARCHAR(100), city VARCHAR(100), tier VARCHAR(20)
);

```

## 1. SCD Type 1（直接覆盖）


```sql
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET t.name = s.name, t.city = s.city, t.tier = s.tier
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier);

```

## 2. SCD Type 2（保留历史版本）


步骤 1: 关闭旧版本

```sql
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = TRUE
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET t.expiry_date = DATEADD(DAY, -1, CURRENT_DATE()),
                    t.is_current  = FALSE;

```

步骤 2: 插入新版本

```sql
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier, CURRENT_DATE(), '9999-12-31', TRUE
FROM stg_customer s
WHERE NOT EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE d.customer_id = s.customer_id AND d.is_current = TRUE
);

```

## 3. 语法设计分析（对 SQL 引擎开发者）


### 3.1 Snowflake 的 SCD 优势: Streams + Tasks 自动化

```sql
CREATE OR REPLACE STREAM stg_customer_stream ON TABLE stg_customer;
```

 Stream 自动跟踪 stg_customer 的 INSERT/UPDATE/DELETE
 配合 Task 定时执行 MERGE 逻辑 → 自动化 SCD 维护
 对比: 传统数据库需要外部 ETL 工具 (Informatica, dbt) 调度

### 3.2 Time Travel: 内置时态查询（免费的"SCD Type 2"）

查询历史状态（无需维度表的 effective/expiry 列）:

```sql
SELECT * FROM dim_customer AT(TIMESTAMP => '2024-06-01 00:00:00'::TIMESTAMP_NTZ);
SELECT * FROM dim_customer AT(OFFSET => -3600);  -- 1 小时前
```

 Time Travel 限制: 最多 90 天（Enterprise），之后需要传统 SCD

 对比:
   传统 SCD Type 2: 无限历史，但维护复杂
   Time Travel:     最多 90 天，零维护成本
   实际方案: Time Travel 覆盖短期需求，SCD Type 2 覆盖长期需求

## 横向对比: SCD 实现

| 能力         | Snowflake         | BigQuery       | PostgreSQL |
|------|------|------|------|
| MERGE SCD    | 完整 MERGE        | 完整 MERGE     | MERGE(15+) |
| CDC 自动化   | Streams+Tasks     | 无原生         | 触发器/WAL |
| 内置时态查询 | Time Travel(90天) | 快照(7天)      | 无原生 |
| 声明式 SCD   | Dynamic Tables    | 不支持         | 不支持 |

