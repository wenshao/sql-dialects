# 约束验证状态 (Constraint Validation States)

约束（Constraint）的"开关与验证"是关系数据库中最容易被忽视、却在迁移与大表运维中频频登场的一组语义。同一个 CHECK 或 FOREIGN KEY，在 PostgreSQL 里叫 `NOT VALID`，在 Oracle 里叫 `ENABLE NOVALIDATE`，在 SQL Server 里叫 `WITH NOCHECK`，在 DB2 里叫 `NOT ENFORCED`，在 MySQL 里叫 `NOT ENFORCED`，在 SQL 标准里叫 `DEFERRABLE INITIALLY DEFERRED` 或 `NOT ENFORCED`。每个名字背后都有自己的"边界条件"：是否检查现有数据？是否检查新数据？是否影响优化器？能否回退？这些细节直接决定了"100 亿行表加约束是 5 秒还是 5 小时"，也是迁移工具与 schema 演进框架（Liquibase、Flyway、Skeema、Atlas、gh-ost、pt-online-schema-change）的核心适配点。本文专门梳理这一组语义，并与 [`constraint-syntax.md`](./constraint-syntax.md)（约束声明语法）和 [`foreign-key-cascade-semantics.md`](./foreign-key-cascade-semantics.md)（外键级联语义）形成完整的约束三部曲。

## 为什么"约束验证状态"值得单独成篇

### ENABLE / DISABLE / VALIDATE / NOVALIDATE / DEFERRABLE 的四个维度

许多文档把"约束的开关"简单描述为"启用或禁用"，但实际上一个约束的状态是由 **四个相互正交的维度** 共同决定的：

1. **是否对新数据强制（Enforced for new DML）**
   - ENABLE / ENFORCED：新插入或更新的行必须满足约束
   - DISABLE / NOT ENFORCED：约束被声明但 DML 不检查

2. **是否验证现有数据（Validated against existing rows）**
   - VALIDATE：CREATE / ALTER 时全表扫描验证
   - NOVALIDATE / NOT VALID / WITH NOCHECK：跳过现有数据的验证

3. **是否可延迟（Deferrability，SQL:1992）**
   - NOT DEFERRABLE：每条 DML 后立即检查
   - DEFERRABLE INITIALLY IMMEDIATE：默认立即，事务内可切到 DEFERRED
   - DEFERRABLE INITIALLY DEFERRED：默认延迟到事务提交

4. **是否被优化器信任（Trustworthy for query rewrite）**
   - 在 Oracle 里叫 RELY / NORELY；在 DB2 里叫 ENABLE QUERY OPTIMIZATION；在 SQL Server 里叫 IS_NOT_TRUSTED
   - 决定了 NOT ENFORCED / NOVALIDATE 的约束能否被 CBO 用于重写（如 join elimination、partition pruning）

这四个维度的组合产生了远比"开关"丰富的状态空间。例如 Oracle 的约束有 `ENABLE VALIDATE`、`ENABLE NOVALIDATE`、`DISABLE VALIDATE`、`DISABLE NOVALIDATE` 四种合法组合，每一种的语义和适用场景都不同（详见 Oracle 章节）。

### 大表迁移的核心痛点

约束验证状态最重要的工程价值在于"对大表加约束"。考虑一个 10 亿行的订单表，业务上要新增一个 CHECK 约束 `total >= 0`：

```sql
-- 朴素写法（PostgreSQL）：阻塞写 + 全表扫描，可能跑数小时
ALTER TABLE orders ADD CONSTRAINT chk_total CHECK (total >= 0);
```

这条 DDL 在 PostgreSQL 中会获取 `AccessExclusiveLock`，阻塞所有读写直到全表扫描完成。在 10 亿行的表上，这等同于服务停摆。而使用 `NOT VALID`：

```sql
-- 两阶段：先快速添加（仅约束元数据），再后台验证
ALTER TABLE orders ADD CONSTRAINT chk_total CHECK (total >= 0) NOT VALID;
-- ↑ 立即返回，新 DML 开始受约束保护

ALTER TABLE orders VALIDATE CONSTRAINT chk_total;
-- ↑ 后台验证现有数据，仅获取 ShareUpdateExclusiveLock，不阻塞读写
```

第一阶段几乎瞬间完成（只更新系统目录），第二阶段虽然仍要扫全表但锁级别低，可以与正常 DML 并发。这是大表 schema 演进的标准模式，也是为什么 Atlas、gh-ost、pg_repack 等工具都把"NOT VALID + VALIDATE"作为一等公民。

### 跨引擎术语混乱的现实

下表总结了同一语义在不同引擎中的术语差异——这种命名分裂正是本文存在的最大理由：

| 语义 | PostgreSQL | Oracle | SQL Server | DB2 | MySQL 8.0+ | SQL 标准 |
|------|-----------|--------|-----------|-----|-----------|---------|
| 跳过现有数据验证 | `NOT VALID` | `NOVALIDATE` | `WITH NOCHECK` | (隐式) | (无) | (未标准化) |
| 不强制新 DML | (无原生) | `DISABLE` | `NOCHECK CONSTRAINT` | `NOT ENFORCED` | `NOT ENFORCED` | `NOT ENFORCED` (SQL:2003) |
| 验证已声明的约束 | `VALIDATE CONSTRAINT` | `ENABLE VALIDATE` | `WITH CHECK CHECK CONSTRAINT` | `SET INTEGRITY` | (重新 ENFORCED) | (未标准化) |
| 延迟到事务结束 | `DEFERRABLE INITIALLY DEFERRED` | `DEFERRABLE INITIALLY DEFERRED` | (不支持) | (不支持) | (不支持) | `DEFERRABLE INITIALLY DEFERRED` (SQL:1992) |
| 优化器信任标志 | (无) | `RELY` | (基于 IS_NOT_TRUSTED 推断) | `ENABLE QUERY OPTIMIZATION` | (不影响优化器) | (未标准化) |

## SQL 标准中的约束状态

### SQL:1992 的 DEFERRABLE 与 IMMEDIATE

SQL:1992（ISO/IEC 9075:1992, Section 4.10 `<constraints>`）定义了 `DEFERRABLE` / `NOT DEFERRABLE` 限定符与 `INITIALLY IMMEDIATE` / `INITIALLY DEFERRED` 初始模式：

```sql
-- SQL:1992 BNF（简化）
<constraint_attributes> ::=
    <constraint_check_time> [ [ NOT ] DEFERRABLE ]
  | [ NOT ] DEFERRABLE [ <constraint_check_time> ]

<constraint_check_time> ::= INITIALLY DEFERRED | INITIALLY IMMEDIATE
```

合法组合：

- `NOT DEFERRABLE` — 必须立即检查，不能延迟（默认）
- `NOT DEFERRABLE INITIALLY IMMEDIATE` — 同上，显式写法
- `DEFERRABLE INITIALLY IMMEDIATE` — 默认立即检查，但可在事务中通过 `SET CONSTRAINTS ... DEFERRED` 切换为延迟
- `DEFERRABLE INITIALLY DEFERRED` — 默认延迟到事务提交时检查

> 注意：标准并未定义 `NOT DEFERRABLE INITIALLY DEFERRED`，这是逻辑矛盾的组合。

`SET CONSTRAINTS` 命令允许在事务内切换检查时机：

```sql
-- 事务中临时延迟某个约束的检查
BEGIN;
SET CONSTRAINTS fk_child_parent DEFERRED;
-- 暂时违反引用完整性的中间状态
COMMIT;  -- 此时检查所有 DEFERRED 约束，违反则回滚
```

`SET CONSTRAINTS ALL DEFERRED` 和 `SET CONSTRAINTS ALL IMMEDIATE` 提供了批量切换。

### SQL:2003 的 ENFORCED / NOT ENFORCED

SQL:2003（ISO/IEC 9075-2:2003）正式引入 `ENFORCED` / `NOT ENFORCED` 限定符，独立于 `DEFERRABLE`：

```sql
-- SQL:2003 BNF（简化）
<constraint_definition> ::=
    [ <constraint_name_definition> ]
    <constraint_specification>
    [ <constraint_attributes> ]
    [ ENFORCED | NOT ENFORCED ]
```

`NOT ENFORCED` 的标准语义：

1. 约束被记录在元数据中
2. 优化器**可以**使用它进行查询重写（具体行为由实现决定）
3. DML 操作**不检查**约束
4. 用户负责保证数据一致性

这是为分析型数据库设计的功能：在 ETL 流水线中，应用层已经保证了主外键关系，再让数据库重复检查只是浪费 CPU。把约束设为 `NOT ENFORCED` 让优化器知道数据的形状（如外键唯一性），从而做 join elimination 等重写。

### 标准与实现的脱节

SQL:1992 的 `DEFERRABLE` 和 SQL:2003 的 `NOT ENFORCED` 都属于"声明语法明确、实现差异巨大"的标准。下面是真实的支持现状：

- 完整支持 `DEFERRABLE INITIALLY DEFERRED` 的引擎仅有：PostgreSQL、Oracle、SQLite（有限）、Firebird、HSQLDB、Greenplum、YugabyteDB、CockroachDB（v22.2+ 仅 FK）
- 完整支持 `NOT ENFORCED` 的引擎仅有：DB2（10+）、MySQL（8.0.16+ 仅 CHECK）、Oracle（用 NOVALIDATE 等价）、Snowflake / BigQuery / Redshift（隐式：所有约束都 NOT ENFORCED）
- 大量引擎选择了"非标准但更直观"的语法：`WITH NOCHECK`（SQL Server）、`NOVALIDATE`（Oracle）、`NOT VALID`（PostgreSQL）

> 注：本文出现的引擎版本与时间，主要参考各引擎的官方版本说明（Release Notes / Changelog）。少数特性的"首发版本"在不同文档中存在分歧（例如 PostgreSQL `NOT VALID` 的部分语义在 9.1 引入但在 9.2 / 9.4 才完全适配 CHECK / FK / NOT NULL），实际工程中请以目标版本的官方文档为准。

## NOT VALID 支持矩阵（45+ 引擎）

`NOT VALID` 的核心语义：**添加约束时跳过对现有数据的验证**。新 DML 仍受约束保护。这是大表迁移的关键特性。

| 引擎 | 关键字 | CHECK | FK | NOT NULL | UNIQUE | 后续 VALIDATE | 版本 |
|------|-------|-------|-----|---------|--------|--------------|------|
| PostgreSQL | `NOT VALID` | 支持 | 支持 | 支持(11+) | 不支持 | `VALIDATE CONSTRAINT` | 9.1 (2011) |
| MySQL | (无) | -- | -- | -- | -- | -- | -- |
| MariaDB | (无) | -- | -- | -- | -- | -- | -- |
| SQLite | (无) | -- | -- | -- | -- | -- | -- |
| Oracle | `NOVALIDATE` | 支持 | 支持 | 支持 | 支持 | `ENABLE VALIDATE` | 9i (2001) |
| SQL Server | `WITH NOCHECK` | 支持 | 支持 | -- | -- | `WITH CHECK CHECK CONSTRAINT` | 2000 |
| DB2 | (隐式 NOT ENFORCED) | 支持 | 支持 | -- | -- | `SET INTEGRITY` | v8 (2002) |
| Snowflake | (全部不强制) | -- | -- | -- | -- | -- | -- |
| BigQuery | (全部不强制) | -- | -- | -- | -- | -- | -- |
| Redshift | (全部不强制) | -- | -- | -- | -- | -- | -- |
| DuckDB | (无) | -- | -- | -- | -- | -- | -- |
| ClickHouse | (无) | -- | -- | -- | -- | -- | -- |
| Trino | -- | -- | -- | -- | -- | -- | -- |
| Presto | -- | -- | -- | -- | -- | -- | -- |
| Spark SQL | -- | -- | -- | -- | -- | -- | -- |
| Hive | (信息性约束) | -- | -- | -- | -- | -- | -- |
| Flink SQL | (`NOT ENFORCED` 必填) | -- | -- | -- | -- | -- | -- |
| Databricks | (信息性约束) | -- | -- | -- | -- | -- | -- |
| Teradata | (无) | -- | -- | -- | -- | -- | -- |
| Greenplum | `NOT VALID` | 支持 | 支持 | 支持 | -- | `VALIDATE CONSTRAINT` | 6.0+(继承 PG) |
| CockroachDB | `NOT VALID` | 支持 | 支持 | 支持 | -- | `VALIDATE CONSTRAINT` | v19.1+ |
| TiDB | (无原生) | -- | -- | -- | -- | -- | -- |
| OceanBase | `NOVALIDATE`(Oracle 模式) | 支持 | 支持 | -- | -- | `ENABLE VALIDATE` | 全版本 |
| YugabyteDB | `NOT VALID` | 支持 | 支持 | 支持 | -- | `VALIDATE CONSTRAINT` | 全版本(继承 PG) |
| SingleStore | (无) | -- | -- | -- | -- | -- | -- |
| Vertica | (无) | -- | -- | -- | -- | -- | -- |
| Impala | (信息性约束) | -- | -- | -- | -- | -- | -- |
| StarRocks | (无) | -- | -- | -- | -- | -- | -- |
| Doris | (无) | -- | -- | -- | -- | -- | -- |
| MonetDB | (无) | -- | -- | -- | -- | -- | -- |
| CrateDB | (无) | -- | -- | -- | -- | -- | -- |
| TimescaleDB | `NOT VALID` | 支持 | 支持 | 支持 | -- | `VALIDATE CONSTRAINT` | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | -- | -- |
| Exasol | (无) | -- | -- | -- | -- | -- | -- |
| SAP HANA | (无) | -- | -- | -- | -- | -- | -- |
| Informix | (无) | -- | -- | -- | -- | -- | -- |
| Firebird | (无) | -- | -- | -- | -- | -- | -- |
| H2 | (无) | -- | -- | -- | -- | -- | -- |
| HSQLDB | (无) | -- | -- | -- | -- | -- | -- |
| Derby | (无) | -- | -- | -- | -- | -- | -- |
| Amazon Athena | -- | -- | -- | -- | -- | -- | -- |
| Azure Synapse | `WITH NOCHECK` | 支持 | 支持 | -- | -- | `WITH CHECK` | 继承 SQL Server |
| Google Spanner | (无) | -- | -- | -- | -- | -- | -- |
| Materialize | (无) | -- | -- | -- | -- | -- | -- |
| RisingWave | (无) | -- | -- | -- | -- | -- | -- |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | -- | -- |
| DatabendDB | -- | -- | -- | -- | -- | -- | -- |
| Yellowbrick | (信息性约束) | -- | -- | -- | -- | -- | -- |
| Firebolt | (信息性约束) | -- | -- | -- | -- | -- | -- |

## DEFERRABLE 支持矩阵

`DEFERRABLE INITIALLY DEFERRED` 的核心语义：**约束检查可延迟到事务提交时**，允许中间状态违反约束。

| 引擎 | DEFERRABLE | INITIALLY DEFERRED | INITIALLY IMMEDIATE | SET CONSTRAINTS | 适用约束 | 版本 |
|------|-----------|-------------------|--------------------|-----------------| --------|------|
| PostgreSQL | 支持 | 支持 | 支持 | 支持 | UNIQUE, PK, EXCLUDE, FK | 7.0+ |
| MySQL | 不支持 | -- | -- | -- | -- | -- |
| MariaDB | 不支持 | -- | -- | -- | -- | -- |
| SQLite | 支持(仅 FK) | 支持 | 支持 | -- | FK | 3.6.19+ |
| Oracle | 支持 | 支持 | 支持 | 支持 | 全部 | 全版本 |
| SQL Server | 不支持 | -- | -- | -- | -- | -- |
| DB2 | 不支持(LUW) | -- | -- | -- | -- | -- |
| Snowflake | 不支持 | -- | -- | -- | -- | -- |
| BigQuery | 不支持 | -- | -- | -- | -- | -- |
| Redshift | 不支持 | -- | -- | -- | -- | -- |
| DuckDB | 不支持 | -- | -- | -- | -- | -- |
| ClickHouse | 不支持 | -- | -- | -- | -- | -- |
| Trino | -- | -- | -- | -- | -- | -- |
| Presto | -- | -- | -- | -- | -- | -- |
| Spark SQL | -- | -- | -- | -- | -- | -- |
| Hive | 不支持 | -- | -- | -- | -- | -- |
| Flink SQL | 不支持 | -- | -- | -- | -- | -- |
| Databricks | 不支持 | -- | -- | -- | -- | -- |
| Teradata | 不支持 | -- | -- | -- | -- | -- |
| Greenplum | 支持 | 支持 | 支持 | 支持 | UNIQUE, PK, EXCLUDE, FK | 继承 PG |
| CockroachDB | 支持(FK) | 支持 | 支持 | 支持 | FK | v22.2+ |
| TiDB | 不支持 | -- | -- | -- | -- | -- |
| OceanBase | 支持(Oracle 模式) | 支持 | 支持 | 支持 | 全部 | 全版本 |
| YugabyteDB | 支持 | 支持 | 支持 | 支持 | UNIQUE, PK, FK | 全版本 |
| SingleStore | 不支持 | -- | -- | -- | -- | -- |
| Vertica | 不支持 | -- | -- | -- | -- | -- |
| Impala | 不支持 | -- | -- | -- | -- | -- |
| StarRocks | 不支持 | -- | -- | -- | -- | -- |
| Doris | 不支持 | -- | -- | -- | -- | -- |
| MonetDB | 不支持 | -- | -- | -- | -- | -- |
| CrateDB | 不支持 | -- | -- | -- | -- | -- |
| TimescaleDB | 支持 | 支持 | 支持 | 支持 | UNIQUE, PK, EXCLUDE, FK | 继承 PG |
| Exasol | 不支持 | -- | -- | -- | -- | -- |
| SAP HANA | 不支持 | -- | -- | -- | -- | -- |
| Informix | 不支持 | -- | -- | -- | -- | -- |
| Firebird | 支持(部分) | 部分 | 部分 | 部分 | 主要为 FK | 3.0+ |
| H2 | 不支持 | -- | -- | -- | -- | -- |
| HSQLDB | 支持 | 支持 | 支持 | 支持 | UNIQUE, PK, FK | 2.0+ |
| Derby | 不支持 | -- | -- | -- | -- | -- |
| Azure Synapse | 不支持 | -- | -- | -- | -- | -- |
| Google Spanner | 不支持 | -- | -- | -- | -- | -- |
| Materialize | 不支持 | -- | -- | -- | -- | -- |
| RisingWave | 不支持 | -- | -- | -- | -- | -- |
| Yellowbrick | 不支持 | -- | -- | -- | -- | -- |
| Firebolt | 不支持 | -- | -- | -- | -- | -- |

> 注：PostgreSQL 的 CHECK 约束**不**支持 DEFERRABLE，始终为 IMMEDIATE 检查。只有 UNIQUE、PRIMARY KEY、EXCLUDE 和 FOREIGN KEY 支持延迟。Oracle 的所有约束类型均支持 DEFERRABLE。

## ENFORCED / NOT ENFORCED 支持矩阵

| 引擎 | ENFORCED 关键字 | 适用约束 | 优化器使用 | 版本 |
|------|----------------|---------|-----------|------|
| PostgreSQL | (无, 用 NOT VALID 等价) | -- | 不使用未验证约束 | -- |
| MySQL | `ENFORCED` / `NOT ENFORCED` | 仅 CHECK | 不使用 | 8.0.16 (2019) |
| MariaDB | (无原生) | -- | -- | -- |
| SQLite | (无) | -- | -- | -- |
| Oracle | (用 ENABLE/DISABLE + VALIDATE/NOVALIDATE) | -- | RELY 控制 | 9i+ |
| SQL Server | (用 WITH CHECK / WITH NOCHECK) | -- | IS_NOT_TRUSTED 推断 | 2000+ |
| DB2 | `ENFORCED` / `NOT ENFORCED` | FK, CHECK, PK, UNIQUE | `ENABLE QUERY OPTIMIZATION` | v8 (2002) |
| Snowflake | (隐式 NOT ENFORCED) | 全部 | 部分使用 | 全版本 |
| BigQuery | `NOT ENFORCED` | PK, FK | 部分使用 | 2022+ |
| Redshift | (隐式 NOT ENFORCED) | 全部 | 不使用 | 全版本 |
| DuckDB | (无) | -- | -- | -- |
| ClickHouse | (无) | -- | -- | -- |
| Hive | `NOT ENFORCED` `RELY` `NOVALIDATE` | 全部 | RELY 控制 | 3.0+ |
| Flink SQL | `NOT ENFORCED` (必填) | PK | 优化器依赖 | 1.13+ |
| Databricks | (Unity Catalog) | PK, FK | 部分使用 | 全版本 |
| Spark SQL | `NOT ENFORCED` (Iceberg/Delta) | PK | 部分使用 | 3.x+ |
| Teradata | (无) | -- | -- | -- |
| CockroachDB | `NOT VALID` 等价 | FK, CHECK | 不使用 | v19.1+ |
| TiDB | (FK 不强制) | FK | 不使用 | 6.6+ |
| YugabyteDB | (无) | -- | -- | 全版本 |
| Impala | (信息性约束) | 全部 | 部分使用 | 全版本 |
| Vertica | (无) | -- | -- | 全版本 |
| Yellowbrick | (信息性约束) | 全部 | 部分使用 | 全版本 |
| Firebolt | (信息性约束) | 全部 | 部分使用 | 全版本 |
| Azure Synapse | `NOT ENFORCED` | PK, FK, UNIQUE | 部分使用 | 全版本 |

## NOCHECK 支持矩阵（SQL Server 系）

| 引擎 | WITH NOCHECK | NOCHECK CONSTRAINT | CHECK CONSTRAINT | sys.check_constraints.is_not_trusted | 版本 |
|------|-------------|-------------------|-----------------|--------------------------------------|------|
| SQL Server | 支持 | 支持 | 支持 | 支持 | 2000+ |
| Azure SQL | 支持 | 支持 | 支持 | 支持 | 全版本 |
| Azure Synapse | 支持 | 支持 | 支持 | 支持 | 全版本 |
| SQL Server 2022 | 支持(标记 deprecated) | 支持 | 支持 | 支持 | 2022 |

> 注：SQL Server 2022 在文档中将"WITH NOCHECK 用于添加新约束"标记为过时（discouraged for new constraints），推荐先用 NOCHECK 状态再用 `ALTER ... CHECK CONSTRAINT` 手动验证，但语法本身仍然可用。

## ENABLE / DISABLE 支持矩阵

`DISABLE` 的语义：**约束元数据保留，但 DML 时不检查**。这是 Oracle 与 SQL Server 系最常用的"约束临时关闭"机制。

| 引擎 | DISABLE | ENABLE | DISABLE CONSTRAINT | NOCHECK CONSTRAINT | 适用约束 | 版本 |
|------|---------|--------|-------------------|-------------------|---------|------|
| PostgreSQL | 不支持 | 不支持 | -- | -- | -- | -- |
| MySQL | 不支持 | 不支持 | -- | -- | -- | -- |
| MariaDB | 不支持 | 不支持 | -- | -- | -- | -- |
| SQLite | 部分(`PRAGMA foreign_keys`) | 部分 | -- | -- | FK | 全版本 |
| Oracle | 支持 | 支持 | 支持 | -- | 全部 | 全版本 |
| SQL Server | 部分(NOCHECK 等价) | 部分 | -- | 支持(CHECK/FK) | CHECK, FK | 2000+ |
| DB2 | 支持 | 支持 | -- | -- | 全部 | 全版本 |
| Snowflake | 不支持 | 不支持 | -- | -- | -- | -- |
| BigQuery | 不支持 | 不支持 | -- | -- | -- | -- |
| Redshift | 不支持 | 不支持 | -- | -- | -- | -- |
| Vertica | 支持 | 支持 | -- | -- | 主要 PK/UNIQUE | 全版本 |
| Exasol | 支持 | 支持 | -- | -- | 全部 | 全版本 |
| SAP HANA | 支持 | 支持 | -- | -- | 全部 | 全版本 |
| Informix | 支持 | 支持 | -- | -- | 全部 | 全版本 |
| Firebird | 支持(INACTIVE) | 支持(ACTIVE) | -- | -- | CHECK, FK | 全版本 |
| Hive | 支持(NOVALIDATE) | 支持 | -- | -- | 全部 | 全版本 |
| OceanBase | 支持(Oracle 模式) | 支持 | 支持 | -- | 全部 | 全版本 |
| Azure Synapse | 部分(NOCHECK) | 部分 | -- | 支持 | CHECK, FK | 全版本 |

## PostgreSQL: NOT VALID + VALIDATE CONSTRAINT

PostgreSQL 是最早把"NOT VALID"系统化为大表迁移工具的引擎。该机制最早在 9.1（2011 年 9 月发布）以 FK 形式引入，9.2 扩展到 CHECK 约束，11 引入了 NOT NULL 的部分等价机制（`SET NOT NULL` + 已有 `CHECK col IS NOT NULL` 的优化）。

### 基本流程

```sql
-- 阶段 1：添加 NOT VALID 约束（瞬间完成，不阻塞读写）
ALTER TABLE orders
    ADD CONSTRAINT chk_total_positive CHECK (total > 0) NOT VALID;

-- 此时：
--   pg_constraint.convalidated = false
--   现有数据未被检查，可能存在 total <= 0 的行
--   新插入或更新的行必须满足约束（约束对新 DML 生效）

-- 阶段 2：后台验证现有数据（仅获取 ShareUpdateExclusiveLock）
ALTER TABLE orders VALIDATE CONSTRAINT chk_total_positive;

-- 验证完成后：
--   pg_constraint.convalidated = true
--   优化器开始信任此约束（如 partition pruning）
```

### 锁级别对比

| 操作 | 锁级别 | 阻塞 SELECT | 阻塞 INSERT/UPDATE/DELETE |
|------|-------|-----------|--------------------------|
| `ALTER TABLE ... ADD CONSTRAINT ... CHECK ...` (无 NOT VALID) | AccessExclusiveLock | 是 | 是 |
| `ALTER TABLE ... ADD CONSTRAINT ... NOT VALID` | ShareRowExclusiveLock | 否 | 部分（仅冲突写） |
| `ALTER TABLE ... VALIDATE CONSTRAINT ...` | ShareUpdateExclusiveLock | 否 | 否 |

### 外键的 NOT VALID

外键的 NOT VALID 也遵循同样模式：

```sql
ALTER TABLE orders
    ADD CONSTRAINT fk_orders_customer
    FOREIGN KEY (customer_id) REFERENCES customers(id)
    NOT VALID;

-- 后续验证
ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_customer;
```

注意点：

1. NOT VALID 的 FK 不会被优化器用于 **join elimination** 等重写
2. VALIDATE 时仍需要扫全表，但不阻塞 DML
3. 子表与父表都会被加锁（VALIDATE 期间），但锁级别允许并发读写

### NOT NULL 的特殊路径

PostgreSQL 11 之前，给大表添加 NOT NULL 的方法是先添加一个等价的 CHECK 约束（NOT VALID + VALIDATE），然后用 `ALTER COLUMN SET NOT NULL`：

```sql
-- PostgreSQL 9.x / 10：迂回方案
ALTER TABLE orders ADD CONSTRAINT chk_email_not_null CHECK (email IS NOT NULL) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT chk_email_not_null;
ALTER TABLE orders ALTER COLUMN email SET NOT NULL;  -- 跳过全表扫描
ALTER TABLE orders DROP CONSTRAINT chk_email_not_null;  -- 清理临时约束
```

PostgreSQL 11 优化了这个流程：如果列已经存在等价的 CHECK 约束，`SET NOT NULL` 会跳过全表扫描。PostgreSQL 12+ 进一步支持 `ALTER TABLE ... ADD COLUMN ... NOT NULL DEFAULT ...` 不重写表（利用 fast default + missing value）。

### 系统目录

```sql
-- 查询所有 NOT VALID 的约束
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       con.conname AS constraint_name,
       con.contype,           -- 'c'=CHECK, 'f'=FK, 'p'=PK, 'u'=UNIQUE, 'x'=EXCLUDE
       con.convalidated       -- false 表示 NOT VALID
FROM pg_constraint con
JOIN pg_class c ON con.conrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE NOT con.convalidated;
```

### 失败处理

如果 `VALIDATE CONSTRAINT` 期间发现违反约束的数据：

```
ERROR:  check constraint "chk_total_positive" of relation "orders" is violated by some row
```

此时约束保持 NOT VALID 状态，需要先清理违规数据（或者修改约束）再重试 VALIDATE。

## Oracle: ENABLE NOVALIDATE / DISABLE / RELY

Oracle 是约束状态语义最完整的引擎，从 9i（2001 年）开始就把约束的"启用/禁用"和"验证/未验证"作为两个正交维度。

### 四种合法状态组合

```sql
-- 1. ENABLE VALIDATE（默认）—— 完全约束
ALTER TABLE orders ENABLE VALIDATE CONSTRAINT chk_quantity;
-- 含义：约束对新 DML 生效，且现有数据已通过验证

-- 2. ENABLE NOVALIDATE —— 大表迁移最常用
ALTER TABLE orders ENABLE NOVALIDATE CONSTRAINT chk_quantity;
-- 含义：约束对新 DML 生效，但不验证现有数据
-- 关键：等价于 PostgreSQL 的 NOT VALID

-- 3. DISABLE VALIDATE —— 锁定表（很少用）
ALTER TABLE orders DISABLE VALIDATE CONSTRAINT chk_quantity;
-- 含义：禁止任何 DML（连违反约束的 DML 都禁止），但保留约束元数据
-- 实际效果：表只读

-- 4. DISABLE NOVALIDATE —— 完全关闭
ALTER TABLE orders DISABLE NOVALIDATE CONSTRAINT chk_quantity;
-- 含义：约束被声明但完全不检查，新数据可以违反约束
-- 用途：批量数据加载时临时关闭
```

### CHECK NOVALIDATE 工作流

```sql
-- 创建时直接 NOVALIDATE
ALTER TABLE orders ADD CONSTRAINT chk_total
    CHECK (total > 0)
    ENABLE NOVALIDATE;

-- 验证现有数据（不阻塞 DML，但需要全表扫描）
ALTER TABLE orders ENABLE VALIDATE CONSTRAINT chk_total;

-- 如果验证失败，定位违规行
SELECT * FROM orders WHERE NOT (total > 0);

-- 也可以用 EXCEPTIONS INTO 子句捕获违规行
CREATE TABLE exceptions (row_id ROWID, owner VARCHAR2(30),
                        table_name VARCHAR2(30), constraint VARCHAR2(30));
ALTER TABLE orders ENABLE VALIDATE CONSTRAINT chk_total
    EXCEPTIONS INTO exceptions;
```

### RELY / NORELY：优化器信任标志

Oracle 独有的 `RELY` 让优化器在约束未验证时仍然信任它（用于物化视图查询重写）：

```sql
-- 普通 NOVALIDATE：优化器不信任
ALTER TABLE sales ADD CONSTRAINT pk_sales PRIMARY KEY (id) RELY ENABLE NOVALIDATE;
-- ↑ 优化器假设 id 唯一（用于物化视图刷新优化）

-- 移除信任
ALTER TABLE sales MODIFY CONSTRAINT pk_sales NORELY;
```

`RELY` 的典型用例：数据仓库的事实表用应用层保证 PK 唯一性，但不希望付出实时检查开销，可以用 `RELY DISABLE NOVALIDATE` 让优化器信任。

### Oracle 与 PostgreSQL 的对应关系

| Oracle | PostgreSQL | 含义 |
|--------|-----------|------|
| `ENABLE VALIDATE` | (默认 VALID) | 完全约束 |
| `ENABLE NOVALIDATE` | `NOT VALID` | 新 DML 检查，旧数据不检查 |
| `DISABLE NOVALIDATE` | (无原生，需 DROP CONSTRAINT) | 完全关闭 |
| `DISABLE VALIDATE` | (无原生) | 表只读但保留约束 |
| `RELY ENABLE NOVALIDATE` | (无原生) | 优化器信任的未验证约束 |

### 历史与版本

- 9i (2001)：引入 `ENABLE NOVALIDATE`
- 10g：扩展 `RELY` 到所有约束类型
- 11g：物化视图查询重写更广泛地使用 RELY 约束
- 12c：支持 `ALTER TABLE ADD COLUMN ... DEFAULT ... NOT NULL` 不重写表
- 19c / 23ai：维护 `INVALIDATE` 子句允许约束在外键引用变化时自动失效

## SQL Server: WITH NOCHECK / WITH CHECK / IS_NOT_TRUSTED

SQL Server 从 2000 版本开始引入 `WITH CHECK` / `WITH NOCHECK` 语法。SQL Server 的特殊性在于：约束被关闭后再启用，**需要显式 `WITH CHECK` 才会重新验证**，否则即使启用了约束，元数据中也标记为"不可信任"（IS_NOT_TRUSTED = 1），优化器不使用它进行重写。

### WITH NOCHECK 的两种用法

```sql
-- 用法 1：添加新约束时跳过现有数据验证
ALTER TABLE Orders WITH NOCHECK
    ADD CONSTRAINT chk_quantity CHECK (Quantity > 0);
-- 等价于 PostgreSQL 的 NOT VALID

-- 用法 2：禁用现有约束
ALTER TABLE Orders NOCHECK CONSTRAINT chk_quantity;
-- 约束保留在元数据中，但 DML 时不检查
-- 等价于 Oracle 的 DISABLE NOVALIDATE
```

### 重新启用与"信任"

启用一个之前被 NOCHECK 的约束有两种方式，结果不同：

```sql
-- 方式 1：仅启用，不验证现有数据
ALTER TABLE Orders CHECK CONSTRAINT chk_quantity;
-- IS_NOT_TRUSTED = 1，优化器不信任

-- 方式 2：启用并验证（推荐）
ALTER TABLE Orders WITH CHECK CHECK CONSTRAINT chk_quantity;
-- 全表扫描验证，IS_NOT_TRUSTED = 0
```

注意 `WITH CHECK CHECK CONSTRAINT` 不是错别字——前一个 `CHECK` 是 `WITH CHECK` 子句，后一个是 `CHECK CONSTRAINT` 命令。

### IS_NOT_TRUSTED 的影响

```sql
-- 检查所有不可信约束（系统视图）
SELECT object_schema_name(parent_object_id) AS schema_name,
       object_name(parent_object_id) AS table_name,
       name AS constraint_name,
       is_not_trusted
FROM sys.check_constraints
WHERE is_not_trusted = 1
UNION ALL
SELECT object_schema_name(parent_object_id),
       object_name(parent_object_id),
       name,
       is_not_trusted
FROM sys.foreign_keys
WHERE is_not_trusted = 1;
```

`IS_NOT_TRUSTED = 1` 的约束**不会**被优化器用于：

1. **Foreign Key Pruning（FK 修剪）**：`WHERE EXISTS (SELECT 1 FROM child WHERE child.fk = parent.id)` 这类查询，可信 FK 允许跳过 EXISTS 检查
2. **CHECK 约束驱动的分区裁剪**：CHECK 约束指明分区范围时，可信约束可触发分区消除
3. **NOT NULL 推断**：可信 CHECK 约束（如 `col > 0`）可让优化器推断 `col IS NOT NULL`
4. **Indexed View 维护优化**：可信约束可减少索引视图维护开销

### CHECK CONSTRAINT name 的"过时"问题

SQL Server 2022 在官方文档中标注：使用 `WITH NOCHECK` 添加新约束的做法被标记为不推荐（discouraged for new constraints），原因是：

1. 新约束默认应该是被信任的，否则违背了"约束保护数据"的初衷
2. 不可信约束破坏了优化器对数据的假设
3. 推荐的做法是先在应用层清理违规数据，再添加 `WITH CHECK` 约束

但实际工程中，对于 100 亿行的事实表，"先清理再添加" 不现实，因此 `WITH NOCHECK` 仍然是大表迁移的标准做法。SQL Server 2022 的标记仅是文档层面的建议，语法本身完全可用。

### 完整迁移流程

```sql
-- 大表添加 CHECK 约束的完整流程
-- 阶段 1：快速添加（NOCHECK）
ALTER TABLE Orders WITH NOCHECK
    ADD CONSTRAINT chk_total CHECK (Total > 0);

-- 阶段 2：清理违规数据
UPDATE Orders SET Total = 0.01 WHERE Total <= 0;
-- 或 DELETE FROM Orders WHERE Total <= 0;

-- 阶段 3：转为可信约束
ALTER TABLE Orders WITH CHECK CHECK CONSTRAINT chk_total;
-- 此时全表扫描验证，但锁不阻塞读
```

## DB2: SET INTEGRITY 与 ENFORCED / NOT ENFORCED

DB2（LUW、z/OS、i 三个产品线）从 v8（2002 年）开始支持 `SET INTEGRITY` 命令，用于把表设为"check pending"状态，并在批量加载后统一验证。DB2 还是少数完整支持 SQL:2003 `ENFORCED / NOT ENFORCED` 语法的引擎之一。

### 基本流程

```sql
-- 阶段 1：把表设为 check pending（关闭约束检查）
SET INTEGRITY FOR ORDERS OFF;
-- 此时所有约束（CHECK、FK、列生成）都不再检查

-- 阶段 2：执行批量加载
LOAD FROM /tmp/orders.del OF DEL INSERT INTO ORDERS;
-- 或者 IMPORT、INSERT 大批量数据

-- 阶段 3：恢复约束检查并验证
SET INTEGRITY FOR ORDERS IMMEDIATE CHECKED;
-- ↑ 全表扫描验证所有约束

-- 阶段 4（可选）：仅恢复约束元数据，不验证
SET INTEGRITY FOR ORDERS IMMEDIATE UNCHECKED;
-- ↑ 跳过验证（用户保证数据合规）
```

### NOT ENFORCED 的标准实现

```sql
-- DB2 支持 SQL:2003 的 NOT ENFORCED
CREATE TABLE orders (
    id INT NOT NULL,
    customer_id INT NOT NULL,
    quantity INT NOT NULL,

    PRIMARY KEY (id),

    CONSTRAINT fk_customer
        FOREIGN KEY (customer_id) REFERENCES customers(id)
        NOT ENFORCED,           -- 优化器可使用，但 DML 不检查

    CONSTRAINT chk_quantity CHECK (quantity > 0) NOT ENFORCED
);

-- 切换 ENFORCED 状态
ALTER TABLE orders ALTER FOREIGN KEY fk_customer ENFORCED;
ALTER TABLE orders ALTER FOREIGN KEY fk_customer NOT ENFORCED;
```

### ENABLE QUERY OPTIMIZATION

DB2 把"约束是否被优化器使用"作为独立属性：

```sql
-- 不强制 + 优化器使用（数据仓库典型）
ALTER TABLE orders ADD CONSTRAINT chk_status
    CHECK (status IN ('A', 'B', 'C'))
    NOT ENFORCED ENABLE QUERY OPTIMIZATION;

-- 不强制 + 优化器不使用（仅作文档）
ALTER TABLE orders ADD CONSTRAINT chk_phone
    CHECK (phone LIKE '+%')
    NOT ENFORCED DISABLE QUERY OPTIMIZATION;
```

`ENABLE QUERY OPTIMIZATION` 等价于 Oracle 的 `RELY`，让优化器把未验证约束视为有效。

### check pending 状态查询

```sql
-- 查询哪些表处于 check pending
SELECT TABSCHEMA, TABNAME, STATUS
FROM SYSCAT.TABLES
WHERE STATUS = 'C';  -- C = check pending

-- 查询具体哪个约束未验证
SELECT TABSCHEMA, TABNAME, CONSTNAME, ENFORCED
FROM SYSCAT.CHECKS
WHERE ENFORCED = 'N';
```

## MySQL: ENFORCED / NOT ENFORCED 的有限实现

MySQL 8.0.16（2019 年 4 月）首次为 CHECK 约束引入 `ENFORCED / NOT ENFORCED` 语法。这是 MySQL 在约束验证状态上唯一遵循 SQL 标准的部分——FK 至今没有等价机制。

### CHECK 约束的 NOT ENFORCED

```sql
-- MySQL 8.0.16+
CREATE TABLE orders (
    id BIGINT NOT NULL AUTO_INCREMENT,
    quantity INT NOT NULL,
    total DECIMAL(10,2) NOT NULL,

    PRIMARY KEY (id),

    CONSTRAINT chk_quantity CHECK (quantity > 0) ENFORCED,    -- 默认
    CONSTRAINT chk_total CHECK (total >= 0) NOT ENFORCED      -- 仅记录，不检查
);

-- 切换状态
ALTER TABLE orders ALTER CHECK chk_total ENFORCED;
ALTER TABLE orders ALTER CHECK chk_total NOT ENFORCED;

-- 查询状态
SELECT CONSTRAINT_NAME, CHECK_CLAUSE, ENFORCED
FROM information_schema.CHECK_CONSTRAINTS
WHERE TABLE_NAME = 'orders';
```

### 关键限制

1. **仅适用于 CHECK 约束**：FK、UNIQUE、PK 没有 NOT ENFORCED 选项
2. **没有 NOT VALID 等价语法**：无法"添加约束但跳过现有数据验证"——MySQL 添加约束时总是全表扫描
3. **优化器不使用 NOT ENFORCED 约束**：不会做 join elimination 等重写

### FK 的"无奈"：跳过验证只能 SET FOREIGN_KEY_CHECKS=0

MySQL 添加 FK 必须验证全部数据，唯一的"跳过验证"方式是 session 级别关闭 FK 检查，再添加约束：

```sql
-- 危险：跳过 FK 验证
SET FOREIGN_KEY_CHECKS = 0;
ALTER TABLE orders ADD CONSTRAINT fk_customer
    FOREIGN KEY (customer_id) REFERENCES customers(id);
SET FOREIGN_KEY_CHECKS = 1;
-- 现在约束存在但可能存在违反 FK 的数据
-- 后续 DML 会因 FK 而拒绝（即使是不相关的更新）
```

这种做法有严重风险：

1. SET FOREIGN_KEY_CHECKS 是 session 变量，只影响当前连接
2. 数据违反 FK 后，任何修改子表的 UPDATE 可能因为"会让违反持续"而被拒绝
3. 没有官方的"VALIDATE 命令"来后续验证

实际工程中常用的替代方案：

- **pt-online-schema-change** / **gh-ost**：用影子表 + 触发器同步，最后切换
- **Vitess / Skeema**：在线 DDL 工具自动处理
- **应用层清理**：先 `DELETE FROM child WHERE fk NOT IN (SELECT id FROM parent)`

### NOT NULL 的添加

```sql
-- MySQL 添加 NOT NULL 总是全表扫描验证
ALTER TABLE orders MODIFY COLUMN email VARCHAR(255) NOT NULL;
-- 在 InnoDB 中，8.0 版本通过 INSTANT 算法可能加速元数据修改
-- 但首次设置 NOT NULL 仍需扫描所有行确认无 NULL 值
```

MySQL 8.0.12+ 引入 `INSTANT` 算法用于"添加列"等少数 DDL 不重写表，但 `MODIFY COLUMN ... NOT NULL` 不在 INSTANT 支持范围。

### MariaDB 的差异

MariaDB 10.2.1（2017 年）早于 MySQL 实现 CHECK 约束执行，但**没有引入 `ENFORCED / NOT ENFORCED` 语法**。MariaDB 中 CHECK 约束总是 ENFORCED，无法关闭。这是 MariaDB 与 MySQL 在约束语义上的一个明显分裂点。

## 大表迁移：NOT VALID + ALTER VALIDATE 模式

### 通用模式

```sql
-- 第 1 步：快速添加约束（仅元数据）
-- PostgreSQL
ALTER TABLE orders ADD CONSTRAINT chk_total CHECK (total > 0) NOT VALID;
-- Oracle
ALTER TABLE orders ADD CONSTRAINT chk_total CHECK (total > 0) ENABLE NOVALIDATE;
-- SQL Server
ALTER TABLE orders WITH NOCHECK ADD CONSTRAINT chk_total CHECK (total > 0);
-- DB2
ALTER TABLE orders ADD CONSTRAINT chk_total CHECK (total > 0) NOT ENFORCED;

-- 第 2 步：业务上线，新数据已受约束保护
-- （此时违规的旧数据仍存在）

-- 第 3 步：清理旧违规数据
UPDATE orders SET total = 0.01 WHERE total <= 0;

-- 第 4 步：触发后台验证
-- PostgreSQL
ALTER TABLE orders VALIDATE CONSTRAINT chk_total;
-- Oracle
ALTER TABLE orders ENABLE VALIDATE CONSTRAINT chk_total;
-- SQL Server
ALTER TABLE orders WITH CHECK CHECK CONSTRAINT chk_total;
-- DB2
SET INTEGRITY FOR orders IMMEDIATE CHECKED;
```

### 各引擎的"是否阻塞 DML"对比

| 引擎 | ADD ... NOT VALID | VALIDATE | 阻塞写 | 阻塞读 |
|------|------------------|----------|-------|-------|
| PostgreSQL | 几乎瞬间 | 后台扫描 | 否 | 否 |
| Oracle | 几乎瞬间 | 后台扫描 | 否（默认 ROW EXCLUSIVE） | 否 |
| SQL Server | 几乎瞬间 | 全表扫描 | 是（VALIDATE 期间） | 否 |
| DB2 | 几乎瞬间 | SET INTEGRITY | 是（默认） | 否 |
| MySQL | 不支持（总扫描） | -- | 是（除非 ALGORITHM=INPLACE 适用） | 否（5.6+ Online DDL） |

注意 SQL Server 的特殊性：`WITH CHECK CHECK CONSTRAINT` 在大表上仍可能阻塞写，因为它需要扫描全部行并比较。MySQL 的 ALTER 在 5.6+ 通过 Online DDL 提供了"INPLACE 算法"在某些情况下可以避免阻塞，但行为依赖具体 DDL 类型。

### 工程检查清单

完整的大表加约束流程：

```
1. 评估违规数据量
   SELECT count(*) FROM orders WHERE NOT (total > 0);

2. 评估表大小、索引数、副本延迟
   - 表行数与磁盘占用
   - 复制延迟（主从、CDC）
   - 当前峰值 QPS / TPS

3. 选择策略：
   a) 小表（< 1000 万行）：直接 ALTER ADD CONSTRAINT
   b) 中表（1000 万 - 1 亿行）：NOT VALID + 立即 VALIDATE
   c) 大表（> 1 亿行）：NOT VALID + 业务上线 + 数据清理 + 异步 VALIDATE
   d) 超大表（> 100 亿行）：考虑分区 + 逐分区 VALIDATE

4. 监控验证进度（部分引擎支持）
   - PostgreSQL: pg_stat_progress_create_index（VALIDATE 不在其中，但可观察 IO）
   - Oracle: V$SESSION_LONGOPS
   - SQL Server: sys.dm_exec_requests.percent_complete

5. 失败回滚
   - PostgreSQL: ALTER TABLE ... DROP CONSTRAINT
   - Oracle: 同上
   - SQL Server: 同上
```

## NOT NULL 的特殊路径

NOT NULL 在大多数引擎中不属于"约束系统"（pg_constraint 中没有条目），而是列属性，因此其验证状态机制与其他约束不同。

### PostgreSQL NOT NULL 的演进

```sql
-- PG 11 之前：迂回方案
-- 阶段 1：等价 CHECK 约束 + NOT VALID
ALTER TABLE orders ADD CONSTRAINT chk_email_nn CHECK (email IS NOT NULL) NOT VALID;
-- 阶段 2：后台验证
ALTER TABLE orders VALIDATE CONSTRAINT chk_email_nn;
-- 阶段 3：转为列 NOT NULL（PG 11+ 优化：发现已有等价 CHECK 时跳过扫描）
ALTER TABLE orders ALTER COLUMN email SET NOT NULL;
-- 阶段 4：删除冗余 CHECK 约束
ALTER TABLE orders DROP CONSTRAINT chk_email_nn;

-- PG 11+：发现等价 CHECK 时直接 SET NOT NULL 不扫描
-- 因为系统知道"已经有 CHECK (email IS NOT NULL)"

-- PG 12+：ADD COLUMN ... DEFAULT ... NOT NULL 不重写表
-- 利用 fast default + missing value 优化
ALTER TABLE orders ADD COLUMN region VARCHAR(20) NOT NULL DEFAULT 'US';
```

### Oracle NOT NULL 的 NOVALIDATE

```sql
-- Oracle 直接支持 NOT NULL 约束的 NOVALIDATE
ALTER TABLE orders MODIFY (email VARCHAR2(255) CONSTRAINT nn_email NOT NULL ENABLE NOVALIDATE);
-- 阶段 1：约束元数据立即添加
-- 阶段 2：后续 VALIDATE
ALTER TABLE orders ENABLE VALIDATE CONSTRAINT nn_email;
```

### SQL Server NOT NULL 的限制

SQL Server 的 NOT NULL 是列属性，不能用 `WITH NOCHECK` 跳过验证。大表加 NOT NULL 的标准做法是：

```sql
-- 方案 1：先添加 CHECK，再改列属性
ALTER TABLE Orders WITH NOCHECK
    ADD CONSTRAINT chk_email_nn CHECK (email IS NOT NULL);
-- 清理违规数据
UPDATE Orders SET email = '' WHERE email IS NULL;
-- 验证 CHECK
ALTER TABLE Orders WITH CHECK CHECK CONSTRAINT chk_email_nn;
-- 改列属性（仍需扫描，但行数已无 NULL）
ALTER TABLE Orders ALTER COLUMN email VARCHAR(255) NOT NULL;
-- 删除冗余 CHECK
ALTER TABLE Orders DROP CONSTRAINT chk_email_nn;

-- 方案 2：用 sp_rename 切换表（在线 DDL）
```

## CHECK 约束的迁移模式

### 模式 1：渐进收紧

业务规则演进时，CHECK 约束可以渐进收紧：

```sql
-- 现状：业务允许 quantity 为 0，但希望禁止负数
-- 阶段 1（即时）：禁止负数（弱约束）
ALTER TABLE orders ADD CONSTRAINT chk_qty_nn CHECK (quantity >= 0) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT chk_qty_nn;

-- 阶段 2（数月后）：业务上完成 0 的清理后，强约束
ALTER TABLE orders DROP CONSTRAINT chk_qty_nn;
ALTER TABLE orders ADD CONSTRAINT chk_qty_pos CHECK (quantity > 0) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT chk_qty_pos;
```

### 模式 2：临时关闭加速批量加载

```sql
-- Oracle / DB2 模式：批量加载前关闭，加载后重新启用
ALTER TABLE orders DISABLE CONSTRAINT chk_total;
ALTER TABLE orders DISABLE CONSTRAINT fk_customer;

-- 批量加载（可能违反约束的中间状态）
INSERT INTO orders SELECT * FROM staging.orders;

-- 重新启用并验证
ALTER TABLE orders ENABLE VALIDATE CONSTRAINT chk_total;
ALTER TABLE orders ENABLE VALIDATE CONSTRAINT fk_customer;
```

### 模式 3：分区独立验证

```sql
-- PostgreSQL 11+ 分区表的约束可以分区独立验证
ALTER TABLE orders ADD CONSTRAINT chk_total CHECK (total > 0) NOT VALID;

-- 逐分区验证（每个分区是独立的 ALTER 操作）
ALTER TABLE orders_2024_01 VALIDATE CONSTRAINT chk_total;
ALTER TABLE orders_2024_02 VALIDATE CONSTRAINT chk_total;
-- ...
```

## DEFERRABLE 的工程用法

### 用法 1：循环引用

```sql
-- 父子表互相引用（员工与部门，部门有 manager_id）
CREATE TABLE departments (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    manager_id INT,
    CONSTRAINT fk_dept_mgr FOREIGN KEY (manager_id) REFERENCES employees(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE employees (
    id INT PRIMARY KEY,
    name VARCHAR(50),
    department_id INT,
    CONSTRAINT fk_emp_dept FOREIGN KEY (department_id) REFERENCES departments(id)
        DEFERRABLE INITIALLY DEFERRED
);

-- 同事务插入双向引用的数据（中间状态违反 FK）
BEGIN;
INSERT INTO departments VALUES (1, 'Engineering', 100);  -- 100 不存在
INSERT INTO employees VALUES (100, 'Alice', 1);          -- 1 已插入
COMMIT;  -- 此时检查所有 FK，都满足
```

### 用法 2：批量数据加载

```sql
-- 暂时禁用所有约束（不删除元数据）
BEGIN;
SET CONSTRAINTS ALL DEFERRED;

-- 批量加载，跨表数据可能瞬时不一致
COPY orders FROM '/tmp/orders.csv';
COPY order_items FROM '/tmp/order_items.csv';

COMMIT;  -- 提交时统一检查所有 DEFERRED 约束
```

### 用法 3：周期更新（PG 独有）

PostgreSQL 的 `DEFERRABLE` UNIQUE 约束允许在事务中临时违反唯一性：

```sql
-- 例：交换两个用户的 email
CREATE TABLE users (
    id INT PRIMARY KEY,
    email VARCHAR(255),
    CONSTRAINT uq_email UNIQUE (email) DEFERRABLE INITIALLY DEFERRED
);

INSERT INTO users VALUES (1, 'a@x.com'), (2, 'b@x.com');

BEGIN;
UPDATE users SET email = 'b@x.com' WHERE id = 1;  -- 暂时重复
UPDATE users SET email = 'a@x.com' WHERE id = 2;  -- 重复消除
COMMIT;
-- 没有 DEFERRABLE 时第一条 UPDATE 会因唯一约束冲突而失败
```

## 信息性约束（Informational Constraints）

### 数仓引擎的统一立场

Snowflake、BigQuery、Redshift、Vertica、Hive、Databricks、Impala 等数仓 / 数据湖引擎采用统一的"信息性约束"模式：

- 接受 PRIMARY KEY、FOREIGN KEY、UNIQUE 的声明语法（兼容迁移）
- 不强制执行（DML 不检查）
- 部分引擎让优化器使用约束信息（如 join elimination）

```sql
-- Snowflake 示例
CREATE TABLE orders (
    id INT NOT NULL,
    customer_id INT NOT NULL,
    PRIMARY KEY (id),                                                  -- 不强制
    CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES customers(id)   -- 不强制
);
-- 任何违反 PK 或 FK 的数据都会被接受
-- 优化器在某些版本中使用 PK 信息优化 join

-- BigQuery 2022+ 增加 PRIMARY KEY / FOREIGN KEY NOT ENFORCED 显式语法
CREATE TABLE dataset.orders (
    id INT64 NOT NULL,
    customer_id INT64 NOT NULL,
    PRIMARY KEY (id) NOT ENFORCED,
    FOREIGN KEY (customer_id) REFERENCES dataset.customers(id) NOT ENFORCED
);
```

### Flink SQL 的特殊约束模式

Flink SQL 在流处理上下文中，PK 的语义完全不同：

```sql
-- Flink: PRIMARY KEY ... NOT ENFORCED 是必填语法
CREATE TABLE orders (
    id BIGINT NOT NULL,
    quantity INT NOT NULL,
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'kafka',
    'format' = 'debezium-json'
);
-- ↑ PK 定义了 changelog 的 key，决定 upsert 语义
-- ↑ Flink 不能"检查"PK 唯一性（流是无限的）
```

Flink 的 `NOT ENFORCED` 是语义上的"我不强制"，而非"我可以强制但选择不"——本质上流处理引擎无法对无限数据流做唯一性检查。

## 优化器对约束验证状态的使用

### 完整的可信度判断

不同引擎对"未验证约束"的处理：

| 引擎 | NOT VALID / NOVALIDATE 约束 | 优化器使用 |
|------|---------------------------|----------|
| PostgreSQL | NOT VALID 的约束 | **不使用**（pg_constraint.convalidated = false） |
| Oracle | ENABLE NOVALIDATE 的约束 | 不使用，除非显式 `RELY` |
| Oracle | RELY ENABLE NOVALIDATE 的约束 | **使用**（用于物化视图重写） |
| SQL Server | NOCHECK 的约束 | 不使用（IS_NOT_TRUSTED = 1） |
| SQL Server | WITH CHECK CHECK CONSTRAINT 启用的约束 | **使用**（IS_NOT_TRUSTED = 0） |
| DB2 | NOT ENFORCED + ENABLE QUERY OPTIMIZATION | **使用** |
| DB2 | NOT ENFORCED + DISABLE QUERY OPTIMIZATION | 不使用 |
| MySQL | NOT ENFORCED 的 CHECK | 不使用 |
| Snowflake | 所有约束 | **使用 PK / UNIQUE / NOT NULL**（部分版本） |
| BigQuery | NOT ENFORCED 的 PK / FK | 部分使用（用于 join elimination） |

### Join Elimination 的实际效果

```sql
-- 表结构
CREATE TABLE orders (id INT PRIMARY KEY, customer_id INT NOT NULL);
ALTER TABLE orders ADD FOREIGN KEY (customer_id) REFERENCES customers(id);

-- 查询
SELECT o.id, o.customer_id
FROM orders o LEFT JOIN customers c ON o.customer_id = c.id;
-- 优化器可识别：FK 保证 customer 存在，LEFT JOIN 退化为 INNER JOIN
-- 进一步：只用到 o.customer_id（FK 列），可完全消除 JOIN

-- 但如果 FK 是 NOT VALID / NOCHECK / NOT ENFORCED 的：
-- PostgreSQL：不消除 JOIN（保守）
-- Oracle 默认：不消除（除非 RELY）
-- SQL Server NOCHECK：不消除
-- DB2 NOT ENFORCED + ENABLE QUERY OPT：消除
-- BigQuery NOT ENFORCED：可能消除（依赖优化器版本）
```

这个差异在 OLAP 场景下可以带来 10x-100x 的性能差异，但前提是数据真的满足约束——一旦约束被破坏，优化器的重写会产生错误结果。

## 跨引擎迁移检查清单

从一个引擎迁移到另一个引擎时，约束验证状态是常见的"哑炸弹"：

### Oracle 到 PostgreSQL

```sql
-- Oracle 中的约束状态
SELECT constraint_name, status, validated, rely
FROM user_constraints
WHERE table_name = 'ORDERS';

-- 状态映射表
-- Oracle ENABLE VALIDATE     → PG (默认 VALID)
-- Oracle ENABLE NOVALIDATE   → PG NOT VALID (但 PG 不能 RELY，需 VALIDATE 才能让优化器使用)
-- Oracle DISABLE VALIDATE    → PG (无原生，需 DROP CONSTRAINT)
-- Oracle DISABLE NOVALIDATE  → PG (无原生，需 DROP CONSTRAINT)
-- Oracle RELY                → PG (无原生)
```

### SQL Server 到 PostgreSQL

```sql
-- 检查 SQL Server 中所有不可信约束
SELECT object_name(parent_object_id), name FROM sys.check_constraints WHERE is_not_trusted = 1
UNION ALL
SELECT object_name(parent_object_id), name FROM sys.foreign_keys WHERE is_not_trusted = 1;

-- 这些约束在迁移到 PG 后，应：
-- a) 创建为 NOT VALID
-- b) 业务上线后清理违规数据
-- c) 然后 VALIDATE CONSTRAINT
```

### MySQL 到 PostgreSQL

```sql
-- MySQL 没有 NOT VALID 概念，所有约束都是已验证的
-- 但 MySQL 8.0.16+ 的 NOT ENFORCED CHECK 需要特殊处理
SELECT TABLE_NAME, CONSTRAINT_NAME, ENFORCED
FROM information_schema.CHECK_CONSTRAINTS
WHERE ENFORCED = 'NO';

-- 这些约束在 PG 中应创建为 NOT VALID
-- 注意：MySQL NOT ENFORCED 的 CHECK 不会拒绝违反约束的数据，可能存在违规行
```

### PostgreSQL 到云数仓（Snowflake / BigQuery / Redshift）

```sql
-- 重要：云数仓不强制约束
-- 迁移时所有 NOT VALID 状态都"丢失"语义
-- 所有约束都变为信息性约束
-- 应用层必须保证数据一致性

-- 推荐：在迁移工具中保留约束作为元数据，但不依赖其执行
-- 用 dbt tests 或外部数据质量工具补充约束检查
```

## Atlas / Liquibase / Flyway 的处理

主流的 schema 迁移工具对约束验证状态的支持差异：

### Atlas（HashiCorp 系）

```hcl
# Atlas HCL：原生支持 NOT VALID
table "orders" {
  schema = schema.public
  check "chk_total" {
    expr = "total > 0"
    enforced = false  # 等价于 NOT VALID（在 PG）或 NOCHECK（SQL Server）
  }
}
```

Atlas 支持的引擎中，会自动选择正确的语法：

- PostgreSQL: `NOT VALID`
- Oracle: `ENABLE NOVALIDATE`
- SQL Server: `WITH NOCHECK`
- DB2: `NOT ENFORCED`

### Liquibase

```xml
<!-- Liquibase XML：用 sql tag 显式指定 -->
<changeSet id="1" author="me">
  <sql>
    ALTER TABLE orders ADD CONSTRAINT chk_total CHECK (total > 0) NOT VALID;
  </sql>
  <sql>
    ALTER TABLE orders VALIDATE CONSTRAINT chk_total;
  </sql>
</changeSet>
```

Liquibase 的标准 changeset（如 `addCheckConstraint`）不直接支持 NOT VALID，需要用原生 SQL。

### Flyway

```sql
-- V1__add_constraint.sql
ALTER TABLE orders ADD CONSTRAINT chk_total CHECK (total > 0) NOT VALID;

-- V2__validate_constraint.sql（独立迁移，可在不同时间执行）
ALTER TABLE orders VALIDATE CONSTRAINT chk_total;
```

Flyway 把每个迁移视为独立单元，"先 NOT VALID 再 VALIDATE"是两个迁移的标准模式。

### gh-ost / pt-online-schema-change（MySQL 在线 DDL）

由于 MySQL 没有 NOT VALID 语法，gh-ost 和 pt-online-schema-change 用"影子表 + 触发器同步"模拟：

```
1. 创建影子表（含新约束）
2. 设置触发器，把主表的 INSERT/UPDATE/DELETE 同步到影子表
3. 后台分批 INSERT INTO 影子表 SELECT FROM 主表
4. 切换：原子地 RENAME 主表为旧表、影子表为主表
5. 删除旧表
```

这种方式实质上是绕开 MySQL 的限制，提供等价于 NOT VALID + VALIDATE 的效果，但实现复杂度极高。

## 关键发现

1. **NOT VALID / NOVALIDATE / NOCHECK / NOT ENFORCED 是同一语义的不同名字**：四个名字、四种 BNF 语法，但核心含义都是"添加约束时不验证现有数据"。这种术语分裂正是跨引擎迁移最痛苦的部分

2. **PostgreSQL 的 NOT VALID（2011）是大表迁移工程的拐点**：在它出现之前，给 10 亿行表加约束意味着"业务停服几小时"。9.1 之后，主流 OLTP 引擎的大表 schema 演进进入了"NOT VALID 时代"

3. **Oracle 的四象限状态机最完整**：`ENABLE/DISABLE × VALIDATE/NOVALIDATE` 的四种合法组合各有用途，叠加 `RELY/NORELY` 后形成完整的状态空间，这是 9i（2001）就奠定的优雅设计

4. **SQL Server 的"trustworthy"概念是独一份**：通过 `IS_NOT_TRUSTED` 标志区分"启用但未验证"和"启用且已验证"的约束，决定优化器是否使用——这种细粒度的"信任度"比 PG / DB2 都更精确

5. **DB2 的 SET INTEGRITY 是批量加载场景的最佳设计**：把整张表设为 check pending，批量加载后统一恢复，避免逐行检查的开销，是数据仓库 ETL 的优雅原语

6. **MySQL 的 NOT VALID 等价机制至今缺失**：8.0.16 引入的 `NOT ENFORCED` 仅适用于 CHECK 约束，且没有"添加 FK 时跳过验证"的语法。大表加 FK 仍需 gh-ost 等外部工具，这是 MySQL 生态的长期痛点

7. **DEFERRABLE 是 SQL:1992 的"标准残骸"**：标准已 30 年，但只有 PG / Oracle / SQLite / Firebird / HSQLDB / YugabyteDB / OceanBase / CockroachDB（v22.2+ 仅 FK）完整实现。MySQL / SQL Server / DB2 用其他机制替代，标准与实现的脱节明显

8. **PG CHECK 约束不支持 DEFERRABLE 是设计取舍**：PG 文档明确说 CHECK 始终为 IMMEDIATE，原因是 CHECK 的语义是"行级"的，延迟到事务末尾的成本（保留所有行的 CHECK 上下文）超过了收益。Oracle 的 CHECK DEFERRABLE 设计上更激进，但实现复杂度也更高

9. **优化器对未验证约束的处理是分水岭**：DB2 / Oracle (RELY) / BigQuery 让优化器使用未验证约束以实现 join elimination；PG / SQL Server / MySQL 保守不使用。前者性能更好但有"约束被破坏导致结果错误"的风险

10. **信息性约束（云数仓）是工作负载分化的产物**：Snowflake / BigQuery / Redshift 全部约束不强制，因为分析场景下"数据一致性由 ETL 保证"，再让数据库重复检查只是浪费资源。这是工程领域"约束模型应匹配工作负载"的成熟认知

11. **Flink SQL / RisingWave 的 NOT ENFORCED PK 是流处理的根本性约束**：流是无限的，无法做唯一性检查，PK 只能定义 changelog 的 key。这不是"选择不强制"，而是"不可能强制"

12. **NOT NULL 与其他约束在大表迁移上的不对称性**：PostgreSQL 11 之前，添加 NOT NULL 必须扫全表，迫使 DBA 用 CHECK NOT VALID 迂回。这种不对称在 PG 11+ 通过"等价 CHECK 检测"修复，但 SQL Server / MySQL 至今仍有同样问题

13. **SQL Server 2022 标记 WITH NOCHECK 为不推荐是文档与现实的冲突**：官方推荐"先清理再添加可信约束"，但对 100 亿行表不现实。文档建议与工程实践之间的张力是 SQL Server 团队的长期话题

14. **MariaDB 与 MySQL 在 NOT ENFORCED 上的分裂**：MariaDB 早于 MySQL 实现 CHECK 强制（2017 vs 2019），但**没有**引入 ENFORCED 关键字。这是两个引擎在约束语义上的明显分歧，迁移时需特别注意

15. **TiDB / CockroachDB / YugabyteDB 的 NOT VALID 路径不同**：YugabyteDB 完整继承 PG 语法；CockroachDB 在 v19.1 引入 NOT VALID（仅 CHECK），v22.2 才加入 DEFERRABLE FK；TiDB 至今没有 NOT VALID 的等价语法，只能依赖在线 DDL 工具（如 ghost）

16. **Atlas 是首个跨引擎抽象 NOT VALID 的工具**：把 `enforced = false` 抽象为统一概念，根据目标引擎自动翻译。这是 schema-as-code 工具相对 Liquibase / Flyway 的关键进步

17. **约束失效后的"静默风险"是引擎共性问题**：所有支持 NOVALIDATE / NOCHECK / NOT ENFORCED 的引擎都面临同一风险——管理员忘记 VALIDATE，约束元数据存在但数据已分裂。监控应包含"未验证约束计数"和"对应表行数"

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992, Section 4.10 / 11.7 (约束属性、DEFERRABLE)
- SQL:2003 标准: ISO/IEC 9075-2:2003 (ENFORCED / NOT ENFORCED 语义)
- PostgreSQL: [ALTER TABLE - VALIDATE CONSTRAINT](https://www.postgresql.org/docs/current/sql-altertable.html)
- PostgreSQL: [9.1 Release Notes - NOT VALID for FK](https://www.postgresql.org/docs/release/9.1.0/)
- PostgreSQL: [SET CONSTRAINTS](https://www.postgresql.org/docs/current/sql-set-constraints.html)
- Oracle: [Constraint States](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/data-integrity.html#GUID-A77E2362-2535-4EBC-A5C1-A4A2DBE54256)
- Oracle: [Validate Existing Data With Disabled Constraints](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/maintaining-data-integrity.html)
- Oracle: [RELY / NORELY](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/constraint.html)
- SQL Server: [WITH CHECK / WITH NOCHECK](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-table-transact-sql)
- SQL Server: [sys.check_constraints (is_not_trusted)](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-check-constraints-transact-sql)
- DB2: [SET INTEGRITY](https://www.ibm.com/docs/en/db2/11.5?topic=statements-set-integrity)
- DB2: [ALTER TABLE - NOT ENFORCED](https://www.ibm.com/docs/en/db2/11.5?topic=statements-alter-table)
- MySQL: [CHECK Constraints (8.0.16)](https://dev.mysql.com/doc/refman/8.0/en/create-table-check-constraints.html)
- MySQL 8.0.16 Release Notes: [CHECK Constraint Support](https://dev.mysql.com/doc/relnotes/mysql/8.0/en/news-8-0-16.html)
- MariaDB: [CHECK Constraints](https://mariadb.com/kb/en/constraint/)
- SQLite: [Foreign Key Support - DEFERRABLE](https://www.sqlite.org/foreignkeys.html#fk_deferred)
- Snowflake: [Constraints](https://docs.snowflake.com/en/sql-reference/constraints-overview)
- BigQuery: [Constraints (NOT ENFORCED)](https://cloud.google.com/bigquery/docs/information-schema-table-constraints)
- CockroachDB: [VALIDATE CONSTRAINT](https://www.cockroachlabs.com/docs/stable/validate-constraint)
- YugabyteDB: [ALTER TABLE - VALIDATE CONSTRAINT](https://docs.yugabyte.com/preview/api/ysql/the-sql-language/statements/ddl_alter_table/)
- Hive: [Constraints (RELY / NOVALIDATE)](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL)
- Flink SQL: [PRIMARY KEY NOT ENFORCED](https://nightlies.apache.org/flink/flink-docs-master/docs/dev/table/sql/create/)
- Atlas: [Constraints HCL](https://atlasgo.io/atlas-schema/hcl)
- gh-ost: [Online schema migrations for MySQL](https://github.com/github/gh-ost)
- Jim Melton, "Understanding SQL's Stored Procedures" (1998) - SQL:1999 约束属性背景
- Tom Kyte, "Effective Oracle by Design" (2003) - Oracle 约束状态机详解
