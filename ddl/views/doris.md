# Apache Doris: 视图与物化视图

 Apache Doris: 视图与物化视图

 参考资料:
   [1] Doris Documentation - CREATE VIEW / MATERIALIZED VIEW
       https://doris.apache.org/docs/sql-manual/sql-statements/

## 1. 设计哲学: 物化视图是 OLAP 引擎的核心优化手段

 在 OLAP 引擎中，视图的价值不在于逻辑封装(传统 RDBMS 用途)，
 而在于物化视图的查询加速——用空间换时间，预计算常用聚合。

 Doris 视图体系:
   普通视图    → 逻辑封装(不存储数据)
   同步物化视图 → 单表聚合加速(与基表同步)，本质上是 ROLLUP 的增强
   异步物化视图 → 多表 JOIN 加速(定时/事件刷新)，2.1+ 支持

 对比:
   StarRocks: 同步 + 异步 MV，CBO 自动改写更成熟
   ClickHouse: MV 是 INSERT 触发器语义，不自动改写查询
   BigQuery:  MV 自动刷新 + 自动改写，用户体验最好
   MySQL:     不支持物化视图(需手动维护汇总表)
   PostgreSQL: REFRESH MATERIALIZED VIEW(手动/定时刷新)

## 2. 普通视图

```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users WHERE age >= 18;

CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users WHERE age >= 18;

CREATE VIEW IF NOT EXISTS active_users AS
SELECT id, username, email, created_at
FROM users WHERE age >= 18;

```

 设计分析:
   Doris 视图不可更新(只读)。与 MySQL 不同——MySQL 简单视图可更新。
   Doris 不支持 WITH CHECK OPTION(因为视图不可更新)。

## 3. 同步物化视图 (Sync MV / ROLLUP 增强)

```sql
CREATE MATERIALIZED VIEW mv_order_agg AS
SELECT user_id, SUM(amount) AS total_amount, COUNT(*) AS order_count
FROM orders GROUP BY user_id;

```

 设计分析:
   同步 MV 与基表绑定——基表导入数据时自动更新 MV。
   优化器透明改写: 查询 SELECT SUM(amount) FROM orders GROUP BY user_id
   会自动路由到 mv_order_agg，无需修改 SQL。

   限制: 仅单表聚合，聚合函数受限(SUM/MIN/MAX/COUNT/BITMAP_UNION/HLL_UNION)。
   与 ROLLUP 的区别: 同步 MV 可以包含表达式，ROLLUP 只能选列。

 对比:
   StarRocks: 同步 MV 完全相同(同源)
   ClickHouse: MaterializedView 在 INSERT 时触发，目标表独立存在

## 4. 异步物化视图 (Async MV，2.1+)

```sql
CREATE MATERIALIZED VIEW mv_order_detail
BUILD IMMEDIATE
REFRESH AUTO
ON SCHEDULE EVERY 1 HOUR
AS
SELECT o.user_id, u.username, SUM(o.amount) AS total
FROM orders o JOIN users u ON o.user_id = u.id
GROUP BY o.user_id, u.username;

```

手动刷新

```sql
REFRESH MATERIALIZED VIEW mv_order_detail;

```

 设计分析:
   异步 MV 是 Doris 2.1 的重要特性:
     支持多表 JOIN(同步 MV 不支持)
     支持定时刷新(ON SCHEDULE) 和自动刷新(REFRESH AUTO)
     BUILD IMMEDIATE = 创建时立即构建数据

   查询改写: 优化器可自动将查询路由到异步 MV(2.1+ 支持)。
   但 StarRocks 的自动改写能力更成熟(CBO 更强)。

 对比:
   StarRocks 2.4+: 异步 MV + CBO 自动改写(更成熟)
   BigQuery:       MV 自动刷新，费用按增量刷新计算

## 5. 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP MATERIALIZED VIEW mv_order_agg ON orders;        -- 同步 MV
DROP MATERIALIZED VIEW mv_order_detail;                -- 异步 MV

```

## 6. 物化视图设计决策 (对引擎开发者)

 物化视图的核心挑战:
1. 增量刷新: 如何只更新变化的数据(而不是全量重建)

2. 查询改写: 如何判断一个查询可以路由到 MV(等价判断)

3. 一致性: 刷新延迟期间，查询结果是否准确


Doris 的实现:
- **同步 MV**: 随基表写入同步更新 → 强一致但限制多
- **异步 MV**: 定时/事件刷新 → 最终一致但灵活

StarRocks 的优势:
- **CBO 改写更成熟**: 支持更多 SQL 模式的自动改写
- **外部表 MV**: 可以基于 Hive/Iceberg 外部表创建 MV

对引擎开发者的启示:
物化视图的查询改写是最难的部分——本质上是"查询等价判断"问题。
StarRocks 的实现基于 SQL 代数规则(列映射 + 谓词推导)。
BigQuery 使用更激进的策略——允许"近似匹配"(freshness 参数)。
