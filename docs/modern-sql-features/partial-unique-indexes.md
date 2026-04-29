# 部分 UNIQUE 索引 (Partial UNIQUE Indexes)

只在满足条件的行子集上强制唯一性——部分 UNIQUE 索引是软删除、状态机、多版本、租户隔离等业务模型的解锁钥匙，也是 SQL 中"约束 + 索引"两种语义最优雅的合体。

## 什么是部分 UNIQUE 索引

部分 UNIQUE 索引（Partial Unique Index）指的是**只在满足某个谓词的行子集上强制唯一性**的索引：

```sql
-- PostgreSQL / SQLite / CockroachDB / Firebird 5.0+ / YugabyteDB
CREATE UNIQUE INDEX uniq_active_email ON users(email)
    WHERE deleted_at IS NULL;

-- SQL Server (filtered unique index)
CREATE UNIQUE NONCLUSTERED INDEX uniq_active_email ON users(email)
    WHERE deleted_at IS NULL;
```

语义：未被软删除（`deleted_at IS NULL`）的用户中，`email` 必须唯一；已软删除的用户不进入索引，因此其 `email` 可以与其他用户重复，也可以同名出现多次。

## 设计动机：为什么需要"条件唯一"

普通的 UNIQUE 约束是"全表唯一"——所有行都必须满足唯一性。但现实世界中大量业务规则是"条件唯一"：

| 业务场景 | 条件唯一规则 |
|---------|-------------|
| 软删除 + 用户名 | 仅在未删除用户中 `username` 唯一；已删除用户的 `username` 可被其他人占用 |
| 多版本文档 | 每个 `document_id` 最多一个 `is_current = true` 的版本 |
| 主收货地址 | 每个用户最多一个 `is_primary = true` 的地址 |
| 任务队列 | 每个 `(queue, key)` 组合最多一个 `state = 'pending'` 的任务 |
| 订阅状态 | 每个 `user_id` 最多一个 `status = 'active'` 的订阅 |
| 配置生效 | 每个 `tenant_id` 最多一条 `is_active = true` 的配置 |
| 选举/锁 | 全局最多一个 `is_leader = true` 的节点 |
| 工作流 | 每个 `request_id` 最多一个未完成的审批 |
| 租户隔离 | 每个 `tenant_id` 内 `slug` 唯一，跨租户允许重复 |
| 邮箱归属 | 已验证 (`is_verified = true`) 的邮箱必须全局唯一，未验证的可以重复 |

如果数据库不支持部分 UNIQUE 索引，要实现这些规则只能通过：

1. **触发器**：可写但有并发漏洞（如果不加表锁），且会显著降低写入性能；
2. **应用层强制**：通过事务 + SELECT ... FOR UPDATE 实现，需要客户端协作，分布式系统下尤其难做对；
3. **NULL 编码技巧**：例如 `UNIQUE (user_id, COALESCE(deleted_at, '1970-01-01'))`，依赖 NULL 在唯一索引中的特殊语义；
4. **UNIQUE NULLS NOT DISTINCT**（PostgreSQL 15+）：把 NULL 视为相等，配合 `NULLIF` 做条件唯一；
5. **生成列 + 唯一索引**（MySQL 8.0+）：把"非删除时的 username"做成生成列再索引。

部分 UNIQUE 索引把上述需求一行 SQL 解决，且语义清晰、性能最优、并发安全。

### 多个 NULL 在 UNIQUE 索引中的特殊语义

部分 UNIQUE 索引另一个常被忽视的用途，是处理 NULL 在唯一性检查中的"特殊地位"：

```sql
-- 标准 SQL（含 PG/Oracle/MSSQL/SQLite）：UNIQUE 约束允许多个 NULL
CREATE TABLE products (
    id BIGINT PRIMARY KEY,
    barcode TEXT UNIQUE  -- 多个 barcode IS NULL 的行不冲突
);

INSERT INTO products(id, barcode) VALUES (1, NULL);  -- OK
INSERT INTO products(id, barcode) VALUES (2, NULL);  -- OK，因为 NULL ≠ NULL
INSERT INTO products(id, barcode) VALUES (3, '123');
INSERT INTO products(id, barcode) VALUES (4, '123');  -- 冲突
```

但 SQL Server 是个例外——它默认把"两个 NULL 视为相等"，因此 UNIQUE 列只能有一个 NULL：

```sql
-- SQL Server 默认行为
CREATE TABLE products (id INT PRIMARY KEY, barcode NVARCHAR(50) UNIQUE);
INSERT INTO products VALUES (1, NULL);  -- OK
INSERT INTO products VALUES (2, NULL);  -- 报错: Cannot insert duplicate key
```

如果想让 SQL Server 允许多 NULL，传统做法就是部分 UNIQUE：

```sql
CREATE UNIQUE NONCLUSTERED INDEX uniq_barcode ON products(barcode)
    WHERE barcode IS NOT NULL;
```

反过来，PostgreSQL 15 引入 `UNIQUE NULLS NOT DISTINCT` 把 NULL 视为相等，让 PG 也能表达"多 NULL 不允许"的语义。这两种特性彼此互补。

## SQL 标准

### CREATE UNIQUE INDEX 不在标准里

ISO/IEC 9075 标准从未定义过 `CREATE INDEX` 语法——索引被视为实现细节，而**部分** UNIQUE 索引则更进一步是厂商扩展。所有引擎的 `CREATE UNIQUE INDEX ... WHERE` 语法都不属于标准。

### SQL:2008 引入 NULLS DISTINCT / NULLS NOT DISTINCT

SQL:2008（ISO/IEC 9075-2:2008，Clause 11.7 `<unique constraint definition>`）引入了 `UNIQUE` 约束的 NULL 处理选项：

```sql
<unique constraint definition> ::=
    <unique specification> [ <unique nulls treatment> ] ( <column name list> )
        [ <unique constraint variants> ]

<unique specification> ::= UNIQUE | PRIMARY KEY

<unique nulls treatment> ::= NULLS DISTINCT | NULLS NOT DISTINCT
```

语义：

- `NULLS DISTINCT`（默认）：每行 NULL 都被视为"独特的"，多行 NULL 不冲突。这是 SQL 历史上的默认语义，也是 PostgreSQL/Oracle/SQLite 等绝大多数引擎的行为。
- `NULLS NOT DISTINCT`：所有 NULL 被视为相等，只允许一行 NULL。这是 SQL Server 的历史默认行为。

部分 UNIQUE 索引 + `NULLS NOT DISTINCT` 的组合，提供了对 NULL 在唯一性中行为的完全控制能力。

## 支持矩阵（综合）

### 部分 UNIQUE 索引基础支持

| 引擎 | 关键字 | 部分 UNIQUE | 表达式部分 UNIQUE | 版本 |
|------|--------|-------------|-------------------|------|
| PostgreSQL | `WHERE` | 是 | 是 | 7.0+ (2000，7.2 完善) |
| MySQL | -- | 否 | 否 | 不支持 |
| MariaDB | -- | 否 | 否 | 不支持 |
| SQLite | `WHERE` | 是 | 是 | 3.8.0+ (2013) |
| Oracle | -- | 否（函数索引模拟） | CASE 模拟 | 不直接支持 |
| SQL Server | `WHERE` (Filtered Unique Index) | 是 | 否（仅简单谓词） | 2008+ (v10) |
| DB2 LUW | -- | 否 | 否 | 不支持 |
| DB2 for i | `WHERE` | 是 | 是 | 7.3+ |
| Snowflake | -- | 不适用 | -- | 不强制（约束仅元数据） |
| BigQuery | -- | -- | -- | 不适用（无二级索引/UNIQUE） |
| Redshift | -- | -- | -- | 不强制（约束仅元数据） |
| DuckDB | -- | 否 | 否 | 不支持 |
| ClickHouse | -- | 否 | 否 | 不支持（无 UNIQUE 约束） |
| Trino | -- | -- | -- | 不适用 |
| Presto | -- | -- | -- | 不适用 |
| Spark SQL | -- | -- | -- | 不适用 |
| Hive | -- | -- | -- | 不适用 |
| Flink SQL | -- | -- | -- | 不适用（流处理） |
| Databricks | -- | -- | -- | 不适用 |
| Teradata | `WHERE` (Sparse Join Index) | 是 | 是 | V2R5+ |
| Greenplum | `WHERE` | 是 | 是 | 继承 PG |
| CockroachDB | `WHERE` | 是 | 是 | 19.2+ (2019) |
| TiDB | -- | 否 | 否 | 不支持 |
| OceanBase | -- | 否 | 否 | 不支持 |
| YugabyteDB | `WHERE` | 是 | 是 | 继承 PG |
| SingleStore (MemSQL) | -- | 否 | 否 | 不支持 |
| Vertica | -- (projection 不强制唯一性) | 否 | 否 | 不强制 |
| Impala | -- | -- | -- | 不适用 |
| StarRocks | -- | -- | -- | 不适用 |
| Doris | -- | -- | -- | 不适用 |
| MonetDB | -- | 否 | 否 | 不支持 |
| CrateDB | -- | -- | -- | 不支持 |
| TimescaleDB | `WHERE` | 是 | 是 | 继承 PG |
| QuestDB | -- | -- | -- | 不支持 |
| Exasol | -- | 否 | 否 | 不支持 |
| SAP HANA | -- | 否 | 否 | 不直接支持 |
| Informix | `FILTER` (functional index) | 有限 | 部分 | 有限支持 |
| Firebird | `WHERE` | 是 | 是 | 5.0+ (2023) |
| H2 | -- | 否 | 否 | 不支持 |
| HSQLDB | -- | 否 | 否 | 不支持 |
| Derby | -- | 否 | 否 | 不支持 |
| Amazon Athena | -- | -- | -- | 不适用 |
| Azure Synapse | `WHERE` (继承 SQL Server) | 是 | 否 | 部分 SKU |
| Google Spanner | `NULL_FILTERED UNIQUE` (特例) | 仅 NULL 过滤 | 否 | GA |
| Materialize | -- | -- | -- | 不适用 |
| RisingWave | -- | -- | -- | 不适用 |
| InfluxDB (SQL) | -- | -- | -- | 不适用 |
| DatabendDB | -- | 否 | 否 | 不支持 |
| Yellowbrick | -- | 否 | 否 | 不支持 |
| Firebolt | -- | -- | -- | 不适用 |

> 统计：在 49 个引擎中，约 11 个引擎支持原生部分 UNIQUE 索引（PostgreSQL 系 + SQL Server 系 + SQLite + CockroachDB + Firebird + Spanner 的 NULL_FILTERED UNIQUE 特例 + Teradata sparse join + DB2 for i）；约 38 个引擎不支持。其中分析型 MPP / 数据湖普遍连 UNIQUE 约束都不强制，部分 UNIQUE 自然不存在。

### UNIQUE NULLS NOT DISTINCT 支持

```sql
-- SQL:2008 标准语法（仅 PG 15+ 完整实现）
CREATE TABLE t (
    a INT,
    b INT,
    UNIQUE NULLS NOT DISTINCT (a, b)
);

CREATE UNIQUE INDEX i ON t (a, b) NULLS NOT DISTINCT;
```

| 引擎 | NULLS DISTINCT 默认 | 显式 NULLS DISTINCT 语法 | NULLS NOT DISTINCT 语法 | 版本 |
|------|---------------------|--------------------------|--------------------------|------|
| PostgreSQL | 是（默认） | 是（PG 15+ 显式） | `NULLS NOT DISTINCT` | 15+ (2022-10) |
| MySQL | 是（默认） | 否 | 不支持 | -- |
| MariaDB | 是（默认） | 否 | 不支持 | -- |
| SQLite | 是（默认） | 否 | 不支持 | -- |
| Oracle | 是（默认） | 否 | 不支持 | -- |
| SQL Server | 否（默认 NULLS NOT DISTINCT） | 否 | 默认行为 | -- |
| DB2 | 是（默认） | 否 | 不支持 | -- |
| Snowflake | 是 | 否 | 不强制（约束仅元数据） | -- |
| BigQuery | -- | -- | -- | 不强制 |
| Redshift | 是 | 否 | 不强制 | -- |
| DuckDB | 是（默认） | 否 | 不支持（计划中） | -- |
| ClickHouse | -- | -- | -- | 无 UNIQUE 约束 |
| CockroachDB | 是（默认） | 否 | 不支持 | -- |
| Firebird | 是（默认） | 否 | 不支持 | -- |
| YugabyteDB | 是（默认） | 否 | 计划支持（PG 15 兼容） | -- |
| H2 | 是 | 否 | 不支持 | -- |
| HSQLDB | 是 | 否 | 不支持 | -- |
| Derby | 是 | 否 | 不支持 | -- |
| Vertica | 是 | 否 | 不支持 | -- |
| Greenplum | 是 | 否 | 计划支持 | -- |
| TimescaleDB | 是 | 是（继承 PG 15） | 是（继承 PG 15） | 跟随 PG |

> 关键：**SQL Server 是唯一一个 NULLS NOT DISTINCT 为默认行为的主流引擎**，与 SQL 标准默认相反——这经常让从其他引擎迁移过来的开发者吃惊。PostgreSQL 15（2022 年 10 月）是第一个完整实现 SQL:2008 `NULLS NOT DISTINCT` 的开源数据库。

### 部分 UNIQUE 索引中允许的谓词

| 引擎 | 等值比较 | NULL 检查 | 范围 | IN | OR | 表达式 | 列之间 | 子查询 |
|------|---------|----------|------|----|----|--------|--------|--------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | 是（IMMUTABLE） | 是 | 否 |
| SQLite | 是 | 是 | 是 | 是 | 是 | 是（确定性） | 是 | 否 |
| SQL Server | 是 | 是 | 部分 | 是（简单） | 是 | 否 | 否 | 否 |
| CockroachDB | 是 | 是 | 是 | 是 | 是 | 是（不可变） | 是 | 否 |
| Firebird 5.0 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 否 |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 否 |
| Spanner NULL_FILTERED | -- | 仅 IS NOT NULL | -- | -- | -- | -- | -- | -- |

### 多列 UNIQUE 与 NULL 处理

部分 UNIQUE 索引的"多列 + NULL"组合是最容易出现意外的场景：

| 引擎 | 多列 UNIQUE 中包含 NULL | 行为 |
|------|------------------------|------|
| PostgreSQL（默认） | 任一列为 NULL，整行视为不冲突 | 多行 (1, NULL) 都允许 |
| PostgreSQL 15 + NULLS NOT DISTINCT | 视为冲突 | 多行 (1, NULL) 报错 |
| SQL Server（默认） | NULL 视为相等 | 多行 (1, NULL) 报错 |
| Oracle | 全部列都是 NULL 才视为相等 | 多行 (1, NULL) 允许；多行 (NULL, NULL) 报错 |
| MySQL/MariaDB | 任一列为 NULL，整行视为不冲突 | 多行 (1, NULL) 都允许 |
| SQLite | 任一列为 NULL，整行视为不冲突 | 多行 (1, NULL) 都允许 |
| DB2 | 任一列为 NULL，整行视为不冲突 | 多行 (1, NULL) 都允许 |
| CockroachDB | 任一列为 NULL，整行视为不冲突 | 多行 (1, NULL) 都允许 |

> 这个表是部分 UNIQUE 索引设计中最容易踩坑的地方——同样一段 DDL 在不同引擎下行为不同。Oracle 的"全 NULL 才相等"与其他所有引擎都不一样，迁移时尤其要注意。

## 各引擎详解

### PostgreSQL（部分 UNIQUE 索引的发明者）

PostgreSQL 7.0（2000 年 5 月）首次引入 `CREATE UNIQUE INDEX ... WHERE` 语法（7.2 完善），是所有主流引擎里最早的实现，也是功能最完整的：

```sql
-- 最经典：每个用户最多一个未删除的主邮箱
CREATE UNIQUE INDEX uniq_primary_email ON users(email)
    WHERE is_primary = true AND deleted_at IS NULL;

-- 软删除 + 唯一用户名
CREATE UNIQUE INDEX uniq_username_live ON users(username)
    WHERE deleted_at IS NULL;

-- 表达式 + 部分 UNIQUE
CREATE UNIQUE INDEX uniq_lower_email ON users(LOWER(email))
    WHERE is_active = true;

-- 多列 + 部分 UNIQUE：每个租户最多一个 default 配置
CREATE UNIQUE INDEX uniq_default_config ON configs(tenant_id)
    WHERE is_default = true;

-- IS NOT NULL：稀疏列上局部唯一
CREATE UNIQUE INDEX uniq_external_id ON accounts(external_id)
    WHERE external_id IS NOT NULL;

-- 复杂谓词：状态机
CREATE UNIQUE INDEX uniq_active_subscription ON subscriptions(user_id, plan_id)
    WHERE status IN ('active', 'trial');

-- INCLUDE + 部分 UNIQUE（PG 11+）
CREATE UNIQUE INDEX uniq_active_with_data ON sessions(user_id) INCLUDE (token, created_at)
    WHERE expires_at > '2024-01-01';
```

PostgreSQL 部分 UNIQUE 索引的关键特性：

1. **谓词必须是 IMMUTABLE 表达式**：不能用 `NOW()`、`CURRENT_DATE` 等。
2. **支持任意确定性谓词**：等值、范围、IN、OR、IS NULL、子表达式都可。
3. **可与 INCLUDE 子句组合**（PG 11+）。
4. **统计信息基于全表**：但行数估算时优化器会先估算谓词选择度。
5. **HOT 更新友好**：当更新的列既不在索引列也不在谓词中时，PG 不需要更新索引。

#### PostgreSQL 15：UNIQUE NULLS NOT DISTINCT

PostgreSQL 15（2022 年 10 月）是第一个开源数据库引入 SQL:2008 `NULLS NOT DISTINCT` 的引擎：

```sql
-- 表级约束语法
CREATE TABLE t (
    a INT,
    b INT,
    UNIQUE NULLS NOT DISTINCT (a, b)
);

-- 等价的索引语法
CREATE UNIQUE INDEX uniq_t_ab ON t (a, b) NULLS NOT DISTINCT;

-- 显式 NULLS DISTINCT（默认行为）
CREATE UNIQUE INDEX uniq_default ON t (a, b) NULLS DISTINCT;
```

效果对比：

```sql
-- 默认（NULLS DISTINCT）
INSERT INTO t VALUES (1, NULL);  -- OK
INSERT INTO t VALUES (1, NULL);  -- OK（NULL ≠ NULL）

-- NULLS NOT DISTINCT
INSERT INTO t VALUES (1, NULL);  -- OK
INSERT INTO t VALUES (1, NULL);  -- 报错：duplicate key value violates unique constraint
```

`NULLS NOT DISTINCT` 与部分 UNIQUE 索引可以叠加使用：

```sql
-- 已删除用户的 email 不进入索引；存活用户中，email + extra 必须唯一
-- 即使 extra 列为 NULL 也不允许多行（因为 NULL 被视为相等）
CREATE UNIQUE INDEX uniq_complex ON users(email, extra) NULLS NOT DISTINCT
    WHERE deleted_at IS NULL;
```

这是部分 UNIQUE + NULL 语义控制的最强组合。

### SQL Server（Filtered Unique Index，2008 年引入）

SQL Server 2008（代码版本 10.0）引入 filtered index 时同时支持 unique filtered index：

```sql
-- 部分 UNIQUE 索引：未删除用户的 email 唯一
CREATE UNIQUE NONCLUSTERED INDEX uniq_active_email
    ON users(email)
    WHERE deleted_at IS NULL;

-- 处理 SQL Server 默认的"多 NULL 冲突"问题
CREATE UNIQUE NONCLUSTERED INDEX uniq_external_id
    ON accounts(external_id)
    WHERE external_id IS NOT NULL;

-- 每个 user 最多一个 is_primary = 1 的邮箱
CREATE UNIQUE NONCLUSTERED INDEX uniq_primary_email
    ON user_emails(user_id)
    WHERE is_primary = 1;

-- 状态机：每个订单最多一个 active 配送
CREATE UNIQUE NONCLUSTERED INDEX uniq_active_shipment
    ON shipments(order_id)
    WHERE status IN ('processing', 'shipped');

-- 带 INCLUDE 列的 filtered unique
CREATE UNIQUE NONCLUSTERED INDEX uniq_pending_with_payload
    ON jobs(queue_name, key)
    INCLUDE (payload, created_at)
    WHERE state = 'pending';
```

#### SQL Server 默认 UNIQUE 行为：NULL 被视为相等

这是 SQL Server 与几乎所有其他引擎最大的差异——SQL Server 默认的 `UNIQUE` 约束认为多个 NULL 是冲突的：

```sql
-- SQL Server
CREATE TABLE t (id INT PRIMARY KEY, ext_id NVARCHAR(50) UNIQUE);
INSERT INTO t VALUES (1, NULL);  -- OK
INSERT INTO t VALUES (2, NULL);
-- Msg 2627: Violation of UNIQUE KEY constraint
-- Cannot insert duplicate key in object 'dbo.t'. The duplicate key value is (<NULL>).
```

要让 SQL Server 允许多个 NULL（即匹配 SQL 标准默认），传统做法是用 filtered unique index：

```sql
-- 排除 NULL 行：标准做法
CREATE UNIQUE NONCLUSTERED INDEX uniq_ext_id_not_null
    ON t(ext_id)
    WHERE ext_id IS NOT NULL;

-- 删除原 UNIQUE 约束
ALTER TABLE t DROP CONSTRAINT [...];
```

这种"用 filtered unique index 模拟标准 NULL 行为"的写法在 SQL Server 项目中极其常见。

#### Filtered Unique Index 的限制

SQL Server filtered index 的谓词限制比 PostgreSQL 严格得多，对 unique filtered index 同样适用：

1. **不能引用变量或参数**：
   ```sql
   DECLARE @threshold DATE = '2024-01-01';
   CREATE UNIQUE INDEX idx_x ON t(col) WHERE created_at > @threshold;  -- 错误
   ```
2. **不能使用计算列、UDF、CLR 函数**。
3. **不能用 `BETWEEN`、`LIKE`、`NOT IN`、`NOT LIKE`**（旧版限制更严，2022 已松动一部分）。
4. **谓词必须是简单的二元布尔表达式或它们的 AND/OR 组合**。
5. **参数化查询匹配陷阱**：与 filtered index 一样，运行时绑定参数无法在编译期匹配 filtered unique index——必须改用字面量或 `OPTION (RECOMPILE)`。

```sql
-- 陷阱
CREATE UNIQUE INDEX uniq_active ON orders(customer_id) WHERE status = 'active';

DECLARE @s VARCHAR(20) = 'active';
INSERT INTO orders(customer_id, status) VALUES (42, @s);
-- 不会通过 unique filtered index 验证，但实际不会报错
-- 危险的是：SELECT 查询不会用到该索引
SELECT * FROM orders WHERE customer_id = 42 AND status = @s;  -- 全表扫描
SELECT * FROM orders WHERE customer_id = 42 AND status = 'active' OPTION (RECOMPILE);  -- 用索引
```

#### Filtered Unique Index 与基表 NULL 行为的互动

由于 SQL Server 默认 UNIQUE 约束把 NULL 视为相等，filtered unique index 经常被用来"修补"这一行为，让 SQL Server 表现得像标准 SQL 一样。

### Oracle（无原生部分 UNIQUE，需 CASE 模拟）

Oracle 至今没有 `CREATE UNIQUE INDEX ... WHERE` 语法，但可以通过函数索引 + CASE 表达式 + Oracle 单列索引的"NULL 不入索引"特性来模拟：

```sql
-- 经典模拟：每个用户最多一个 is_primary = 1 的邮箱
CREATE UNIQUE INDEX uniq_primary_email ON user_emails(
    CASE WHEN is_primary = 1 THEN user_id END
);

-- 原理：is_primary <> 1 时 CASE 返回 NULL，Oracle 单列 B-Tree 索引不存 NULL 键
-- 因此只有 is_primary = 1 的行进入索引，UNIQUE 仅在该子集生效
```

更复杂的场景需要构造多列 CASE：

```sql
-- 软删除 + 唯一用户名（多列模拟）
CREATE UNIQUE INDEX uniq_username_live ON users(
    CASE WHEN deleted_at IS NULL THEN username END,
    CASE WHEN deleted_at IS NULL THEN 1 END  -- 占位列保证多列索引中的 NULL 处理
);

-- 或更简洁的写法（依赖 Oracle 多列索引中"全部 NULL 才视为相等"的语义）：
CREATE UNIQUE INDEX uniq_username_live ON users(
    CASE WHEN deleted_at IS NULL THEN username END
);
```

#### Oracle 模拟方案的关键限制

1. **查询必须用相同表达式**才能命中索引：
   ```sql
   -- 写入时被 unique 索引拦截没问题
   -- 但查询想走索引必须写：
   SELECT * FROM user_emails
   WHERE CASE WHEN is_primary = 1 THEN user_id END = 42;  -- 命中
   
   -- 普通写法不会命中
   SELECT * FROM user_emails WHERE is_primary = 1 AND user_id = 42;  -- 全表扫描
   ```
   解决：在表达式上建额外的非唯一索引，或显式重写查询。

2. **多列 NULL 语义微妙**：Oracle 的多列 UNIQUE 中"任一列非 NULL 即记录到索引"，与部分索引语义略有不同。

3. **CASE 写法繁琐**：每个谓词条件都要包成 CASE，DDL 可读性差。

4. **Oracle 19c+ 虚拟列**：可以先建虚拟列再建普通 UNIQUE 索引，但增加了 schema 复杂度：
   ```sql
   ALTER TABLE user_emails ADD primary_user_id AS (
       CASE WHEN is_primary = 1 THEN user_id END
   );
   CREATE UNIQUE INDEX uniq_primary_email ON user_emails(primary_user_id);
   ```

#### Oracle 多列 UNIQUE 中的 NULL：唯一与众不同

Oracle 对多列 UNIQUE 的 NULL 处理与所有其他引擎都不同：

```sql
CREATE TABLE t (a INT, b INT);
CREATE UNIQUE INDEX i ON t (a, b);

INSERT INTO t VALUES (1, NULL);  -- OK
INSERT INTO t VALUES (1, NULL);  -- OK（PG/MySQL/SQLite 也允许）
INSERT INTO t VALUES (NULL, NULL);  -- OK
INSERT INTO t VALUES (NULL, NULL);  -- ERROR! Oracle 认为全 NULL 元组冲突
```

> Oracle 是少数对"全 NULL 行为多 NULL 元组"做特殊判定的引擎。这一行为不是标准也不是其他引擎的默认。

### MySQL / MariaDB（不支持，只能生成列变通）

MySQL 和 MariaDB 至今都**不支持** `CREATE UNIQUE INDEX ... WHERE` 语法：

```sql
-- MySQL/MariaDB 错误
CREATE UNIQUE INDEX uniq_username_live ON users(username) WHERE deleted_at IS NULL;
-- ERROR 1064 (42000): You have an error in your SQL syntax
```

#### MySQL 8.0 / MariaDB 10.2+：生成列 + UNIQUE 索引

最常用的变通方案是"软删除时让目标列为 NULL"，配合 MySQL/MariaDB 默认的"NULL 在 UNIQUE 中独立"语义：

```sql
-- MySQL 8.0+
ALTER TABLE users ADD COLUMN username_live VARCHAR(64) AS (
    CASE WHEN deleted_at IS NULL THEN username ELSE NULL END
) STORED;

ALTER TABLE users ADD UNIQUE INDEX uniq_username_live (username_live);

-- 删除用户时自动把 username_live 变 NULL，从而退出唯一索引
UPDATE users SET deleted_at = NOW() WHERE id = 42;
```

代价：

1. **多一个生成列**：占用 row 空间（即使是 STORED）；
2. **DDL 变得复杂**：`ALTER TABLE ADD COLUMN AS ... STORED` 在大表上需要 metadata-only 或 inplace；
3. **VIRTUAL 与 STORED 选择**：VIRTUAL 不占空间但每次查询计算；STORED 占空间但 INSERT 时一次计算；
4. **错误信息丑陋**：违反 unique 约束的报错引用的是 `username_live`，需要应用层转换。

#### 触发器方案（不推荐）

```sql
DELIMITER //
CREATE TRIGGER trg_unique_username_live
BEFORE INSERT ON users FOR EACH ROW
BEGIN
    IF NEW.deleted_at IS NULL AND EXISTS (
        SELECT 1 FROM users
        WHERE username = NEW.username AND deleted_at IS NULL
    ) THEN
        SIGNAL SQLSTATE '23000' SET MESSAGE_TEXT = 'Duplicate live username';
    END IF;
END//
DELIMITER ;
```

问题：

1. **并发漏洞**：默认 InnoDB 隔离级别下，两个并发 INSERT 都会"发现没有冲突"然后都成功。需要显式 `SELECT ... FOR UPDATE` 或锁全表。
2. **性能差**：每次 INSERT 都要做一次唯一性查询。
3. **维护困难**：触发器逻辑分散，迁移和 schema 变更易出错。

### SQLite（3.8.0，2013 年 8 月）

SQLite 在 3.8.0（2013 年 8 月 26 日）引入部分索引，包括部分 UNIQUE 索引：

```sql
-- 软删除 + 唯一用户名
CREATE UNIQUE INDEX uniq_username_live ON users(username)
    WHERE deleted_at IS NULL;

-- 主邮箱唯一
CREATE UNIQUE INDEX uniq_primary_email ON user_emails(user_id)
    WHERE is_primary = 1;

-- 任务队列：每个 key 最多一个 pending 任务
CREATE UNIQUE INDEX uniq_pending_job ON jobs(key)
    WHERE state = 'pending';

-- 表达式部分 UNIQUE
CREATE UNIQUE INDEX uniq_lower_email ON users(LOWER(email))
    WHERE is_active = 1;
```

SQLite 限制：

1. WHERE 子句中只能使用**确定性表达式**（不能 `random()`、`current_timestamp` 等）；
2. 谓词匹配较 PostgreSQL 简单——只做字面量包含；
3. 嵌入式数据库的优势让 SQLite 的部分 UNIQUE 在移动端 App 中尤其常用——本地 SQLite 数据库经常需要"软删除 + 唯一字段"。

### CockroachDB（19.2，2019 年）

CockroachDB 19.2（2019 年 11 月）首先支持部分索引（包括 UNIQUE），20.2 进一步增强匹配能力：

```sql
-- 软删除 + 唯一约束
CREATE UNIQUE INDEX uniq_username_live ON users (username)
    WHERE deleted_at IS NULL;

-- 状态机：每个 user 最多一个 active 订阅
CREATE UNIQUE INDEX uniq_active_sub ON subscriptions (user_id)
    WHERE status = 'active';

-- 表达式部分 UNIQUE
CREATE UNIQUE INDEX uniq_lower_email ON users (LOWER(email))
    WHERE is_verified = true;

-- 多列部分 UNIQUE
CREATE UNIQUE INDEX uniq_default_config ON tenant_configs (tenant_id, env)
    WHERE is_default = true;
```

CockroachDB 部分 UNIQUE 索引对**分布式系统特别有意义**：

1. **写放大降低**：每个 KV 键值对都要 Raft 复制 3 次，部分 UNIQUE 让"无关的 99% 行"完全不进入索引；
2. **全局唯一性自动维护**：CockroachDB 的分布式事务确保跨节点的部分 UNIQUE 检查原子完成；
3. **谓词蕴含算法**：参考自 PostgreSQL 的 `predtest.c`，做范围、布尔代数、常量折叠的推理。

### Firebird 5.0（2023 年 6 月）

Firebird 5.0 终于在 2023 年 6 月加入部分索引（包括部分 UNIQUE）：

```sql
-- 基本语法
CREATE UNIQUE INDEX uniq_username_live ON users (username)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uniq_primary_email ON user_emails (user_id)
    WHERE is_primary = TRUE;
```

Firebird 实现相对基础：谓词不能引用其他表、不能用聚合、不能用子查询、不能用绑定参数；谓词匹配采用简单字面量对比。

### Google Spanner（NULL_FILTERED UNIQUE 特例）

Spanner 不支持任意谓词的部分 UNIQUE 索引，但提供一个特例：`NULL_FILTERED` 索引——索引中跳过任意索引列为 NULL 的行：

```sql
CREATE UNIQUE NULL_FILTERED INDEX uniq_external_id
    ON users (external_id);

-- 等价于"WHERE external_id IS NOT NULL"
-- 多个 external_id IS NULL 的行不冲突，因为它们不进入索引
```

设计考虑：分布式索引的谓词匹配开销很高，Spanner 把功能限制到"最常见的子集（NULL 过滤）"，避免完整谓词匹配的复杂度。

### DB2 for i（iSeries / AS/400）

DB2 for i 与 DB2 LUW 的差异在部分 UNIQUE 索引上特别明显——只有 DB2 for i 支持：

```sql
-- DB2 for i 7.3+
CREATE UNIQUE INDEX uniq_active_user ON users (username)
    WHERE deleted = 'N';
```

DB2 LUW（Linux/Unix/Windows）至今不支持，需要用 MQT（Materialized Query Table）或触发器变通。

### Teradata（Sparse Join Index 模拟）

Teradata 通过 **Sparse Unique Join Index** 实现类似部分 UNIQUE 的功能：

```sql
CREATE UNIQUE JOIN INDEX uniq_active_email_ji AS
SELECT user_id, email
FROM users
WHERE deleted_at IS NULL
PRIMARY INDEX (user_id);
```

实质是带 WHERE 的物化连接索引，物化结果上自然带 UNIQUE。优化器在查询匹配时会自动选择该 join index。

### YugabyteDB / Greenplum / TimescaleDB（继承 PostgreSQL）

这些 PG 生态扩展完全继承 PostgreSQL 的部分 UNIQUE 语义：

```sql
-- YugabyteDB（分布式 PG 兼容）
CREATE UNIQUE INDEX uniq_active_email ON users (email) WHERE deleted_at IS NULL;

-- Greenplum
CREATE UNIQUE INDEX uniq_active_email ON users (email) WHERE deleted_at IS NULL;

-- TimescaleDB（hypertable 上）
CREATE UNIQUE INDEX uniq_recent_event ON events (user_id, dedup_key)
    WHERE event_type = 'critical';
-- 注意：hypertable 上的 UNIQUE 必须包含分区键
```

> 重要：在 TimescaleDB hypertable 上，唯一索引（包括部分唯一）必须包含分区键（time 列），因为 chunk 是物理隔离的，跨 chunk 的全局 UNIQUE 不可保证。

### 其他不支持的引擎

#### MySQL 8.0+：UNIQUE NULLS NOT DISTINCT 也不支持

MySQL/MariaDB 既不支持部分 UNIQUE，也不支持 SQL:2008 的 `NULLS NOT DISTINCT`。它们的 UNIQUE 始终是"NULL 独立"。

#### Snowflake / BigQuery / Redshift（约束仅元数据）

这些云数据仓库的 UNIQUE 约束**不被强制**——它们只是优化器提示（informational constraint），用于改进执行计划：

```sql
-- Snowflake：UNIQUE 仅元数据，不强制
CREATE TABLE users (id INT, email STRING UNIQUE);
INSERT INTO users VALUES (1, 'a@b.com');
INSERT INTO users VALUES (2, 'a@b.com');  -- 不报错！
```

因此部分 UNIQUE 在这些引擎里也没有意义——任何 UNIQUE 都不强制。如果应用需要唯一性，必须在写入路径上自己保证（MERGE 语句或事务 + EXISTS 检查）。

#### ClickHouse / DuckDB

ClickHouse 完全没有 UNIQUE 约束（除了 ReplacingMergeTree 引擎的最终一致去重，但那不是约束）。

DuckDB 支持普通 UNIQUE 约束，但目前不支持 `CREATE UNIQUE INDEX ... WHERE`。

## UNIQUE NULLS NOT DISTINCT 详解

### 历史背景

SQL 标准中，`NULL = NULL` 永远返回 `UNKNOWN`，因此 UNIQUE 约束的默认行为是"两个 NULL 不冲突"。这导致了一个广为人知的痛点：

```sql
CREATE TABLE products (id INT, sku TEXT UNIQUE);
INSERT INTO products VALUES (1, NULL);
INSERT INTO products VALUES (2, NULL);   -- 允许！
INSERT INTO products VALUES (3, NULL);   -- 也允许！
INSERT INTO products VALUES (4, NULL);   -- 还允许！
-- 想让 sku 唯一时不要 NULL，但 NULL 又是合法的"未知 SKU"
```

历史上，开发者只能选择：

1. 把列改成 NOT NULL（牺牲业务表达力）；
2. 用部分 UNIQUE `WHERE sku IS NOT NULL`（PG/SQLite/SQL Server）；
3. 用占位符（如空字符串）代替 NULL（容易造成业务语义污染）；
4. 在 SQL Server 上享受默认行为（NULL 视为相等，但不符合标准）。

SQL:2008 引入 `NULLS [NOT] DISTINCT` 子句，允许 DDL 显式声明这一行为。

### PostgreSQL 15 的实现

PostgreSQL 15（2022 年 10 月）是第一个开源数据库实现 SQL:2008 `NULLS NOT DISTINCT`：

```sql
-- 表级约束语法
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    sku TEXT,
    UNIQUE NULLS NOT DISTINCT (sku)
);

-- 索引语法
CREATE UNIQUE INDEX uniq_sku ON products (sku) NULLS NOT DISTINCT;

-- 显式 NULLS DISTINCT（默认）
CREATE UNIQUE INDEX uniq_sku_default ON products (sku) NULLS DISTINCT;
```

行为对比：

```sql
-- NULLS DISTINCT (默认)
INSERT INTO products(sku) VALUES (NULL);  -- OK
INSERT INTO products(sku) VALUES (NULL);  -- OK，因为 NULL ≠ NULL

-- NULLS NOT DISTINCT
INSERT INTO products(sku) VALUES (NULL);  -- OK
INSERT INTO products(sku) VALUES (NULL);  -- ERROR: duplicate key
```

### NULLS NOT DISTINCT 与多列 UNIQUE

多列 UNIQUE 的 NULLS NOT DISTINCT 行为：

```sql
CREATE TABLE t (a INT, b INT, UNIQUE NULLS NOT DISTINCT (a, b));

INSERT INTO t VALUES (1, NULL);  -- OK
INSERT INTO t VALUES (1, NULL);  -- ERROR
INSERT INTO t VALUES (2, NULL);  -- OK（a 不同）
INSERT INTO t VALUES (NULL, 1);  -- OK
INSERT INTO t VALUES (NULL, 1);  -- ERROR
INSERT INTO t VALUES (NULL, NULL);  -- OK
INSERT INTO t VALUES (NULL, NULL);  -- ERROR
```

逻辑：所有 NULL 视为相同值，因此 (1, NULL) 与 (1, NULL) 冲突，(NULL, NULL) 与 (NULL, NULL) 冲突。

### NULLS NOT DISTINCT 与部分 UNIQUE 的叠加

PG 15+ 允许两者同时使用：

```sql
-- 在未删除的用户中，(email, secondary_email) 必须唯一
-- 即使其中一列是 NULL，也不允许多行
CREATE UNIQUE INDEX uniq_emails_active 
    ON users (email, secondary_email) 
    NULLS NOT DISTINCT
    WHERE deleted_at IS NULL;
```

这是 SQL 历史上对"条件唯一 + NULL 控制"最完整的表达方式。

### 其他引擎对 NULLS NOT DISTINCT 的支持

| 引擎 | 进展 |
|------|------|
| PostgreSQL | 15+ 完整支持 (2022-10) |
| YugabyteDB | 计划继承 PG 15 兼容性 |
| TimescaleDB | 跟随 PG 15 |
| Greenplum | 跟随 PG 计划中 |
| CockroachDB | 已讨论但暂未实现 |
| MySQL | 无计划 |
| MariaDB | 无计划 |
| SQL Server | 默认即 NULLS NOT DISTINCT，无需额外语法 |
| Oracle | 无计划，但其多列 UNIQUE 中"全 NULL 视为相等"的行为部分类似 |
| DuckDB | 计划支持 |

## 经典使用模式

### 模式 1：软删除 + 唯一字段

最经典也最常用的部分 UNIQUE 用法：

```sql
-- 未删除用户的 username 唯一；删除后该 username 可再次使用
CREATE UNIQUE INDEX uniq_username_live ON users(username)
    WHERE deleted_at IS NULL;

-- 完整 schema
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    email TEXT,
    deleted_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX uniq_username_live ON users(username)
    WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX uniq_email_live ON users(email)
    WHERE deleted_at IS NULL AND email IS NOT NULL;

-- 操作
INSERT INTO users(username, email) VALUES ('alice', 'a@b.com');
-- alice 软删除
UPDATE users SET deleted_at = NOW() WHERE username = 'alice';
-- 新用户 alice 可以注册成功（因为旧 alice 已退出唯一索引）
INSERT INTO users(username, email) VALUES ('alice', 'a@b.com');  -- 不冲突
```

#### 软删除 + 唯一字段的反模式

如果不用部分 UNIQUE，常见的丑陋方案：

```sql
-- 反模式 1：删除时改名
UPDATE users SET deleted_at = NOW(),
                 username = username || '_deleted_' || EXTRACT(EPOCH FROM NOW())
WHERE id = 42;
-- 问题：原 username 信息污染、长度可能溢出、查询/审计代码全部要适配

-- 反模式 2：编码技巧
ALTER TABLE users ADD UNIQUE (username, COALESCE(deleted_at, '1970-01-01'));
-- 问题：表达式索引在不同引擎语义不同；查询时无法直接命中

-- 反模式 3：触发器
-- 问题：并发漏洞 + 性能差
```

部分 UNIQUE 让上述反模式都不需要存在。

### 模式 2：状态机的"活跃唯一"

```sql
-- 每个用户最多一个 active 订阅
CREATE TABLE subscriptions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    plan_id BIGINT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('active', 'cancelled', 'expired'))
);
CREATE UNIQUE INDEX uniq_active_sub ON subscriptions(user_id)
    WHERE status = 'active';

-- 操作流程
INSERT INTO subscriptions(user_id, plan_id, status) VALUES (1, 100, 'active');  -- OK
INSERT INTO subscriptions(user_id, plan_id, status) VALUES (1, 200, 'active');  -- 冲突
-- 必须先取消旧的
UPDATE subscriptions SET status = 'cancelled' WHERE user_id = 1 AND status = 'active';
INSERT INTO subscriptions(user_id, plan_id, status) VALUES (1, 200, 'active');  -- OK
```

### 模式 3：多版本文档/单一当前版本

```sql
CREATE TABLE document_versions (
    id BIGSERIAL PRIMARY KEY,
    document_id BIGINT NOT NULL,
    version INT NOT NULL,
    content TEXT,
    is_current BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX uniq_document_id_version ON document_versions(document_id, version);
CREATE UNIQUE INDEX uniq_current_version ON document_versions(document_id)
    WHERE is_current = true;
```

任何 `document_id` 最多一个 `is_current = true` 的版本。

### 模式 4：分布式锁/选举

```sql
-- 全局只能有一个 leader
CREATE TABLE cluster_state (
    id BIGSERIAL PRIMARY KEY,
    node_id TEXT NOT NULL,
    is_leader BOOLEAN NOT NULL DEFAULT false,
    heartbeat_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX uniq_leader ON cluster_state(is_leader)
    WHERE is_leader = true;
-- 等价于"全表只有一行 is_leader = true"
```

注：`UNIQUE INDEX` 索引列是 `is_leader`，但谓词只允许 TRUE 进入索引——索引中只有一行（如果有的话），且其值固定为 TRUE，因此整个索引强制"最多一行"。

### 模式 5：每个对象的"唯一主项"

```sql
-- 用户最多一个 is_primary = true 的邮箱
CREATE TABLE user_emails (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    email TEXT NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX uniq_primary_email_per_user ON user_emails(user_id)
    WHERE is_primary = true;

-- 用户最多一个 default 收货地址
CREATE UNIQUE INDEX uniq_default_address ON addresses(user_id)
    WHERE is_default = true;

-- 租户最多一条 published 配置
CREATE UNIQUE INDEX uniq_published_config ON configs(tenant_id, key)
    WHERE published = true;
```

### 模式 6：任务队列幂等

```sql
-- 每个 (queue, idempotency_key) 最多一个未完成的任务
CREATE TABLE jobs (
    id BIGSERIAL PRIMARY KEY,
    queue_name TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    state TEXT NOT NULL,
    payload JSONB,
    completed_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX uniq_pending_idempotency 
    ON jobs(queue_name, idempotency_key)
    WHERE completed_at IS NULL;

-- 重复提交相同 (queue, idempotency_key) 在未完成期间会被拦截
-- 完成后允许重新提交
```

### 模式 7：稀疏外键唯一

```sql
-- 大多数行 external_id 为 NULL，只有少数同步过的行有值
-- 这些有值的 external_id 必须唯一
CREATE UNIQUE INDEX uniq_external_id ON accounts(external_id)
    WHERE external_id IS NOT NULL;
```

PG 在没有部分索引时也允许多个 NULL（NULLS DISTINCT 默认），但部分 UNIQUE 让索引更小、查询更快——大多数 NULL 行不进入索引。

### 模式 8：多列复合条件

```sql
-- 同一租户的同一类型最多一个 active 配置
CREATE UNIQUE INDEX uniq_tenant_type_active 
    ON configs(tenant_id, config_type)
    WHERE is_active = true;

-- 最多一个未审核的相同金额转账（防重提）
CREATE UNIQUE INDEX uniq_pending_transfer 
    ON transfers(from_account, to_account, amount)
    WHERE status = 'pending';
```

## Oracle CASE 模拟方案详解

由于 Oracle 缺乏原生部分 UNIQUE，CASE 函数索引是社区最常用的解决办法。下面对各场景给出完整模板：

### 场景 1：软删除 + 唯一用户名

```sql
-- 表结构
CREATE TABLE users (
    id NUMBER PRIMARY KEY,
    username VARCHAR2(64),
    deleted_at TIMESTAMP
);

-- 模拟 "WHERE deleted_at IS NULL"
CREATE UNIQUE INDEX uniq_username_live ON users(
    CASE WHEN deleted_at IS NULL THEN username END
);

-- 测试
INSERT INTO users VALUES (1, 'alice', NULL);   -- OK
INSERT INTO users VALUES (2, 'alice', NULL);   -- ORA-00001 unique constraint violated
UPDATE users SET deleted_at = SYSTIMESTAMP WHERE id = 1;
-- 现在 alice 退出索引（CASE 返回 NULL）
INSERT INTO users VALUES (3, 'alice', NULL);   -- OK
```

原理：Oracle 单列 B-Tree 索引**不存储 NULL 键**。当 `deleted_at IS NOT NULL` 时，CASE 返回 NULL，行不进入索引，因此不参与唯一性检查。

### 场景 2：状态机活跃唯一

```sql
-- 每个用户最多一个 active 订阅
CREATE UNIQUE INDEX uniq_active_sub ON subscriptions(
    CASE WHEN status = 'active' THEN user_id END
);
```

### 场景 3：多列复合 + 状态条件

```sql
-- 每个 (tenant_id, env) 最多一个 default 配置
-- 复杂处：多列 UNIQUE 时，单列 NULL 也会进入索引（Oracle 多列索引不像单列那样跳过 NULL）
-- 解决方法：让所有 CASE 同时为 NULL
CREATE UNIQUE INDEX uniq_default_config ON configs(
    CASE WHEN is_default = 'Y' THEN tenant_id END,
    CASE WHEN is_default = 'Y' THEN env END
);
-- 当 is_default <> 'Y' 时，两列都返回 NULL，整行不进入索引
```

### 场景 4：复杂谓词

```sql
-- WHERE deleted_at IS NULL AND is_primary = 1
CREATE UNIQUE INDEX uniq_primary_email_live ON user_emails(
    CASE 
        WHEN deleted_at IS NULL AND is_primary = 1 
        THEN email 
    END
);
```

### Oracle 19c+ 虚拟列方案

```sql
-- 先定义虚拟列
ALTER TABLE users ADD (
    username_live AS (
        CASE WHEN deleted_at IS NULL THEN username END
    )
);

-- 在虚拟列上建普通 UNIQUE 索引
CREATE UNIQUE INDEX uniq_username_live ON users(username_live);

-- 优势：DDL 更整洁、查询不需要写 CASE 表达式
-- 代价：schema 多一列（虚拟列不占空间但增加 DESC 输出复杂度）
```

### Oracle CASE 方案的局限

1. **查询要走索引必须用相同表达式**：
   ```sql
   -- 想用 idx 必须写：
   SELECT * FROM users 
   WHERE CASE WHEN deleted_at IS NULL THEN username END = 'alice';
   
   -- 普通写法不命中：
   SELECT * FROM users WHERE username = 'alice' AND deleted_at IS NULL;  -- 全表扫描
   ```
   解决：在普通列上额外建索引，或用虚拟列让查询自然命中。

2. **多列索引中"全 NULL 才认为相等"**：依赖这个 Oracle 独有行为，迁移到其他引擎时语义会变。

3. **可读性差**：CASE 在 DDL 中嵌套，DBA 维护成本上升。

4. **谓词扩展困难**：增加新条件需要重写整个 CASE，且要谨慎处理 NULL 传播。

## 引擎实现：部分 UNIQUE 索引的内部机制

### 写路径：插入时如何检查唯一性

```
INSERT (row r) 流程：
  1. 评估 partial_predicate(r)
     - 若返回 FALSE 或 NULL：跳过索引（行不进入索引）
     - 若返回 TRUE：进入步骤 2
  2. 计算索引键 key = expr(r)
  3. 在索引中查找 key
     - 若已存在键 k 且 k.row != r.row（且不是同一行的 MVCC 旧版本）：
         报错 unique violation
     - 否则：插入索引项 (key, row_id)
```

### 写路径：UPDATE 时的四种状态转移

更新对部分 UNIQUE 索引的影响比普通 UNIQUE 复杂——可能让一行"进入"或"离开"索引：

```
原行满足谓词       新行满足谓词       索引动作
    是                  是              UPDATE 索引项（若键变化则 DELETE + INSERT）
    是                  否              DELETE（从索引移除）
    否                  是              INSERT（向索引添加，需要 UNIQUE 检查）
    否                  否              无操作
```

特别注意第三种情况：原行不在索引中，新行进入索引时必须做唯一性检查，可能与现有索引项冲突。

### MVCC 引擎的并发挑战

PostgreSQL 是 MVCC 引擎，更新会产生新版本。部分 UNIQUE 检查必须考虑可见性：

```
事务 T1: INSERT (alice, deleted_at = NULL) -- 进入索引
事务 T2: SELECT FROM users WHERE username = 'alice'  -- 等待 T1
事务 T1 commit
事务 T3: INSERT (alice, deleted_at = NULL) -- 检测到冲突
事务 T1: UPDATE users SET deleted_at = NOW() WHERE username = 'alice'
        -- 新版本不满足谓词，从索引中"移除"（实际是新版本不进入索引）
事务 T4: INSERT (alice, deleted_at = NULL) -- 此时不冲突
```

PG 的实现通过 HOT chain + 索引版本管理保证可见性正确。

### 并发构建（CONCURRENTLY）的二阶段扫描

`CREATE UNIQUE INDEX CONCURRENTLY` 在生产环境不可或缺，但实现复杂：

```
阶段 1（快照 A）：
  1. 创建 invalid 索引（无法被查询使用，但参与写路径维护）
  2. 扫描基表，对每行评估部分 UNIQUE 谓词
  3. 满足谓词的行：插入索引（必要时检查唯一性冲突）
  4. 不满足谓词的行：跳过

阶段 2（快照 B，B > A）：
  1. 扫描快照 A 与 B 之间的所有变更（通过 xmin/xmax 或 WAL）
  2. 补齐遗漏的索引条目
  3. 处理 UPDATE 触发的"进入/离开索引"

阶段 3：
  1. 等待所有持有旧快照的事务结束
  2. 标记索引 valid
```

这一过程对部分 UNIQUE 比普通 UNIQUE 还复杂，因为还要处理"行在不同快照下满足/不满足谓词"的情况。

### 谓词蕴含与查询匹配

部分 UNIQUE 索引被查询使用的前提：优化器证明查询谓词 Q 蕴含索引谓词 P：

```
索引谓词 P: status = 'active' AND deleted_at IS NULL
查询 1: WHERE status = 'active' AND deleted_at IS NULL                -- Q ⇒ P，可用
查询 2: WHERE status = 'active' AND deleted_at IS NULL AND id > 100   -- Q ⇒ P，可用
查询 3: WHERE status = 'active'                                        -- Q !⇒ P，不可用
查询 4: WHERE status IN ('active', 'pending') AND deleted_at IS NULL  -- Q !⇒ P，不可用
```

这一逻辑在 PostgreSQL 由 `src/backend/optimizer/util/predtest.c` 实现，是部分索引"能否被查询利用"的关键。

注意：**部分 UNIQUE 的"约束作用"始终生效**（写入时强制），不依赖谓词蕴含；只有"被查询用作访问路径"才需要 Q ⇒ P 的证明。

## 部分 UNIQUE 索引的代价与陷阱

### 代价 1：参数化查询无法命中

与部分索引一样，参数化谓词无法在编译期判定：

```sql
CREATE UNIQUE INDEX uniq_active ON orders(customer_id) WHERE status = 'active';

-- 不会命中索引（status 是参数）
PREPARE q AS SELECT * FROM orders WHERE customer_id = $1 AND status = $2;
EXECUTE q(42, 'active');

-- 命中索引（字面量）
SELECT * FROM orders WHERE customer_id = 42 AND status = 'active';
```

应对：使用字面量、`OPTION (RECOMPILE)`（SQL Server）、`prepareThreshold=0`（JDBC）。

### 代价 2：谓词字面量必须一致

```sql
-- 索引谓词
CREATE UNIQUE INDEX uniq_x ON t(c) WHERE flag = 1;

-- 查询写 'true' 而不是 1，可能不命中（取决于类型转换规则）
SELECT * FROM t WHERE c = 42 AND flag = TRUE;  -- 视引擎而定
```

### 代价 3：多列 UNIQUE 中 NULL 行为差异

如前所述，Oracle 与其他引擎对"全 NULL 元组"的判定不同。从 Oracle 迁移到 PG 时，同一段 DDL 可能放过 Oracle 拒绝的数据，造成迁移后唯一性"看起来失效"。

### 代价 4：索引结构碎片化

部分 UNIQUE 因为只索引子集，写入时可能更新模式倾斜：例如所有 `state = 'pending'` 的行集中插入然后转 `state = 'completed'` 时离开索引。频繁的进出可能导致索引页分裂。

### 代价 5：部分 UNIQUE 与 GENERATED COLUMN 相互作用

```sql
-- 生成列上建部分 UNIQUE
CREATE TABLE t (
    id BIGSERIAL,
    name TEXT,
    norm_name TEXT GENERATED ALWAYS AS (LOWER(TRIM(name))) STORED,
    UNIQUE (norm_name) WHERE name IS NOT NULL  -- 部分引擎不允许此组合
);
```

不同引擎对"生成列 + 部分 UNIQUE"的支持差异显著：PG 允许；SQL Server 不允许 filtered index 引用计算列；Oracle 必须 CASE 模拟整个表达式。

### 代价 6：分区表上的"全局 UNIQUE"

PostgreSQL 的声明式分区表上，部分 UNIQUE 索引是"per-partition local"的：

```sql
CREATE TABLE orders (...) PARTITION BY RANGE (created_at);
CREATE TABLE orders_2024 PARTITION OF orders FOR VALUES FROM (...);

-- 这个 UNIQUE 仅在每个分区内生效，跨分区不保证！
CREATE UNIQUE INDEX uniq_active ON orders(customer_id) WHERE status = 'active';
```

要在分区表上做"全局部分 UNIQUE"，必须把分区键加入索引列：

```sql
CREATE UNIQUE INDEX uniq_active ON orders(customer_id, created_at) 
    WHERE status = 'active';
-- 分区键必须出现在索引列中
```

或者使用 PG 11+ 的"全局唯一约束"（partition-key-aware）。

## 跨引擎迁移指南

### PostgreSQL → MySQL

最痛苦的迁移方向之一。常见做法：

```sql
-- PostgreSQL 原 DDL
CREATE UNIQUE INDEX uniq_username_live ON users(username) WHERE deleted_at IS NULL;

-- MySQL 8.0 等价
ALTER TABLE users ADD COLUMN username_live VARCHAR(64) AS (
    CASE WHEN deleted_at IS NULL THEN username ELSE NULL END
) STORED;
ALTER TABLE users ADD UNIQUE INDEX uniq_username_live (username_live);
```

风险：原有引用 `username` 的查询不会自动用新索引；需要显式改写为引用 `username_live` 或依赖 MySQL 的索引匹配优化（部分版本支持）。

### PostgreSQL → Oracle

```sql
-- PostgreSQL
CREATE UNIQUE INDEX uniq_username_live ON users(username) WHERE deleted_at IS NULL;

-- Oracle CASE 方案
CREATE UNIQUE INDEX uniq_username_live ON users(
    CASE WHEN deleted_at IS NULL THEN username END
);

-- 或 Oracle 19c+ 虚拟列方案
ALTER TABLE users ADD (username_live AS (
    CASE WHEN deleted_at IS NULL THEN username END
));
CREATE UNIQUE INDEX uniq_username_live ON users(username_live);
```

风险：查询代码可能需要改写或依赖虚拟列 + 索引重写。

### SQL Server → PostgreSQL（含 NULLS NOT DISTINCT 行为差异）

```sql
-- SQL Server：UNIQUE 默认 NULLS NOT DISTINCT
CREATE TABLE t (id INT PRIMARY KEY, sku NVARCHAR(64) UNIQUE);
-- 同一个 sku = NULL 不允许多行

-- PostgreSQL 14 及以下：UNIQUE 默认 NULLS DISTINCT，行为不一致
CREATE TABLE t (id INT PRIMARY KEY, sku TEXT UNIQUE);
-- 同一个 sku = NULL 允许多行

-- PostgreSQL 15+ 显式恢复 SQL Server 行为
CREATE TABLE t (
    id INT PRIMARY KEY, 
    sku TEXT, 
    UNIQUE NULLS NOT DISTINCT (sku)
);
```

### MySQL → PostgreSQL（生成列方案的清理）

如果 MySQL 项目用了生成列变通，迁到 PG 后应该把生成列删掉，改为原生部分 UNIQUE：

```sql
-- 删除冗余的生成列
ALTER TABLE users DROP COLUMN username_live;
-- 用部分 UNIQUE 替代
CREATE UNIQUE INDEX uniq_username_live ON users(username) WHERE deleted_at IS NULL;
```

## 真实案例

### 案例 1：电商系统的"三个唯一"

```sql
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email TEXT,
    phone TEXT,
    username TEXT,
    deleted_at TIMESTAMPTZ
);

-- 三个独立的部分 UNIQUE，覆盖三种"用户标识"
CREATE UNIQUE INDEX uniq_email_live ON users(LOWER(email))
    WHERE deleted_at IS NULL AND email IS NOT NULL;
CREATE UNIQUE INDEX uniq_phone_live ON users(phone)
    WHERE deleted_at IS NULL AND phone IS NOT NULL;
CREATE UNIQUE INDEX uniq_username_live ON users(LOWER(username))
    WHERE deleted_at IS NULL AND username IS NOT NULL;
```

每个标识独立保证：未删除用户中唯一；可选标识（NULL）不冲突；删除用户后标识可被重新使用。

### 案例 2：CockroachDB 上的金融幂等

```sql
-- 转账请求表，每个 idempotency_key 在未完成期间最多一条
CREATE TABLE transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_account UUID NOT NULL,
    to_account UUID NOT NULL,
    amount DECIMAL NOT NULL,
    idempotency_key TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    completed_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX uniq_pending_transfer 
    ON transfers(idempotency_key)
    WHERE completed_at IS NULL;

-- 重复发送的 transfer 在前一个完成前会被拦截
-- 完成后允许再次提交（业务上代表"另一笔独立转账"）
```

### 案例 3：SaaS 多租户配置

```sql
-- 每个 (tenant, key) 组合最多一个 active 配置
CREATE TABLE feature_flags (
    id BIGSERIAL PRIMARY KEY,
    tenant_id UUID NOT NULL,
    flag_key TEXT NOT NULL,
    value JSONB,
    is_active BOOLEAN DEFAULT true,
    activated_at TIMESTAMPTZ,
    deactivated_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX uniq_active_flag 
    ON feature_flags(tenant_id, flag_key)
    WHERE is_active = true;

-- 切换标志值时：
-- 1. UPDATE 旧行 SET is_active = false, deactivated_at = now()
-- 2. INSERT 新行 (..., is_active = true)
-- 全程是同一个事务，部分 UNIQUE 索引保证不会有"两条 active 同时存在"
```

### 案例 4：分布式系统的 Leader 选举

```sql
CREATE TABLE leader_election (
    id BIGSERIAL PRIMARY KEY,
    node_id TEXT NOT NULL,
    is_leader BOOLEAN NOT NULL DEFAULT false,
    heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    term_id BIGINT NOT NULL
);

-- 全局只能有一个 leader（无论 term）
CREATE UNIQUE INDEX uniq_leader ON leader_election(is_leader)
    WHERE is_leader = true;

-- 节点抢主：
INSERT INTO leader_election (node_id, is_leader, term_id) 
VALUES ('node-1', true, 1)
ON CONFLICT (is_leader) WHERE is_leader = true 
DO NOTHING;
-- 第一个成功抢到的节点成为 leader；后续 INSERT 都失败
```

部分 UNIQUE + ON CONFLICT 是 PostgreSQL 上实现"原子抢主"最优雅的方案。

## 部分 UNIQUE 索引与 ON CONFLICT / MERGE 的互动

### PostgreSQL 的 ON CONFLICT 必须能"指向"索引

```sql
CREATE UNIQUE INDEX uniq_active_email ON users(email) WHERE deleted_at IS NULL;

-- 错误：ON CONFLICT 不带谓词
INSERT INTO users(email, deleted_at) VALUES ('a@b.com', NULL)
ON CONFLICT (email) DO NOTHING;
-- ERROR: there is no unique or exclusion constraint matching the ON CONFLICT specification

-- 正确：带 index_predicate
INSERT INTO users(email, deleted_at) VALUES ('a@b.com', NULL)
ON CONFLICT (email) WHERE deleted_at IS NULL DO NOTHING;
```

PG 的 `ON CONFLICT` 子句必须明确指定一个唯一索引，包括它的谓词，才能用部分 UNIQUE。

### MERGE 与部分 UNIQUE

```sql
-- PostgreSQL 15+ 的 MERGE
MERGE INTO users tgt
USING (VALUES ('alice', 'a@b.com')) AS src(username, email)
ON tgt.username = src.username AND tgt.deleted_at IS NULL
WHEN MATCHED THEN UPDATE SET email = src.email
WHEN NOT MATCHED THEN INSERT (username, email) VALUES (src.username, src.email);
```

注意：MERGE 的 `ON` 条件必须显式包含部分索引的谓词（`deleted_at IS NULL`），否则 PG 不会用部分索引做匹配。

### SQL Server MERGE

```sql
MERGE users AS tgt
USING (VALUES ('alice', 'a@b.com')) AS src(username, email)
ON tgt.username = src.username AND tgt.deleted_at IS NULL
WHEN MATCHED THEN UPDATE SET email = src.email
WHEN NOT MATCHED THEN INSERT (username, email) VALUES (src.username, src.email);
```

SQL Server 的 filtered unique index 与 MERGE 兼容性较好，但仍需注意参数化查询的匹配陷阱。

## 关键发现

1. **部分 UNIQUE 索引解锁了"条件唯一"业务规则**：软删除、状态机、多版本、单一主项、分布式锁——这些场景没有部分 UNIQUE 只能靠触发器或编码技巧。

2. **PostgreSQL 7.0（2000）是先驱**：最早实现 `CREATE UNIQUE INDEX ... WHERE`（7.2 完善），至今仍是功能最完整的引擎，谓词最灵活、匹配最智能、与表达式索引/INCLUDE 自由组合。

3. **SQL Server 2008 跟进 filtered unique index**：语法相近但限制更多——参数化查询匹配陷阱、谓词不能用计算列/UDF/`BETWEEN` 等是常见痛点。

4. **SQLite 3.8.0 (2013) 让嵌入式数据库也能玩**：移动端 App 经常需要"软删除 + 唯一字段"，SQLite 部分 UNIQUE 是杀手级特性。

5. **CockroachDB 19.x (2019) 把它带进分布式数据库**：减少 Raft 写放大对分布式系统尤其有意义；谓词匹配算法借鉴自 PG。

6. **Firebird 5.0 (2023) 是最晚跟进的关系数据库之一**：证明部分 UNIQUE 是被持续主动选择的特性而非历史包袱。

7. **MySQL/MariaDB/Oracle 是缺席者**：MySQL/MariaDB 完全不支持，只能靠生成列 + 全表 UNIQUE 变通；Oracle 通过 CASE 函数索引模拟，但查询必须用相同表达式才能命中。

8. **SQL:2008 的 NULLS NOT DISTINCT 是补丁但来得很晚**：PostgreSQL 15（2022 年 10 月）是第一个开源数据库实现，YugabyteDB/Greenplum/DuckDB/CockroachDB 在跟进或计划中，MySQL/Oracle 尚无计划。

9. **SQL Server 默认 UNIQUE = NULLS NOT DISTINCT**：与几乎所有其他引擎相反，迁移时是常见痛点；filtered unique index `WHERE col IS NOT NULL` 是 SQL Server 把 UNIQUE 改回标准行为的常用变通。

10. **Oracle 多列 UNIQUE 的"全 NULL 才相等"独一无二**：与所有其他引擎不同，迁移到 PG/MySQL 时这一行为差异需要特别小心。

11. **分析型 MPP 普遍不强制 UNIQUE**：Snowflake/BigQuery/Redshift 的 UNIQUE 仅是元数据提示，部分 UNIQUE 在这里也没有意义；ClickHouse 干脆没有 UNIQUE 约束。

12. **Spanner 的 NULL_FILTERED UNIQUE 是分布式系统的折衷**：只支持"过滤 NULL 行"这一最常见子集，避开任意谓词匹配的复杂度。

13. **谓词蕴含判断是技术核心**：部分 UNIQUE 的"约束作用"无条件生效（写入时强制），但"被查询利用"需要 Q ⇒ P 证明；PostgreSQL 的 `predtest.c` 是业界最完整的实现。

14. **参数化查询匹配陷阱普遍存在**：所有引擎都难以在编译期匹配参数化谓词到字面量索引谓词；OPTION (RECOMPILE)、字面量内联、`prepareThreshold=0` 是常见解法。

15. **部分 UNIQUE + ON CONFLICT / MERGE 是杀手组合**：PostgreSQL 的 `ON CONFLICT (...) WHERE ...` 把"幂等写入条件唯一"变成单语句操作，是分布式系统幂等设计的最佳工具。

16. **多列 + 部分 + NULL 处理 + NULLS NOT DISTINCT 一起用**：是 PG 15+ 提供的最强组合，可以精确表达任何复杂的"条件唯一 + NULL 行为"业务需求。

## 参考资料

- PostgreSQL: [CREATE UNIQUE INDEX](https://www.postgresql.org/docs/current/sql-createindex.html)
- PostgreSQL: [Partial Indexes](https://www.postgresql.org/docs/current/indexes-partial.html)
- PostgreSQL 15 Release Notes: [UNIQUE NULLS NOT DISTINCT](https://www.postgresql.org/docs/15/release-15.html)
- PostgreSQL 源码: `src/backend/optimizer/util/predtest.c`（谓词蕴含判断）
- SQL Server: [Create Filtered Indexes](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/create-filtered-indexes)
- SQL Server: [UNIQUE Constraints with NULL](https://learn.microsoft.com/en-us/sql/relational-databases/tables/unique-constraints-and-check-constraints)
- SQLite: [Partial Indexes](https://www.sqlite.org/partialindex.html)
- CockroachDB: [Partial Indexes](https://www.cockroachlabs.com/docs/stable/partial-indexes)
- Oracle: [Function-Based Indexes](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/indexes-and-index-organized-tables.html)
- Firebird 5.0 Release Notes: [Partial Indexes](https://firebirdsql.org/file/documentation/release_notes/html/en/5_0/rnfb50-engine-partial-index.html)
- YugabyteDB: [Partial Indexes](https://docs.yugabyte.com/preview/explore/ysql-language-features/indexes-constraints/partial-index-ysql/)
- Google Spanner: [NULL_FILTERED Indexes](https://cloud.google.com/spanner/docs/secondary-indexes#null-filtered)
- ISO/IEC 9075-2:2008 Foundation, Clause 11.7（unique constraint definition）
- 学术论文: Stonebraker, M. "The Case for Partial Indexes" (1989), SIGMOD Record 18(4)
