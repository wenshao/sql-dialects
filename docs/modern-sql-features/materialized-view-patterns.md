# 物化视图的各种实现模式

从定时全量刷新到流式增量维护——各引擎对查询加速与数据新鲜度之间 trade-off 的不同选择。

## 支持矩阵

| 引擎 | 支持 | 刷新模式 | 查询改写 | 版本 |
|------|------|---------|---------|------|
| Oracle | 完整支持 | Complete / Fast / Force | 自动 Query Rewrite | 8i+ |
| PostgreSQL | 基本支持 | REFRESH [CONCURRENTLY] | 不支持 | 9.3+ |
| SQL Server | Indexed Views | 自动维护（同步） | 自动（Enterprise） | 2000+ |
| BigQuery | 完整支持 | 自动刷新 | 智能查询改写 | GA |
| Snowflake | 完整支持 | 自动刷新 | 自动 | Enterprise+ |
| ClickHouse | 特殊实现 | INSERT 触发 | 不支持 | 早期 |
| Databricks | 完整支持 | 自动/手动 | 自动 | Runtime 12.2+ |
| Doris | 完整支持 | 自动/手动 | 自动 | 2.0+ |
| StarRocks | 完整支持 | 自动/手动 | 自动 | 2.4+ |
| Materialize | 流式 MV | 增量维护（实时） | 自动 | GA |
| MySQL | 不支持 | - | - | 需手动模拟 |
| SQLite | 不支持 | - | - | - |
| MariaDB | 不支持 | - | - | - |

## 基本概念

物化视图（Materialized View）是预计算并存储结果的视图。与普通视图（只存定义、每次查询时执行）不同，物化视图**实际存储数据**。

```
普通视图:    定义 → 查询时执行 → 实时结果
物化视图:    定义 → 预计算存储 → 查询时直接读取 → 需要刷新机制
```

核心 trade-off：**查询性能** vs **数据新鲜度** vs **存储/计算成本**。

## 各引擎详解

### Oracle（最完善的实现）

Oracle 的物化视图系统是业界最成熟的，提供多种刷新策略和自动查询改写。

```sql
-- 创建物化视图
CREATE MATERIALIZED VIEW mv_sales_summary
BUILD IMMEDIATE                          -- 创建时立即填充
REFRESH FAST ON COMMIT                   -- 基表提交时增量刷新
ENABLE QUERY REWRITE                     -- 允许优化器自动使用
AS
SELECT dept_id, SUM(amount) AS total, COUNT(*) AS cnt
FROM sales
GROUP BY dept_id;

-- 刷新模式:
-- COMPLETE: 全量重算 (TRUNCATE + INSERT AS SELECT)
-- FAST: 增量刷新 (只处理变更数据，需要 materialized view log)
-- FORCE: 优先 FAST，不行就 COMPLETE

-- 刷新时机:
-- ON COMMIT: 基表事务提交时自动刷新 (实时但有性能开销)
-- ON DEMAND: 手动或定时刷新

-- 增量刷新的前提: 创建物化视图日志
CREATE MATERIALIZED VIEW LOG ON sales
WITH ROWID, SEQUENCE (dept_id, amount)
INCLUDING NEW VALUES;

-- 手动刷新
EXEC DBMS_MVIEW.REFRESH('mv_sales_summary', 'F');  -- F=FAST, C=COMPLETE

-- 定时刷新
CREATE MATERIALIZED VIEW mv_daily_stats
REFRESH COMPLETE
START WITH SYSDATE
NEXT SYSDATE + 1    -- 每天刷新一次
AS SELECT ...;

-- 查询改写 (Query Rewrite): 用户查基表，优化器自动读 MV
SELECT dept_id, SUM(amount)   -- 查的是 sales 表
FROM sales
GROUP BY dept_id;
-- 优化器检测到 mv_sales_summary 可以回答这个查询
-- 自动改写为: SELECT dept_id, total FROM mv_sales_summary
```

### PostgreSQL（基本但实用）

```sql
-- 创建物化视图
CREATE MATERIALIZED VIEW mv_sales_summary AS
SELECT dept_id,
    SUM(amount) AS total_amount,
    COUNT(*) AS order_count,
    AVG(amount) AS avg_amount
FROM sales
GROUP BY dept_id;

-- 全量刷新（阻塞读取）
REFRESH MATERIALIZED VIEW mv_sales_summary;

-- 并发刷新（不阻塞读取，但需要 UNIQUE INDEX）
CREATE UNIQUE INDEX ON mv_sales_summary (dept_id);
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_sales_summary;
-- CONCURRENTLY 在后台构建新数据，完成后原子切换
-- 刷新期间旧数据仍可读取

-- PostgreSQL 的局限:
-- 1. 无增量刷新（每次都全量重算）
-- 2. 无自动刷新（需要外部调度: pg_cron, crontab 等）
-- 3. 无查询改写（用户必须显式查询 MV）

-- 常用的自动刷新方案: pg_cron
SELECT cron.schedule('refresh_mv', '*/5 * * * *',
    'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_sales_summary');

-- 查看物化视图状态
SELECT schemaname, matviewname, ispopulated
FROM pg_matviews;
```

### SQL Server（Indexed Views）

SQL Server 的"物化视图"叫 Indexed Views，设计哲学完全不同——通过在视图上建聚集索引实现自动同步维护。

```sql
-- 创建 Indexed View (物化视图的 SQL Server 实现)
-- 1. 视图必须绑定 schema
CREATE VIEW dbo.vw_sales_summary
WITH SCHEMABINDING         -- 必须! 防止基表结构变更
AS
SELECT dept_id,
    SUM(amount) AS total_amount,
    COUNT_BIG(*) AS order_count   -- 必须用 COUNT_BIG
FROM dbo.sales
GROUP BY dept_id;

-- 2. 在视图上创建唯一聚集索引 → 物化!
CREATE UNIQUE CLUSTERED INDEX IX_vw_sales ON dbo.vw_sales_summary(dept_id);

-- 创建聚集索引后:
-- - 视图数据被物化存储
-- - 基表的 INSERT/UPDATE/DELETE 自动同步更新视图
-- - Enterprise Edition: 优化器自动使用视图 (即使查基表)
-- - Standard Edition: 需要 WITH (NOEXPAND) 提示

-- 显式使用 (Standard Edition)
SELECT dept_id, total_amount
FROM dbo.vw_sales_summary WITH (NOEXPAND);

-- Indexed Views 的限制:
-- - 不能包含 OUTER JOIN, UNION, 子查询, DISTINCT
-- - 聚合只能用 SUM 和 COUNT_BIG
-- - 必须 SCHEMABINDING
-- - 每次基表写入都有维护开销
```

### BigQuery（自动管理）

```sql
-- 创建物化视图
CREATE MATERIALIZED VIEW mv_sales_summary
AS
SELECT dept_id,
    SUM(amount) AS total_amount,
    COUNT(*) AS order_count
FROM sales
GROUP BY dept_id;

-- BigQuery 自动管理:
-- 1. 自动刷新: 基表数据变更后自动增量更新（通常几分钟内）
-- 2. 智能查询改写: 查基表时自动使用 MV
-- 3. 零维护: 无需手动调度

-- 手动刷新 (可选)
CALL BQ.REFRESH_MATERIALIZED_VIEW('project.dataset.mv_sales_summary');

-- 查询时自动使用 MV (用户感知不到)
SELECT dept_id, SUM(amount) FROM sales GROUP BY dept_id;
-- BigQuery 优化器: "mv_sales_summary 可以回答，直接读 MV"

-- 最大新鲜度配置
CREATE MATERIALIZED VIEW mv_sales
OPTIONS (max_staleness = INTERVAL '4' HOUR)
AS SELECT ...;
-- 允许最多 4 小时的延迟，减少刷新频率
```

### ClickHouse（独特的 INSERT 触发模型）

ClickHouse 的物化视图与传统 MV 完全不同——它本质上是一个 INSERT 触发器：

```sql
-- ClickHouse 物化视图 = INSERT 触发器
CREATE MATERIALIZED VIEW mv_sales_summary
ENGINE = SummingMergeTree()
ORDER BY dept_id
AS
SELECT dept_id,
    sum(amount) AS total_amount,
    count() AS order_count
FROM sales
GROUP BY dept_id;

-- 工作原理:
-- 1. 每当 INSERT INTO sales 时，触发 MV 的 SELECT
-- 2. SELECT 的结果 INSERT INTO mv_sales_summary
-- 3. SummingMergeTree 引擎自动合并相同 dept_id 的行

-- 关键区别:
-- - 只处理新 INSERT 的数据，不扫描历史数据
-- - 不处理 UPDATE/DELETE (ClickHouse 本身也很少用)
-- - 创建 MV 时不回填历史数据!
-- - MV 本身是一个独立的表，有自己的引擎和存储

-- 带目标表的写法（更灵活）
CREATE TABLE mv_target (
    dept_id UInt32,
    total_amount Decimal(18,2),
    order_count UInt64
) ENGINE = SummingMergeTree()
ORDER BY dept_id;

CREATE MATERIALIZED VIEW mv_sales TO mv_target
AS SELECT dept_id, sum(amount) AS total_amount, count() AS order_count
FROM sales GROUP BY dept_id;

-- 回填历史数据（需要手动）
INSERT INTO mv_target
SELECT dept_id, sum(amount), count() FROM sales GROUP BY dept_id;
```

### Materialize（流式增量维护）

```sql
-- Materialize: 物化视图是核心产品
-- 连接外部数据流
CREATE SOURCE orders_source
FROM KAFKA BROKER 'kafka:9092' TOPIC 'orders'
FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY 'http://schema-registry:8081';

-- 创建增量维护的物化视图
CREATE MATERIALIZED VIEW live_dashboard AS
SELECT
    region,
    COUNT(*) AS order_count,
    SUM(amount) AS total_revenue,
    AVG(amount) AS avg_order_value
FROM orders_source
GROUP BY region;

-- 特点:
-- 1. 实时增量更新（毫秒级延迟）
-- 2. 基于 differential dataflow 算法
-- 3. 支持复杂查询: JOIN, 窗口函数, 子查询
-- 4. 查询结果始终反映最新数据
```

### MySQL（手动模拟）

```sql
-- MySQL 不支持物化视图，需要手动实现

-- 方案 1: 辅助表 + 定时任务
CREATE TABLE mv_sales_summary (
    dept_id INT PRIMARY KEY,
    total_amount DECIMAL(18,2),
    order_count INT,
    last_refreshed TIMESTAMP
);

-- 刷新存储过程
DELIMITER //
CREATE PROCEDURE refresh_mv_sales()
BEGIN
    TRUNCATE TABLE mv_sales_summary;
    INSERT INTO mv_sales_summary
    SELECT dept_id, SUM(amount), COUNT(*), NOW()
    FROM sales
    GROUP BY dept_id;
END //
DELIMITER ;

-- 定时调用 (MySQL Event Scheduler)
CREATE EVENT refresh_mv_every_hour
ON SCHEDULE EVERY 1 HOUR
DO CALL refresh_mv_sales();

-- 方案 2: 触发器维护（实时但有性能开销）
CREATE TRIGGER trg_sales_insert AFTER INSERT ON sales
FOR EACH ROW
BEGIN
    INSERT INTO mv_sales_summary (dept_id, total_amount, order_count)
    VALUES (NEW.dept_id, NEW.amount, 1)
    ON DUPLICATE KEY UPDATE
        total_amount = total_amount + NEW.amount,
        order_count = order_count + 1;
END;
```

## 设计分析: 刷新策略对比

| 策略 | 数据新鲜度 | 写入开销 | 实现复杂度 | 代表引擎 |
|------|-----------|---------|-----------|---------|
| 全量刷新 | 刷新时才更新 | 刷新时高 | 低 | PostgreSQL |
| 同步增量 | 实时 | 每次写入都有 | 高 | SQL Server Indexed Views |
| 异步增量 | 秒~分钟级 | 低（批量处理） | 高 | Oracle FAST, BigQuery |
| INSERT 触发 | 写入时 | 中（只处理新增） | 中 | ClickHouse |
| 流式维护 | 毫秒级 | 持续消耗 | 最高 | Materialize |
| 定时全量 | 调度间隔 | 刷新时高 | 低 | PostgreSQL + pg_cron |

### 查询改写 (Query Rewrite) 的价值

查询改写是物化视图最有价值的能力之一：用户查基表，优化器自动使用 MV。

```sql
-- 用户写的查询
SELECT dept_id, SUM(amount) FROM sales WHERE year = 2024 GROUP BY dept_id;

-- 如果存在 MV 包含 dept_id, year, SUM(amount)
-- 优化器改写为
SELECT dept_id, SUM(total_amount)
FROM mv_sales_by_dept_year WHERE year = 2024
GROUP BY dept_id;
```

查询改写需要满足的条件：

1. MV 的列能覆盖查询需要的所有列
2. MV 的 GROUP BY 粒度不粗于查询的 GROUP BY
3. MV 的数据足够新鲜（或用户可以接受的新鲜度）

## 对引擎开发者的实现建议

### 1. 全量刷新的实现

最简单的方案，适合 MVP 版本：

```
REFRESH MATERIALIZED VIEW mv:
    1. 创建临时表 tmp
    2. INSERT INTO tmp AS SELECT ... (MV 的定义查询)
    3. 原子性交换: RENAME mv → mv_old, tmp → mv
    4. DROP mv_old
```

CONCURRENTLY 变体需要增量 diff：

```
REFRESH MATERIALIZED VIEW CONCURRENTLY mv:
    1. 执行 MV 的定义查询，得到新结果集
    2. 与现有 MV 数据做 diff (需要 UNIQUE INDEX)
    3. 应用 INSERT/UPDATE/DELETE 到 MV
    4. 整个过程不阻塞读取（读取旧数据直到完成）
```

### 2. 增量刷新的实现

增量刷新需要捕获基表变更（change capture）：

```
方案 A: 变更日志 (Oracle Materialized View Log)
    基表维护 INSERT/UPDATE/DELETE 日志
    刷新时只处理日志中的变更

方案 B: 时间戳过滤
    MV 记录上次刷新时间 T
    刷新时: 处理 WHERE updated_at > T 的行

方案 C: LSN/WAL 位点
    MV 记录上次处理的 WAL 位点
    刷新时: 重放 WAL 中后续的变更
```

### 3. 查询改写的实现

查询改写在优化器中作为一个规则：

```
输入: 用户查询 Q
对每个物化视图 MV:
    1. 检查 MV 是否能回答 Q (subsumption test)
    2. 如果能，构造改写后的查询 Q'
    3. 估算 Q' 的成本，与原始 Q 比较
    4. 选择成本更低的方案
```

subsumption test 的核心判断：
- MV 的 FROM 表是否包含 Q 需要的表
- MV 的 WHERE 条件是否弱于 Q 的条件
- MV 的 GROUP BY 粒度是否不粗于 Q 的粒度
- MV 的 SELECT 列是否包含 Q 需要的列

## 参考资料

- Oracle: [Materialized Views](https://docs.oracle.com/en/database/oracle/oracle-database/19/dwhsg/basic-materialized-views.html)
- PostgreSQL: [MATERIALIZED VIEW](https://www.postgresql.org/docs/current/sql-creatematerializedview.html)
- SQL Server: [Indexed Views](https://learn.microsoft.com/en-us/sql/relational-databases/views/create-indexed-views)
- BigQuery: [Materialized Views](https://cloud.google.com/bigquery/docs/materialized-views-intro)
- ClickHouse: [Materialized Views](https://clickhouse.com/docs/en/guides/developer/cascading-materialized-views)
- Materialize: [Materialized Views](https://materialize.com/docs/sql/create-materialized-view/)
