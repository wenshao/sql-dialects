# TRUNCATE vs DELETE 深度对比

同样是清空表，`TRUNCATE` 可能毫秒级完成，`DELETE FROM t` 却会让数据库跑到怀疑人生。它们看起来只是"快"与"慢"的差别，实则横跨 DDL / DML、事务 / 自动提交、触发器 / 无触发器、最小日志 / 完整日志，是 SQL 引擎设计中最容易被误解的一对操作。本文跨越 48 个 SQL 引擎，从 SQL:2008 标准到各家实现差异，系统梳理 `TRUNCATE` 与 `DELETE` 的语义边界。

## 背景：看似相似，实则完全不同

一句话总结二者的本质：

- `DELETE FROM t` 是 **DML**，逐行从数据页中标记或移除记录，生成完整的 Undo / Redo / Binlog，保留所有触发器、行级检查。
- `TRUNCATE TABLE t` 是 **DDL**（在多数引擎上），通过重置数据文件 / 释放区（extent） / 重建段（segment）来"清空"表，代价与表中数据量几乎无关。

这带来一连串语义差异：

| 维度 | DELETE | TRUNCATE |
|------|--------|----------|
| 类别 | DML | 多数引擎 DDL |
| 事务 | 完全事务 | 取决于引擎（PG 可 ROLLBACK，Oracle 不可） |
| 触发器 | 触发 BEFORE/AFTER DELETE | 多数不触发；PG 有独立 TRUNCATE 触发器 |
| 自增 | 不重置 AUTO_INCREMENT | 多数重置 AUTO_INCREMENT/IDENTITY |
| 日志 | 行级完整日志 | 最小日志 / 页释放 |
| 外键 | 按约束级联 | 多数被外键引用时禁止，或需 CASCADE |
| 锁 | 行锁 / 表锁，允许并发 SELECT | 多数获取 exclusive / Schema-M 锁 |
| 权限 | DELETE | DROP / ALTER / TRUNCATE |
| 性能 | O(N) | ~O(1) |

## SQL:2008 标准化

`TRUNCATE TABLE` 直到 SQL:2008（ISO/IEC 9075-2:2008, Feature T581 "Regular and immediate check constraints"，以及新增的 `<truncate table statement>` 语法部分）才进入核心标准，语法定义为：

```sql
<truncate table statement> ::=
    TRUNCATE TABLE <target table>
    [ <identity column restart option> ]

<identity column restart option> ::=
      CONTINUE IDENTITY
    | RESTART IDENTITY
```

标准关键点：

1. **强制清空目标表的所有行**，但 `TRUNCATE` 不是 `SELECT`/`DELETE` 的派生操作——它被定义为独立的语句类别。
2. **自增列处理可选**：`CONTINUE IDENTITY`（默认）保留下次取值，`RESTART IDENTITY` 将序列重置为初始值。
3. **触发器行为未定义**：标准没有强制要求触发 DELETE 触发器（因此大多数厂商选择不触发）。
4. **视图与继承表未定义**：由各厂商扩展，例如 PostgreSQL 加入 `CASCADE` 级联。
5. **标准未包含 `CASCADE` 语义**：外键下的处理由实现决定。

值得注意的是，SQL:2008 之前，`TRUNCATE` 已经在几乎所有主流商业数据库（Oracle、SQL Server、DB2、MySQL）作为非标准扩展存在了十年以上。标准实际上是事后追认而非前瞻定义。

## 支持矩阵

### 1. TRUNCATE TABLE 语句支持

| 引擎 | 支持 | 关键字/语法 | 备注 |
|------|------|-------------|------|
| PostgreSQL | 是 | `TRUNCATE [TABLE] t [, ...]` | 支持多表 |
| MySQL | 是 | `TRUNCATE [TABLE] t` | 5.5+ 实为隐式 DDL |
| MariaDB | 是 | `TRUNCATE [TABLE] t` | 与 MySQL 相同 |
| SQLite | 是* | `DELETE FROM t`（TRUNCATE 优化） | 没有 TRUNCATE 关键字 |
| Oracle | 是 | `TRUNCATE TABLE t` | DDL，auto-commit |
| SQL Server | 是 | `TRUNCATE TABLE t` | 最小日志 |
| DB2 | 是 | `TRUNCATE TABLE t IMMEDIATE` | IMMEDIATE 必需 |
| Snowflake | 是 | `TRUNCATE [TABLE] t` | Time Travel 可恢复 |
| BigQuery | 是 | `TRUNCATE TABLE t` | 2022 GA |
| Redshift | 是 | `TRUNCATE [TABLE] t` | 继承 PG |
| DuckDB | 是 | `TRUNCATE t` | 0.3+ |
| ClickHouse | 是 | `TRUNCATE TABLE t [ON CLUSTER c]` | Replicated 经 ZK |
| Trino | 是 | `TRUNCATE TABLE t` | 依赖 connector |
| Presto | 部分 | `TRUNCATE TABLE t` | 依赖 connector |
| Spark SQL | 是 | `TRUNCATE TABLE t [PARTITION (...)]` | 支持分区截断 |
| Hive | 是 | `TRUNCATE TABLE t [PARTITION (...)]` | 仅 managed 表 |
| Flink SQL | 是 | `TRUNCATE TABLE t` | 1.18+ |
| Databricks | 是 | `TRUNCATE TABLE t` | Delta 不支持*见下 |
| Teradata | 是 | `DELETE FROM t ALL`（等价） | 无 TRUNCATE 关键字 |
| Greenplum | 是 | `TRUNCATE [TABLE] t` | 继承 PG |
| CockroachDB | 是 | `TRUNCATE [TABLE] t [, ...]` | 实为 DROP+RECREATE |
| TiDB | 是 | `TRUNCATE TABLE t` | region 重建极快 |
| OceanBase | 是 | `TRUNCATE TABLE t` | Oracle 兼容模式 DDL |
| YugabyteDB | 是 | `TRUNCATE [TABLE] t` | 继承 PG，但仍异步 |
| SingleStore | 是 | `TRUNCATE TABLE t` | 原子 |
| Vertica | 是 | `TRUNCATE TABLE t` | 快速 |
| Impala | 是 | `TRUNCATE TABLE [IF EXISTS] t` | 2.3+ |
| StarRocks | 是 | `TRUNCATE TABLE t [PARTITION (...)]` | 支持分区 |
| Doris | 是 | `TRUNCATE TABLE t [PARTITION (...)]` | 支持分区 |
| MonetDB | 是 | `TRUNCATE [TABLE] t` | 事务 |
| CrateDB | 否 | -- | 需 DELETE + OPTIMIZE |
| TimescaleDB | 是 | `TRUNCATE t` | 继承 PG，hypertable 特殊 |
| QuestDB | 是 | `TRUNCATE TABLE t` | 非事务 |
| Exasol | 是 | `TRUNCATE TABLE t` | DDL |
| SAP HANA | 是 | `TRUNCATE TABLE t` | DDL |
| Informix | 是 | `TRUNCATE [TABLE] t` | 11.50+ |
| Firebird | 否 | -- | 必须 DELETE FROM t |
| H2 | 是 | `TRUNCATE TABLE t` | DDL |
| HSQLDB | 是 | `TRUNCATE TABLE t [RESTART IDENTITY]` | 标准最贴近 |
| Derby | 是 | `TRUNCATE TABLE t` | 10.11+ |
| Amazon Athena | 否 | -- | 外部表不支持 |
| Azure Synapse | 是 | `TRUNCATE TABLE t` | 继承 SQL Server |
| Google Spanner | 否 | -- | 需 `DELETE FROM t WHERE TRUE` |
| Materialize | 否 | -- | 不支持 DML/DDL 清表 |
| RisingWave | 否 | -- | 物化视图语义 |
| InfluxDB (SQL) | 否 | `DROP MEASUREMENT` | 无 TRUNCATE |
| DatabendDB | 是 | `TRUNCATE TABLE t [PURGE]` | PURGE 释放历史 |
| Yellowbrick | 是 | `TRUNCATE [TABLE] t` | 继承 PG |
| Firebolt | 是 | `TRUNCATE TABLE t` | 快速清空 |

> 统计：约 41 个引擎支持 `TRUNCATE TABLE` 关键字，Teradata 通过 `DELETE ... ALL` 等价实现，SQLite 通过"TRUNCATE 优化"隐式实现。

### 2. CASCADE 级联删除依赖行

| 引擎 | 支持 CASCADE | 语法 | 备注 |
|------|--------------|------|------|
| PostgreSQL | 是 | `TRUNCATE t CASCADE` | 级联所有 FK 引用表 |
| MySQL | 否 | -- | 有 FK 直接报错 |
| MariaDB | 否 | -- | 同 MySQL |
| SQLite | 否 | -- | 无 TRUNCATE |
| Oracle | 部分 | `TRUNCATE TABLE t CASCADE` | 12c+，需 ON DELETE CASCADE |
| SQL Server | 否 | -- | FK 存在则禁止 |
| DB2 | 否 | -- | FK 存在则禁止 |
| Snowflake | 否 | -- | 无 FK 约束检查 |
| BigQuery | 否 | -- | 无 FK |
| Redshift | 是 | `TRUNCATE t CASCADE` | 继承 PG |
| DuckDB | 否 | -- | 无 FK 强制 |
| ClickHouse | 否 | -- | 无 FK |
| Trino | 否 | -- | 依赖 connector |
| Spark SQL | 否 | -- | 无 FK |
| Hive | 否 | -- | 无 FK |
| Flink SQL | 否 | -- | 无 FK |
| Databricks | 否 | -- | 无 FK 强制 |
| Greenplum | 是 | `TRUNCATE t CASCADE` | 继承 PG |
| CockroachDB | 是 | `TRUNCATE t CASCADE` | 级联引用 |
| TiDB | 否 | -- | 有 FK 报错 |
| OceanBase | 部分 | `TRUNCATE TABLE t CASCADE` | Oracle 模式 |
| YugabyteDB | 是 | `TRUNCATE t CASCADE` | 继承 PG |
| Vertica | 否 | -- | 有 FK 需手动 |
| SingleStore | 否 | -- | 无 FK 强制 |
| Impala | 否 | -- | 无 FK |
| StarRocks | 否 | -- | 无 FK |
| Doris | 否 | -- | 无 FK |
| H2 | 否 | -- | 有 FK 报错 |
| HSQLDB | 否 | -- | 有 FK 报错 |
| Derby | 否 | -- | 有 FK 报错 |
| TimescaleDB | 是 | `TRUNCATE t CASCADE` | 继承 PG |
| SAP HANA | 否 | -- | FK 存在则禁止 |
| Informix | 否 | -- | 有 FK 报错 |
| Exasol | 否 | -- | 有 FK 报错 |
| DatabendDB | 否 | -- | 无 FK |
| Yellowbrick | 是 | `TRUNCATE t CASCADE` | 继承 PG |
| Firebolt | 否 | -- | 无 FK |

> 统计：约 8 个引擎支持 `TRUNCATE ... CASCADE`，均来自 PostgreSQL 血统；Oracle 12c+ 在启用 `ON DELETE CASCADE` 外键时亦支持。其余引擎大多禁止截断被引用表，需先断开外键或删除引用方。

### 3. RESTART IDENTITY / CONTINUE IDENTITY

| 引擎 | RESTART IDENTITY | 默认行为 | 关键字 |
|------|------------------|---------|--------|
| PostgreSQL | 是 | CONTINUE | `TRUNCATE t RESTART IDENTITY` |
| MySQL | 自动重置 | 重置 | 无关键字，AUTO_INCREMENT=1 |
| MariaDB | 自动重置 | 重置 | 同 MySQL |
| Oracle | 是 | CONTINUE（11g 前） | `TRUNCATE ... [REUSE|DROP STORAGE]`；12c+ 序列不重置 |
| SQL Server | 自动重置 | 重置 | IDENTITY 恢复为 SEED |
| DB2 | 是 | 无默认 | `[CONTINUE|RESTART] IDENTITY` 必选其一 |
| Snowflake | 否 | CONTINUE | 不重置 sequence |
| BigQuery | 否 | 无 IDENTITY | -- |
| Redshift | 是 | CONTINUE | `TRUNCATE t RESTART IDENTITY` |
| DuckDB | 是 | CONTINUE | 10+ 支持 |
| ClickHouse | 不适用 | -- | 无 IDENTITY 概念 |
| Trino | 否 | -- | 依赖 connector |
| Spark SQL | 不适用 | -- | 无 IDENTITY（Delta 有） |
| Flink SQL | 不适用 | -- | -- |
| Databricks | 部分 | CONTINUE | Delta IDENTITY 不重置 |
| Greenplum | 是 | CONTINUE | 继承 PG |
| CockroachDB | 是 | CONTINUE | `TRUNCATE t RESTART IDENTITY` |
| TiDB | 自动重置 | 重置 | AUTO_INCREMENT=1 |
| OceanBase | 自动重置 | 重置 | MySQL 模式 |
| YugabyteDB | 是 | CONTINUE | 继承 PG |
| SingleStore | 自动重置 | 重置 | -- |
| Vertica | 是 | 重置 | 默认重置 IDENTITY |
| Impala | 不适用 | -- | 无 IDENTITY |
| StarRocks | 不适用 | -- | -- |
| Doris | 不适用 | -- | -- |
| H2 | 是 | CONTINUE | `RESTART IDENTITY` |
| HSQLDB | 是 | CONTINUE | 标准语法 |
| Derby | 否 | CONTINUE | 仍需 `ALTER TABLE ... RESTART` |
| TimescaleDB | 是 | CONTINUE | 继承 PG |
| SAP HANA | 是 | 重置 | `TRUNCATE TABLE t` 默认重置 |
| Informix | 是 | -- | `RESTART WITH` |
| Exasol | 是 | 重置 | 默认重置 IDENTITY |
| Firebolt | 不适用 | -- | 无 IDENTITY |

> 统计：16 个引擎支持标准的 `RESTART IDENTITY` 关键字；MySQL/MariaDB/TiDB/SQL Server 等默认重置，无需显式关键字；Snowflake 与 Databricks（Delta）独特地保持序列不重置。

### 4. 事务支持（ROLLBACK）

| 引擎 | 事务内 TRUNCATE | ROLLBACK 有效 | 备注 |
|------|----------------|--------------|------|
| PostgreSQL | 是 | 是 | 完整 MVCC |
| MySQL (InnoDB) | 否 | 否 | 隐式提交 |
| MariaDB | 否 | 否 | 同 MySQL |
| SQLite | 是 | 是 | DELETE 优化路径 |
| Oracle | 否 | 否 | DDL auto-commit |
| SQL Server | 是 | 是 | 与 DELETE 同事务 |
| DB2 | 是 | 是 | 带 IMMEDIATE |
| Snowflake | 是 | 是 | Time Travel |
| BigQuery | 否 | 否 | 无显式事务 |
| Redshift | 是 | 是 | 但截断全局可见 |
| DuckDB | 是 | 是 | MVCC |
| ClickHouse | 否 | 否 | 不支持回滚 |
| Trino | 取决于 | -- | 依赖 connector |
| Spark SQL | 否 | 否 | 非 ACID |
| Hive | 否 | 否 | 非事务 |
| Flink SQL | 否 | 否 | 流语义 |
| Databricks (Delta) | 部分 | 否 | 单语句 ACID |
| Greenplum | 是 | 是 | 继承 PG |
| CockroachDB | 否 | 否 | 独立 DDL |
| TiDB | 否 | 否 | DDL 隐式提交 |
| OceanBase | 否 | 否 | DDL 隐式提交 |
| YugabyteDB | 是 | 是 | 继承 PG |
| Vertica | 是 | 是 | WOS/ROS |
| SingleStore | 否 | 否 | -- |
| Impala | 否 | 否 | -- |
| StarRocks | 否 | 否 | -- |
| Doris | 否 | 否 | -- |
| H2 | 是 | 是 | -- |
| HSQLDB | 是 | 是 | -- |
| Derby | 否 | 否 | DDL auto-commit |
| TimescaleDB | 是 | 是 | 继承 PG |
| SAP HANA | 否 | 否 | DDL auto-commit |
| Informix | 否 | 否 | DDL auto-commit |
| Exasol | 是 | 是 | -- |
| DatabendDB | 是 | 是 | 对象存储版本化 |
| Yellowbrick | 是 | 是 | 继承 PG |
| Firebolt | 否 | 否 | -- |

> 统计：约 16 个引擎允许 `TRUNCATE` 在事务中被 `ROLLBACK`。Oracle / MySQL / DB2 阵营（传统 DDL auto-commit）阻止回滚；PostgreSQL 系与 SQL Server 在事务块内可撤销。

### 5. 触发器行为

| 引擎 | DELETE 触发器 | TRUNCATE 触发器 | 备注 |
|------|--------------|-----------------|------|
| PostgreSQL | 是 | 是 | 8.4+ 独立 `CREATE TRIGGER ... TRUNCATE` |
| MySQL | 是 | 否 | TRUNCATE 跳过所有触发器 |
| MariaDB | 是 | 否 | 同 MySQL |
| Oracle | 是 | 否 | DDL 触发器可监听 |
| SQL Server | 是 | 否 | TRUNCATE 绕过触发器 |
| DB2 | 是 | 否 | 需显式 `IGNORE DELETE TRIGGERS` / `RESTRICT` |
| Snowflake | 不适用 | 不适用 | 无行级触发器 |
| BigQuery | 不适用 | 不适用 | 无触发器 |
| Redshift | 不适用 | 不适用 | 无触发器 |
| DuckDB | 不适用 | 不适用 | 无触发器 |
| ClickHouse | 不适用 | 不适用 | 无触发器 |
| Trino | 不适用 | 不适用 | 无触发器 |
| Spark SQL | 不适用 | 不适用 | 无触发器 |
| Hive | 不适用 | 不适用 | 无触发器 |
| Flink SQL | 不适用 | 不适用 | -- |
| Databricks | 不适用 | 不适用 | -- |
| Greenplum | 是 | 是 | 继承 PG |
| CockroachDB | 不适用 | 不适用 | 不支持触发器 |
| TiDB | 不适用 | 不适用 | 不支持 |
| OceanBase | 是 | 否 | Oracle 兼容 |
| YugabyteDB | 是 | 是 | 继承 PG |
| SingleStore | 不适用 | 不适用 | -- |
| Vertica | 不适用 | 不适用 | -- |
| Impala | 不适用 | 不适用 | -- |
| StarRocks | 不适用 | 不适用 | -- |
| Doris | 不适用 | 不适用 | -- |
| H2 | 是 | 否 | -- |
| HSQLDB | 是 | 否 | -- |
| Derby | 是 | 否 | -- |
| TimescaleDB | 是 | 是 | 继承 PG |
| SAP HANA | 是 | 否 | -- |
| Informix | 是 | 否 | -- |
| Firebird | 是 | 不适用 | 无 TRUNCATE |
| Exasol | 不适用 | 不适用 | -- |

> 关键结论：几乎所有引擎都不触发 DELETE 触发器——`TRUNCATE` 被视为"集合级"操作。PostgreSQL 独树一帜，通过新增 `TRUNCATE` 触发器类型解决"审计需求"。

### 6. 日志与持久化

| 引擎 | DELETE 日志级别 | TRUNCATE 日志级别 | 说明 |
|------|----------------|-------------------|------|
| PostgreSQL | 完整 WAL | 仅记录文件 unlink / 重建 | WAL 极小 |
| MySQL (InnoDB) | 行级 Undo+Redo+Binlog | Redo 仅 DDL，Binlog 记 DDL | 5.5+ 隐式重建 |
| SQLite | 完整 journal | TRUNCATE 优化：小 journal | "DELETE 大优化" |
| Oracle | 行级 Undo + Redo | 仅 DDL + 段头 | 不产生 UNDO |
| SQL Server | 行级日志 | 页/区 deallocation 记录 | 最小日志 |
| DB2 | 行级日志 | 可选 `IGNORE DELETE TRIGGERS` / `NOT LOGGED` | 支持 NOT LOGGED INITIALLY |
| Snowflake | 新 micropartition | 取消引用 micropartition | Time Travel 可见 |
| BigQuery | 按字节计费 | 免费（DDL） | 2022 起 |
| Redshift | 完整 | 仅元数据 | -- |
| ClickHouse | 重写 part | 删除 part | Replicated: ZK 协调 |
| Spark SQL | 取决于格式 | 清空路径 | -- |
| Hive | 视表类型 | 清空目录 | managed 表 |
| TiDB | 行级日志 | DDL | 区域重建 |
| OceanBase | 完整日志 | DDL | Oracle/MySQL 模式 |
| YugabyteDB | 完整日志 | DDL 异步 | -- |
| H2 | 完整 | 最小 | -- |
| HSQLDB | 完整 | 最小 | -- |

### 7. 权限模型

| 引擎 | DELETE 权限 | TRUNCATE 权限 |
|------|-------------|---------------|
| PostgreSQL | `DELETE ON TABLE` | `TRUNCATE ON TABLE`（独立权限，8.4+） |
| MySQL | `DELETE` | `DROP`（TRUNCATE 被视为 DROP+CREATE） |
| Oracle | `DELETE ANY TABLE` | `DROP ANY TABLE` 或表所有者 |
| SQL Server | `DELETE` | `ALTER ON TABLE` |
| DB2 | `DELETE` | `ALTER` 或 `DATAACCESS` |
| Snowflake | `DELETE` on table | `OWNERSHIP` 或 `TRUNCATE`（9+） |
| BigQuery | `bigquery.tables.updateData` | `bigquery.tables.update` + `updateData` |
| Redshift | `DELETE` | `TRUNCATE`（独立，PG 风格） |
| ClickHouse | `ALTER DELETE` | `TRUNCATE` |
| CockroachDB | `DELETE` | `DROP` |
| TiDB | `DELETE` | `DROP` |
| Vertica | `DELETE` | `TRUNCATE` 独立 |
| SAP HANA | `DELETE` | `DELETE` 或 `ALTER` |

> PostgreSQL 自 8.4 起将 TRUNCATE 从 "DELETE 权限" 分离出来，这样高权限的批量清空不会被普通 DELETE 权限滥用。这是精细授权的典范。

### 8. 并发与锁

| 引擎 | DELETE 锁 | TRUNCATE 锁 | 阻塞 SELECT? |
|------|-----------|-------------|--------------|
| PostgreSQL | 行锁 | ACCESS EXCLUSIVE | 是 |
| MySQL (InnoDB) | 行锁 (S/X) | MDL exclusive | 是（DDL） |
| SQLite | 数据库锁 | 数据库锁 | 是 |
| Oracle | 行锁 | TM exclusive | 是 |
| SQL Server | 行/页/表锁 | Sch-M | 是 |
| DB2 | 行锁 | exclusive | 是 |
| Snowflake | 无需锁 | 无需锁 | 否（MVCC） |
| BigQuery | 快照 | 快照 | 否 |
| Redshift | 表锁 | AccessExclusiveLock | 是 |
| ClickHouse | 分区锁 | 分区锁 | 基本否 |
| CockroachDB | 行锁 | online DDL | 否 |
| TiDB | 行锁 | online DDL（慢） | 否 |
| Spark SQL | -- | 文件系统锁 | -- |
| Databricks (Delta) | 乐观并发 | 乐观并发 | 否 |
| Vertica | 表锁 | exclusive | 是 |

## 详细语义与实现（按引擎）

### PostgreSQL：事务型 TRUNCATE 的标杆

```sql
BEGIN;
TRUNCATE TABLE orders RESTART IDENTITY CASCADE;
-- 发现不对
ROLLBACK;
-- orders 表数据完好
```

PG 的 `TRUNCATE` 实际上在文件系统层面创建一个新的 `relfilenode`，旧 `relfilenode` 只有在事务提交后才被回收。若 `ROLLBACK`，新 relfilenode 被丢弃，旧的仍有效。因此：

- 可以 `ROLLBACK`：事务 MVCC 完整。
- 但其他事务看不到原表行（`ACCESS EXCLUSIVE` 锁直到事务结束）。
- 可以 `CASCADE` 级联被 FK 引用的所有表。
- 可以 `RESTART IDENTITY` 重置所有相关序列。

从 8.4 起，PG 支持 `CREATE TRIGGER ... AFTER TRUNCATE`，解决审计场景。触发器按语句级触发，不可访问行数据（因为"所有行"被一次性清空）。

```sql
CREATE OR REPLACE FUNCTION log_truncate() RETURNS trigger AS $$
BEGIN
  INSERT INTO audit_log(table_name, action, ts)
  VALUES (TG_TABLE_NAME, 'TRUNCATE', now());
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_truncate_audit
AFTER TRUNCATE ON orders
FOR EACH STATEMENT EXECUTE FUNCTION log_truncate();
```

### Oracle：DDL 教科书

```sql
-- 无事务控制
TRUNCATE TABLE orders;          -- 立即提交
TRUNCATE TABLE orders REUSE STORAGE;   -- 保留已分配段
TRUNCATE TABLE orders DROP STORAGE;    -- 默认，释放段
TRUNCATE TABLE orders CASCADE;  -- 12c+，前提是 FK 配置了 ON DELETE CASCADE
```

Oracle 特征：

- `TRUNCATE` 是 **DDL**：先提交前面的所有未提交事务，然后执行，最后再次提交。整个过程不可 `ROLLBACK`。
- **重置 HWM（High Water Mark）**：这是性能关键。全表扫描在 Oracle 中扫到 HWM 为止，`DELETE` 不重置 HWM，导致后续 `SELECT COUNT(*)` 仍扫空页；`TRUNCATE` 重置 HWM 到段头。
- 不触发 DML 触发器，但会触发 DDL 触发器（如 `BEFORE TRUNCATE ON SCHEMA`）。
- 若表被启用的 FK 引用（无论有无数据），默认拒绝；12c 引入 `CASCADE` 要求 FK 为 `ON DELETE CASCADE`。
- `REUSE STORAGE`：保留已分配的 extent，供后续插入快速复用。

### SQL Server：最小日志的误解

```sql
BEGIN TRAN;
TRUNCATE TABLE orders;
ROLLBACK;   -- 成功回滚
```

SQL Server 的 `TRUNCATE` 一直是支持回滚的，这与 Oracle/MySQL 形成鲜明对比。

"最小日志"（minimally logged）的真实含义：SQL Server 不记录**每一行**的删除，而是记录 **页 / 区释放**。这意味着：

- 日志体积远小于等价 DELETE。
- 崩溃恢复仍然完整：页释放记录足以重放。
- 需要在 SIMPLE 或 BULK_LOGGED 恢复模式下才能真正享受最小日志优势；FULL 恢复模式下，事务日志仍会被完整记录（但仍远小于 DELETE）。
- 拿的是 `Sch-M`（Schema Modify）锁，比 DELETE 的行锁级别更高，但持续时间短。
- 不触发 DELETE 触发器，不能有引用的 FK（无视是否 disabled）。

### MySQL / MariaDB InnoDB：5.5+ 的隐式 DDL

```sql
-- MySQL 5.1 及之前：按行 DELETE，非常慢
-- MySQL 5.5+：等价于 DROP TABLE + CREATE TABLE
TRUNCATE TABLE orders;
```

5.5 以后 MySQL InnoDB 的 `TRUNCATE` 演变为：

1. 获取 MDL exclusive。
2. 创建与原表结构完全相同的新 `.ibd` 文件。
3. 原子替换。
4. AUTO_INCREMENT 重置为 1（或表定义的起点）。

副作用：

- **不能回滚**：隐式提交前序事务。
- **外键存在引用时直接报错**：ERROR 1701 "Cannot truncate a table referenced in a foreign key constraint"。
- 主从复制使用 binlog 事件 `Query: TRUNCATE TABLE`，从库重放同样快。
- GTID 下 TRUNCATE 产生单独的 GTID。
- 5.7+ 引入"延迟加载 undo"，TRUNCATE 不再需要扫描 undo 段。

### DB2：RESTART 必选

```sql
-- DB2 要求至少一个限定符
TRUNCATE TABLE orders IMMEDIATE;
TRUNCATE TABLE orders DROP STORAGE IMMEDIATE;
TRUNCATE TABLE orders REUSE STORAGE IGNORE DELETE TRIGGERS IMMEDIATE;

-- 重置 IDENTITY
TRUNCATE TABLE orders RESTART IDENTITY IMMEDIATE;

-- 保留 IDENTITY
TRUNCATE TABLE orders CONTINUE IDENTITY IMMEDIATE;
```

`IMMEDIATE` 是 DB2 独有的强制关键字，表明"我明确知道这条语句立即生效、不可回滚"，是一种安全提示。

- 默认 `IGNORE DELETE TRIGGERS`，可改为 `RESTRICT WHEN DELETE TRIGGERS` 来强制报错。
- 不允许在具有 enabled 外键的表上运行。
- DB2 LUW 与 DB2 for z/OS 语法略有不同。

### SQLite：TRUNCATE 优化

SQLite 没有 `TRUNCATE` 关键字，但它对 `DELETE FROM t`（无 WHERE）有一个专门的"TRUNCATE 优化"：

- 检测到无 WHERE 子句且无 DELETE 触发器时，不逐行扫描删除。
- 直接 drop + 重建 B-Tree 根页。
- 不影响 `sqlite_sequence` 表（AUTO_INCREMENT），除非手动 `DELETE FROM sqlite_sequence WHERE name='t'`。
- 若存在 DELETE 触发器或 `RETURNING` 子句，退化为逐行扫描。
- PRAGMA `count_changes` 下，返回的行数为 0（因为没有逐行），这在历史上是兼容性问题；现代版本修复返回正确行数。

```sql
DELETE FROM orders;  -- TRUNCATE 优化
DELETE FROM orders WHERE 1;  -- 仍是 TRUNCATE 优化
DELETE FROM orders WHERE created_at < '2020-01-01';  -- 非优化
```

### MySQL / MariaDB：外键的陷阱

```sql
CREATE TABLE parent(id INT PRIMARY KEY);
CREATE TABLE child(pid INT, FOREIGN KEY (pid) REFERENCES parent(id));
INSERT INTO parent VALUES (1);
INSERT INTO child VALUES (1);

TRUNCATE TABLE parent;
-- ERROR 1701 (42000): Cannot truncate a table referenced
```

绕过方法：

```sql
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE parent;
SET FOREIGN_KEY_CHECKS = 1;
```

这在线上极危险——会留下 child 指向不存在 parent 的孤儿行。

### TiDB：分布式 TRUNCATE

TiDB 的 `TRUNCATE` 极其快速，原理：

1. 在 schema 中把表 `t` 的 `tableID` 替换为新的；
2. 旧的 `tableID` 进入 `gc_queue`，由 GC worker 异步回收；
3. 新 `tableID` 上没有任何 region，立即可用。

这与 CockroachDB 类似——都是"改名+重建"的虚拟 DDL。代价：

- 在极短时间内，schema 需要刷新到所有 TiDB 节点，期间并发事务可能遇到 schema 过旧错误。
- GC 前旧数据仍占存储。
- 自增 ID 从 `AUTO_INCREMENT_OFFSET`（通常 1）重启。

### OceanBase：双兼容模式

OceanBase 同时支持 MySQL 和 Oracle 语法模式：

- MySQL 模式：`TRUNCATE TABLE t`，行为贴近 MySQL（隐式 DDL，不可回滚，AUTO_INCREMENT 重置）。
- Oracle 模式：支持 `TRUNCATE ... [REUSE|DROP] STORAGE` 与 `CASCADE`，行为贴近 Oracle DDL。

分布式层面类似 TiDB，通过 partition 重分配实现 O(1)。

### ClickHouse：复制协调

```sql
-- 本地表
TRUNCATE TABLE events;

-- 分布式/复制表
TRUNCATE TABLE events ON CLUSTER my_cluster;
```

对于 `ReplicatedMergeTree`：

- 通过 ZooKeeper/Keeper 创建 `DROP_RANGE` 条目。
- 所有副本按顺序应用，保证一致性。
- 对旧 parts 标记删除，后台 merger 执行真正回收。

非 Replicated 引擎：直接删除本地 part 目录。

ClickHouse 不支持事务型 TRUNCATE，无 ROLLBACK。

### Snowflake：Time Travel 保护

```sql
TRUNCATE TABLE orders;
-- 立即之后
SELECT COUNT(*) FROM orders;  -- 0

-- Time Travel 恢复
SELECT COUNT(*) FROM orders AT (OFFSET => -60);  -- 1 分钟前的行数
INSERT INTO orders
  SELECT * FROM orders AT (OFFSET => -60);  -- 恢复数据
```

- `TRUNCATE` 清空表的**活跃版本**，micropartitions 并未物理删除。
- Time Travel（最长 90 天）仍可访问截断前的数据。
- Sequence / AUTO_INCREMENT 列不重置（Snowflake 的 sequence 是独立对象）。
- 不影响表属性、grants、约束。
- 清空是即时可见的，但不是立即可回收存储——存储仍按历史计费直到 Fail-safe 窗口结束。

### BigQuery：2022 年才支持

```sql
TRUNCATE TABLE mydataset.orders;
```

- 2022 年以前，需要 `CREATE OR REPLACE TABLE` 或 `DELETE FROM t WHERE TRUE`。
- TRUNCATE 被视为 DDL，**不计入查询字节费用**。
- 清空所有分区；不能指定单分区（单分区要用 `DELETE FROM t WHERE _PARTITIONDATE = '...'`）。
- 清空后 schema、约束、分区模板保留。

### Redshift / Greenplum / YugabyteDB：PG 血统

均继承 PG 的 `TRUNCATE` 语义：事务内、支持 `CASCADE`、`RESTART IDENTITY`、`TRUNCATE` 权限独立。

Redshift 特殊：

- 清空后立即对所有会话可见（与 PG 不同，PG 要等事务提交）。
- 不触发自动 VACUUM，表元数据中的行数被重置。

YugabyteDB：

- 分布式实现，底层通过重建 tablet 完成。
- 事务支持完全继承 PG 语法。

### CockroachDB：SQL 层 DROP + CREATE

```sql
TRUNCATE TABLE orders RESTART IDENTITY CASCADE;
```

内部实现：SQL 层执行 `DROP TABLE` + `CREATE TABLE` 并保留表 ID 的引用关系。这使 TRUNCATE 不是原子事务的一部分——事务中的 DML 与 TRUNCATE 混合会有可见性陷阱。

### Databricks / Delta Lake

```sql
TRUNCATE TABLE orders;
```

- Delta 表：创建新 commit，metadata 中标记所有历史 parquet 为 removed。
- 通过 `VERSION AS OF` 可恢复：`RESTORE TABLE orders TO VERSION AS OF 5`。
- `VACUUM` 之后物理删除，默认保留 7 天。
- 不重置 Delta IDENTITY 列（与 SQL Server 相反）。
- 非 Delta 表（外部表、Parquet 表）：清空文件目录。

### Spark SQL：分区级 TRUNCATE

```sql
TRUNCATE TABLE events;
TRUNCATE TABLE events PARTITION (dt='2024-01-01');
```

- 原生 Spark 的 `TRUNCATE` 仅支持 managed 表。
- 分区语法可保留表结构清空单个分区。
- 非 ACID，并发写入者可能看到不一致。

### Hive：仅 managed 表

```sql
TRUNCATE TABLE events;
TRUNCATE TABLE events PARTITION (ds='2024-01-01', hr='10');
```

- External 表禁止 TRUNCATE。
- 内部实现：清空 HDFS 目录，保留元数据。
- 与 Spark 行为一致，非 ACID。

### Teradata：没有 TRUNCATE 关键字

```sql
DELETE FROM orders ALL;
```

Teradata 用 `DELETE ... ALL` 实现等价语义：

- `ALL` 关键字触发"fast path" DELETE，通过删除数据块（cylinder）实现 O(1)。
- 不记录单行日志（minimal logging）。
- 事务内可 ROLLBACK。
- 触发 DELETE 触发器取决于版本——默认跳过。

### DuckDB：单文件 MVCC

```sql
BEGIN;
TRUNCATE t;
ROLLBACK;  -- 有效
```

DuckDB 的 TRUNCATE 类似 PG：
- 事务 MVCC 完整。
- 单进程/嵌入式，无需锁协调。
- 0.10 之后支持 `RESTART IDENTITY`。

### Vertica：WOS/ROS 双区域

- `DELETE`：在 WOS（Write Optimized Store）中标记删除，最终 Tuple Mover 写入 ROS。
- `TRUNCATE`：直接清空 ROS 容器，WOS 也清除。
- 独立 TRUNCATE 权限。
- 默认重置 IDENTITY。

### Exasol：内存列存

- TRUNCATE 是 DDL，立即释放列 chunk。
- 事务内可回滚。
- 重置 IDENTITY。

### SAP HANA：内存表特殊

- `TRUNCATE TABLE` 是 DDL，auto-commit。
- Column Store 表：清空列存结构。
- Row Store 表：直接重置。
- IDENTITY 默认重置。

### HSQLDB / H2 / Derby：嵌入式 Java 引擎

- HSQLDB 是对 SQL:2008 语法最贴近的实现：`TRUNCATE TABLE t [CONTINUE|RESTART] IDENTITY [AND COMMIT|NO ACTION]`。
- H2：事务型，支持 `RESTART IDENTITY`。
- Derby 10.11+：支持 TRUNCATE，但仍需 `ALTER TABLE ... RESTART` 手动重置 IDENTITY。

### Firebird：不支持 TRUNCATE

Firebird 无 `TRUNCATE` 关键字，必须：

```sql
DELETE FROM orders;
-- 或者
RECREATE TABLE orders(...);
```

对大表，`RECREATE TABLE` 因可以借助备份 / 元数据恢复脚本实现近似 TRUNCATE 效果。

### Google Spanner：全局强一致的代价

Spanner 没有 TRUNCATE：

```sql
DELETE FROM orders WHERE true;
```

原因：Spanner 的 Paxos 全局时间戳承诺禁止"绕开数据路径"。即使 `DELETE ... WHERE TRUE`，优化器也将其分发到 split-level 批处理，相对较快，但仍是行级操作。

### Materialize / RisingWave：流语义

- Materialize：物化视图语义不允许清空源表状态。
- RisingWave：维护流增量，TRUNCATE 会破坏下游计算，因此禁用。

两者建议 `DROP SOURCE / DROP MATERIALIZED VIEW` + 重建。

### StarRocks / Doris：分区 TRUNCATE

```sql
TRUNCATE TABLE events;
TRUNCATE TABLE events PARTITION (p20240101, p20240102);
```

- 内部实现：更换 tablet ID（类似 TiDB/CRDB 的重命名式 TRUNCATE）。
- O(1) 性能，不受行数影响。
- 分区级是独特优势，适合时序数据归档。

### Impala：3.x+

```sql
TRUNCATE TABLE events;
TRUNCATE TABLE IF EXISTS events;
```

- 2.3 起原生支持。
- 内部对 HDFS 文件列表清空 + 元数据更新。
- 不支持事务；不支持分区级别 TRUNCATE（需 `ALTER TABLE ... DROP PARTITION`）。

### QuestDB：时序库

- TRUNCATE 直接释放 column file 映射。
- 非事务。
- 分区按目录组织，TRUNCATE 清空所有分区目录。

### CrateDB：不支持 TRUNCATE

```sql
DELETE FROM mytable;
OPTIMIZE TABLE mytable WITH (max_num_segments = 1);
```

需要 DELETE + OPTIMIZE（强制 Lucene merge）才能释放磁盘空间。

### InfluxDB（SQL 接口）：无 TRUNCATE

```sql
DROP MEASUREMENT orders;
CREATE MEASUREMENT orders(...);
```

InfluxDB 时序语义不直接支持 TRUNCATE；最接近的是 `DELETE FROM m WHERE time >= ... AND time < ...`。

## PostgreSQL TRUNCATE ... CASCADE 深度解析

`CASCADE` 是 PG 独有也是最"危险"的 TRUNCATE 修饰符。

考虑下列 schema：

```sql
CREATE TABLE orders(id SERIAL PRIMARY KEY, user_id INT);
CREATE TABLE order_items(id SERIAL PRIMARY KEY,
                         order_id INT REFERENCES orders(id),
                         sku TEXT);
CREATE TABLE shipments(id SERIAL PRIMARY KEY,
                       order_item_id INT REFERENCES order_items(id));

INSERT INTO orders(user_id) VALUES (1), (2);
INSERT INTO order_items(order_id, sku) VALUES (1, 'A'), (1, 'B');
INSERT INTO shipments(order_item_id) VALUES (1), (2);
```

执行：

```sql
TRUNCATE TABLE orders;
-- ERROR: cannot truncate a table referenced in a foreign key constraint
-- DETAIL: Table "order_items" references "orders".
-- HINT: Truncate table "order_items" at the same time, or use TRUNCATE ... CASCADE.
```

CASCADE 将**递归**清空所有下游：

```sql
TRUNCATE TABLE orders CASCADE;
-- NOTICE: truncate cascades to table "order_items"
-- NOTICE: truncate cascades to table "shipments"
```

注意事项：

1. **完全不看 FK 是否 ON DELETE CASCADE**——只要被引用就递归。这与 DELETE CASCADE 是两回事。
2. 可以结合 `RESTART IDENTITY`，所有涉及的 sequence 一并重置：
   ```sql
   TRUNCATE TABLE orders, users RESTART IDENTITY CASCADE;
   ```
3. CASCADE 会同时锁定**所有**被级联的表，死锁风险大。
4. 生产环境建议：先显式列出所有目标表，不依赖 CASCADE：
   ```sql
   TRUNCATE TABLE shipments, order_items, orders RESTART IDENTITY;
   ```

## 性能对比：TRUNCATE vs DELETE WHERE TRUE

以下数据基于 1 亿行的 `orders` 表（InnoDB，SSD）：

| 操作 | 耗时 | 产生 undo | 产生 binlog | 锁模式 |
|------|------|-----------|-------------|--------|
| `DELETE FROM orders` | ~35 分钟 | 40+ GB | 25+ GB | 行锁（多次升级） |
| `DELETE FROM orders WHERE id > 0 LIMIT 10000` 循环 | ~20 分钟 | 每次 ~100MB | 每次 ~80MB | 间歇行锁 |
| `TRUNCATE TABLE orders` | <1 秒 | 0 | 1 行 DDL | MDL exclusive |
| `DROP TABLE + CREATE TABLE` | <1 秒 | 0 | 2 行 DDL | MDL exclusive |

PostgreSQL 对照：

| 操作 | 耗时 | 产生 WAL | 磁盘回收 |
|------|------|---------|----------|
| `DELETE FROM orders` | ~40 分钟 | ~30 GB | 需 VACUUM FULL |
| `TRUNCATE TABLE orders` | <1 秒 | ~几 KB | 立即释放 |

结论：清空全表场景下，`TRUNCATE` 性能高出 3-4 个数量级，唯一代价是**不可以带 WHERE**。

## 常见坑

### 1. AUTO_INCREMENT 是否"连续"

MySQL `DELETE` 后下次 INSERT 仍从最大 ID + 1 开始；`TRUNCATE` 后从 1 开始。这在审计 / 关联关系中可能引入数据污染：

```sql
DELETE FROM orders;
INSERT INTO orders(...) VALUES (...);  -- id = 1000001（大 ID）

TRUNCATE TABLE orders;
INSERT INTO orders(...) VALUES (...);  -- id = 1
-- 如果其他系统以 id 做 join key，后果严重
```

### 2. 外键引用陷阱

```sql
-- MySQL
SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE parent;
SET FOREIGN_KEY_CHECKS=1;
-- child 中出现孤儿行
```

务必先 `TRUNCATE child` 再 `TRUNCATE parent`（或 PG 的 `CASCADE`）。

### 3. 触发器审计缺失

```sql
CREATE TRIGGER trg_del AFTER DELETE ON orders FOR EACH ROW ...;

DELETE FROM orders;   -- 触发器执行，写审计日志
TRUNCATE TABLE orders; -- 触发器跳过！无任何审计
```

在 PG 中补救：

```sql
CREATE TRIGGER trg_truncate AFTER TRUNCATE ON orders
  FOR EACH STATEMENT EXECUTE FUNCTION log_truncate();
```

其他引擎：在应用层或审计框架（如 DB2 `RESTRICT WHEN DELETE TRIGGERS`）前置拦截。

### 4. 事务混用

```sql
-- PostgreSQL OK
BEGIN;
INSERT INTO log VALUES ('about to truncate');
TRUNCATE orders;
ROLLBACK;
-- log 回滚，orders 回滚

-- MySQL 错误预期
BEGIN;
INSERT INTO log VALUES ('about to truncate');  -- 已提交！
TRUNCATE orders;   -- 隐式提交触发
ROLLBACK;
-- log 依然存在，orders 被截断
```

MySQL DBA 必须内化：**DDL 前的事务已隐式提交**。

### 5. 复制延迟

`TRUNCATE` 在主库 O(1)，但从库需要同样时间。不过若从库有读流量，从库的 TRUNCATE 会阻塞查询，且 MDL 等待可能引发从库崩溃。建议：

- 维护窗口执行，或
- 使用 `pt-online-schema-change` 一类的工具清空（对极大表）。

### 6. 跨引擎迁移陷阱

从 Oracle 迁到 PG 的 SQL 代码：

```sql
TRUNCATE TABLE orders;
```

在 Oracle 中自动提交 = 应用不会对此事务负责；在 PG 中被包在事务里 ROLLBACK 则完全回退。业务逻辑若假设 "TRUNCATE 一定生效"，在 PG 上可能导致数据重现。

## 替代方案

### 1. DROP + CREATE

```sql
DROP TABLE orders;
CREATE TABLE orders(...);
```

- 优点：跨所有引擎可用。
- 缺点：失去 grants、注释、索引定义等需要脚本化维护。

### 2. DELETE + VACUUM/OPTIMIZE

```sql
DELETE FROM t;
VACUUM FULL t;   -- PostgreSQL
OPTIMIZE TABLE t;  -- MySQL / MariaDB
```

- 保留触发器/权限/约束行为。
- 代价：磁盘 I/O + 长锁。

### 3. 分区交换

```sql
-- Oracle
ALTER TABLE orders EXCHANGE PARTITION p_2024_01
   WITH TABLE orders_empty;  -- 瞬时清空旧分区

-- MySQL
ALTER TABLE orders TRUNCATE PARTITION p_2024_01;

-- PostgreSQL
ALTER TABLE orders DETACH PARTITION orders_2024_01;
DROP TABLE orders_2024_01;
```

时序场景下最优解：清空单个分区不影响其他分区并发访问。

### 4. 重建表（MySQL pt-osc）

```bash
pt-online-schema-change --alter 'ENGINE=InnoDB' t=orders,D=mydb --execute
```

通过触发器双写 + 切换，对业务零感知清空。

### 5. 物化视图重建

```sql
-- Materialize/RisingWave
DROP MATERIALIZED VIEW mv_orders;
CREATE MATERIALIZED VIEW mv_orders AS ...;
```

流处理语境下 TRUNCATE 被 "物化视图重建" 替代。

## 设计启示

### 为什么几乎所有引擎都不触发 DELETE 触发器

触发器是"面向行"的副作用合约。`TRUNCATE` 被设计为"集合级"操作——引擎不打算逐行处理。若强制触发 DELETE 触发器：

1. O(1) 性能特性丧失。
2. BEFORE DELETE 触发器可能阻止部分行删除，破坏"全部或没有"语义。
3. 许多触发器是"审计"或"级联维护"——前者 PG 用 `AFTER TRUNCATE` 触发器解决，后者用 `CASCADE` 解决。

### 为什么 Oracle 坚持 DDL auto-commit

Oracle 历史上将所有 DDL 视为"schema 变更"，必须独立原子。这源于 Oracle 对 data dictionary 的严格锁定设计——任何 DDL 都需要递归调用其他 DDL（分配 segment、更新 SYSAUX 等），事务嵌套过于复杂。

PG/SQL Server 选择相反的路径：DDL 也纳入 MVCC / WAL。代价是实现复杂（PG 的 "relfilenode 双指针" 是为此发明的）。

### 为什么 MySQL 的 TRUNCATE 不可回滚

InnoDB 重设表 ibd 文件需要物理层面的原子替换，InnoDB redo 无法表示"撤销 ibd 文件替换"。作为妥协，选择隐式提交。

### 为什么 PostgreSQL 的 TRUNCATE 需要 ACCESS EXCLUSIVE

虽然 PG 的 MVCC 在行级别非常松散，但 `TRUNCATE` 替换整个 relfilenode。任何正在扫描该 relation 的事务（即使只读）都会突然读到新的空文件，导致不一致。因此必须阻塞所有访问，换取事务完整性。

### SQL:2008 的缺席代价

SQL:2008 最终标准化 TRUNCATE，但只规定了最基本的语法骨架——未涵盖：

- 事务行为
- 触发器行为
- 外键交互
- 权限模型

这为各厂商留出"创新"空间，也留下"不可移植"的恶果。任何跨方言 SQL 生成器（如 Hibernate、Prisma、jOOQ）都必须为 TRUNCATE 写不同的代码路径。

## 选型建议

| 场景 | 推荐做法 |
|------|---------|
| 清空整表 + 保留 schema | TRUNCATE |
| 清空部分行 | DELETE WHERE |
| 需要审计删除行 | DELETE（或 PG `AFTER TRUNCATE` 触发器） |
| 清空后立刻大量 INSERT | TRUNCATE（Oracle：REUSE STORAGE） |
| 归档时序数据 | 分区 TRUNCATE / DETACH |
| 外键引用表 | PG：CASCADE；MySQL：先断 child；Oracle：12c+ CASCADE |
| 事务中需要可回滚 | PG/SQL Server/DB2 的 TRUNCATE；其他引擎选 DELETE |
| 云数据仓库（Snowflake/BQ/Redshift） | TRUNCATE（Time Travel 作为 safety net） |
| 流式引擎（Flink/Materialize） | DROP + RECREATE 物化视图 |
| 跨方言迁移 | 用 DROP + CREATE 替换，最保险 |

## 关键结论

1. **SQL:2008 姗姗来迟**：TRUNCATE 在标准化前就已在所有主流商业数据库存在多年，标准只覆盖基础语法，事务、触发器、外键语义均由实现决定，跨方言不可移植。
2. **事务性是分水岭**：PostgreSQL / SQL Server / DB2 / DuckDB 允许 ROLLBACK；Oracle / MySQL / ClickHouse 等隐式提交。这是最大的语义陷阱。
3. **触发器几乎普遍绕过**：设计上 TRUNCATE 是集合级操作，PG 独创的 `AFTER TRUNCATE` 是唯一补救方案。
4. **自增列处理分三派**：PG/HSQLDB/DB2 要求显式 `RESTART/CONTINUE`；MySQL/SQL Server/TiDB 默认重置；Snowflake/Delta 默认保留。
5. **外键处理分裂**：MySQL/SQL Server/DB2 直接禁止，PG/Redshift 支持 `CASCADE`，Oracle 12c+ 有条件支持。
6. **日志开销差距巨大**：TRUNCATE 只记录页/区/段释放，DELETE 记录行级；这是 TRUNCATE 性能的根本来源。
7. **分布式引擎 O(1)**：TiDB / OceanBase / CockroachDB / StarRocks / Doris 通过"改表 ID"实现即时 TRUNCATE，这是分布式 SQL 的显著优势。
8. **云数仓的 safety net**：Snowflake Time Travel / Delta Time Travel / BigQuery 快照 让 TRUNCATE 不再是"不可逆"操作。
9. **流处理引擎拒绝 TRUNCATE**：Materialize / RisingWave / Flink（早期）因违背流语义而不提供，被动接受 `DROP + CREATE`。
10. **SQLite 的 TRUNCATE 优化是隐式的**：应用层看是 `DELETE`，引擎层走 DDL 路径，是嵌入式数据库的聪明折衷。
11. **TRUNCATE 的权限应独立**：PG 8.4+ 的做法值得借鉴，避免"低权限用户通过 DELETE 清空表"风险。
12. **跨方言 SQL 最好避免依赖 TRUNCATE 语义**：事务行为、触发器行为、外键处理差异太大，ORM 层应提供抽象或改用 DELETE + 优化。

TRUNCATE 看起来只是一条清空语句，却是 SQL 引擎设计中横跨 DDL/DML、事务/自动提交、日志/持久化、锁/并发、外键/触发器的"小型试金石"。读懂 TRUNCATE，就读懂了一个 SQL 引擎的灵魂。
