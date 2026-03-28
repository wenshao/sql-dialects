# StarRocks: 视图与物化视图

> 参考资料:
> - [1] StarRocks - CREATE MATERIALIZED VIEW
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


## 1. StarRocks 物化视图: CBO 自动改写是核心优势

 StarRocks 的物化视图是其相对 Doris 最大的功能优势之一。
 CBO 优化器(Cascades 框架)能自动判断查询是否可路由到 MV。

 对比:
   StarRocks: CBO 自动改写——支持聚合上卷、谓词补偿、JOIN 改写
   Doris:     2.1+ 支持自动改写，但规则和覆盖面弱于 StarRocks
   BigQuery:  自动改写 + 自动刷新，体验最好
   ClickHouse: 不自动改写(MV 是独立的目标表，用户显式查询)
   PostgreSQL: 不自动改写(用户需显式查询 MV)
   MySQL:     不支持物化视图

## 2. 普通视图

```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users WHERE age >= 18;

CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users WHERE age >= 18;

```

 视图不可更新。不支持 WITH CHECK OPTION。

## 3. 同步物化视图

```sql
CREATE MATERIALIZED VIEW mv_order_agg AS
SELECT user_id, SUM(amount) AS total_amount, COUNT(*) AS order_count
FROM orders GROUP BY user_id;

```

 与 Doris 完全相同(同源)。随基表写入同步更新。
 限制: 仅单表聚合。3.0+ 推荐异步 MV 替代。

## 4. 异步物化视图 (2.4+，StarRocks 核心优势)

```sql
CREATE MATERIALIZED VIEW mv_order_detail
REFRESH ASYNC EVERY (INTERVAL 1 HOUR)
AS
SELECT o.user_id, u.username, SUM(o.amount) AS total
FROM orders o JOIN users u ON o.user_id = u.id
GROUP BY o.user_id, u.username;

```

手动刷新

```sql
REFRESH MATERIALIZED VIEW mv_order_detail;

```

 基于外部表的 MV(StarRocks 独有优势):
 CREATE MATERIALIZED VIEW mv_hive_agg
 REFRESH ASYNC EVERY (INTERVAL 1 DAY)
 AS SELECT dt, COUNT(*) FROM hive_catalog.db.events GROUP BY dt;
 将 Hive 数据物化到 StarRocks 本地，查询加速 10-100 倍。

 CBO 自动改写示例(无需修改 SQL):
 用户查询: SELECT user_id, SUM(amount) FROM orders GROUP BY user_id
 优化器自动路由到 mv_order_agg(精确匹配)
 用户查询: SELECT SUM(amount) FROM orders
 优化器从 mv_order_agg 聚合上卷(SUM of SUM)

 刷新策略:
   REFRESH ASYNC: 手动触发
   REFRESH ASYNC EVERY (INTERVAL ...): 定时
   REFRESH ASYNC START('时间') EVERY (INTERVAL ...): 指定首次时间

## 5. 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP MATERIALIZED VIEW mv_order_agg;
DROP MATERIALIZED VIEW mv_order_detail;

```

## 6. StarRocks vs Doris 物化视图对比

 语法差异:
   StarRocks: REFRESH ASYNC EVERY (INTERVAL 1 HOUR)
   Doris:     BUILD IMMEDIATE REFRESH AUTO ON SCHEDULE EVERY 1 HOUR

 CBO 改写:
   StarRocks: 更成熟(聚合上卷、谓词补偿、JOIN 改写)
   Doris:     2.1+ 追赶中

 外部表 MV:
   StarRocks: 支持基于 Hive/Iceberg 外部表创建 MV
   Doris:     2.1+ 支持

 对引擎开发者的启示:
   MV 查询改写的实现本质是"查询包含关系判断":
1. 列映射: MV 列 >= 查询列

2. 谓词包含: MV 的 WHERE 被查询的 WHERE 包含(或无条件)

3. 聚合兼容: SUM 可上卷，COUNT 可上卷(SUM of COUNT)，AVG 不可

4. JOIN 兼容: 查询的 JOIN 图是 MV 的子图

StarRocks 的实现在 fe/optimizer/rule/transformation/materialization/ 目录。

