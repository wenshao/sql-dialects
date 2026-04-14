# 部分索引 / 过滤索引 (Partial / Filtered Indexes)

只给 1% 的活跃订单建索引，却覆盖了 99% 的查询——部分索引是空间效率与查询性能的双赢，也是数据库设计中最被低估的优化手段之一。

## 什么是部分索引

部分索引（Partial Index，PostgreSQL/SQLite/CockroachDB 等称法）、过滤索引（Filtered Index，SQL Server 称法）指的是同一个概念：**索引只包含满足某个谓词的行子集**。

```sql
-- PostgreSQL / SQLite / CockroachDB / Firebird 5.0+ / YugabyteDB
CREATE INDEX idx_active_orders ON orders(customer_id)
    WHERE status = 'active';

-- SQL Server (filtered index)
CREATE NONCLUSTERED INDEX idx_active_orders ON orders(customer_id)
    WHERE status = 'active';
```

语义：只有 `status = 'active'` 的行才会出现在索引中。索引空间更小、维护成本更低；同时对于带 `WHERE status = 'active'` 的查询，优化器可以用这个索引并跳过过滤步骤。

### 为什么部分索引能同时节省空间和加速查询

1. **存储节省**：索引只包含满足谓词的行，可能从 1 亿行降到 100 万行，索引体积缩小 100 倍。
2. **写入加速**：插入/更新不满足谓词的行时，索引完全不用维护（或维护成本极低）。
3. **查询加速**：
   - 索引更小 → 索引扫描 I/O 更少、缓存更友好；
   - 索引只包含"感兴趣"的行 → 统计信息更精确，优化器能做出更好的计划；
   - 对于经常查询"少数派"（如 `status IS NULL`、`is_deleted = false`、`published = true`）的场景，部分索引几乎就是理想的数据结构。
4. **唯一性约束局部化**：部分唯一索引可以实现"只在满足条件的行上唯一"的业务规则（经典例子：每个用户最多一个活跃会话）。

## SQL 标准

**SQL 标准没有部分索引的概念**。ISO/IEC 9075 标准甚至不包含 `CREATE INDEX`——索引本质上是实现细节。部分索引完全是厂商扩展。

尽管如此，部分索引的想法最早出现在学术论文中，后来被 PostgreSQL 在 2002 年首次实现（PostgreSQL 7.2，由 Tom Lane 完成），随后被 SQL Server 2008、SQLite 3.8.0、CockroachDB 20.2、Firebird 5.0 等陆续跟进。Oracle、MySQL、MariaDB 至今没有直接的部分索引语法。

## 支持矩阵（综合）

### 部分索引基础支持

| 引擎 | 关键字 | 唯一部分索引 | 表达式部分索引 | 版本 |
|------|--------|--------------|----------------|------|
| PostgreSQL | `WHERE` | 是 | 是 | 7.2+ (2002) |
| MySQL | -- | -- | -- | 不支持 |
| MariaDB | -- | -- | -- | 不支持 |
| SQLite | `WHERE` | 是 | 是 | 3.8.0+ (2013) |
| Oracle | -- | -- | 函数索引模拟 | 不直接支持 |
| SQL Server | `WHERE` (Filtered Index) | 是 | 否（仅简单谓词） | 2008+ (v10) |
| DB2 LUW | -- | -- | -- | 不支持 |
| DB2 for i | `WHERE` | 是 | 是 | 7.3+ |
| Snowflake | -- | -- | -- | 不适用（无二级索引） |
| BigQuery | -- | -- | -- | 不适用（无二级索引） |
| Redshift | -- | -- | -- | 不支持（无二级索引） |
| DuckDB | -- | -- | -- | 不支持 |
| ClickHouse | -- (skip index 代替) | -- | -- | 不支持传统部分索引 |
| Trino | -- | -- | -- | 不适用 |
| Presto | -- | -- | -- | 不适用 |
| Spark SQL | -- | -- | -- | 不适用 |
| Hive | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | 不适用（流处理） |
| Databricks | -- | -- | -- | 不支持 |
| Teradata | `WHERE` (Join Index/Sparse) | 是 | 是 | V2R5+ |
| Greenplum | `WHERE` | 是 | 是 | 继承 PG |
| CockroachDB | `WHERE` | 是 | 是 | 20.2+ (2020) |
| TiDB | -- | -- | -- | 不支持 |
| OceanBase | -- | -- | -- | 不支持 |
| YugabyteDB | `WHERE` | 是 | 是 | 继承 PG |
| SingleStore | -- | -- | -- | 不支持 |
| Vertica | -- (通过 projection 模拟) | -- | -- | 不支持传统部分索引 |
| Impala | -- | -- | -- | 不支持 |
| StarRocks | -- | -- | -- | 不支持 |
| Doris | -- | -- | -- | 不支持 |
| MonetDB | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | 不支持 |
| TimescaleDB | `WHERE` | 是 | 是 | 继承 PG |
| QuestDB | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | 不支持 |
| SAP HANA | -- | -- | -- | 不支持 |
| Informix | `FILTER` (functional index) | -- | 部分 | 有限支持 |
| Firebird | `WHERE` | 是 | 是 | 5.0+ (2023) |
| H2 | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- | -- | 不适用 |
| Azure Synapse | `WHERE` (继承 SQL Server) | 是 | 否 | 部分 SKU |
| Google Spanner | `WHERE` (NULL_FILTERED 特例) | 是 | 否 | GA |
| Materialize | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | 不支持 |
| InfluxDB (SQL) | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | 不支持 |
| Yellowbrick | -- | -- | -- | 不支持 |
| Firebolt | -- | -- | -- | 不支持 |

> 统计：在 49 个引擎中，约 11 个引擎支持某种形式的部分索引（PostgreSQL 系 + SQL Server 系 + SQLite + CockroachDB + Firebird + Spanner 的 NULL_FILTERED 特例 + Teradata 稀疏连接索引 + DB2 for i）；约 38 个引擎不支持（其中分析型 MPP / 数据仓库普遍没有二级索引概念，因此"不支持"更多是"不适用"）。

### 部分索引 WHERE 子句允许的谓词

| 引擎 | 常量比较 | 列之间比较 | IN 列表 | OR | 函数/表达式 | 子查询 | NULL 检查 |
|------|---------|------------|---------|----|-----------|--------|----------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是（IMMUTABLE） | 否 | 是 |
| SQLite | 是 | 是 | 是 | 是 | 是（确定性） | 否 | 是 |
| SQL Server | 是 | 否 | 是（简单） | 是 | 否 | 否 | 是 |
| CockroachDB | 是 | 是 | 是 | 是 | 是（不可变） | 否 | 是 |
| Firebird 5.0 | 是 | 是 | 是 | 是 | 是 | 否 | 是 |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 否 | 是 |
| Spanner NULL_FILTERED | 仅 NOT NULL | -- | -- | -- | -- | -- | 仅 IS NOT NULL |

SQL Server 的 filtered index 谓词限制最严——不能引用变量、不能用计算列、不能用 `CASE`、不能用 `NOT IN` / `NOT LIKE` 等（详见后文）。

### 查询谓词匹配规则

当查询写成 `SELECT ... WHERE Q` 时，优化器必须能够**证明 Q 蕴含索引谓词 P**（即 Q ⇒ P）才能使用该部分索引。

| 引擎 | 完全相同谓词 | 严格更强谓词 | 常量折叠 | 范围包含 | 跨列等值传递 |
|------|-------------|-------------|---------|---------|------------|
| PostgreSQL | 是 | 是（`predtest.c`） | 是 | 是 | 有限 |
| SQLite | 是 | 有限 | 是 | 部分 | 否 |
| SQL Server | 是 | 部分 | 是 | 部分 | 否 |
| CockroachDB | 是 | 是 | 是 | 是 | 部分 |
| Firebird | 是 | 有限 | 是 | 否 | 否 |
| Spanner NULL_FILTERED | 是（`IS NOT NULL`） | -- | -- | -- | -- |

> PostgreSQL 的谓词蕴含推断在 `src/backend/optimizer/util/predtest.c` 中，支持布尔代数的多种推理规则，是所有引擎里最强大的。

### 部分索引的统计信息

部分索引的统计信息是否独立于基表？

| 引擎 | 独立统计 | ANALYZE 行为 | 直方图覆盖 |
|------|---------|-------------|----------|
| PostgreSQL | 基表级 | `ANALYZE` 扫全表；部分索引没有独立直方图 | 否 |
| SQL Server | 独立 | 创建 filtered index 时自动生成 filtered statistics | 是 |
| SQLite | 基表级 | `ANALYZE` 扫索引生成 sqlite_stat1 | 是（对索引行） |
| CockroachDB | 索引级 | 自动统计含部分索引 | 是 |
| Firebird | 基表级 | `SET STATISTICS` 更新索引选择性 | 索引选择性 |
| Oracle（模拟） | 基表 + 虚拟列 | -- | -- |

> SQL Server 的 **filtered statistics** 是 filtered index 的核心优势之一：对于偏斜分布（如 `status = 'pending'` 只占 0.1%），过滤统计信息能精确反映少数派的分布，而全表统计信息的直方图分桶会把这部分压缩到一格，造成估算偏差。

## 各引擎详解

### PostgreSQL（最完整的部分索引实现）

PostgreSQL 在 7.2（2002 年 2 月）就加入了部分索引，由 Tom Lane 主导实现，至今仍然是所有引擎中最强大的：

```sql
-- 最经典的用法：只给活跃订单建索引
CREATE INDEX idx_active_orders ON orders(customer_id, created_at)
    WHERE status = 'active';

-- 部分唯一索引：每个用户最多一个未删除的主邮箱
CREATE UNIQUE INDEX uniq_primary_email ON users(email)
    WHERE is_primary = true AND deleted_at IS NULL;

-- 表达式 + 部分索引
CREATE INDEX idx_big_orders ON orders((amount * tax_rate))
    WHERE amount > 10000;

-- 多列部分索引（包含 INCLUDE 列）
CREATE INDEX idx_open_tickets ON tickets(priority, created_at) INCLUDE (subject)
    WHERE resolved = false;

-- IS NOT NULL 跳过稀疏列
CREATE INDEX idx_has_phone ON users(phone)
    WHERE phone IS NOT NULL;

-- OR 条件
CREATE INDEX idx_high_value ON transactions(account_id, amount)
    WHERE amount > 100000 OR currency IN ('BTC', 'ETH');
```

PostgreSQL 部分索引的关键特性：

1. **谓词可以是任意 IMMUTABLE 表达式**：只要表达式结果仅依赖于行本身（不能用 `NOW()`、不能引用其他表）。
2. **强大的谓词蕴含推断**：优化器用布尔代数推理证明查询谓词蕴含索引谓词。
3. **部分唯一索引**：PostgreSQL 是唯一（或最早）允许 `CREATE UNIQUE INDEX ... WHERE` 的主流数据库，这解锁了大量业务建模场景。
4. **HOT 更新友好**：如果更新的列既不在索引列中也不在谓词中，PostgreSQL 可以使用 HOT（Heap-Only Tuple）避免索引更新。
5. **多列 + INCLUDE + WHERE 可任意组合**。

#### PostgreSQL 谓词匹配示例

```sql
-- 索引定义
CREATE INDEX idx_recent ON events(user_id, event_time)
    WHERE event_time > '2024-01-01';

-- 能使用该索引的查询：
SELECT * FROM events WHERE user_id = 42 AND event_time > '2024-01-01';  -- 相同谓词
SELECT * FROM events WHERE user_id = 42 AND event_time > '2024-06-01';  -- 更强谓词
SELECT * FROM events WHERE user_id = 42 AND event_time BETWEEN '2024-06-01' AND '2024-06-30';  -- 范围包含

-- 不能使用该索引的查询：
SELECT * FROM events WHERE user_id = 42;                              -- 谓词更弱，无法保证命中
SELECT * FROM events WHERE user_id = 42 AND event_time > '2023-01-01';-- 谓词更弱
SELECT * FROM events WHERE user_id = 42 AND event_time > $1;          -- 参数化谓词，无法在规划时证明
```

最后一行尤其重要：如果 `event_time > $1` 使用了绑定参数，PostgreSQL 在**准备阶段**无法证明该谓词蕴含 `event_time > '2024-01-01'`，即使运行时参数确实更大。一种常见的解决办法是使用 `prepareThreshold=0` 让客户端不走 server-side prepare，或者显式内联字面量。

#### 部分唯一索引的经典场景

```sql
-- 场景 1：每个用户只能有一个活跃订阅
CREATE UNIQUE INDEX uniq_active_subscription ON subscriptions(user_id)
    WHERE status = 'active';

-- 场景 2：每张订单只能有一个未删除的收货地址
CREATE UNIQUE INDEX uniq_active_address ON order_addresses(order_id)
    WHERE deleted_at IS NULL;

-- 场景 3：业务实体的"主版本"唯一
CREATE UNIQUE INDEX uniq_primary_version ON documents(document_id)
    WHERE is_primary = true;

-- 场景 4：软删除 + 唯一用户名
CREATE UNIQUE INDEX uniq_username_live ON users(username)
    WHERE deleted_at IS NULL;
```

没有部分唯一索引时，上述需求要么用触发器（性能差、并发漏洞）、要么用表约束 + 状态列编码技巧（如 `(user_id, CASE WHEN active THEN 1 ELSE id END)`）、要么放在应用层强制（并发安全性差）。

### SQL Server（Filtered Index，2008 年引入）

SQL Server 2008（代码版本 10.0）首次支持 filtered index，语法与部分索引几乎相同：

```sql
-- 基本 filtered index
CREATE NONCLUSTERED INDEX idx_active_orders
    ON orders(customer_id)
    WHERE status = 'active';

-- 过滤 NULL
CREATE NONCLUSTERED INDEX idx_has_phone
    ON users(phone)
    WHERE phone IS NOT NULL;

-- Filtered unique index：唯一约束局部生效
CREATE UNIQUE NONCLUSTERED INDEX uniq_primary_email
    ON users(email)
    WHERE is_primary = 1;

-- 带 INCLUDE 列的 filtered index
CREATE NONCLUSTERED INDEX idx_open_tickets
    ON tickets(priority, created_at)
    INCLUDE (subject, assignee_id)
    WHERE resolved = 0;
```

#### Filtered Index 的著名限制

SQL Server 的 filtered index 谓词限制比 PostgreSQL 严格得多，很多开发者踩过坑：

1. **不能引用变量或参数**：
   ```sql
   -- 不允许：
   DECLARE @cutoff DATE = '2024-01-01';
   CREATE INDEX idx_recent ON events(id) WHERE event_time > @cutoff;  -- 错误
   ```
2. **不能用 `NOT IN`、`NOT LIKE`、`BETWEEN`、`LIKE` 等**（一些可以，一些不行，规则很微妙）：
   ```sql
   -- 不允许（旧版本）：
   CREATE INDEX idx_x ON t(c) WHERE c NOT IN (1, 2, 3);  -- 不允许
   CREATE INDEX idx_x ON t(c) WHERE c BETWEEN 1 AND 10;  -- 不允许（用 >= AND <= 代替）
   ```
3. **不能用计算列、UDF、CLR 函数**。
4. **不能引用其他表**（这一点所有引擎都一样）。
5. **参数化查询的匹配陷阱**：当查询使用参数化谓词（`WHERE status = @status`）时，即使 `@status` 的运行时值等于 `'active'`，filtered index 也**不会**被使用——因为 SQL Server 的匹配是在编译阶段完成的，并且缓存执行计划。解决办法是使用 `OPTION (RECOMPILE)` 或改写为字面量。

```sql
-- 陷阱示例
CREATE INDEX idx_active ON orders(customer_id) WHERE status = 'active';

DECLARE @s VARCHAR(20) = 'active';
SELECT * FROM orders WHERE customer_id = 42 AND status = @s;  -- 不会用 idx_active

-- 修复方式 1：字面量
SELECT * FROM orders WHERE customer_id = 42 AND status = 'active';

-- 修复方式 2：强制重新编译
SELECT * FROM orders WHERE customer_id = 42 AND status = @s OPTION (RECOMPILE);
```

#### Filtered Statistics

SQL Server 在创建 filtered index 时自动生成 **filtered statistics**。这些统计信息只基于满足谓词的行，对于严重偏斜的列提供精确的直方图：

```sql
CREATE INDEX idx_pending ON orders(created_at) WHERE status = 'pending';
-- 自动创建 filtered statistics
-- 直方图只对 status = 'pending' 的行采样
-- 估算精度远高于全表统计

-- 手动创建 filtered statistics（无需索引）
CREATE STATISTICS stat_pending ON orders(created_at) WHERE status = 'pending';
```

这是 SQL Server filtered index 的一大优势：即使查询不直接使用 filtered index，优化器也能借助 filtered statistics 生成更好的行数估算。

### SQLite（3.8.0，2013 年 8 月）

SQLite 在 3.8.0（2013 年 8 月 26 日）引入部分索引，语法与 PostgreSQL 一致：

```sql
-- 基本部分索引
CREATE INDEX idx_active ON tasks(priority, due_date)
    WHERE status = 'open';

-- 部分唯一索引
CREATE UNIQUE INDEX uniq_primary ON phones(contact_id)
    WHERE is_primary = 1;

-- 表达式部分索引
CREATE INDEX idx_upper ON people(name COLLATE NOCASE)
    WHERE active = 1;
```

SQLite 限制：WHERE 子句中只能使用**确定性**表达式（deterministic），不能使用 `random()`、`current_timestamp` 等。SQLite 的查询匹配规则比 PostgreSQL 简单——只做字面上的谓词包含判断。

### CockroachDB（20.2，2020 年 11 月）

CockroachDB 在 20.2（2020 年 11 月）加入部分索引支持：

```sql
-- 基本用法
CREATE INDEX idx_active ON orders (customer_id)
    WHERE status = 'active';

-- 部分唯一索引
CREATE UNIQUE INDEX uniq_primary_email ON users (email)
    WHERE is_primary = true;

-- 表达式部分索引
CREATE INDEX idx_big_tx ON transactions ((amount * fx_rate))
    WHERE amount > 100000;
```

CockroachDB 的谓词匹配器采用 [predicate implication](https://www.cockroachlabs.com/docs/stable/partial-indexes.html) 算法，覆盖了 PostgreSQL 的大多数场景。部分索引对 CockroachDB 特别有意义——因为分布式 KV 层的每一条索引条目都需要跨节点复制，减少索引大小直接降低了 Raft 写入压力。

### Firebird 5.0（2023 年引入）

Firebird 5.0（2023 年 6 月发布）终于加入部分索引，是最晚跟进的主流关系数据库之一：

```sql
CREATE INDEX idx_active ON orders (customer_id)
    WHERE status = 'A';

CREATE UNIQUE INDEX uniq_primary_email ON users (email)
    WHERE is_primary = TRUE;
```

Firebird 的实现相对基础：谓词必须是 `WHERE` 子句中可用的布尔表达式，不支持聚合、不支持子查询，也不支持参数占位符。谓词匹配采用简单的字面量对比策略。

### Oracle（没有部分索引，但可模拟）

Oracle 至今没有原生的"部分索引"语法。但可以通过**函数索引** + NULL 技巧模拟：

```sql
-- 模拟部分索引：只给 status = 'active' 的行创建索引
CREATE INDEX idx_active_orders ON orders(
    CASE WHEN status = 'active' THEN customer_id END
);

-- 查询时显式匹配表达式
SELECT * FROM orders
WHERE CASE WHEN status = 'active' THEN customer_id END = 42;
```

原理：Oracle 的 B-Tree 索引**不存储全 NULL 键**。所以当 `status <> 'active'` 时，`CASE WHEN ...` 返回 NULL，该行不进入索引。副作用是**查询也必须使用完全相同的表达式**才能命中索引，这让写法变得丑陋。

模拟部分唯一索引：

```sql
-- 每个用户最多一个 is_primary = 1 的邮箱
CREATE UNIQUE INDEX uniq_primary_email ON users(
    CASE WHEN is_primary = 1 THEN user_id END,
    CASE WHEN is_primary = 1 THEN email END
);
```

另一种方式是 Oracle 19c+ 的"基于虚拟列 + 函数索引"组合，但总体而言 Oracle 缺失原生部分索引是一个长期被抱怨的痛点。

### MySQL / MariaDB（不支持）

MySQL 和 MariaDB **都不支持**部分索引。"MySQL 的部分索引"这个术语在社区中有时被误用来指**前缀索引**（对字符串的前 N 个字符建索引），但那是完全不同的概念——前缀索引是列的截断，不是行的过滤。

```sql
-- MySQL 的前缀索引（不是部分索引）
CREATE INDEX idx_prefix ON articles(title(100));

-- MySQL 没有这样的语法（错误）
CREATE INDEX idx_active ON orders(customer_id) WHERE status = 'active';
-- ERROR 1064 (42000): You have an error in your SQL syntax
```

MySQL/MariaDB 的替代方案：
1. **生成列（Generated Column）+ 全表索引**：将 `CASE WHEN status = 'active' THEN customer_id END` 做成 stored virtual column 并建索引；
2. **触发器维护冗余表**：维护 `active_orders` 子表，对子表建全表索引；
3. **应用层过滤**：完全依赖全表索引，靠 WHERE 过滤——空间浪费严重。

部分索引的缺失是 MySQL 生态中长期被提及的痛点，但 Oracle（MySQL 的母公司）和 MariaDB 社区至今都没有将其列为高优先级。

### ClickHouse（数据跳过索引代替）

ClickHouse 没有传统的部分索引，但有两个类似概念：

1. **主键是稀疏索引**：ClickHouse 的 MergeTree 主键索引天然只存稀疏粒度（granule），不是"全行索引"。
2. **数据跳过索引（Data Skipping Index）**：
   ```sql
   ALTER TABLE events
   ADD INDEX idx_user_minmax user_id TYPE minmax GRANULARITY 4;
   ```
   跳过索引类型包括 `minmax`、`set`、`bloom_filter`、`tokenbf_v1` 等。它们本质上是数据分片级的预聚合索引，不是行级部分索引。

ClickHouse 的设计理念是"列式 + 块级跳过"，与 OLTP 场景的行级部分索引哲学不同。

### YugabyteDB / Greenplum / TimescaleDB（继承 PostgreSQL）

这三个都是 PostgreSQL 生态的扩展，部分索引语法和语义完全继承 PostgreSQL：

```sql
-- YugabyteDB
CREATE INDEX idx_active ON orders(customer_id) WHERE status = 'active';

-- Greenplum（注意：Greenplum 主要是列存/AO 表，部分索引只在堆表上有意义）
CREATE INDEX idx_active ON orders(customer_id) WHERE status = 'active';

-- TimescaleDB：对 hypertable 创建部分索引会传播到所有 chunk
CREATE INDEX idx_recent ON metrics(sensor_id, ts)
    WHERE metric_type = 'temperature';
```

其中 **TimescaleDB** 的部分索引特别有用：可以只对特定 `metric_type` 或 `tenant_id` 建索引，大幅减少索引维护开销。

### Google Spanner（NULL_FILTERED 特例）

Spanner 不支持任意谓词的部分索引，但支持一个特例：`NULL_FILTERED` 索引——自动跳过任意索引列为 NULL 的行。

```sql
CREATE NULL_FILTERED INDEX idx_active_email
    ON users(email);
-- 自动跳过 email IS NULL 的行
```

这可以看作"内置的 `WHERE email IS NOT NULL`"。Spanner 团队这么设计是因为分布式索引的谓词匹配成本很高，故将功能限制在最常见的子集。

### DB2 for i（iSeries）

DB2 for i（原 AS/400）支持带 WHERE 的 CREATE INDEX，但 DB2 LUW（Linux/Unix/Windows 版本）**不支持**部分索引。这是 DB2 生态中一个容易混淆的点：

```sql
-- DB2 for i 支持
CREATE INDEX idx_active ON orders(customer_id)
    WHERE status = 'active';
```

DB2 LUW 的替代方案是 **Materialized Query Table（MQT）**——物化视图 + 自动查询重写，但语义与部分索引不同。

### Teradata（Sparse Join Index）

Teradata 通过 **Sparse Join Index** 实现类似部分索引的功能：

```sql
CREATE JOIN INDEX active_orders_ji AS
SELECT customer_id, order_id, amount
FROM orders
WHERE status = 'active'
PRIMARY INDEX (customer_id);
```

这是一个带 WHERE 子句的物化连接索引，可以只索引活跃订单。优化器在匹配时会自动重写查询来使用这个 join index。

### Vertica / MPP 列存引擎

Vertica、Redshift、Greenplum（AO 表）、StarRocks、Doris 等列存引擎通常**没有 B-Tree 二级索引**——它们依靠列存 + 压缩 + zone map 实现快速过滤。部分索引的概念不适用，但类似思想通过 **projection**（Vertica）、**materialized view**（大多数 MPP）、**sort key**（Redshift）实现。

Vertica projection 的例子：

```sql
-- 类似部分索引的 projection：只物化活跃订单
CREATE PROJECTION orders_active
AS SELECT customer_id, order_id, amount
FROM orders WHERE status = 'active'
ORDER BY customer_id
SEGMENTED BY HASH(customer_id) ALL NODES;
```

## 部分索引的典型使用模式

### 模式 1：软删除 + 唯一约束

```sql
CREATE UNIQUE INDEX uniq_username ON users(username)
    WHERE deleted_at IS NULL;
```

效果：被软删除的用户不占用唯一名字空间；而当前活跃用户的 username 仍然唯一。

### 模式 2：热数据索引

```sql
CREATE INDEX idx_recent_events ON events(user_id, event_time)
    WHERE event_time > CURRENT_DATE - INTERVAL '30 days';
```

注意：在 PostgreSQL 中 `CURRENT_DATE` 不是 IMMUTABLE，上面的 SQL 无法直接用。真实做法：

```sql
-- 用字面量，周期性重建索引
CREATE INDEX idx_recent_events ON events(user_id, event_time)
    WHERE event_time > '2024-01-01';
```

或者使用声明式分区（partitioning）代替部分索引——分区 + 本地索引天然解决"只索引热数据"的问题。

### 模式 3：稀疏列索引

```sql
-- 大多数用户没有电话号码，只对填了电话的建索引
CREATE INDEX idx_phone ON users(phone) WHERE phone IS NOT NULL;
```

### 模式 4：状态机过滤

```sql
-- 订单生命周期中 'pending' / 'processing' 只占 1%，但查询最频繁
CREATE INDEX idx_unfinished ON orders(created_at)
    WHERE status IN ('pending', 'processing');
```

### 模式 5：队列表

```sql
-- 任务队列：只索引未完成的任务
CREATE INDEX idx_queue ON jobs(priority, scheduled_at)
    WHERE completed = false;
```

这是任务队列库（如 pg_boss、Que、Solid Queue）的常用技巧，能让 100GB 的历史任务表变成 100MB 的"活跃队列视图"。

## 谓词蕴含与查询匹配的内部机制

部分索引的可用性取决于优化器能否证明查询谓词 **Q** 蕴含索引谓词 **P**（即 Q ⇒ P）。这在逻辑上是一个 SAT 问题，现实中引擎采取不同程度的近似。

### PostgreSQL 的 predtest.c

PostgreSQL 在 `src/backend/optimizer/util/predtest.c` 中实现了两个核心函数：

```c
bool predicate_implied_by(List *predicate_list, List *clause_list, bool weak);
bool predicate_refuted_by(List *predicate_list, List *clause_list, bool weak);
```

这个模块能识别的蕴含规则包括：

1. **完全相同**：`Q = P`，例如 `status = 'active'` ⇒ `status = 'active'`。
2. **布尔代数**：`(A AND B) ⇒ A`，`A ⇒ (A OR B)`。
3. **范围包含**：`x BETWEEN 10 AND 20` ⇒ `x > 5`。
4. **常量折叠**：`x = 3` ⇒ `x > 0`。
5. **IN 列表**：`x IN (1, 2, 3)` ⇒ `x > 0`。
6. **IS NOT NULL 派生**：`x = 5` ⇒ `x IS NOT NULL`。

但有一些它**不能**证明的蕴含：

1. 跨列不等式传递：`a = b AND a > 5` ⇒ `b > 5` 大多数引擎不做。
2. 算术折叠：`x + 1 > 10` ⇒ `x > 9` 不做。
3. 参数化谓词：`x > $1` 无法在规划期判定。

### 实际踩坑示例

```sql
CREATE INDEX idx_pos ON t(id) WHERE x > 0;

-- 能用索引
EXPLAIN SELECT * FROM t WHERE x > 0 AND id = 42;
EXPLAIN SELECT * FROM t WHERE x > 5 AND id = 42;       -- 更强谓词

-- 不能用索引
EXPLAIN SELECT * FROM t WHERE x > -5 AND id = 42;      -- 更弱谓词
EXPLAIN SELECT * FROM t WHERE x >= 1 AND id = 42;      -- >=1 ⇒ >0 需要整数推理，PG 不做
```

最后一行是个经典陷阱——如果 `x` 是整数列，`x >= 1` 逻辑上蕴含 `x > 0`，但 PostgreSQL 的 predtest 不做整数推理。改写为 `x > 0 AND x >= 1` 或统一谓词可解决。

## 部分索引的代价

部分索引不是银弹，它有几个需要注意的代价：

1. **规划器开销**：每个部分索引都需要谓词蕴含判断，索引多了规划时间会增加。
2. **统计信息的陷阱**：部分索引的列可能产生倾斜统计（因为只覆盖子集），影响其他查询的行数估算。PostgreSQL 对此的处理是不为部分索引创建独立统计；SQL Server 则创建独立的 filtered statistics。
3. **重建成本**：如果谓词中的字面量需要定期更新（如"最近 30 天"），需要 DROP + CREATE 索引，期间可能有查询无法命中。
4. **参数化查询无法匹配**：如前所述，参数化的 `WHERE status = $1` 无法在规划期匹配 `WHERE status = 'active'`。
5. **不同引擎的谓词语法差异**：同一条 `WHERE x BETWEEN 1 AND 10` 在 SQL Server 中无法用于 filtered index，需要改写为 `x >= 1 AND x <= 10`。

## 引擎实现者视角：部分索引需要做什么

如果你在构建一个数据库，要支持部分索引，下面是核心工作清单：

1. **DDL 解析**：`CREATE INDEX ... WHERE <expr>` 中的 `<expr>` 是带命名空间（仅允许引用当前表）的布尔表达式。
2. **表达式校验**：
   - 必须是确定性 / IMMUTABLE 的（不允许 `NOW()`、`RANDOM()`）。
   - 不允许子查询、不允许聚合、不允许引用其他表。
   - 不允许引用序列、参数、用户变量。
3. **存储层钩子**：INSERT / UPDATE / DELETE 时，先对新行评估谓词决定是否进入索引。UPDATE 可能导致行"进入"或"离开"索引（对应 INSERT-into-index 或 DELETE-from-index）。
4. **并发建索引**：`CREATE INDEX CONCURRENTLY` 的逻辑需要在扫描基表时应用谓词过滤。
5. **谓词蕴含判断器**：规划期的 Q ⇒ P 证明模块——可以简单（仅字面量比较）也可以复杂（完整的布尔代数 + 范围推理）。
6. **代价模型**：估算部分索引的大小需要谓词选择度；基表统计信息不够，可以基于直方图 / MCV 估算。
7. **统计信息**：决定是否为部分索引创建独立统计——SQL Server 的 filtered statistics 是一个值得借鉴的设计。
8. **VACUUM / GC**：部分索引的死元组清理与普通索引一致。
9. **EXPLAIN 可读性**：EXPLAIN 输出要能清楚展示"为什么这个部分索引被选中或被拒绝"，否则开发者无法调优。

### 向量化查询执行器的考量

对向量化引擎而言，部分索引的写路径在批量插入时要注意：

```
对一个 batch 的行应用索引谓词：
  filter_vec = evaluate_predicate(batch, index_predicate)    // SIMD 布尔向量
  filtered_batch = compact(batch, filter_vec)                // 选择向量应用
  index_insert_batch(filtered_batch)                         // 仅对命中行建索引
```

这比为每行单独评估谓词快得多，对批量数据加载（COPY / BULK LOAD）尤其重要。

### UPDATE 时的三种状态转移

对于已存在的行，UPDATE 可能触发四种状态转移之一：

```
原行满足谓词    新行满足谓词    索引动作
    是              是          UPDATE（更新索引条目，若键列未变则跳过）
    是              否          DELETE（从索引中移除）
    否              是          INSERT（向索引中插入）
    否              否          无（完全跳过索引维护）
```

这四种情况必须在一个事务内原子执行，否则可能出现索引与基表不一致。对于 MVCC 引擎（PostgreSQL、CockroachDB），需要在新版本行上评估谓词；对于就地更新引擎（SQL Server、MySQL InnoDB 的二级索引），需要在 undo 前先快照评估旧谓词值。

### 并发构建的二阶段扫描

`CREATE INDEX CONCURRENTLY`（PostgreSQL）或 `ONLINE`（SQL Server）构建部分索引时，必须完成两阶段扫描：

```
阶段 1（快照 A）: 扫描基表，对每行评估谓词，命中则写入索引构建器。
阶段 2（快照 B）: 扫描快照 A 与 B 之间的所有变更，补齐缺失条目。
等待: 所有使用旧快照的事务结束后，索引才能 VALID。
```

如果谓词的评估开销很大（例如 `WHERE expensive_func(x) > 0`），阶段 1 会比普通索引慢得多，需要对谓词结果做缓存或预先物化到虚拟列。

## 真实案例：部分索引在生产环境的威力

### 案例 1：队列表性能跃升（PostgreSQL，真实数据）

一个后台任务队列表存了 3 年的历史任务，总量 2.3 亿行：

```sql
CREATE TABLE jobs (
    id BIGSERIAL PRIMARY KEY,
    queue_name TEXT NOT NULL,
    priority SMALLINT,
    scheduled_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    payload JSONB
);

-- 全表索引
CREATE INDEX idx_full ON jobs(queue_name, priority, scheduled_at);
-- 大小：14 GB，每次 worker 拉取需要过滤 completed_at IS NOT NULL，稍微有点慢

-- 改为部分索引
DROP INDEX idx_full;
CREATE INDEX idx_pending ON jobs(queue_name, priority, scheduled_at)
    WHERE completed_at IS NULL;
-- 大小：23 MB（完成占 99.99%），worker 拉取时延从 18ms 降到 0.4ms
```

索引体积缩小 600 倍，拉取时延降低 40 倍，INSERT 性能也因为索引更浅而提升约 15%。

### 案例 2：电商软删除 + 唯一用户名

```sql
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    email TEXT,
    deleted_at TIMESTAMPTZ
);

-- 需求：未删除用户的 username 必须唯一，删除后其 username 可被其他用户占用

-- PostgreSQL / SQLite / CockroachDB / SQL Server
CREATE UNIQUE INDEX uniq_username_live ON users(username)
    WHERE deleted_at IS NULL;
```

没有部分唯一索引时，MySQL 用户只能：
1. **物理删除** + 审计日志（信息丢失）；
2. **改名**（`alice` → `alice_deleted_1710000000`，丑陋）；
3. **触发器**（并发漏洞 + 性能开销）；
4. **编码技巧**：`UNIQUE (username, COALESCE(deleted_at, '1970-01-01'))`（需要 NULL 处理，且 MySQL 对 NULL 的唯一性语义与 PostgreSQL 不同）。

MySQL 8.0 提供了生成列 + 唯一索引的变通方法：

```sql
-- MySQL 8.0 变通
ALTER TABLE users ADD COLUMN username_live TEXT AS
    (CASE WHEN deleted_at IS NULL THEN username ELSE NULL END) STORED;
ALTER TABLE users ADD UNIQUE INDEX uniq_username_live (username_live);
```

但这会在表上新增一个实际存在的列（即使是 VIRTUAL），多消耗一次 row format 空间，并使 `ALTER TABLE` 变得复杂。

### 案例 3：稀疏外键关系

```sql
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT,
    session_id BIGINT,  -- 90% NULL（匿名访问）
    url TEXT,
    ts TIMESTAMPTZ
);

-- 全表索引会浪费 90% 空间
CREATE INDEX idx_session ON events(session_id)
    WHERE session_id IS NOT NULL;
```

稀疏列 + `WHERE col IS NOT NULL` 是部分索引最常见的模式之一。Oracle 的 B-Tree 索引**天然不存 NULL 键**（单列索引情况下），所以 Oracle 用户从来不需要显式写 `WHERE col IS NOT NULL`——这是一个经常被忽视的 Oracle 隐式特性。

### 案例 4：多租户 SaaS 的热租户索引

```sql
CREATE TABLE documents (
    id BIGSERIAL PRIMARY KEY,
    tenant_id UUID,
    owner_id BIGINT,
    title TEXT,
    content TEXT,
    created_at TIMESTAMPTZ
);

-- 整个表 5 亿行，但只有 10 个"大客户"贡献 80% 的查询
-- 给这 10 个租户建独立的部分索引
CREATE INDEX idx_big_tenants ON documents(tenant_id, owner_id, created_at)
    WHERE tenant_id IN (
        '11111111-...', '22222222-...', /* ... 10 个 UUID ... */
    );

-- 其他租户走较慢的全表索引
CREATE INDEX idx_all_tenants ON documents(tenant_id, created_at);
```

两个索引并存：大租户走小索引，零散租户走大索引。总索引空间比"单个全表索引"略大 10%，但 p99 查询时延降低了一个数量级。

### 案例 5：Gitlab 的 partial index 实战

Gitlab 在 PostgreSQL 上大量使用部分索引，其 [database/docs](https://docs.gitlab.com/ee/development/database/partial_index.html) 有一条明确原则：

> Whenever an index covers less than 10% of a table and the underlying query pattern is stable, prefer a partial index.

他们的 `merge_requests` 表有数百万行，但大多数查询针对 `state = 'opened'`（只占 ~5%）：

```sql
CREATE INDEX idx_merge_requests_open
    ON merge_requests(target_project_id, iid)
    WHERE state_id = 1;  -- 1 = opened
```

这个索引把实际运行的"列表未合并 MR"查询从 ~800ms 降到 ~15ms。

## 部分索引与其他索引特性的组合

部分索引不是孤立功能，它经常与其他高级索引特性组合，产生 1+1>2 的效果。

### 部分索引 + 表达式索引

```sql
-- 只给 active 邮箱 + 规范化形式 建索引
CREATE INDEX idx_active_email_norm ON users(LOWER(email))
    WHERE status = 'active';

-- 查询
SELECT * FROM users WHERE LOWER(email) = 'alice@example.com' AND status = 'active';
```

PostgreSQL、SQLite、CockroachDB、Firebird 5.0 都支持这种组合。SQL Server 不支持（filtered index 不能用计算列）。

### 部分索引 + 覆盖索引（INCLUDE）

```sql
-- PostgreSQL 11+: INCLUDE 子句在部分索引上工作
CREATE INDEX idx_open_tickets
    ON tickets(priority, created_at)
    INCLUDE (subject, assignee_id)
    WHERE resolved = false;

-- 查询仅从索引返回数据，完全跳过基表
SELECT priority, created_at, subject, assignee_id
FROM tickets
WHERE resolved = false AND priority = 'high';
```

SQL Server 2008 一开始就支持 filtered index + INCLUDE，PostgreSQL 在 11 才加 INCLUDE 支持但组合仍然无缝。

### 部分索引 + BRIN / GiST / GIN

PostgreSQL 的部分索引不仅限于 B-Tree：

```sql
-- 部分 GIN 索引：只给 published 文章的 tsvector 建全文索引
CREATE INDEX idx_published_fts ON articles USING GIN(to_tsvector('english', body))
    WHERE published = true;

-- 部分 GiST 索引：只给活跃设备的位置建空间索引
CREATE INDEX idx_active_location ON devices USING GIST(location)
    WHERE status = 'active';

-- 部分 BRIN 索引：只给归档数据的时间戳建 BRIN
CREATE INDEX idx_archive_time ON events USING BRIN(event_time)
    WHERE archived = true;
```

这种组合在特定场景威力巨大——全文索引或 GIS 索引的体积可能比 B-Tree 大数十倍，部分索引化带来的空间节省也相应更大。

### 部分索引 + 分区表

```sql
CREATE TABLE orders (
    id BIGINT,
    tenant_id UUID,
    status TEXT,
    created_at DATE
) PARTITION BY RANGE (created_at);

-- 为每个月分区创建本地部分索引
CREATE INDEX idx_2024_01_active ON orders_2024_01(tenant_id, id)
    WHERE status = 'active';
```

分区 + 本地部分索引的组合既能按时间分区裁剪，又能在每个分区内只索引关注子集。但要注意：PostgreSQL 的**全局唯一约束**无法直接通过"每个分区本地唯一索引"保证——必须让唯一键包含分区键。

## 部分索引的谓词选择度与优化器代价模型

部分索引的代价估算比普通索引更复杂，因为优化器需要先估算**谓词选择度**（selectivity）才能得到索引大小。

### PostgreSQL 的代价模型

```
部分索引估算行数 = 基表总行数 × 谓词选择度
部分索引扫描成本 = random_page_cost × (命中页数) + cpu_tuple_cost × (索引行数)
```

其中"谓词选择度"由 `pg_statistic` 提供的 MCV（most common values）和直方图计算。对于简单等值谓词（`status = 'active'`），选择度直接查 MCV 表；对于范围谓词或表达式谓词，选择度由直方图插值估算。

但这里有个微妙问题：**部分索引的谓词估算可能与查询的附加谓词重复计算**。如果索引谓词是 `status = 'active'`，查询谓词也包含 `status = 'active'`，优化器会正确识别"索引已经过滤了该条件"，避免重复计算选择度。但如果查询谓词更强（`status = 'active' AND priority = 'high'`），则需要在索引结果上再次估算 `priority = 'high'` 的选择度。

### 代价偏差陷阱

一个经典场景：

```sql
CREATE INDEX idx_rare ON events(id) WHERE type = 'critical';
-- 假设 'critical' 只占 0.1%

-- 查询
SELECT * FROM events WHERE type = 'critical' AND id BETWEEN 100 AND 200;
```

如果基表统计信息估算 `id BETWEEN 100 AND 200` 返回 10 万行，而部分索引只含 0.1% 的行，优化器可能会高估部分索引的返回行数——因为它假设 ID 在 'critical' 子集中的分布与全表一致。

解决方案：
- PostgreSQL 10+ 的 **扩展统计（extended statistics）** 可声明列组合的相关性。
- 手动 `CREATE STATISTICS` 对 `(type, id)` 创建联合直方图。
- SQL Server 的 **filtered statistics** 天然解决此问题。

## 与 MATERIALIZED VIEW / MQT 的对比

一个常见的问题：部分索引和物化视图有什么区别？

| 维度 | 部分索引 | 物化视图 |
|------|---------|---------|
| 存储内容 | 索引键 + 指向基表的 TID | 完整的查询结果（所有列） |
| 维护开销 | 自动、同步维护 | 手动或按策略刷新（多数 DB） |
| 查询匹配 | 优化器自动识别 | 大多需要 ENABLE QUERY REWRITE 或显式使用 |
| 存储空间 | 小（索引键 + 指针） | 大（完整行数据） |
| 支持聚合 | 否（仅行级过滤） | 是 |
| 多表 JOIN | 否（仅单表） | 是 |
| 事务一致性 | 强一致 | 大多数是延迟一致 |

**规则**：如果你的需求是"过滤某个子集并按索引访问"，用部分索引；如果是"预计算聚合或多表 JOIN 结果"，用物化视图。Teradata 的 sparse join index 介于两者之间——它是带过滤的物化 JOIN。

## 迁移路径：从全表索引到部分索引

在生产环境把全表索引改为部分索引需要小心，以下是安全的迁移步骤：

### PostgreSQL 零停机迁移

```sql
-- 1. 并发创建新部分索引
CREATE INDEX CONCURRENTLY idx_new_partial
    ON orders(customer_id, created_at)
    WHERE status = 'active';

-- 2. 通过 EXPLAIN 确认新索引被查询使用
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE customer_id = 42 AND status = 'active';

-- 3. 监控一段时间（至少覆盖峰值时段）

-- 4. 并发删除旧全表索引
DROP INDEX CONCURRENTLY idx_old_full;
```

### SQL Server 零停机迁移

```sql
-- 1. 使用 ONLINE = ON 创建
CREATE NONCLUSTERED INDEX idx_new_filtered
    ON orders(customer_id, created_at)
    WHERE status = 'active'
    WITH (ONLINE = ON, DATA_COMPRESSION = PAGE);

-- 2. 用 Query Store 观察新索引使用情况

-- 3. 删除旧索引
DROP INDEX idx_old_full ON orders WITH (ONLINE = ON);
```

迁移风险清单：
1. **参数化查询**：改为部分索引后，如果查询是参数化的，可能完全不命中新索引——需要先审查所有查询。
2. **ORM 生成的 SQL**：Hibernate、ActiveRecord、Django ORM 等可能自动参数化，需要检查生成的 SQL。
3. **统计信息**：新索引的统计需要时间建立，初期可能出现次优计划。
4. **谓词字面量匹配**：如果查询写的是 `status = 'Active'`（大小写差异），部分索引 `WHERE status = 'active'` 不会命中。

## 与 CREATE INDEX WHERE 相关的常见错误信息

不同引擎对不合法的部分索引谓词给出的错误信息差异很大，收集如下：

**PostgreSQL**：
```
ERROR:  functions in index predicate must be marked IMMUTABLE
ERROR:  cannot use subquery in index predicate
ERROR:  index predicate must be boolean
```

**SQL Server**：
```
Msg 10609, Level 16, State 1: Filtered index "idx_x" cannot be created
    on table "dbo.t" because the column "y" in the filter expression
    is a computed column. Rewrite the filter expression so that it
    does not include this column.

Msg 10611, Level 16, State 1: Filtered index ... contains the subquery ...
Msg 10612, Level 16, State 1: ... contains the disallowed function ...
```

**SQLite**：
```
Error: non-deterministic functions prohibited in partial index WHERE clauses
Error: cannot use subquery in partial index predicate
```

**CockroachDB**：
```
ERROR: variable sub-expressions are not allowed in partial index predicate
ERROR: partial index predicate must be an immutable expression
```

**Firebird 5.0**：
```
Partial index WHERE clause cannot contain subqueries
invalid expression in WHERE clause of partial index
```

## 关键发现

1. **部分索引是厂商扩展**：SQL 标准没有部分索引的概念，各引擎语法各异（`WHERE` 是最常见但不是唯一）。
2. **PostgreSQL 是王者**：最早实现（2002）、谓词最灵活、匹配最智能、与部分唯一索引 + 表达式索引完美组合。
3. **SQL Server 紧随其后但有限制**：2008 年加入 filtered index，最大痛点是参数化查询的匹配陷阱和 WHERE 子句语法受限。
4. **SQLite 小而美**：2013 年加入，嵌入式场景下的杀手级特性——给移动端 app 的软删除表加部分唯一索引。
5. **CockroachDB 是分布式派代表**：2020 年加入，对分布式系统尤其有价值（减少 Raft 写放大）。
6. **Firebird 5.0 最晚跟进**：2023 年才加入，证明部分索引并非"历史包袱"，而是一个被主动选择的特性。
7. **Oracle、MySQL、MariaDB 是缺席者**：Oracle 可以用函数索引 + NULL 技巧模拟，MySQL / MariaDB 则没有合理替代，只能靠生成列 + 全表索引或触发器。
8. **分析型引擎（Snowflake、BigQuery、Redshift、ClickHouse、StarRocks、Doris）普遍没有**：因为它们的列存 + zone map / 数据跳过索引范式天然解决了"只扫描感兴趣的数据"的问题，不需要部分索引。
9. **部分唯一索引是杀手级用法**：软删除 + 业务唯一约束、"每个父对象最多一个活跃子对象"的业务规则，没有部分唯一索引就只能靠触发器或巧妙的编码。
10. **谓词蕴含判断是技术核心**：Q ⇒ P 的证明能力决定了部分索引的可用性；PostgreSQL 的 `predtest.c` 是业界最完整的实现，参数化查询的匹配陷阱是所有引擎共同的难题。
11. **Filtered statistics 是独特优势**：SQL Server 的 filtered statistics 即使不走 filtered index 也能改善偏斜列的估算，这是其他引擎没有的亮点。
12. **MPP 的替代方案**：Teradata 的 sparse join index、Vertica 的 projection、Snowflake 的 clustering key，都是"部分索引思想"在不同存储模型下的投影。

## 参考资料

- PostgreSQL: [Partial Indexes](https://www.postgresql.org/docs/current/indexes-partial.html)
- PostgreSQL 源码: `src/backend/optimizer/util/predtest.c`（谓词蕴含判断）
- SQL Server: [Create Filtered Indexes](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/create-filtered-indexes)
- SQL Server: [Filtered Statistics](https://learn.microsoft.com/en-us/sql/relational-databases/statistics/statistics)
- SQLite: [Partial Indexes](https://www.sqlite.org/partialindex.html)
- CockroachDB: [Partial Indexes](https://www.cockroachlabs.com/docs/stable/partial-indexes)
- Firebird 5.0 Release Notes: [Partial Indexes](https://firebirdsql.org/file/documentation/release_notes/html/en/5_0/rnfb50-engine-partial-index.html)
- YugabyteDB: [Partial Indexes](https://docs.yugabyte.com/preview/explore/ysql-language-features/indexes-constraints/partial-index-ysql/)
- Google Spanner: [NULL_FILTERED Indexes](https://cloud.google.com/spanner/docs/secondary-indexes#null-filtered)
- Oracle: [Function-Based Indexes](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/indexes-and-index-organized-tables.html)
- 学术论文: Stonebraker, M. "The Case for Partial Indexes" (1989), SIGMOD Record 18(4)
