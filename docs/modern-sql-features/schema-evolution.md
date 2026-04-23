# Schema 演进模式 (Schema Evolution Patterns)

凌晨三点发布新版本，应用代码需要在用户表新增一列 `mfa_enabled BOOLEAN`——如果这条 ALTER TABLE 锁表 40 分钟，整个登录系统将在最高峰期彻底瘫痪。Schema 演进（Schema Evolution）不只是 ALTER TABLE 的语法，而是一门关于**向后兼容性、零停机部署、多版本读写共存**的工程艺术。

本文聚焦于 Schema 演进的**模式与策略**，而不是 ALTER TABLE 的基础语法（见 `alter-table-syntax.md`）或 online DDL 的底层实现机制（见 `online-ddl-implementation.md` 与 `ddl-transactionality-online.md`）。

## 为什么 Schema 演进如此关键

在单体应用 + 单点部署的时代，停机维护窗口是常态，一条 `ALTER TABLE` 锁表 30 分钟是可以接受的。但现代系统架构的三大趋势让 Schema 演进从"运维操作"上升为"核心架构能力"：

1. **零停机部署 (Zero-downtime deployment)**：蓝绿部署、滚动升级、灰度发布要求**新旧版本代码共存**，schema 必须同时兼容新旧代码。
2. **持续集成/持续部署 (CI/CD)**：每天可能有几十次 schema 变更，每次都必须是可逆、可回滚、对生产系统零影响的。
3. **分布式与多副本**：schema 变更必须在所有节点上**一致地完成**，不能出现某些节点已更新而另一些节点仍在使用旧 schema 的情况。

典型反面案例：
- 直接 `DROP COLUMN`：如果应用代码仍在写入该列，立刻 SQL 错误。
- `ALTER COLUMN TYPE` 从 `INT` 到 `BIGINT`：MySQL 5.7 会锁表并重写整张表。
- 重命名列：老代码用旧名字读，新代码用新名字读，同时存在时会崩溃。

这些问题背后的共同答案是 **Expand-Contract（扩张-收缩）模式**，本文会深入展开。

## 没有 SQL 标准

SQL:2003 定义了基础的 `ALTER TABLE` 语法（ADD COLUMN、DROP COLUMN、ALTER COLUMN），但**没有定义任何关于 schema 演进、online DDL 或 metadata-only 变更的行为**。所有"快速 ADD COLUMN"、"INSTANT DDL"、"metadata-only 变更"都是引擎各自的扩展。

这导致了三个后果：

1. **术语混乱**：MySQL 叫 `INSTANT`，PostgreSQL 叫 `fast-default`，Oracle 叫 `ADD COLUMN with DEFAULT`，Snowflake/BigQuery 叫 `metadata-only`。
2. **语义差异**：同样是"不重写表"，各引擎对 NULL/DEFAULT/NOT NULL 的组合支持度不同。
3. **可移植性几乎为零**：跨引擎的 schema 迁移脚本几乎都需要重写。

## 支持矩阵（45+ 引擎综合）

### 核心能力：添加/删除/修改列

| 引擎 | 添加可空列 O(1) | 添加 NOT NULL + DEFAULT O(1) | 删除列 | 重命名列 | 加宽类型安全 |
|------|----------------|------------------------------|--------|----------|--------------|
| PostgreSQL | 是 (元数据) | 是 (PG 11+, fast-default) | 是 (元数据, VACUUM 物理) | 是 (元数据) | 部分 (INT→BIGINT 需重写) |
| MySQL 8.0 | 是 (INSTANT) | 是 (INSTANT) | 是 (INSTANT, 8.0.29+) | 是 (INSTANT) | 是 (INSTANT 仅限 VARCHAR 扩展) |
| MySQL 8.0.29+ | 是 (任意位置) | 是 (任意位置) | 是 (INSTANT) | 是 (元数据) | 部分 |
| MariaDB | 是 (INSTANT, 10.3+) | 是 | 是 (10.5+) | 是 | 部分 |
| SQLite | 是 (元数据) | 是 (3.35+) | 是 (3.35+) | 是 (3.25+) | 否 (需要 rebuild) |
| Oracle | 是 | 是 (11g+) | 是 (物理删除可选) | 是 | 是 |
| SQL Server | 是 (元数据) | 是 (2012+) | 是 (元数据) | 是 (sp_rename) | 是 (VARCHAR) |
| DB2 | 是 | 是 | 是 | 是 | 是 |
| Snowflake | 是 (metadata-only) | 是 | 是 | 是 | 是 (所有变更 metadata-only) |
| BigQuery | 是 (metadata-only) | 部分 (REQUIRED 有限制) | 是 | 是 (2022+) | 是 (partition-aware) |
| Redshift | 是 | 是 | 是 | 是 | 部分 (VARCHAR) |
| DuckDB | 是 | 是 | 是 | 是 | 是 |
| ClickHouse | 是 (metadata-only, mutation) | 是 | 是 (mutation) | 是 | 是 (部分需 mutation) |
| Trino | 依赖连接器 | 依赖连接器 | 依赖连接器 | 依赖连接器 | 依赖连接器 |
| Presto | 依赖连接器 | 依赖连接器 | 依赖连接器 | 依赖连接器 | 依赖连接器 |
| Spark SQL | 是 (Iceberg/Delta) | 依赖格式 | 是 | 是 | 是 (Iceberg) |
| Hive | 是 | 部分 | 是 (ORC 元数据) | 是 | 部分 |
| Flink SQL | 是 (Catalog 级) | -- | 部分 | 部分 | -- |
| Databricks | 是 (Delta) | 是 (Delta) | 是 (Delta) | 是 (Delta) | 是 (Delta) |
| Teradata | 是 | 是 | 是 | 是 | 部分 |
| Greenplum | 是 | 是 (继承 PG) | 是 | 是 | 部分 |
| CockroachDB | 是 (F1 online) | 是 | 是 (异步) | 是 | 是 (online) |
| TiDB | 是 (INSTANT, 6.5+) | 是 | 是 (异步) | 是 | 部分 (online) |
| OceanBase | 是 (4.0+) | 是 | 是 | 是 | 部分 |
| YugabyteDB | 是 (继承 PG 语义) | 是 | 是 | 是 | 部分 |
| SingleStore | 是 (online ALTER) | 是 | 是 | 是 | 部分 |
| Vertica | 是 (metadata) | 是 | 是 | 是 | 是 |
| Impala | 是 | 是 | 是 | 是 | 依赖格式 |
| StarRocks | 是 (LightSchemaChange) | 是 | 是 | 是 (3.1+) | 部分 |
| Doris | 是 (LightSchemaChange, 1.2+) | 是 | 是 | 是 | 部分 |
| MonetDB | 是 | 是 | 是 | 是 | 部分 |
| CrateDB | 是 | 部分 | 否 (限制) | 否 (限制) | 部分 |
| TimescaleDB | 是 (继承 PG) | 是 | 是 | 是 | 部分 |
| QuestDB | 是 | 部分 | 是 | 是 (6.3+) | 部分 |
| Exasol | 是 | 是 | 是 | 是 | 是 |
| SAP HANA | 是 | 是 | 是 | 是 | 是 |
| Informix | 是 | 是 | 是 | 是 | 部分 |
| Firebird | 是 | 是 | 是 | 是 | 部分 |
| H2 | 是 | 是 | 是 | 是 | 部分 |
| HSQLDB | 是 | 是 | 是 | 是 | 部分 |
| Derby | 是 | 部分 | 是 | 是 | 部分 |
| Amazon Athena | 是 (Iceberg/Glue) | -- | 依赖格式 | 依赖格式 | 依赖格式 |
| Azure Synapse | 是 | 是 | 是 | 是 | 部分 |
| Google Spanner | 是 (online) | 是 | 是 (long-running job) | 否 (需 CREATE/DROP) | 部分 |
| Materialize | 是 | 部分 | 是 | 是 | 部分 |
| RisingWave | 是 | 部分 | 是 | 是 | 部分 |
| InfluxDB (SQL) | 是 (schemaless) | -- | 部分 | -- | -- |
| DatabendDB | 是 | 是 | 是 | 是 | 是 |
| Yellowbrick | 是 | 是 | 是 | 是 | 部分 |
| Firebolt | 是 | 是 | 是 | 是 | 部分 |
| Iceberg (表格式) | 是 (schema ID) | 是 | 是 | 是 (column ID) | 是 (promotion 规则) |
| Delta Lake (表格式) | 是 (mergeSchema) | 是 | 是 (7+) | 是 (column mapping) | 是 |
| Hudi (表格式) | 是 | 是 | 是 | 部分 | 部分 |

### 进阶能力：类型变更、列重排、版本追踪

| 引擎 | 缩窄类型 (unsafe) | 在线类型变更 | 列重排序 | 重命名表 | Schema 版本追踪 |
|------|------------------|--------------|----------|----------|-----------------|
| PostgreSQL | 重写表 | 部分 (USING 子句) | 否 (固定顺序) | 是 | 无 (需外部) |
| MySQL 8.0 | 重写表或 COPY | 是 (ALGORITHM=INPLACE) | 是 (AFTER col) | 是 | 无 |
| MySQL 8.0.29+ | 重写表或 COPY | 是 | 是 (INSTANT) | 是 | 无 |
| MariaDB | 重写表 | 部分 | 是 | 是 | 无 |
| SQLite | 重建表 | 否 | 否 | 是 | 无 |
| Oracle | 重写表或 MOVE | 是 (online redef) | 否 | 是 (11g+) | 是 (edition) |
| SQL Server | 重写表 | 是 (online) | 否 | sp_rename | 无 (有 DDL trigger) |
| DB2 | 重写表 | 是 | 否 | 是 | 无 |
| Snowflake | metadata-only | 是 (metadata) | 否 | 是 | 是 (Time Travel) |
| BigQuery | 受限 | 受限 | 否 | 是 | 是 (snapshot) |
| Redshift | 受限 | 受限 | 否 | 是 | 无 |
| DuckDB | 是 | 是 | 否 | 是 | 无 |
| ClickHouse | mutation | mutation | 是 (AFTER/FIRST) | 是 | 无 |
| Trino | 依赖连接器 | 依赖连接器 | 依赖连接器 | 依赖连接器 | 依赖 |
| Spark SQL | 依赖格式 | Iceberg 支持 | 是 (Iceberg) | 是 | 是 (Iceberg snapshot) |
| Hive | 重写 | 部分 | 是 (AFTER/FIRST) | 是 | 无 |
| Databricks | Delta 支持 | Delta 支持 | 是 (Delta) | 是 | 是 (Delta version) |
| Teradata | 是 | 部分 | 否 | 是 | 无 |
| CockroachDB | 是 (F1 online) | 是 (F1 online) | 否 | 是 | 是 (descriptor version) |
| TiDB | 是 | 是 | 否 | 是 | 是 (schema version) |
| OceanBase | 是 | 部分 | 否 | 是 | 是 |
| YugabyteDB | 是 | 是 | 否 | 是 | 是 (DocDB schema) |
| StarRocks | 部分 | 部分 | 否 | 是 | 无 |
| Doris | 部分 | 部分 | 否 | 是 | 无 |
| Vertica | 是 | 是 | 否 | 是 | 无 |
| Google Spanner | 部分 | 部分 | 否 | 否 | 是 (schema change history) |
| Iceberg | 否 (显式 DROP/ADD) | schema ID 切换 | 是 | 是 | 是 (schema history) |
| Delta Lake | overwriteSchema | 部分 | 是 (column mapping) | 是 | 是 (transaction log) |
| Hudi | 部分 | 部分 | 部分 | 是 | 是 (commit timeline) |

> 统计：约 35 个引擎支持某种形式的 "INSTANT / metadata-only" ADD COLUMN；约 10 个引擎（含湖仓表格式）提供真正的 schema 版本追踪；只有 Iceberg/Delta/Hudi 与 MySQL 8.0.29+/CockroachDB/TiDB 能够在不重写数据的前提下做出"安全的列重命名"。

## 各能力详解

### 添加可空列：几乎所有引擎都是 O(1)

这是最基本的向后兼容变更。老代码读到新列是 NULL，新代码写入新值。

```sql
-- 通用语法：几乎所有引擎都支持，都是 metadata-only
ALTER TABLE users ADD COLUMN mfa_enabled BOOLEAN;  -- NULL 默认
```

实现原理：只修改系统表（pg_attribute / INFORMATION_SCHEMA.COLUMNS / Iceberg schema JSON），不触碰数据文件。老数据行读取时，遇到"新列"自动返回 NULL。

### 添加 NOT NULL + DEFAULT 列：关键分水岭

这是"快速 DDL"能力的分水岭。在 PostgreSQL 11 之前，这条 DDL 需要**全表重写**（每行都要物理上写入 DEFAULT 值）：

```sql
ALTER TABLE users ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';
```

PostgreSQL 10 的执行：O(N) 全表重写，锁表，10 亿行表需要数小时。
PostgreSQL 11+ 的执行：O(1) 元数据变更，将 DEFAULT 存入 `pg_attribute.attmissingval`，读取老行时遇到该列直接返回 missingval。这被称为 **fast-default**。

```sql
-- PG 11+ 内部原理
-- 1. 变更 pg_attribute: 记录 atthasmissing=true, attmissingval='active'
-- 2. 新写入的行: 正常包含 status 列
-- 3. 老行的读取: 解析到末尾发现缺 status → 用 attmissingval 填充
```

MySQL 8.0 的 INSTANT ADD COLUMN 原理类似，但有一个关键限制：**8.0.0~8.0.28 只能添加到表末尾**。这是因为 InnoDB 行格式（COMPACT/DYNAMIC）中列按 ordinal 位置存储，若插入中间位置会破坏所有老行的解析。8.0.29（2022 年 4 月）通过引入 **行版本号 (row version)** 解决了这个问题：每行都标记自己属于哪个 schema 版本，读取时按对应版本解析。

### 删除列：元数据 vs 物理删除

大多数引擎的 DROP COLUMN 语义是：

```sql
ALTER TABLE users DROP COLUMN legacy_field;
```

1. **元数据删除**（PostgreSQL / MySQL 8.0 INSTANT / Snowflake / ClickHouse）：系统表中标记该列为"已删除"，查询时隐藏。存储层数据保留，直到后续的 VACUUM / OPTIMIZE / mutation 才真正删除。
2. **物理删除**（SQLite 3.35+ / 一些简单引擎）：立刻重写整个表或文件。

```sql
-- PostgreSQL: 逻辑上立刻删除，物理上 VACUUM FULL 才回收
ALTER TABLE users DROP COLUMN legacy_field;
VACUUM FULL users;  -- 物理回收空间（锁表）

-- MySQL 8.0.29+: INSTANT DROP COLUMN
ALTER TABLE users DROP COLUMN legacy_field, ALGORITHM=INSTANT;

-- Snowflake: 纯元数据变更，无需 VACUUM
ALTER TABLE users DROP COLUMN legacy_field;
```

### 重命名列：最危险的变更

因为绝大多数引擎直接修改元数据，重命名瞬间完成：

```sql
-- PostgreSQL / MySQL / Oracle / SQL Server (sp_rename) 等
ALTER TABLE users RENAME COLUMN email TO email_address;
```

但危险在于**应用层**：老代码仍然 `SELECT email FROM users`，会立刻报错。所以重命名列几乎总是要通过 Expand-Contract 模式来完成：
1. 先 ADD COLUMN email_address
2. 双写 email 和 email_address
3. 回填 email_address
4. 应用切换读 email_address
5. DROP COLUMN email

### 加宽类型：部分安全、部分重写

"加宽"指不会丢失数据的类型变更：

| 变更 | 是否安全 | 是否需要重写 |
|------|----------|--------------|
| VARCHAR(50) → VARCHAR(100) | 安全 | 多数引擎 metadata-only |
| INT → BIGINT | 安全 | 多数引擎需重写（存储格式不同） |
| FLOAT → DOUBLE | 安全 | 多数引擎需重写 |
| DECIMAL(10,2) → DECIMAL(20,2) | 安全 | PG/Oracle metadata-only，MySQL 需重写 |
| TIMESTAMP → TIMESTAMPTZ | 半安全 | 需要考虑时区解释 |
| DATE → TIMESTAMP | 安全 | 需要重写 |

```sql
-- MySQL: VARCHAR 长度增加可能是 INSTANT（如果新长度仍 ≤ 255 或仍 > 255）
ALTER TABLE users MODIFY COLUMN name VARCHAR(100), ALGORITHM=INSTANT;
-- 跨越 255 边界时不支持 INSTANT（因为长度前缀字节数变化）

-- PostgreSQL: VARCHAR(N) 增加长度是 O(1) 元数据变更
ALTER TABLE users ALTER COLUMN name TYPE VARCHAR(100);
```

### 缩窄类型：总是 unsafe

```sql
-- 危险变更: VARCHAR(100) → VARCHAR(50)
-- 可能导致数据截断
ALTER TABLE users ALTER COLUMN name TYPE VARCHAR(50);
-- PostgreSQL: 会扫描全表验证，若有行 len > 50 则报错
-- MySQL: 默认截断并发出 warning (STRICT_TRANS_TABLES 下报错)

-- 正确做法：先扫描验证，再收窄
SELECT COUNT(*) FROM users WHERE LENGTH(name) > 50;
-- = 0 才能安全收窄
```

### 列重排序：鲜为人知的分歧

SQL 标准没有"列位置"的概念，但 MySQL 和 ClickHouse 支持 `AFTER col` / `FIRST`：

```sql
-- MySQL: 添加到指定位置
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;
-- MySQL 8.0.29+: 这是 INSTANT 变更
-- MySQL 8.0.28 及以前: 即使 ADD COLUMN INSTANT 也只能加到末尾

-- ClickHouse
ALTER TABLE users ADD COLUMN phone String AFTER email;

-- PostgreSQL: 完全不支持（列顺序由 attnum 决定，不可变）
-- 变通: 必须重建表
```

PostgreSQL 不支持列重排是**有意的设计**：允许列重排会让行存储格式的 ordinal 位置成为全局可变量，每次重排都需要重写所有行。

### 重命名表：多数引擎支持

```sql
-- 标准语法
ALTER TABLE old_name RENAME TO new_name;

-- Oracle 11g+、MySQL、PostgreSQL、SQL Server 等都支持
-- Google Spanner 不直接支持：必须 CREATE TABLE + copy + DROP
```

陷阱：外键引用、视图、触发器可能不会自动更新到新表名（各引擎行为不一致）。

### Schema 版本追踪

真正的 schema 版本追踪需要数据库内部维护"每个事务看到哪个 schema 版本"：

| 引擎 | 版本追踪机制 |
|------|-------------|
| Oracle Edition-Based Redefinition | 完整的多版本 schema，不同会话可绑定到不同 edition |
| CockroachDB / TiDB | schema descriptor 的版本号，结合 F1 paper 的多态状态 |
| Google Spanner | schema change history，每次变更生成新版本号 |
| Iceberg | schema history 存储在 table metadata JSON |
| Delta Lake | transaction log 记录每次 schema 变化 |
| Hudi | commit timeline 包含 schema 演化 |
| Snowflake | Time Travel 查询历史 schema |
| 其他 | 大多依赖外部工具（Flyway / Liquibase / sqitch） |

## 各引擎深度剖析

### MySQL 8.0：INSTANT ADD COLUMN 的演进史

MySQL InnoDB 的 INSTANT 能力经历了多个阶段：

**阶段 1 (MySQL 5.7 及以前)**: 任何 ADD COLUMN 都需要 COPY 或 INPLACE 重建整表。10 亿行表可能锁表数小时。

**阶段 2 (MySQL 8.0.12, 2018)**: 引入 INSTANT ADD COLUMN，但限制严格：
- 只能添加到**表末尾**
- 不能与其他变更组合（如同时 ADD INDEX）
- 表必须是 InnoDB，REDUNDANT 行格式不支持
- 被加密的表不支持

```sql
-- MySQL 8.0.12 ~ 8.0.28
ALTER TABLE orders ADD COLUMN status VARCHAR(20) DEFAULT 'pending',
    ALGORITHM=INSTANT;
-- ✓ 加到末尾 OK

ALTER TABLE orders ADD COLUMN status VARCHAR(20) AFTER customer_id,
    ALGORITHM=INSTANT;
-- ✗ 报错：ALGORITHM=INSTANT is not supported for this operation
```

**阶段 3 (MySQL 8.0.29, 2022 年 4 月)**: 引入 **row version (行版本号)**，真正的 INSTANT ADD/DROP COLUMN anywhere。

```sql
-- MySQL 8.0.29+
ALTER TABLE orders ADD COLUMN country VARCHAR(2) AFTER customer_id,
    ALGORITHM=INSTANT;
-- ✓ 插入中间位置也是 INSTANT

ALTER TABLE orders DROP COLUMN legacy_col, ALGORITHM=INSTANT;
-- ✓ INSTANT DROP
```

实现原理：InnoDB 在每行的 header 中加入一个 `row_version` 字段，每次 INSTANT DDL 递增表的 `current_version`。读取时：
- `row_version == current_version`: 直接用当前 schema 解析
- `row_version < current_version`: 查找"版本映射表"，按老 schema 解析后补齐新列的 DEFAULT

**INSTANT 数量上限**: 每表最多 64 次 INSTANT 变更（行版本号用 6 位）。超过后必须通过 OPTIMIZE TABLE 重置。

```sql
-- 检查表的 INSTANT 计数
SELECT * FROM information_schema.INNODB_TABLES WHERE NAME LIKE '%orders%';
-- TOTAL_ROW_VERSIONS 字段
```

### PostgreSQL：fast-default 的精巧设计

PostgreSQL 11 (2018) 通过 `pg_attribute.attmissingval` 实现 O(1) 的 `ADD COLUMN ... DEFAULT`:

```sql
-- PG 11+
ALTER TABLE orders ADD COLUMN priority INT NOT NULL DEFAULT 0;
-- 元数据变更，瞬间完成

-- 内部实现
SELECT attname, atthasmissing, attmissingval
FROM pg_attribute
WHERE attrelid = 'orders'::regclass AND attname = 'priority';
-- atthasmissing=t, attmissingval={0}
```

关键设计：fast-default 只对**常量 DEFAULT** 生效。如果 DEFAULT 是 `volatile` 函数（如 `random()` 或 `nextval('seq')`），PG 仍然需要全表重写——因为每行应该拿到独立的值。

```sql
-- ✓ O(1) metadata-only
ALTER TABLE orders ADD COLUMN created_at TIMESTAMP DEFAULT '2024-01-01';

-- ✗ 全表重写 (volatile 函数)
ALTER TABLE orders ADD COLUMN order_id BIGINT DEFAULT nextval('orders_seq');

-- ✗ 全表重写 (也是 volatile)
ALTER TABLE orders ADD COLUMN assigned_at TIMESTAMP DEFAULT NOW();
```

另一个关键限制：**PostgreSQL 不支持列重排**。列的 ordinal 位置由 `attnum` 决定，不可修改。如需调整列顺序，唯一方案是重建表。

### Oracle：ADD COLUMN with DEFAULT 的历史

Oracle 11g (2007) 就支持了 O(1) 的 `ADD COLUMN ... DEFAULT`（早于 PG 11 整整 11 年）:

```sql
-- Oracle 11g+
ALTER TABLE orders ADD priority NUMBER DEFAULT 0 NOT NULL;
-- 元数据变更，瞬间完成
```

Oracle 12c 进一步扩展：可变 DEFAULT（如 SEQUENCE.NEXTVAL）也能做 metadata-only，通过在读取时动态生成。

对于需要重排、需要压缩重组的场景，Oracle 提供 **online redefinition (DBMS_REDEFINITION)**:

```sql
-- Oracle 的 online table redefinition
BEGIN
  DBMS_REDEFINITION.START_REDEF_TABLE(
    uname        => 'SCOTT',
    orig_table   => 'ORDERS',
    int_table    => 'ORDERS_INT',
    options_flag => DBMS_REDEFINITION.CONS_USE_ROWID
  );
END;
```

基本思路：创建一个"影子表"，在后台复制数据，通过日志捕获增量变更，最后瞬间切换。**Edition-Based Redefinition (EBR)** 更进一步，允许应用与多版本 schema 共存。

### SQL Server：2005 以来的 INSTANT

SQL Server 2005 起，简单的 `ADD COLUMN ... NULL` 就是元数据变更。SQL Server 2012 开始，`ADD COLUMN ... NOT NULL DEFAULT` 对固定长度类型也是 metadata-only（与 Oracle 类似的思路：read-time fill-in）。

```sql
-- SQL Server 2012+
ALTER TABLE orders ADD priority INT NOT NULL DEFAULT 0;
-- metadata-only, 瞬间完成

-- 但是 VARCHAR 的 DEFAULT 对 NOT NULL 列仍可能触发重写
ALTER TABLE orders ADD status VARCHAR(20) NOT NULL DEFAULT 'pending';
-- 2012+ 也是 metadata-only，但对 MAX 类型有限制
```

SQL Server 的"在线 DDL" 在企业版中支持 `WITH (ONLINE = ON)` 选项，大部分 ALTER TABLE 不会阻塞 DML。

### TiDB：继承 F1 设计 + INSTANT

TiDB 从设计之初就采用 F1 paper 的 online schema change 协议（下面 CockroachDB 节详解）。6.5 版本起，TiDB 加入了 MySQL 兼容的 INSTANT DDL：

```sql
-- TiDB 6.5+
ALTER TABLE orders ADD COLUMN priority INT DEFAULT 0;
-- 默认 ALGORITHM=INSTANT，瞬间完成

-- 监控 schema 版本
SELECT * FROM information_schema.ddl_jobs ORDER BY start_time DESC LIMIT 5;
```

TiDB 的所有 schema 变更都会经过 DDL owner 协调，确保全集群的 schema 版本一致。即使是 INSTANT ADD COLUMN 也需要通过 PD (Placement Driver) 同步 schema 版本。

### CockroachDB：F1 paper 的忠实实现

CockroachDB 的 online schema change 基于 Google F1 团队 2013 年的 VLDB 论文 "Online, Asynchronous Schema Change in F1"。核心思想：一个 schema 变更不能跨多个节点瞬间完成（分布式一致性约束），但**可以通过中间状态让新老 schema 安全共存**。

F1 协议的四个状态：

```
ABSENT → DELETE_ONLY → WRITE_ONLY → DELETE_AND_WRITE_ONLY → PUBLIC
```

以 "添加二级索引" 为例：
1. **ABSENT**: 索引不存在
2. **DELETE_ONLY**: 所有节点知道索引存在，但**只处理删除**（老数据进入索引会被忽略，但新数据的删除要同步到索引）
3. **WRITE_ONLY**: 所有节点**处理插入和删除**，但查询**不使用**索引
4. **DELETE_AND_WRITE_ONLY**: 开始**回填**现有数据到索引
5. **PUBLIC**: 回填完成，查询可用索引

```sql
-- CockroachDB: 完全异步的 DDL
CREATE INDEX ON orders (customer_id);
-- 立刻返回，后台进度

-- 监控 schema 变更
SHOW JOBS;
-- 可看到 SCHEMA CHANGE 类型的任务进度
```

F1 协议保证了：**任何时刻，任意两个相邻状态的节点协作都不会产生数据不一致**。这是分布式 online DDL 的理论基础。

### Snowflake：metadata-only 的极致

Snowflake 的架构（存储计算分离 + 不可变存储文件）使得几乎所有 schema 变更都是 metadata-only：

```sql
-- 所有这些都是 O(1) metadata-only
ALTER TABLE orders ADD COLUMN priority INT DEFAULT 0;
ALTER TABLE orders DROP COLUMN legacy_field;
ALTER TABLE orders RENAME COLUMN status TO order_status;
ALTER TABLE orders ALTER COLUMN name SET DATA TYPE VARCHAR(200);
```

原理：Snowflake 的表数据以不可变的 micro-partition 存储，每个 micro-partition 的 header 记录了它所属的 schema version。查询时运行时按每个 micro-partition 的 schema version 解析。

Time Travel 让 schema 回滚成为可能：

```sql
-- 查询 30 分钟前的数据（带当时的 schema）
SELECT * FROM orders AT (OFFSET => -30*60);

-- 基于历史版本克隆
CREATE TABLE orders_backup CLONE orders BEFORE (STATEMENT => '<query_id>');
```

### BigQuery：partition-aware schema change

BigQuery 的 schema 变更在分区表上有特殊语义：每个分区可以有独立的 schema 版本：

```sql
-- BigQuery: 添加可空列是 metadata-only
ALTER TABLE `project.dataset.orders` ADD COLUMN priority INT64;

-- BigQuery 特殊性：REQUIRED → NULLABLE 的松弛允许
ALTER TABLE `project.dataset.orders`
ALTER COLUMN status DROP NOT NULL;  -- REQUIRED → NULLABLE 允许

-- 但 NULLABLE → REQUIRED 不允许 (会破坏现有 NULL 行)
```

BigQuery 的 schema 变更都是 metadata-only 且立即对新查询生效，无需等待后台任务。

### Iceberg / Delta / Hudi：表格式层的 schema 演进

这三大湖仓表格式（table format）在 schema 演进上做了最前沿的设计：

#### Apache Iceberg

Iceberg 的核心创新是 **列有唯一 ID**（不是名字）。schema 存储类似：

```json
{
  "schema-id": 3,
  "fields": [
    {"id": 1, "name": "id", "type": "long"},
    {"id": 2, "name": "email_address", "type": "string"},
    {"id": 5, "name": "priority", "type": "int"}
  ]
}
```

列 ID 一旦分配永不重用。这带来了：

1. **安全的列重命名**: 只改名字，ID 不变。即使有列同名切换（A→B，然后新加 A），也不会混淆。
2. **安全的列删除+重加**: 删除的 ID 永远不复用，避免了"看起来是旧列但实际是新列"的陷阱。
3. **schema evolution 规则**: 严格定义了哪些类型变更是安全的。

```sql
-- Iceberg 支持的类型 promotion
-- int → long: 允许
-- float → double: 允许
-- decimal(P,S) → decimal(P',S) where P' > P: 允许
-- 其他类型变更: 必须显式 DROP + ADD COLUMN（新 column ID）

ALTER TABLE orders ALTER COLUMN amount TYPE BIGINT;  -- int → long, OK
ALTER TABLE orders ALTER COLUMN name TYPE INT;  -- string → int, 错误
```

Iceberg schema history 保留所有历史 schema：

```sql
-- 查询表的历史 schema
SELECT * FROM orders.history;
-- 每个 snapshot 对应一个 schema-id
```

#### Delta Lake

Delta Lake 使用 **column mapping** 解决类似问题：

```sql
-- 启用 column mapping（默认关闭）
ALTER TABLE orders SET TBLPROPERTIES (
  'delta.columnMapping.mode' = 'name',
  'delta.minReaderVersion' = '2',
  'delta.minWriterVersion' = '5'
);

-- 启用后，DROP COLUMN 不需要重写文件
ALTER TABLE orders DROP COLUMN legacy_field;  -- metadata-only

-- 重命名列也是安全的
ALTER TABLE orders RENAME COLUMN email TO email_address;
```

Delta 的 `mergeSchema` 允许自动 schema 演进：

```python
# Spark + Delta: 自动添加新列
df.write.format("delta") \
    .option("mergeSchema", "true") \
    .mode("append") \
    .saveAsTable("orders")
# 若 df 有新列，Delta 自动 ADD COLUMN

# overwriteSchema: 完全替换 schema
df.write.format("delta") \
    .option("overwriteSchema", "true") \
    .mode("overwrite") \
    .saveAsTable("orders")
```

Delta transaction log (`_delta_log/*.json`) 记录了每次 schema 变更，可以回溯：

```sql
-- 查询表的历史
DESCRIBE HISTORY orders;
-- 每一行显示 operation, operationParameters, schema 变化
```

#### Apache Hudi

Hudi 的 schema 演进相对保守（较晚加入 full schema evolution），但支持：

- ADD COLUMN (nullable 列)
- 类型 promotion (int → long, float → double, etc.)
- RENAME COLUMN (0.11+)

```sql
-- Hudi via Spark SQL
ALTER TABLE hudi_orders ADD COLUMNS (priority INT);
ALTER TABLE hudi_orders RENAME COLUMN status TO order_status;

-- Hudi 0.11+ 支持 full schema evolution
SET hoodie.schema.on.read.enable = true;
```

Hudi commit timeline 记录了每次 schema 版本，通过 `.hoodie/` 目录下的 commit 文件可以追溯。

## Expand-Contract 模式深度剖析

这是零停机部署的核心模式，也叫 "parallel change" 或 "blue-green schema"。

### 基本流程

以"将 `users.email` 重命名为 `users.email_address`" 为例：

```
阶段 1: EXPAND (扩张)
  - 数据库: ADD COLUMN email_address
  - 应用: 仍读写 email
  - 状态: 双列存在, 但 email_address 全为 NULL

阶段 2: MIGRATE WRITE (迁移写入)
  - 应用 v1.1: 写入时同时写 email 和 email_address
  - 读取时: 仍读 email
  - 状态: 新数据两列一致, 老数据 email_address=NULL

阶段 3: BACKFILL (回填)
  - 后台任务: UPDATE users SET email_address = email WHERE email_address IS NULL
  - 分批执行, 限流, 避免锁
  - 状态: 所有行两列一致

阶段 4: MIGRATE READ (迁移读取)
  - 应用 v1.2: 读取时从 email_address 读
  - 写入时: 仍双写
  - 状态: 两列一致, 读取路径已切换

阶段 5: CONTRACT (收缩)
  - 应用 v1.3: 只读写 email_address
  - 验证一段时间（通常 1-2 周）
  - 数据库: DROP COLUMN email
  - 状态: 完成迁移
```

### SQL 实现细节

```sql
-- Phase 1: EXPAND
ALTER TABLE users ADD COLUMN email_address VARCHAR(255);

-- Phase 2: MIGRATE WRITE (应用层改动) + 可选的 trigger 兜底
CREATE TRIGGER users_dual_write BEFORE INSERT OR UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION sync_email_columns();

CREATE OR REPLACE FUNCTION sync_email_columns() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.email IS DISTINCT FROM OLD.email THEN
        NEW.email_address := NEW.email;
    ELSIF NEW.email_address IS DISTINCT FROM OLD.email_address THEN
        NEW.email := NEW.email_address;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Phase 3: BACKFILL (分批)
DO $$
DECLARE
    batch_size INT := 10000;
    updated INT;
BEGIN
    LOOP
        UPDATE users SET email_address = email
        WHERE id IN (
            SELECT id FROM users
            WHERE email_address IS NULL
            LIMIT batch_size
            FOR UPDATE SKIP LOCKED
        );
        GET DIAGNOSTICS updated = ROW_COUNT;
        COMMIT;
        EXIT WHEN updated = 0;
        PERFORM pg_sleep(0.1);  -- 限流
    END LOOP;
END $$;

-- Phase 4: MIGRATE READ (应用层改动)

-- Phase 5: CONTRACT
DROP TRIGGER users_dual_write ON users;
ALTER TABLE users DROP COLUMN email;
```

### Expand-Contract 的陷阱

1. **回填窗口过长**: 大表的回填可能需要几小时甚至几天，期间写入放大。
2. **触发器性能**: 双写触发器会拖慢每次写入，需要对高 TPS 表谨慎使用。
3. **错过的边界情况**: 应用代码可能有"使用 email 但不经过 ORM"的路径（如后台脚本、JDBC 直连），要仔细审计。
4. **回滚困难**: 到阶段 4 后如果发现 bug，回滚到阶段 2 不是那么简单——需要反向迁移。
5. **唯一约束冲突**: 如果原列有 UNIQUE 约束，新列何时加 UNIQUE 约束有讲究——太早（回填前）会在回填时冲突，太晚（切读后）会在切换窗口出现重复。

## Rails / Django 迁移中的 Expand-Contract

### Rails: strong_migrations 与 safe defaults

Rails 社区的 [strong_migrations](https://github.com/ankane/strong_migrations) gem 强制了安全的 schema 迁移模式：

```ruby
# Rails migration: 添加列带 DEFAULT
class AddPriorityToOrders < ActiveRecord::Migration[7.0]
  def change
    # Rails 5.2+: 自动使用 fast-default (PG 11+ / MySQL 8.0+)
    add_column :orders, :priority, :integer, default: 0, null: false
  end
end

# 危险操作会被 strong_migrations 拦截
class RenameEmailColumn < ActiveRecord::Migration[7.0]
  def change
    rename_column :users, :email, :email_address
    # strong_migrations 报错:
    # "Renaming a column that's in use will cause errors in your application."
  end
end
```

Rails 社区推荐的重命名模式（真正的 Expand-Contract）:

```ruby
# Migration 1 (deploy 1)
class AddEmailAddressToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :email_address, :string
  end
end

# App code (deploy 2): 双写
class User < ApplicationRecord
  before_save :sync_email_address
  def sync_email_address
    self.email_address = self.email if email_changed?
  end
end

# Migration 3 (后台任务 + deploy 3): 回填 + 切读
class BackfillEmailAddress < ActiveRecord::Migration[7.0]
  def up
    User.in_batches.update_all('email_address = email')
  end
end

# Migration 4 (deploy 4): 移除旧列
class RemoveEmailFromUsers < ActiveRecord::Migration[7.0]
  def change
    safety_assured { remove_column :users, :email }
  end
end
```

### Django: RunPython + 三段式部署

Django ORM 在 migrations 中也推崇 Expand-Contract：

```python
# migrations/0010_add_email_address.py (部署 1)
class Migration(migrations.Migration):
    operations = [
        migrations.AddField(
            model_name='user',
            name='email_address',
            field=models.CharField(max_length=255, null=True),
        ),
    ]

# migrations/0011_backfill_email_address.py (部署 2, 需应用双写代码)
def backfill(apps, schema_editor):
    User = apps.get_model('myapp', 'User')
    for user in User.objects.iterator(chunk_size=1000):
        user.email_address = user.email
        user.save()

class Migration(migrations.Migration):
    operations = [
        migrations.RunPython(backfill, reverse_code=migrations.RunPython.noop),
    ]

# migrations/0012_remove_email.py (部署 3, 应用切读 email_address)
class Migration(migrations.Migration):
    operations = [
        migrations.RemoveField('user', 'email'),
    ]
```

Django 的 `RunPython` 允许在迁移中执行任意 Python 代码，但大表回填建议用 Celery 异步任务而不是同步迁移。

## 事件溯源系统中的 Schema 演进

事件溯源（Event Sourcing）系统面临**历史事件的 schema 演进**这一特殊挑战：旧事件是**不可变的**，无法重写。

### Upcasting 模式

在读取事件时，动态转换老版本 schema 到新版本：

```java
// Axon Framework 的 event upcaster
public class OrderCreatedV1ToV2Upcaster extends SingleEventUpcaster {
    @Override
    protected boolean canUpcast(IntermediateEventRepresentation ier) {
        return ier.getType().getName().equals("OrderCreated")
            && ier.getType().getRevision().equals("1");
    }

    @Override
    protected IntermediateEventRepresentation doUpcast(IntermediateEventRepresentation ier) {
        return ier.upcastPayload(
            new SimpleSerializedType("OrderCreated", "2"),
            JsonNode.class,
            payload -> {
                ObjectNode obj = (ObjectNode) payload;
                // V1 没有 currency 字段，默认为 USD
                if (!obj.has("currency")) {
                    obj.put("currency", "USD");
                }
                return obj;
            }
        );
    }
}
```

### 事件 schema 演进的三种策略

1. **Weak schema (弱 schema)**: JSON 存储，允许缺失字段。新代码处理"字段不存在"。
2. **Upcasting**: 读取时转换到当前版本。需要维护所有版本间的迁移链。
3. **Event Migration**: 批量重写事件（本质上违反了"事件不可变"原则，但对于 schema 错误修正有时必要）。

### SQL 层面的模拟

用 SQL 数据库实现事件溯源时：

```sql
-- 事件表
CREATE TABLE events (
    event_id UUID PRIMARY KEY,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    event_version INT NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMP NOT NULL
);

-- 应用层的 upcaster 处理 payload schema 演进
-- 数据库 schema 本身很稳定: 从不修改 payload 字段的结构

-- 查询时带版本判断
SELECT event_id, event_type, event_version, payload
FROM events
WHERE aggregate_id = $1
ORDER BY created_at;
-- 应用拿到每个事件后, 根据 event_type + event_version 应用 upcaster
```

事件溯源系统通常选择 **PostgreSQL JSONB** 或**专用事件存储（EventStore, Axon Server）**，而不是强类型的关系表，正是为了降低 schema 演进压力。

## Parquet Schema 演进规则

Parquet 是列式存储的事实标准，其 schema 演进规则影响着 Iceberg/Delta/Hudi 等上层系统：

### Parquet 自身的 schema

Parquet 文件头记录了 schema，通过 **column name** (早期) 或 **field ID** (较新) 匹配列。

### 跨文件的 schema 差异

当多个 Parquet 文件的 schema 不一致时（典型场景：流式写入中途新增列）：

| 情况 | 处理方式 |
|------|----------|
| 老文件缺列 | 读取时填 NULL |
| 新文件多列 | 查询若选择该列，老文件返回 NULL |
| 类型不一致 | 需要 union schema 策略 |
| 列顺序不同 | 按名称匹配（不按位置） |

### Spark 的 schema 合并

```python
# 开启 Parquet schema merging
spark.read.option("mergeSchema", "true").parquet("s3://bucket/events/")
```

策略：对所有文件的 schema 求**并集**，读取时按并集 schema 对齐。开销：需读取每个文件的 footer。

### 安全的类型演进（Parquet + Iceberg）

| 源类型 | 可演进到 |
|--------|----------|
| int32 | int64 |
| float | double |
| decimal(P, S) | decimal(P', S) where P' > P |
| date | timestamp |
| required | optional (放松 nullability) |
| optional | required (仅当无 NULL 数据, unsafe) |

任何其他变更（如 string → int）都需要**重写数据**或**新建列 ID**。

## 跨引擎的 Schema 演进能力对比

### 零停机 DDL 能力总览

| 引擎 | 添加列 | 删除列 | 改类型 | 重命名列 | 版本追踪 |
|------|--------|--------|--------|----------|----------|
| Snowflake | 完全 | 完全 | 完全 | 完全 | 完全 |
| Iceberg | 完全 | 完全 | 类型 promotion | 完全 (ID) | 完全 |
| Delta Lake | 完全 | 需 column mapping | 完全 | 需 column mapping | 完全 |
| CockroachDB | 完全 (F1) | 完全 (F1) | 完全 (F1) | 完全 (F1) | 完全 |
| TiDB | 完全 (INSTANT + F1) | 完全 | 部分 | 完全 | 完全 |
| Oracle | 完全 (11g+) | 完全 | online redef | 完全 | EBR |
| PostgreSQL 11+ | 完全 (fast-default) | 完全 | 部分 | 完全 | 无 |
| MySQL 8.0.29+ | 完全 (INSTANT) | 完全 (INSTANT) | 部分 | 完全 | 无 |
| SQL Server | 完全 | 完全 | online | 完全 | 无 |
| BigQuery | 完全 | 完全 | 受限 | 完全 | snapshot |
| ClickHouse | 完全 | mutation | mutation | 完全 | 无 |
| SQLite | 完全 | 完全 (3.35+) | 差 | 完全 | 无 |

### 最佳实践矩阵

| 场景 | 推荐方案 | 备注 |
|------|----------|------|
| OLTP 高频小表 | MySQL 8.0.29+ INSTANT / PG 11+ fast-default | 元数据变更瞬间完成 |
| 超大表(TB级)结构变更 | Oracle DBMS_REDEFINITION / GH-OST / pt-online-schema-change | 在线重建 |
| 数据湖 schema 演进 | Iceberg (列 ID) / Delta Lake (column mapping) | 最灵活 |
| 分布式 SQL 一致演进 | CockroachDB F1 协议 / TiDB | 多节点一致 |
| 事件溯源 | JSONB + 应用层 upcaster | 历史不可变 |
| 流批一体 schema 漂移 | Delta Lake mergeSchema / Iceberg | 自动合并 |
| 极致零停机 | Expand-Contract 模式 | 与引擎能力无关的最强兜底 |

## 关键发现

1. **INSTANT/fast-default 不是万能的**：volatile 函数、超过 256 字节的 VARCHAR、跨行格式的类型变更都会退化为全表重写。上线前应通过 `EXPLAIN` 或 dry-run 验证。

2. **MySQL 8.0.29 是分水岭**：2022 年 4 月之后，MySQL 的 INSTANT DDL 才真正可用于生产（支持任意位置）。仍在用 8.0.28 及更老版本的系统，升级优先级应该很高。

3. **PG 不支持列重排是有原因的**：这是一个优雅的权衡——放弃"列顺序可变"换来每次 ADD COLUMN 都不需要重写。若确实需要重排，重建表是唯一选择（pg_repack 工具可辅助）。

4. **F1 paper 是分布式 online DDL 的圣经**：CockroachDB、TiDB、YugabyteDB、Google Spanner 都不同程度地借鉴了其"中间状态共存"的思想。任何严肃的分布式 SQL 引擎都绕不开这套协议。

5. **湖仓表格式碾压传统数据库**：Iceberg 的 column ID 设计、Delta Lake 的 column mapping、Hudi 的 schema evolution 都远比 MySQL/PG 激进。表格式层的 schema 演进能力是"云原生数据栈"的关键优势之一。

6. **Expand-Contract 是引擎无关的护身符**：无论引擎能力如何，Expand-Contract 模式都能保证零停机。当引擎 INSTANT 不可用或有限制时，Expand-Contract 是最后的兜底。

7. **重命名列永远不要信任引擎的元数据重命名**：即使引擎瞬间完成，应用代码的引用也需要同步更新。Expand-Contract 的"双写+切读+删除"流程不可省略。

8. **DEFAULT 的语义陷阱**：`ADD COLUMN x INT DEFAULT 0` 在 PG 11+/MySQL 8.0+/Oracle 11g+ 都是 O(1)，但若 DEFAULT 是 `random()` / `uuid_generate_v4()` / `nextval()` 则退化为 O(N)。生产前必须测试。

9. **MySQL 的 INSTANT 次数上限很容易忽略**：每表 64 次 INSTANT 变更上限。对于迭代频繁的表（如每月加一列），两年后就需要 OPTIMIZE TABLE 重置，这本身是阻塞操作。

10. **Snowflake/BigQuery 的"一切 metadata-only"是云数据仓库的范式优势**：对比传统 OLTP 引擎的种种限制，云数仓把 schema 变更降级成"改 JSON 元数据"的简单操作，这也是近年来 OLAP 引擎普遍追赶的方向（StarRocks LightSchemaChange、Doris Light Schema Change 都是此思路）。

11. **事件溯源系统故意避开 schema 演进**：用 JSONB/JSON 存储 payload 并在应用层做 upcasting，本质上是把 schema 演进从"DDL 操作"转化为"代码演进"。这是架构上的根本性权衡。

12. **跨引擎迁移时 schema 演进历史几乎无法保留**：除非使用 Iceberg/Delta 这类中立格式，否则从 Oracle 迁到 PG 时，原有的 schema 演进路径（edition 等）完全丢失。这是数据库选型时的隐藏成本。

## 参考资料

- Rae, Ian, et al. "Online, Asynchronous Schema Change in F1" (2013), VLDB — CRDB/TiDB online DDL 的理论基础
- MySQL 8.0 Reference Manual: [Online DDL Operations](https://dev.mysql.com/doc/refman/8.0/en/innodb-online-ddl-operations.html)
- MySQL 8.0.29 Release Notes: [INSTANT ADD/DROP COLUMN anywhere](https://dev.mysql.com/doc/relnotes/mysql/8.0/en/news-8-0-29.html)
- PostgreSQL 11 Release Notes: [fast ALTER TABLE ADD COLUMN with DEFAULT](https://www.postgresql.org/docs/11/release-11.html)
- Oracle Database: [Edition-Based Redefinition](https://docs.oracle.com/en/database/oracle/oracle-database/19/adfns/editions.html)
- Snowflake: [Time Travel](https://docs.snowflake.com/en/user-guide/data-time-travel)
- Iceberg Spec: [Schema Evolution](https://iceberg.apache.org/spec/#schema-evolution)
- Delta Lake: [Column Mapping](https://docs.delta.io/latest/delta-column-mapping.html)
- Hudi: [Schema Evolution](https://hudi.apache.org/docs/schema_evolution)
- CockroachDB: [Online Schema Changes](https://www.cockroachlabs.com/docs/stable/online-schema-changes)
- TiDB: [DDL Statements](https://docs.pingcap.com/tidb/stable/ddl-introduction)
- Google Spanner: [Schema Updates](https://cloud.google.com/spanner/docs/schema-updates)
- Ankane, A. "strong_migrations" — Rails 迁移安全检查 gem
- Fowler, M. "Evolutionary Database Design" (2003) — Expand-Contract 模式的经典阐述
- Young, G. "Versioning in an Event Sourced System" (2017) — 事件溯源 schema 演进
