# Spanner: 视图

> 参考资料:
> - [Spanner Documentation - CREATE VIEW](https://cloud.google.com/spanner/docs/reference/standard-sql/data-definition-language#create_view)
> - [Spanner Documentation - Views](https://cloud.google.com/spanner/docs/views)
> - [Spanner Documentation - STORING Index](https://cloud.google.com/spanner/docs/secondary-indexes#storing-columns)
> - [Spanner Documentation - Change Streams](https://cloud.google.com/spanner/docs/change-streams)
> - [Spanner Documentation - Query Syntax](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## 基本视图

Spanner 视图必须指定 SQL SECURITY INVOKER（调用者权限模型）

```sql
CREATE VIEW active_users
SQL SECURITY INVOKER
AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

```

CREATE OR REPLACE VIEW
```sql
CREATE OR REPLACE VIEW active_users
SQL SECURITY INVOKER
AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

```

视图中的列别名
```sql
CREATE VIEW user_summary
SQL SECURITY INVOKER
AS
SELECT id AS uid, username AS name, email AS mail
FROM users;

```

## SQL SECURITY INVOKER 说明

Spanner 视图强制要求 SQL SECURITY 子句:
  SQL SECURITY INVOKER: 使用调用视图的用户权限执行底层查询
  这意味着: 用户必须有底层表的 SELECT 权限才能查询视图

**对比:** 其他数据库:
  Spanner:      强制 INVOKER（无 DEFINER 选项）
  MySQL:        默认 DEFINER，可选 SQL SECURITY INVOKER
  PostgreSQL:   默认调用者权限（OWNER 仅影响视图的所有权）
  SQL Server:   视图默认使用调用者权限
  Oracle:       视图使用定义者权限（默认）

## STORING 索引与视图的交互

Spanner 的 STORING 索引可以替代部分物化视图的场景。
STORING 允许在二级索引中 "物化" 额外的列数据。

创建带 STORING 的索引
```sql
CREATE INDEX idx_users_by_city ON users(city)
    STORING (username, email, age);
```

STORING 子句将 username/email/age 数据冗余存储在索引中
查询只需访问索引，不需要回读基表（index-only scan）

视图可以利用 STORING 索引加速
```sql
CREATE VIEW users_by_city
SQL SECURITY INVOKER
AS
SELECT city, username, email, age
FROM users
WHERE city IS NOT NULL;
```

此视图的查询可被 idx_users_by_city 的 STORING 列完全覆盖
Spanner 优化器会自动选择 index-only scan

STORING 索引 vs 物化视图对比:
  STORING 索引:
    - 自动与基表同步（强一致性）
    - 增加写入成本（每次写入需更新索引）
    - 存储成本较高（冗余列数据）
    - 适合固定查询模式的加速
  物化视图:
    - Spanner 不支持（STORING 索引是替代方案）
    - 其他数据库（Oracle/PostgreSQL）可异步刷新
    - 适合聚合查询（COUNT/SUM 等）

STORING 的设计 trade-off:
  优点: 查询时避免回读基表（减少一次 RPC）
  缺点: 写入时需要更新更多数据（索引 + STORING 列）
  最佳实践: 只 STORING 高频查询需要的列

## Change Streams（变更流）

Spanner 的 Change Streams 是实时数据变更捕获机制，
可以配合视图实现类似物化视图的增量更新效果。

创建 Change Stream（捕获 users 表的变更）
```sql
CREATE CHANGE STREAM users_stream
FOR users
OPTIONS (retention_period = '7d');
```

监控 users 表的所有 INSERT/UPDATE/DELETE
retention_period: 变更记录保留 7 天

创建监控所有表的 Change Stream
```sql
CREATE CHANGE STREAM all_changes
FOR ALL
OPTIONS (retention_period = '3d');

```

通过 Change Streams API 读取变更（伪代码）:
## 应用读取 Change Stream 获取增量变更

## 将变更应用到汇总表（模拟物化视图）

## 视图基于汇总表查询


实现模式:
```sql
CREATE TABLE mv_user_stats (          -- 模拟物化视图的汇总表
    user_id     INT64 NOT NULL,
    order_count INT64 NOT NULL DEFAULT 0,
    total_amount FLOAT64 NOT NULL DEFAULT 0,
    last_updated TIMESTAMP,
) PRIMARY KEY (user_id);

CREATE VIEW user_stats_view           -- 视图封装查询逻辑
SQL SECURITY INVOKER
AS
SELECT user_id, order_count, total_amount
FROM mv_user_stats
WHERE order_count > 0;

```

Change Streams + 汇总表 vs 传统物化视图:
  Change Streams: 实时增量更新，应用层维护，更灵活
  物化视图:       数据库自动维护，更简单但不灵活
  Spanner 的设计: 牺牲简单性换取可控性（适合大规模分布式场景）

## 交错表与视图

Spanner 的 INTERLEAVE（交错表）是父子表物理邻近存储，
视图可以抽象交错表的查询逻辑。

交错表定义
```sql
CREATE TABLE singers (
    singer_id INT64 NOT NULL,
    name      STRING(255),
) PRIMARY KEY (singer_id);

CREATE TABLE albums (
    singer_id INT64 NOT NULL,
    album_id  INT64 NOT NULL,
    title     STRING(255),
) PRIMARY KEY (singer_id, album_id),
  INTERLEAVE IN PARENT singers ON DELETE CASCADE;

```

视图封装交错表 JOIN
```sql
CREATE VIEW singer_albums
SQL SECURITY INVOKER
AS
SELECT s.singer_id, s.name AS singer_name, a.album_id, a.title AS album_title
FROM singers s
INNER JOIN albums a ON s.singer_id = a.singer_id;

```

## 可更新视图

Spanner 视图不可更新（只读）
不支持 WITH CHECK OPTION
不支持通过视图进行 INSERT / UPDATE / DELETE

## 删除视图

```sql
DROP VIEW active_users;
```

不支持 DROP VIEW IF EXISTS（使用客户端逻辑处理）

## 视图限制

必须指定 SQL SECURITY INVOKER
不支持物化视图（用 STORING 索引 + Change Streams 替代）
不支持 IF NOT EXISTS / IF EXISTS
不支持 WITH CHECK OPTION
视图不可更新
视图中不能使用 DML 语句
视图定义长度有限制

## 设计分析（对 SQL 引擎开发者）

Spanner 的视图设计体现了云原生分布式数据库的理念:

### 为什么 Spanner 不支持物化视图:

  Spanner 是全球分布式数据库，数据跨区域复制
  物化视图的自动维护需要全球同步 → 延迟极高
  替代方案: STORING 索引（同步维护）+ Change Streams（异步维护）
  启发: 分布式数据库应将 "视图维护" 交给应用层（更可控）

### SQL SECURITY INVOKER 强制的设计哲学:

  Spanner 没有视图 "定义者" 概念（避免权限提升风险）
  在多租户场景下，INVOKER 模型更安全
  对比 MySQL DEFINER: 可能导致权限泄露（低权限用户通过视图访问高权限数据）

### 跨方言对比:

  Spanner:      只读视图, INVOKER only, 无物化视图, Change Streams
  BigQuery:     支持物化视图, CREATE OR REPLACE
  CockroachDB:  视图不可更新, 无物化视图
  TiDB:         可更新视图（简单）, MySQL 兼容
  PostgreSQL:   最丰富（物化视图, 可更新视图, WITH CHECK OPTION）
  Oracle:       最完整（物化视图刷新策略, Query Rewrite, 超多选项）

### 版本演进:

  Spanner GA (2017): 基础视图支持
  Spanner 2019+:     CREATE OR REPLACE VIEW
  Spanner 2021+:     Change Streams 功能（替代物化视图的增量更新）
  Spanner 2023+:     Change Streams 支持 ALL 表监控
  Spanner 最新:       持续增强 Change Streams 和视图功能
