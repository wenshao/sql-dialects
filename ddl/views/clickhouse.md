# ClickHouse: 视图（Views）

> 参考资料:
> - [1] ClickHouse Documentation - CREATE VIEW
>   https://clickhouse.com/docs/en/sql-reference/statements/create/view
> - [2] ClickHouse Documentation - Materialized View
>   https://clickhouse.com/docs/en/sql-reference/statements/create/view#materialized-view
> - [3] ClickHouse Blog - Materialized Views Internals
>   https://clickhouse.com/blog/using-materialized-views-in-clickhouse


## 1. 普通视图


```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users WHERE age >= 18;

CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email FROM users WHERE age >= 18;

CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email FROM users WHERE age >= 18;

DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;

```

 普通视图在 ClickHouse 中只是查询别名（query alias），不存储数据。
 与 MySQL/PostgreSQL 的视图行为相同。

## 2. 物化视图: ClickHouse 最独特的核心特性（对引擎开发者）


 ClickHouse 的物化视图与传统数据库的物化视图有本质区别:

 传统物化视图（PostgreSQL/Oracle/BigQuery）:
   基表数据 → 定期全量/增量刷新 → 物化视图表
   需要 REFRESH 操作（手动或定时）

 ClickHouse 物化视图:
   INSERT 到基表 → 触发物化视图的 SELECT → 结果写入目标表
   本质上是 INSERT 触发器 + 子查询 + 写入目标表
   不需要 REFRESH，实时增量更新

 这是根本性的设计差异:
   传统: "拍快照"模式 → 数据可能过期
   ClickHouse: "流处理"模式 → 数据始终最新（对新插入的数据）
   但: 不处理基表的 UPDATE/DELETE（ClickHouse 很少有这些操作）

### 2.1 基本物化视图（隐式目标表）

```sql
CREATE MATERIALIZED VIEW mv_order_summary
ENGINE = SummingMergeTree()
ORDER BY user_id
AS
SELECT user_id, count() AS order_count, sum(amount) AS total_amount
FROM orders
GROUP BY user_id;

```

 INSERT INTO orders 时自动触发:
 (1) 对新 INSERT 的行执行 SELECT user_id, count(), sum(amount) GROUP BY user_id
 (2) 结果写入 mv_order_summary 的内部存储表
 (3) SummingMergeTree 在后台 merge 时自动累加相同 user_id 的行

### 2.2 显式目标表（TO 语法）

```sql
CREATE TABLE order_summary (
    user_id      UInt64,
    order_count  UInt64,
    total_amount Decimal(18,2)
) ENGINE = SummingMergeTree()
ORDER BY user_id;

CREATE MATERIALIZED VIEW mv_to_summary TO order_summary
AS
SELECT user_id, count() AS order_count, sum(amount) AS total_amount
FROM orders
GROUP BY user_id;

```

 TO 语法的优势:
   (a) 多个物化视图可以写入同一个目标表
   (b) DROP VIEW 不会删除目标表的数据
   (c) 可以直接对目标表执行查询和操作
 对比隐式表: DROP VIEW 会同时删除内部存储表和数据

### 2.3 AggregatingMergeTree: 精确增量聚合

```sql
CREATE MATERIALIZED VIEW mv_user_stats
ENGINE = AggregatingMergeTree()
ORDER BY user_id
AS
SELECT
    user_id,
    countState() AS order_count,           -- 聚合状态（不是最终值）
    sumState(amount) AS total_amount,
    uniqState(product_id) AS unique_products
FROM orders
GROUP BY user_id;

```

 查询时需要用 -Merge 后缀函数还原聚合状态:
 SELECT user_id,
        countMerge(order_count),
        sumMerge(total_amount),
        uniqMerge(unique_products)
 FROM mv_user_stats GROUP BY user_id;

 设计分析:
   countState/sumState 存储的是中间聚合状态（partial aggregate），
   不是最终值。这使得增量合并时能正确累加。
   SummingMergeTree 只能处理 SUM/COUNT 这种简单累加，
   AggregatingMergeTree 可以处理 uniq/avg/quantile 等复杂聚合。
   这是 ClickHouse 独有的设计，其他数据库没有类似机制。

### 2.4 POPULATE: 回填历史数据

```sql
CREATE MATERIALIZED VIEW mv_backfill
ENGINE = SummingMergeTree()
ORDER BY user_id
POPULATE                               -- 创建时立即处理基表所有现有数据
AS
SELECT user_id, count() AS cnt FROM orders GROUP BY user_id;

```

 注意: POPULATE 期间新插入到基表的数据可能丢失（竞态条件）
 推荐做法: 先创建不带 POPULATE 的物化视图 → 手动 INSERT ... SELECT 回填

## 3. 物化视图的典型应用模式


### 3.1 实时数据管道（ETL）

原始数据 → 物化视图 A（清洗） → 物化视图 B（聚合）

```sql
CREATE TABLE raw_events (
    timestamp DateTime, event_type String, user_id UInt64, payload String
) ENGINE = MergeTree() ORDER BY timestamp;

CREATE MATERIALIZED VIEW mv_clean TO clean_events AS
SELECT timestamp, event_type, user_id,
       JSONExtractString(payload, 'action') AS action
FROM raw_events WHERE event_type != 'heartbeat';
```

 过滤 + 解析 JSON，实时写入 clean_events

### 3.2 多表扇出（一个 INSERT 触发多个物化视图）

 一张基表可以有任意多个物化视图，每个计算不同的聚合:
 raw_events → mv_hourly_counts（按小时统计）
 raw_events → mv_user_funnel（用户漏斗）
 raw_events → mv_error_alert（错误监控）

## 4. LIVE VIEW（实验性，22.x+）


 SET allow_experimental_live_view = 1;
 CREATE LIVE VIEW lv_user_count AS SELECT count() FROM users;
 WATCH lv_user_count;    -- 实时订阅，基表变化时推送新结果

 LIVE VIEW 是内存缓存 + 推送通知的组合。
 类似 WebSocket 的数据库版本。
 目前是实验性功能，不建议生产使用。

## 5. 对比与引擎开发者启示

ClickHouse 物化视图的核心设计:
(1) INSERT 触发器模式（不是快照刷新）→ 实时增量
(2) 聚合状态函数（countState/sumState）→ 精确增量聚合
(3) 引擎可选（SummingMergeTree/AggregatingMergeTree）→ 灵活
(4) 多视图扇出 → 一次 INSERT 触发多个下游计算

对比其他物化视图实现:
PostgreSQL: REFRESH MATERIALIZED VIEW（全量刷新或 CONCURRENTLY 增量）
BigQuery:   自动刷新（30 分钟间隔），限于单表聚合
Oracle:     ON COMMIT / ON DEMAND 刷新，fast refresh 需要 MV log
ClickHouse: INSERT 触发，最实时但只处理新数据

对引擎开发者的启示:
ClickHouse 的物化视图本质上是"嵌入式流处理引擎":
每个物化视图定义了一个 INSERT → SELECT → INSERT 的数据流。
这使得 ClickHouse 可以替代简单的 Kafka Streams / Flink 作业。
如果设计 OLAP 引擎，这种"INSERT 触发"的物化视图模式值得考虑。

