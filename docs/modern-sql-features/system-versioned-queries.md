# 系统版本控制查询 / 时间旅行 (System-Versioned Queries and Time Travel)

"昨天下午 3 点那张订单表长什么样？" —— 这个看似简单的问题，在绝大多数生产系统里都是一场噩梦。备份恢复需要数小时，binlog 重放需要复杂脚本，而现代 SQL 的回答只有一行：`SELECT * FROM orders FOR SYSTEM_TIME AS OF '2026-04-14 15:00:00'`。时间旅行查询（Time Travel Query）让数据库变成一台可读的时光机，是审计、调试、事故恢复与合规留存的终极利器。

## 为什么需要时间旅行查询

在只能看见"当前状态"的数据库中，以下场景都异常痛苦：

1. **审计与合规**：SOX、GDPR、HIPAA 等法规要求追溯任意历史时刻的数据快照。使用 trigger + history 表的传统方案复杂、易错且拖慢主库。
2. **线上事故恢复**：用户误执行 `DELETE FROM users WHERE id < 1000000`，没有时间旅行只能从最近备份恢复到另一个实例再对比回填；有时间旅行只需 `INSERT INTO users SELECT * FROM users FOR SYSTEM_TIME AS OF (NOW() - INTERVAL '10 MINUTE') WHERE id < 1000000`。
3. **业务分析与 BI 一致性**：长事务跨 ETL 任务访问同一张维度表，需要所有查询看到同一时刻的快照，避免"月初跑出来的数字和月末对不上"。
4. **调试与复现**：生产 bug 复现需要的不是"现在"的数据，而是"当时"的数据。时间旅行让开发者可以把测试环境定格到事故发生的那一瞬间。
5. **历史回归测试**：机器学习特征工程、风险模型回测都需要严格的"point-in-time correctness"，任何未来泄漏都会让回测结果失真。
6. **非阻塞读取**：`AS OF SYSTEM TIME` 可以读取"几秒前"的快照，跳过活跃事务的锁等待，CockroachDB、Spanner 等分布式数据库把它作为 follower read / stale read 的关键入口。

时间旅行查询与本站另一篇文章 [时态表 (Temporal Tables)](./temporal-tables.md) 互为补充：后者负责"如何声明一张系统版本控制表"（schema DDL），本文聚焦"如何查询一张已有的系统版本控制表"（DML 的 AS OF 子句）。

## SQL:2011 标准定义

SQL:2011（ISO/IEC 9075-2:2011）首次在标准中正式引入时态表（Temporal Tables）与时间旅行查询。对于系统版本控制表，标准在 Section 7.6 `<table reference>` 中定义了以下语法：

```sql
<table_reference> ::=
    <table_name> FOR SYSTEM_TIME <system time period specification>

<system time period specification> ::=
      AS OF <datetime value expression>
    | BETWEEN [ ASYMMETRIC | SYMMETRIC ] <datetime value expression>
          AND <datetime value expression>
    | FROM <datetime value expression> TO <datetime value expression>
    | CONTAINED IN ( <datetime value expression>, <datetime value expression> )
    | ALL
```

标准的关键语义：

1. **AS OF ts**：返回在时刻 ts 有效的那一行版本，即 `SYS_START <= ts < SYS_END` 的所有行。
2. **BETWEEN a AND b**（闭区间）：返回所有行版本，其有效区间与 `[a, b]` 有交集，即 `SYS_START <= b AND SYS_END > a`。
3. **FROM a TO b**（半开区间 `[a, b)`）：返回所有行版本，其有效区间与 `[a, b)` 有交集，即 `SYS_START < b AND SYS_END > a`。
4. **CONTAINED IN (a, b)**：只返回那些完全包含在 `[a, b)` 内的行版本，即 `SYS_START >= a AND SYS_END <= b`。
5. **ALL**：返回所有历史版本，等价于不对时间加约束。
6. **不指定 FOR SYSTEM_TIME**：默认只看"当前行"（current rows），即 `SYS_END = 'infinity'` 的行。

标准不规定如何物理存储历史版本，也不规定历史数据的保留期——这些都由引擎自行实现。

## 支持矩阵（综合）

### FOR SYSTEM_TIME AS OF / BETWEEN / FROM / CONTAINED IN 原生支持

| 引擎 | AS OF | BETWEEN | FROM...TO | CONTAINED IN | 版本 | 备注 |
|------|-------|---------|-----------|--------------|------|------|
| PostgreSQL | -- | -- | -- | -- | -- | 无原生；扩展 temporal_tables |
| MySQL | -- | -- | -- | -- | -- | 无 |
| MariaDB | 是 | 是 | 是 | 是 | 10.3+ (2018) | 完整 SQL:2011 语法 |
| SQLite | -- | -- | -- | -- | -- | 无 |
| Oracle | AS OF TIMESTAMP | 无 | VERSIONS BETWEEN | 无 | 9i R2 (2003) | Flashback Query，非标准 |
| SQL Server | 是 | 是 | 是 | 是 | 2016+ | 完整 SQL:2011 语法 |
| DB2 (LUW/z) | 是 | 是 | 是 | 无 | 10.1 (2012) | 系统时间 + 业务时间 |
| Snowflake | `AT`/`BEFORE` | -- | -- | -- | GA | 非标准 Time Travel 语法 |
| BigQuery | 是 | -- | -- | -- | 2020+ | 7 天窗口 |
| Redshift | -- | -- | -- | -- | -- | 无；依赖快照 |
| DuckDB | -- | -- | -- | -- | -- | 无（读 Iceberg/Delta 时支持） |
| ClickHouse | -- | -- | -- | -- | -- | 无；靠 ReplacingMergeTree 手动模拟 |
| Trino | `FOR VERSION/TIMESTAMP AS OF` | -- | -- | -- | 398+ | 仅对连接器（Iceberg/Delta/Hudi）生效 |
| Presto | 类似 Trino | -- | -- | -- | 0.280+ | 连接器级 |
| Spark SQL | `VERSION/TIMESTAMP AS OF` | -- | -- | -- | 3.3+ | Delta/Iceberg/Hudi |
| Hive | -- | -- | -- | -- | -- | 无（Iceberg 表通过 Hive SQL 支持） |
| Flink SQL | `FOR SYSTEM_TIME AS OF` | -- | -- | -- | 1.9+ | 语义不同：时态 JOIN，非历史查询 |
| Databricks | `VERSION/TIMESTAMP AS OF` | -- | -- | -- | Delta 0.7+ | 基于 Delta Lake |
| Teradata | -- | -- | -- | -- | -- | 有 Temporal 选项但不普及 |
| Greenplum | -- | -- | -- | -- | -- | 继承 PostgreSQL |
| CockroachDB | `AS OF SYSTEM TIME` | -- | -- | -- | 1.1+ (2017) | 全局，非仅表级 |
| TiDB | `AS OF TIMESTAMP` | -- | -- | -- | 5.0+ (2021) | Stale Read |
| OceanBase | `AS OF SCN / TIMESTAMP` | 无 | VERSIONS BETWEEN | 无 | 2.2+ | 兼容 Oracle Flashback |
| YugabyteDB | -- | -- | -- | -- | -- | 无（内部 MVCC 但未暴露语法） |
| SingleStore | -- | -- | -- | -- | -- | 无 |
| Vertica | -- | -- | -- | -- | -- | `AT EPOCH`/`AT TIME` 是 epoch 快照，非 SQL:2011 |
| Impala | -- | -- | -- | -- | -- | 仅 Iceberg 表：`FOR SYSTEM_TIME/VERSION AS OF` |
| StarRocks | -- | -- | -- | -- | -- | 仅 Iceberg/Paimon 外表 |
| Doris | -- | -- | -- | -- | -- | 仅 Iceberg/Hudi 外表 |
| MonetDB | -- | -- | -- | -- | -- | 无 |
| CrateDB | -- | -- | -- | -- | -- | 无 |
| TimescaleDB | -- | -- | -- | -- | -- | 无；推荐 continuous aggregate |
| QuestDB | -- | -- | -- | -- | -- | 无 |
| Exasol | -- | -- | -- | -- | -- | 无 |
| SAP HANA | -- | -- | -- | -- | -- | 有 `AS OF COMMIT_ID` 但非 SQL:2011 |
| Informix | -- | -- | -- | -- | -- | 无 |
| Firebird | -- | -- | -- | -- | -- | 无 |
| H2 | -- | -- | -- | -- | -- | 无 |
| HSQLDB | 是 | 是 | 是 | 是 | 2.3+ | 语法符合 SQL:2011，但无自动历史表 |
| Derby | -- | -- | -- | -- | -- | 无 |
| Amazon Athena | -- | -- | -- | -- | -- | 仅 Iceberg 表 |
| Azure Synapse | 是 | 是 | 是 | 是 | 2022+ | SQL Server 语法子集，仅专用池 |
| Google Spanner | -- | -- | -- | -- | -- | 通过 Stale Read（`timestamp_bound`）实现 |
| Materialize | -- | -- | -- | -- | -- | 无 |
| RisingWave | -- | -- | -- | -- | -- | 无 |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | 无（时序数据库原生保留历史） |
| DatabendDB | `AT` | -- | -- | -- | GA | Snowflake 风格 |
| Yellowbrick | -- | -- | -- | -- | -- | 无 |
| Firebolt | -- | -- | -- | -- | -- | 无 |

> 统计：约 14 个引擎具备某种原生时间旅行语法；约 5 个通过 Iceberg/Delta/Hudi 连接器获得；其余 26 个引擎完全不支持或需要外部扩展/备份方案。

### Oracle 风格 AS OF TIMESTAMP / AS OF SCN (Flashback Query)

| 引擎 | AS OF TIMESTAMP | AS OF SCN | VERSIONS BETWEEN | 最大回溯窗口 | 版本 |
|------|----------------|-----------|------------------|-------------|------|
| Oracle | 是 | 是 | 是 | 依赖 `UNDO_RETENTION`（默认 900s） | 9i R2 (2003) |
| OceanBase | 是 | 是 | 是 | 依赖 `undo_retention` | 2.2+ |
| PostgreSQL | -- | -- | -- | -- | -- |
| SQL Server | -- | -- | -- | -- | -- |
| MariaDB | -- | -- | -- | -- | -- |
| DB2 | -- | -- | -- | -- | -- |
| Snowflake | 代以 `AT(TIMESTAMP)` | -- | -- | 1–90 天 | GA |
| TiDB | 类 Oracle 的 `AS OF TIMESTAMP` | -- | -- | `tidb_gc_life_time`（默认 10m） | 5.0+ |
| CockroachDB | 类 SCN 的 HLC 时间戳 | -- | -- | 默认 25h（`gc.ttlseconds`） | 1.1+ |

### 命名 savepoint / 版本号查询

| 引擎 | 语法 | 说明 |
|------|------|------|
| Snowflake | `AT(STATEMENT => '<query_id>')` | 按前序语句 ID 回退 |
| Snowflake | `BEFORE(STATEMENT => '<query_id>')` | 回到该语句执行前一刻 |
| Snowflake | `AT(OFFSET => -60*5)` | 5 分钟前的快照 |
| Delta Lake | `VERSION AS OF 12` | 按 commit version 号 |
| Iceberg | `FOR SYSTEM_VERSION AS OF 314159` | 按 snapshot-id |
| Iceberg | `FOR SYSTEM_VERSION AS OF 'branch_main'` | 按命名分支/标签 |
| Hudi | `TIMESTAMP AS OF '20250101010101'` | 按 commit 时间戳 |
| BigQuery | `FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(...)` | 无 snapshot-id 概念 |
| Oracle | `AS OF SCN 14235678` | SCN (System Change Number) |
| OceanBase | `AS OF SCN 14235678` | 兼容 Oracle |

### 历史数据保留期与时间粒度

| 引擎 | 默认保留期 | 最大保留期 | 配置项 | 时间粒度 |
|------|-----------|-----------|--------|---------|
| Oracle | 900 秒 | 由 UNDO tablespace 大小限制 | `UNDO_RETENTION` | 毫秒 |
| SQL Server | 无限 | 无限 | 表级 `HISTORY_RETENTION_PERIOD` | 100ns（datetime2(7)） |
| MariaDB | 无限 | 无限 | `SYSTEM_VERSIONING_ASOF` + 分区清理 | 微秒 |
| DB2 | 无限 | 无限 | 历史表独立管理 | 微秒 |
| Snowflake | 1 天（Standard） | 90 天（Enterprise+） | `DATA_RETENTION_TIME_IN_DAYS` | 毫秒 |
| BigQuery | 7 天（固定 2020–2022） | 7 天（2–7 天可配置，2022+） | `max_time_travel_hours` | 毫秒 |
| CockroachDB | 25 小时 | 无限（但影响存储） | `gc.ttlseconds` | 纳秒 HLC |
| TiDB | 10 分钟 | 由 `tidb_gc_life_time` 限制 | `tidb_gc_life_time` | 毫秒 |
| OceanBase | 1800 秒 | 由 undo 大小限制 | `undo_retention` | 微秒 |
| Delta Lake | 30 天（日志）+ 7 天（数据） | 由 `VACUUM` 控制 | `logRetentionDuration` | 毫秒 |
| Iceberg | 无限（直到 `expire_snapshots`） | 无限 | `history.expire.max-snapshot-age-ms` | 毫秒 |
| Azure Synapse | 7 天 | 7 天 | `HISTORY_RETENTION_PERIOD` | 100ns |
| Spanner | 1 小时 | 7 天 | `version_retention_period` | 微秒 |

## SQL:2011 标准语法深入解析

### AS OF：点时刻查询

```sql
-- 返回 2026-01-01 12:00 当时 employees 表的状态
SELECT * FROM employees
    FOR SYSTEM_TIME AS OF TIMESTAMP '2026-01-01 12:00:00';

-- 等价语义：
SELECT * FROM employees_history
WHERE  sys_start <= TIMESTAMP '2026-01-01 12:00:00'
  AND  sys_end   >  TIMESTAMP '2026-01-01 12:00:00';
```

关键要点：
- 时间点是**闭-开**区间：`sys_start <= t < sys_end`，保证在同一时间点不会返回两个版本。
- 表必须是 SQL:2011 系统版本控制表（system-versioned），即 DDL 中声明了 `PERIOD FOR SYSTEM_TIME (sys_start, sys_end) WITH SYSTEM VERSIONING`。
- 当 t 早于最早的 `sys_start`，结果为空（不是错误）。
- 当 t 指向未来，返回当前行（等价于 `sys_end = 'infinity'` 的行）。

### BETWEEN：时间区间内的所有版本

```sql
SELECT emp_id, salary, sys_start, sys_end
FROM   employees
       FOR SYSTEM_TIME BETWEEN TIMESTAMP '2026-01-01' AND TIMESTAMP '2026-04-01';
```

返回所有在 `[2026-01-01, 2026-04-01]` 闭区间内曾经存在过的行版本，即 `sys_start <= '2026-04-01' AND sys_end > '2026-01-01'`。可用于"这段时间某员工薪资变过几次？"这类问题。

注意：BETWEEN 产生的是"版本切片"，同一个逻辑行可能在结果中出现多次（每次变更一条）。如果你只想要"区间开始时"和"区间结束时"两个快照做 diff，应使用两次 `AS OF` 查询再 `FULL OUTER JOIN`。

### FROM ... TO：半开区间

```sql
SELECT * FROM employees
    FOR SYSTEM_TIME FROM TIMESTAMP '2026-01-01' TO TIMESTAMP '2026-04-01';
```

与 BETWEEN 的唯一区别：`FROM..TO` 是**半开区间** `[start, end)`，而 BETWEEN 是**闭区间** `[start, end]`。在需要把一年切成 12 个不重叠月片的场景（审计、计费），FROM..TO 更安全：相邻两个月没有重叠的 boundary 行。

### CONTAINED IN：完全包含语义

```sql
SELECT * FROM employees
    FOR SYSTEM_TIME CONTAINED IN (
        TIMESTAMP '2026-01-01', TIMESTAMP '2026-04-01');
```

只返回那些 `[sys_start, sys_end)` 完全位于 `[2026-01-01, 2026-04-01)` 内部的行版本。语义是"在这个窗口内生成并消亡的短命版本"，常用于排查"这个 bug 只影响了某段时间内产生又被覆盖的数据"。跨越窗口边界的行会被排除。

### ALL：所有历史版本

```sql
SELECT * FROM employees FOR SYSTEM_TIME ALL;
```

等同于不对 SYSTEM_TIME 施加任何过滤——既包括当前行也包括所有历史行，返回的是整张历史表 + 当前表的并集。对审计查询和全量重建派生表（物化视图、搜索索引）特别有用。

## 各引擎语法详解

### SQL Server：SQL:2011 的最完整实现之一

SQL Server 2016 引入 system-versioned temporal tables，随后 Azure SQL、Azure SQL Managed Instance、Azure Synapse（2022 起）也获得同样支持。

```sql
-- 1. 定义系统版本控制表
CREATE TABLE dbo.Employee (
    EmpID       INT PRIMARY KEY,
    Name        NVARCHAR(100),
    Salary      DECIMAL(10,2),
    SysStart    DATETIME2(7) GENERATED ALWAYS AS ROW START NOT NULL,
    SysEnd      DATETIME2(7) GENERATED ALWAYS AS ROW END   NOT NULL,
    PERIOD FOR SYSTEM_TIME (SysStart, SysEnd)
) WITH (SYSTEM_VERSIONING = ON (
    HISTORY_TABLE = dbo.EmployeeHistory,
    HISTORY_RETENTION_PERIOD = 5 YEARS));

-- 2. 查询过去某一时刻
SELECT * FROM dbo.Employee
    FOR SYSTEM_TIME AS OF '2026-01-01 12:00:00';

-- 3. 查询某段时间内所有历史版本
SELECT EmpID, Name, Salary, SysStart, SysEnd
FROM dbo.Employee
    FOR SYSTEM_TIME BETWEEN '2026-01-01' AND '2026-03-31'
ORDER BY EmpID, SysStart;

-- 4. 差集对比：昨天的快照与今天的差异
SELECT c.EmpID, c.Salary AS today_salary, h.Salary AS yesterday_salary
FROM   dbo.Employee c
LEFT JOIN dbo.Employee FOR SYSTEM_TIME AS OF DATEADD(DAY, -1, SYSUTCDATETIME()) h
       ON c.EmpID = h.EmpID
WHERE  c.Salary <> h.Salary OR h.EmpID IS NULL;

-- 5. 在事务中回滚误 UPDATE
BEGIN TRANSACTION;
    MERGE dbo.Employee AS tgt
    USING (SELECT * FROM dbo.Employee
           FOR SYSTEM_TIME AS OF '2026-04-14 14:59:00') AS src
    ON  tgt.EmpID = src.EmpID
    WHEN MATCHED THEN UPDATE SET
         tgt.Name = src.Name, tgt.Salary = src.Salary;
COMMIT;
```

关键特性：
- **时间精度**：`datetime2(7)` 即 100ns。
- **历史表**：可以是系统管理或用户指定的普通表，可加索引、压缩、分区。
- **HISTORY_RETENTION_PERIOD**：自动后台清理超期行，无需手动维护。
- **FOR SYSTEM_TIME AS OF 不支持未来时间**：传入未来时间戳会返回当前行。
- **约束**：系统版本控制表不能有 INSTEAD OF trigger、不能截断（先关闭 SYSTEM_VERSIONING）。

### Oracle：Flashback Query（SQL:2011 之前就存在的先驱）

Oracle 9i Release 2（2003 年）首次引入 Flashback Query，比 SQL:2011 标准早 8 年，语法不遵循标准，但影响了后来几乎所有"时间旅行"实现。

```sql
-- 1. AS OF TIMESTAMP：按 wall-clock 时间
SELECT * FROM employees AS OF TIMESTAMP
    TO_TIMESTAMP('2026-01-01 12:00:00', 'YYYY-MM-DD HH24:MI:SS');

-- 2. AS OF SCN：按系统变更号（精确）
SELECT * FROM employees AS OF SCN 14235678;

-- 3. 最近 5 分钟的历史版本
SELECT * FROM employees AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '5' MINUTE);

-- 4. VERSIONS BETWEEN：Flashback Version Query
SELECT versions_xid, versions_starttime, versions_endtime,
       versions_operation, emp_id, salary
FROM   employees
       VERSIONS BETWEEN TIMESTAMP SYSTIMESTAMP - INTERVAL '1' HOUR AND SYSTIMESTAMP
WHERE  emp_id = 100;

-- 5. 恢复误删的行
INSERT INTO employees
SELECT * FROM employees AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '10' MINUTE)
WHERE  emp_id NOT IN (SELECT emp_id FROM employees);

-- 6. 取当前 SCN（作为 savepoint）
SELECT current_scn FROM v$database;
```

Flashback Query 的关键事实：

- **存储**：基于 undo tablespace，不需要历史表。undo 被回收后，对应时刻的 Flashback 会报 `ORA-01555: snapshot too old`。
- **UNDO_RETENTION**：默认 900 秒。生产系统通常设置为几小时到几天，与 undo 表空间大小正相关。
- **SCN**：System Change Number，单调递增的 64-bit 整数，比 wall-clock 时间更精确（时间戳与 SCN 的映射由 `smon_scn_time` 维护，粒度 3 秒）。
- **Flashback Query ≠ Flashback Table**：前者是**只读**查询语句（`SELECT ... AS OF`），后者是**DDL**（`FLASHBACK TABLE t TO TIMESTAMP ...`），会直接把整张表回滚到历史状态，需要 `ROW MOVEMENT` 权限。
- **Flashback Version Query**：`VERSIONS BETWEEN` 返回伪列 `VERSIONS_XID / VERSIONS_STARTSCN / VERSIONS_ENDSCN / VERSIONS_OPERATION`，是审计变更的核心工具。
- **Flashback Data Archive**：Oracle 11g+ 的 Total Recall 特性，把历史数据从 undo 迁移到独立归档，提供无限保留期，语法仍是 `AS OF TIMESTAMP`。

### PostgreSQL：无原生支持，三种替代方案

PostgreSQL 是主流开源关系库中时间旅行支持最弱的。原因：PostgreSQL 的 MVCC 依赖 VACUUM 回收死元组，一旦 vacuum 执行就再也回不去——没有 undo log，没有长期保留的旧版本。

可用的替代方案：

```sql
-- 方案 A：temporal_tables 扩展（最接近 SQL:2011）
CREATE EXTENSION temporal_tables;

CREATE TABLE employees (
    emp_id      INT PRIMARY KEY,
    name        TEXT,
    salary      NUMERIC,
    sys_period  TSTZRANGE NOT NULL);

CREATE TABLE employees_history (LIKE employees);

CREATE TRIGGER employees_versioning
    BEFORE INSERT OR UPDATE OR DELETE ON employees
    FOR EACH ROW EXECUTE PROCEDURE
    versioning('sys_period', 'employees_history', true);

-- 查询历史
SELECT * FROM employees_history
WHERE  sys_period @> TIMESTAMPTZ '2026-01-01 12:00:00'
UNION ALL
SELECT emp_id, name, salary, sys_period FROM employees
WHERE  sys_period @> TIMESTAMPTZ '2026-01-01 12:00:00';

-- 方案 B：PITR（point-in-time recovery）+ 临时实例
-- 只能恢复整库到另一台机器，粒度是时间点，不能 JOIN 当前库

-- 方案 C：逻辑复制 + 历史表 trigger（手动实现）
CREATE TABLE employees_audit (
    emp_id INT, name TEXT, salary NUMERIC,
    changed_at TIMESTAMPTZ, op CHAR(1));

CREATE FUNCTION audit_employees() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO employees_audit VALUES
        (OLD.emp_id, OLD.name, OLD.salary, NOW(), TG_OP::CHAR(1));
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
```

PostgreSQL 社区多年讨论 `FOR SYSTEM_TIME` 原生支持但尚未进入核心（阻力来自 vacuum 模型与页级存储限制）。Greenplum、TimescaleDB 继承了这个缺陷。

### MariaDB：开源 SQL:2011 的最强实现

MariaDB 10.3（2018）率先在开源关系库中实现完整的 SQL:2011 系统版本控制。

```sql
-- 1. 创建系统版本控制表（整表版本化）
CREATE TABLE employees (
    emp_id   INT PRIMARY KEY,
    name     VARCHAR(100),
    salary   DECIMAL(10,2)
) WITH SYSTEM VERSIONING;

-- 或显式声明时间列
CREATE TABLE employees (
    emp_id   INT PRIMARY KEY,
    name     VARCHAR(100),
    salary   DECIMAL(10,2),
    sys_start TIMESTAMP(6) GENERATED ALWAYS AS ROW START,
    sys_end   TIMESTAMP(6) GENERATED ALWAYS AS ROW END,
    PERIOD FOR SYSTEM_TIME (sys_start, sys_end)
) WITH SYSTEM VERSIONING;

-- 2. 查询历史
SELECT * FROM employees FOR SYSTEM_TIME AS OF TIMESTAMP '2026-01-01 12:00:00';

SELECT * FROM employees FOR SYSTEM_TIME
    BETWEEN '2026-01-01' AND '2026-04-01';

SELECT * FROM employees FOR SYSTEM_TIME
    FROM '2026-01-01' TO '2026-04-01';

SELECT * FROM employees FOR SYSTEM_TIME
    CONTAINED IN ('2026-01-01', '2026-04-01');

SELECT * FROM employees FOR SYSTEM_TIME ALL;

-- 3. 会话级默认
SET SYSTEM_VERSIONING_ASOF = '2026-01-01 12:00:00';
SELECT * FROM employees;  -- 自动应用 AS OF

-- 4. 按分区存储历史（INTERVAL 分区自动老化）
CREATE TABLE logs (
    id BIGINT PRIMARY KEY,
    payload TEXT
) WITH SYSTEM VERSIONING
  PARTITION BY SYSTEM_TIME INTERVAL 1 WEEK (
      PARTITION p0 HISTORY,
      PARTITION p1 HISTORY,
      PARTITION p2 HISTORY,
      PARTITION pnow CURRENT);

-- 5. 排除列不版本化
CREATE TABLE sessions (
    sid INT PRIMARY KEY,
    user_id INT,
    last_ping TIMESTAMP WITHOUT SYSTEM VERSIONING
) WITH SYSTEM VERSIONING;
```

关键要点：
- 时间精度是 `TIMESTAMP(6)`，微秒级。
- 历史行与当前行默认存在同一张物理表（通过内部 `row_start/row_end` 区分），无单独 history table。
- 支持**分区按时间老化历史**：INTERVAL 分区让清理变成 `DROP PARTITION`，代价 O(1)。
- 支持**部分列版本化**：`WITHOUT SYSTEM VERSIONING` 标记的列更新时不产生新版本行。
- MySQL 社区版至今（8.4）没有跟进此特性。

### DB2：10.1（2012）同时支持 system-time 与 business-time

IBM DB2 是继 Oracle 之后最早具备完整时态能力的商业库，并同时支持"系统时间"（真实事务时间）和"业务时间"（业务有效期）——这是 SQL:2011 的完整两维时态表模型。

```sql
-- 系统时间表
CREATE TABLE employees (
    emp_id    INT NOT NULL PRIMARY KEY,
    name      VARCHAR(100),
    salary    DECIMAL(10,2),
    sys_start TIMESTAMP(12) GENERATED ALWAYS AS ROW BEGIN NOT NULL,
    sys_end   TIMESTAMP(12) GENERATED ALWAYS AS ROW END   NOT NULL,
    trans_id  TIMESTAMP(12) GENERATED ALWAYS AS TRANSACTION START ID,
    PERIOD SYSTEM_TIME (sys_start, sys_end)
);

CREATE TABLE employees_history LIKE employees;

ALTER TABLE employees ADD VERSIONING USE HISTORY TABLE employees_history;

-- 查询历史
SELECT * FROM employees
    FOR SYSTEM_TIME AS OF '2026-01-01-12.00.00';

SELECT * FROM employees
    FOR SYSTEM_TIME BETWEEN '2026-01-01' AND '2026-04-01';

SELECT * FROM employees
    FOR SYSTEM_TIME FROM '2026-01-01' TO '2026-04-01';

-- 业务时间查询
CREATE TABLE policy (
    pol_id INT, amount DECIMAL(10,2),
    b_start DATE, b_end DATE,
    PERIOD BUSINESS_TIME (b_start, b_end)
);

SELECT * FROM policy FOR BUSINESS_TIME AS OF DATE '2026-06-01';

-- 双时态：在 2026-01-01 这个事务时刻，业务有效期内的保单状态
SELECT * FROM policy
    FOR SYSTEM_TIME AS OF '2026-01-01'
    FOR BUSINESS_TIME AS OF '2026-06-01';
```

### Snowflake：最灵活的 Time Travel 之一

Snowflake 采用非标准的 `AT`/`BEFORE` 子句，但提供了丰富的"锚点"类型：时间戳、相对偏移、语句 ID。

```sql
-- 时间点
SELECT * FROM orders AT(TIMESTAMP => '2026-01-01 12:00:00'::TIMESTAMP_NTZ);

-- 相对偏移（单位：秒；负数表示过去）
SELECT * FROM orders AT(OFFSET => -60*5);   -- 5 分钟前
SELECT * FROM orders AT(OFFSET => -60*60*24); -- 1 天前

-- 按语句 ID（query_id），回到该语句提交后的状态
SELECT * FROM orders AT(STATEMENT => '019c7e...-query-uuid');

-- BEFORE：回到该时刻之前一刻
SELECT * FROM orders BEFORE(STATEMENT => '019c7e...-query-uuid');

-- 配合 CREATE TABLE 做 rollback
CREATE OR REPLACE TABLE orders_restore AS
SELECT * FROM orders AT(OFFSET => -60*10);

-- 在 JOIN 中使用
SELECT curr.id, curr.amount AS now_amount, old.amount AS then_amount
FROM   orders curr
LEFT JOIN orders AT(OFFSET => -60*60) old
       ON curr.id = old.id
WHERE  curr.amount <> old.amount;

-- UNDROP：被 DROP 掉的表/schema/db 也能从 Time Travel 恢复
UNDROP TABLE orders;
```

保留期（`DATA_RETENTION_TIME_IN_DAYS`）：
- Standard Edition：1 天（上限）
- Enterprise / Business Critical / VPS：最大 90 天
- 过期后数据进入 **Fail-safe**（7 天），仅 Snowflake 客服可恢复
- 可在 account / database / schema / table 任一层覆盖

### BigQuery：简洁的 7 天窗口

Google BigQuery 在 2020 年引入 `FOR SYSTEM_TIME AS OF`，语法符合 SQL:2011 子集。

```sql
SELECT * FROM `my_project.my_dataset.orders`
    FOR SYSTEM_TIME AS OF TIMESTAMP '2026-04-14 15:00:00 UTC';

-- 最近 1 小时前的快照
SELECT * FROM `my_project.my_dataset.orders`
    FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR);

-- 恢复被误 TRUNCATE 的表
CREATE OR REPLACE TABLE `my_project.my_dataset.orders_restored` AS
SELECT * FROM `my_project.my_dataset.orders`
    FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 10 MINUTE);
```

关键约束：
- **最大回溯：7 天**，这是硬上限。2022 年起可在 2–7 天之间配置 `max_time_travel_hours`，但不能超过 7 天。
- 只支持 `AS OF`，不支持 BETWEEN / FROM..TO / CONTAINED IN。
- 不支持对 streaming buffer 中的数据使用时间旅行。
- 不支持对 view / external table 使用。
- 被 `DROP TABLE` 的表同样可在 7 天内通过 `@<timestamp>` 语法恢复（实际上是 `FOR SYSTEM_TIME AS OF` 的别名）。

### CockroachDB：非阻塞读取的战术武器

CockroachDB 把 `AS OF SYSTEM TIME` 作为一等公民，任何 `SELECT` 都可以附加，它是分布式 SQL 的核心特性。

```sql
-- 绝对时间点
SELECT * FROM orders AS OF SYSTEM TIME '2026-04-14 15:00:00';

-- 相对偏移
SELECT * FROM orders AS OF SYSTEM TIME '-10s';
SELECT * FROM orders AS OF SYSTEM TIME '-1h';

-- follower_read_timestamp()：读取最近的已复制快照（高可用场景）
SELECT * FROM orders AS OF SYSTEM TIME follower_read_timestamp();

-- experimental_follower_read_timestamp(): 读取更早的历史
SELECT * FROM orders AS OF SYSTEM TIME experimental_follower_read_timestamp();

-- 整个事务使用历史视图（只读事务）
BEGIN TRANSACTION AS OF SYSTEM TIME '-30s';
    SELECT * FROM orders;
    SELECT * FROM customers JOIN orders USING (cust_id);
COMMIT;
```

核心特性：
- **非阻塞**：因为读取的是 MVCC 历史版本，完全跳过当前活跃事务的锁，适合 OLAP/报表负载跑在 OLTP 集群上。
- **follower read**：从最近的副本读取（而非 leader），延迟更低、吞吐更高。
- **时间戳单位**：HLC（Hybrid Logical Clock），纳秒 + 逻辑时钟。
- **保留窗口**：由 `gc.ttlseconds` 控制（默认 90000s = 25 小时）。设置越长，MVCC 存储越大。

### TiDB：AS OF TIMESTAMP 的 stale read

TiDB 5.0（2021）引入 Oracle 风格的 `AS OF TIMESTAMP`，主要目的是 **Stale Read**——读取稍旧的快照以避免跨 region 访问 leader。

```sql
-- 绝对时间
SELECT * FROM orders AS OF TIMESTAMP '2026-04-14 15:00:00';

-- 相对时间
SELECT * FROM orders AS OF TIMESTAMP NOW() - INTERVAL 10 SECOND;

-- 最近 5 秒内的任意一个可用快照（最灵活，延迟最低）
SELECT * FROM orders AS OF TIMESTAMP TIDB_BOUNDED_STALENESS(NOW() - INTERVAL 10 SECOND, NOW());

-- 事务级
START TRANSACTION READ ONLY AS OF TIMESTAMP NOW() - INTERVAL 5 SECOND;
    SELECT * FROM orders;
COMMIT;

-- 会话级默认（免除每个查询都写）
SET @@tidb_read_staleness = -5;  -- 5 秒前
```

受限于 `tidb_gc_life_time`（默认 10 分钟），超出这个窗口的 AS OF 会报错。

### Delta Lake / Databricks：VERSION AS OF 与 TIMESTAMP AS OF

Delta Lake 的时间旅行依赖其 transaction log（`_delta_log`）。

```sql
-- 按提交版本号（最精确）
SELECT * FROM orders VERSION AS OF 12;

-- 按 wall-clock 时间
SELECT * FROM orders TIMESTAMP AS OF '2026-04-14 15:00:00';

-- 查询某个表的提交历史
DESCRIBE HISTORY orders;
-- 返回列: version, timestamp, userId, operation, operationParameters, ...

-- 恢复表到历史版本
RESTORE TABLE orders TO VERSION AS OF 12;
-- 或
RESTORE TABLE orders TO TIMESTAMP AS OF '2026-04-14 15:00:00';

-- Python / Scala
-- df = spark.read.format("delta").option("versionAsOf", 12).load("/path")
-- df = spark.read.format("delta").option("timestampAsOf", "2026-04-14").load("/path")
```

Databricks SQL 支持 Delta 的 `@v12` / `@20260414150000000` 简写：
```sql
SELECT * FROM orders@v12;
SELECT * FROM orders@20260414150000000;
```

保留期由 `delta.logRetentionDuration`（默认 30 天）和 `delta.deletedFileRetentionDuration`（默认 7 天）共同决定。`VACUUM` 操作会永久删除旧文件，执行后早于 retention 的时间旅行会失败。

### Apache Iceberg：版本号与命名分支

Iceberg 是三大 Lakehouse 表格式中时间旅行语义最丰富的：既按 snapshot-id（版本）又按时间戳，还支持 branch/tag。

```sql
-- 按 snapshot-id
SELECT * FROM orders FOR SYSTEM_VERSION AS OF 8234567890123;

-- 按时间戳
SELECT * FROM orders FOR SYSTEM_TIME AS OF TIMESTAMP '2026-04-14 15:00:00';

-- 按命名分支 / tag
SELECT * FROM orders FOR SYSTEM_VERSION AS OF 'audit_2026_q1';

-- Trino 语法
SELECT * FROM iceberg.sales.orders FOR VERSION AS OF 8234567890123;
SELECT * FROM iceberg.sales.orders FOR TIMESTAMP AS OF TIMESTAMP '2026-04-14 15:00:00 UTC';

-- Spark 语法
SELECT * FROM orders VERSION AS OF 8234567890123;
SELECT * FROM orders TIMESTAMP AS OF '2026-04-14 15:00:00';

-- 查看历史 snapshot
SELECT committed_at, snapshot_id, parent_id, operation
FROM   orders.snapshots;

-- 创建命名 tag / branch 用于将来的时间旅行
ALTER TABLE orders CREATE TAG `eod_2026_04_14` AS OF VERSION 8234567890123;
ALTER TABLE orders CREATE BRANCH audit_branch AS OF VERSION 8234567890123;
```

Iceberg 的时间旅行不受固定窗口限制——直到运行 `expire_snapshots` 过程才会真正清理旧 snapshot。这也是很多数据工程团队选择 Iceberg 的主要原因之一：**可以按业务需要保留任意久的历史**。

### 其他引擎简述

**Flink SQL**：`FOR SYSTEM_TIME AS OF` 的语义完全不同——不是查询历史，而是 **Temporal Join** 的左右值对齐。`SELECT * FROM orders JOIN currency_rates FOR SYSTEM_TIME AS OF orders.proc_time` 表示"用订单发生时刻的汇率对齐"。不要与 SQL Server / MariaDB 的时间旅行混淆。

**SAP HANA**：`SELECT * FROM orders AS OF COMMIT_ID 14235`，基于 HANA 的 commit ID（非时间戳），不符合 SQL:2011。

**Vertica**：`AT EPOCH 12345` / `AT TIME '2026-04-14 15:00:00'`，基于 epoch model（Ancient History Mark, AHM），不是标准语法，回溯窗口由 epoch 保留策略决定。

**Spanner**：通过客户端 `TimestampBound`（`exact_staleness` / `read_timestamp` / `max_staleness`）实现 stale read，没有 SQL AS OF 语法。最大保留 1 小时，可调至 7 天。

**HSQLDB**：语法上符合 SQL:2011，但需要手动声明 history 表，缺乏自动历史管理。

**ClickHouse**：通过 `FINAL` 关键字 + `ReplacingMergeTree` 可以模拟"取最新版本"，但不支持真正的 AS OF 历史查询。靠 `PARTITION BY toDate(event_time)` + 复制分区可做粗粒度快照。

**Azure Synapse Dedicated SQL Pool**：2022 年起支持 SQL Server 语法子集的 temporal tables 与 `FOR SYSTEM_TIME`，Serverless SQL Pool 不支持。

## Snowflake Time Travel 深入

Snowflake Time Travel 是最成熟的商用时间旅行之一，值得单独一节。

### 层级结构

```
Active storage   ──┐
     │              │ 可用 AT / BEFORE 查询
     ▼              │
Time Travel (1-90d) ┘
     │
     ▼
Fail-safe (7d)  ←─── 仅 Snowflake 员工可恢复，用户不可访问
     │
     ▼
Permanently deleted
```

### 配置粒度

```sql
-- Account 层
ALTER ACCOUNT SET DATA_RETENTION_TIME_IN_DAYS = 7;

-- Database 层（覆盖 account）
ALTER DATABASE prod SET DATA_RETENTION_TIME_IN_DAYS = 30;

-- Schema 层
ALTER SCHEMA prod.sales SET DATA_RETENTION_TIME_IN_DAYS = 14;

-- Table 层
ALTER TABLE prod.sales.orders SET DATA_RETENTION_TIME_IN_DAYS = 90;

-- 临时表 / transient 表：最大 1 天
CREATE TEMPORARY TABLE t (id INT);  -- 默认 0 天
```

### 实用模式

```sql
-- 模式 1：误操作恢复
CREATE OR REPLACE TABLE orders AS
SELECT * FROM orders BEFORE(STATEMENT => 'the_bad_query_id');

-- 模式 2：长任务基线锁定（避免上游变更干扰）
SET job_start_ts = CURRENT_TIMESTAMP();
-- ... 数小时的 pipeline ...
SELECT * FROM dim_customer AT(TIMESTAMP => $job_start_ts);

-- 模式 3：慢慢扫描历史
WITH yesterday AS (
    SELECT * FROM orders AT(OFFSET => -60*60*24)),
today AS (
    SELECT * FROM orders)
SELECT t.id, y.amount AS yday_amount, t.amount AS today_amount
FROM   today t FULL OUTER JOIN yesterday y USING (id)
WHERE  COALESCE(y.amount, 0) <> COALESCE(t.amount, 0);
```

## BigQuery 7 天 Time Travel 的机制

BigQuery 的 Time Travel 基于其底层 Capacitor 列存储的不可变性：每次 DML 都产生新版本，旧版本保留在底层 Colossus 上。

```sql
-- 默认 7 天，2022 年后可配置 2–7 天
ALTER SCHEMA `project.dataset` SET OPTIONS (
    max_time_travel_hours = 168  -- 7 天
);

-- 配合 TABLE 函数恢复
CREATE TABLE `project.dataset.orders_restored` AS
SELECT * FROM `project.dataset.orders`
    FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR);

-- Time Travel 以外的恢复：fail-safe 7 天
-- BigQuery 在 time travel 结束后还有 7 天 fail-safe（类似 Snowflake），
-- 但需要联系 Google Cloud Support 恢复
```

**计费**：Time Travel 存储会计入表存储费用。长保留的大表会明显增加账单。

## Oracle Flashback Query vs Flashback Table 的区别

这是 Oracle 生态中最容易混淆的两个概念。

| 维度 | Flashback Query | Flashback Table |
|------|----------------|------------------|
| 语句类型 | SELECT（DML，只读） | FLASHBACK TABLE（DDL，可写） |
| 语法 | `SELECT * FROM t AS OF TIMESTAMP ...` | `FLASHBACK TABLE t TO TIMESTAMP ...` |
| 效果 | 返回历史行，不修改当前表 | 把整张表"倒带"到历史状态 |
| 依赖 | undo tablespace | undo + ROW MOVEMENT 权限 |
| 可组合 | 可以 JOIN 当前表 | 不可，是整表操作 |
| 回滚粒度 | 行级（SELECT 出来后自行处理） | 表级 |
| 是否可撤销 | 本身无副作用 | 可再次 FLASHBACK 回到更近时间 |
| 典型场景 | 审计、差异对比、误删恢复 | 快速整表恢复（发现问题 30 分钟内） |

```sql
-- Flashback Query：审计
SELECT * FROM employees AS OF TIMESTAMP SYSTIMESTAMP - INTERVAL '1' HOUR
MINUS
SELECT * FROM employees;

-- Flashback Table：整表倒带
ALTER TABLE employees ENABLE ROW MOVEMENT;
FLASHBACK TABLE employees TO TIMESTAMP SYSTIMESTAMP - INTERVAL '10' MINUTE;

-- Flashback Drop（完全不同！从回收站 RECYCLEBIN 恢复被 DROP 的表）
FLASHBACK TABLE orders TO BEFORE DROP;

-- Flashback Database（整库倒带，最重）
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
FLASHBACK DATABASE TO TIMESTAMP SYSTIMESTAMP - INTERVAL '1' HOUR;
ALTER DATABASE OPEN RESETLOGS;
```

四个 Flashback 的"重量级"递增：Flashback Query（零成本）→ Flashback Table（中等）→ Flashback Drop（从回收站）→ Flashback Database（需要停机 + 开启 Flashback Logging）。

## 引擎实现要点

### 1. 版本存储模型对比

```
Undo-based (Oracle, OceanBase):
    事务修改 → 在 undo tablespace 写入旧版本
    优点: 主表不变胖，回滚快
    缺点: undo 空间限制回溯窗口

MVCC 多版本 (PostgreSQL, CockroachDB, TiDB):
    每次 UPDATE/DELETE 保留旧 tuple
    优点: 天然支持快照读
    缺点: 依赖 vacuum/gc 回收，回溯窗口 = gc 窗口

History table (SQL Server, DB2):
    旧版本写入独立的 history 表
    优点: 可独立索引、压缩、分区、无限保留
    缺点: 写放大（每次更新产生两份）

File-level snapshot (Snowflake, BigQuery):
    列式不可变文件 + 元数据快照
    优点: 存储高效，快照零拷贝
    缺点: 粒度是文件批，细粒度查询需要重新扫描

Transaction log replay (Delta, Iceberg):
    基于 commit log 物化任一历史版本
    优点: 可重现任意中间状态
    缺点: 回溯成本随 log 长度增长，需 compaction
```

### 2. 查询计划的改写

当 SQL 包含 `FOR SYSTEM_TIME AS OF t` 时，优化器需要：

1. **重写表引用**：把 `orders` 替换成 `UNION ALL` 当前表和历史表（SQL Server/DB2 模型）或把谓词 `sys_start <= t < sys_end` 下推到物理扫描。
2. **索引选择**：在历史表上通常需要 `(sys_start, sys_end, pk)` 或时间范围 BRIN 索引。
3. **JOIN 下推**：`SELECT * FROM a FOR SYSTEM_TIME AS OF t JOIN b FOR SYSTEM_TIME AS OF t` 两个 AS OF 必须一致才能下推成单次版本视图。
4. **谓词下推**：`WHERE emp_id = 100` 可以安全下推到时间过滤之后——但不能下推到时间过滤之前，否则可能错过已被删除的行。
5. **快照锁定**：在分布式系统中，需要选择一个全局一致的时间戳（HLC 或 TSO），并向所有 shard 广播。

### 3. GC 与保留窗口的权衡

保留窗口的选择是**存储成本 × 回溯价值**的平衡：

- **OLTP 主库**：默认 15 分钟到 1 天，仅用于"误操作即时恢复"。
- **审计库 / 监管库**：7 年（金融法规），用 history table + 冷归档分层。
- **ML 回测库**：1–5 年，按分区老化到廉价对象存储。
- **BI 数据仓库**：1–7 天，主要用于"长查询期间的基线锁定"。

### 4. 分布式一致性时间戳

```
TrueTime (Spanner):
    硬件 GPS + 原子钟 → 全局绝对时间
    commit wait = 7ms 左右

HLC (CockroachDB, YugabyteDB):
    physical_time << 16 | logical_counter
    任意节点单调 + 近似物理时间

TSO (TiDB, OceanBase):
    单点中心化时间戳分发器
    精确 + 低延迟，但 TSO 是 SPOF
```

分布式 AS OF 查询的挑战：**时间戳解析**——用户传入的 wall-clock 时间必须映射到系统内部的事务时间戳。Spanner 使用 TrueTime 区间直接比较；CockroachDB 查 HLC 表；TiDB 向 PD 请求对应时间点的 TSO。

### 5. 长窗口回溯对 vacuum 的影响

MVCC 引擎的长保留窗口会直接阻止 vacuum 回收死元组：

- **PostgreSQL**：`hot_standby_feedback` + replica 的长事务会拖住主库 vacuum，导致 bloat。没有原生 AS OF 的一个原因正是 vacuum 模型不允许长时间保留。
- **CockroachDB**：`gc.ttlseconds` 越大，MVCC tuple 越多，随机读变慢、compaction 压力增加。
- **TiDB**：`tidb_gc_life_time` 过长会让 TiKV 的 RocksDB 层级 compaction 不及时，读延迟上升。

因此几乎所有 MVCC 数据库都把默认窗口设得很短（10 分钟到 25 小时），而 history table 模型（SQL Server/DB2/MariaDB）可以支持无限保留。

### 6. Schema evolution 与历史查询

当表结构发生变化，历史查询会遇到一个难题：`ALTER TABLE ADD COLUMN` 之后回到之前的时间点，应该返回几列？

- **SQL Server**：history 表结构与当前表结构联动，新增列用 NULL 回填历史行。
- **MariaDB**：同 SQL Server。
- **Iceberg**：schema 版本与 snapshot 绑定，回到 snapshot_id X 会看到当时的 schema（更严格的 point-in-time correctness）。
- **Snowflake**：当前 schema 应用于历史数据，缺失列 NULL 回填。
- **Oracle**：DDL 会使更早的 Flashback Query 失败（`ORA-01466: unable to read data - table definition has changed`）。

ML 回测尤其需要注意：如果历史回测应该使用"当时"的特征 schema，`Iceberg` 的严格模型更合适；如果要用"现在"的 schema 做对比，SQL Server 模型更合适。

## 测试要点

引擎测试时间旅行功能的要点清单：

1. **时间点边界**：`AS OF sys_start` 应返回新版本，`AS OF sys_start - 1ns` 应返回旧版本。
2. **精度**：毫秒/微秒/纳秒边界的并发插入是否能区分版本。
3. **保留窗口**：超过窗口的 AS OF 应返回明确错误（`snapshot too old`），不能静默返回当前行。
4. **DDL 交互**：ALTER TABLE 后对 DDL 之前的时间点查询应有明确语义（报错 / NULL 填充 / 旧 schema）。
5. **事务性**：同一事务内多次 `AS OF t` 应返回完全一致的行集。
6. **JOIN 传播**：`a FOR SYSTEM_TIME AS OF t JOIN b` 只有 a 带 AS OF，b 是否读当前？（标准：b 读当前）
7. **DELETE 可见性**：被 DELETE 的行在 `AS OF (delete_time - 1ns)` 应仍可见。
8. **索引利用**：AS OF 查询应该能利用历史表上的索引，不能退化成全表扫描。
9. **统计信息**：优化器对历史行的基数估计是否准确。
10. **权限**：AS OF 查询的权限检查应基于**当前**用户权限，还是查询时刻的权限？（标准：当前）

## 关键发现

1. **SQL:2011 是一个"晚到的标准"**：Oracle 9i（2003）、DB2 10.1（2012）、SQL Server 2016、MariaDB 10.3（2018）、BigQuery（2020）、TiDB 5.0（2021），标准与实现之间长达 13 年的错位——正因如此，Oracle 的 `AS OF TIMESTAMP`、Snowflake 的 `AT/BEFORE`、Delta 的 `VERSION AS OF` 各自成体系。

2. **PostgreSQL 是最大的缺失**：作为最流行的开源关系库，PostgreSQL 至今没有原生 `FOR SYSTEM_TIME`。核心原因是 vacuum 回收模型与长保留窗口天然冲突，而重写存储层（改成 history table）又会动摇其 MVCC 架构。

3. **Lakehouse 后来居上**：Delta / Iceberg / Hudi 三大开放表格式全部原生支持时间旅行，反过来让 Trino / Spark / Presto / Databricks / Impala / StarRocks / Doris / Athena 都"间接"获得了时间旅行能力——前提是数据表采用这些格式。

4. **保留窗口决定使用场景**：
   - 秒~分钟级（CockroachDB/TiDB/OceanBase）：主要用于 **stale read 性能优化**
   - 小时~天级（BigQuery 7d、Snowflake 1d）：主要用于 **误操作恢复**
   - 月~年级（SQL Server/DB2/MariaDB/Iceberg）：主要用于 **审计与合规**
   - 永久（Oracle Flashback Data Archive、Iceberg + 明确保留策略）：主要用于 **监管留存与历史回测**

5. **时间戳 vs 版本号**：基于 wall-clock 时间戳的 AS OF 查询看起来直观，但有时钟歧义（两个事务同一毫秒完成）。基于单调版本号（SCN、snapshot-id、HLC）的查询精确但不易读。成熟系统同时提供两者。

6. **Flashback Query 不等于 Flashback Table**：Oracle 文档中清晰区分的这两个概念，在其他引擎中经常被混为一谈。SELECT 级别的"时间旅行"是零副作用查询，表级的"倒带"是具有破坏性的 DDL。

7. **MVCC 不免费**：支持时间旅行的系统都必须延长版本保留，这对 vacuum / gc / compaction 产生直接压力。Snowflake 之所以能做到 90 天只是因为其列式不可变文件存储天然适合保留历史——同样的能力在 PostgreSQL / MySQL 的页级存储上成本高得多。

8. **Flink 的 `FOR SYSTEM_TIME AS OF` 不是时间旅行**：它是流处理中的 temporal join，语义与批引擎的历史查询完全不同，是标准里最容易被误解的一处。

9. **历史查询 + DDL = 潜在炸弹**：几乎所有实现都对 DDL 与时间旅行的交互有限制。最优工程实践是**先冻结 schema，再延长保留窗口**；频繁 ALTER 的表不适合开启长窗口时间旅行。

10. **BigQuery 的 7 天是硬上限**：当你需要更长审计窗口，BigQuery 的答案是"把 snapshot 导出到另一张表并长期保留"——这实际上把问题抛回给用户，设计上不如 Snowflake 的 90 天与 Iceberg 的无限灵活。

11. **非阻塞读是被低估的卖点**：CockroachDB / TiDB 的 AS OF 除了历史查询，还是跑报表、跑 ETL 时规避 OLTP 锁等待的绝佳手段。把"5 秒前的快照"当主数据读，性能与正确性都可接受，而对主库压力几乎为零。

12. **时态表 vs 时间旅行是两个问题**：前者是 DDL（如何把一张表变成系统版本控制表），后者是 DML（如何查询一张已经系统版本控制的表）。开源生态经常把这两个问题绑定——其实像 CockroachDB、Snowflake、BigQuery 这些引擎是**对所有表默认提供时间旅行**的，不需要显式的 temporal table DDL。

## 参考资料

- SQL:2011 标准: ISO/IEC 9075-2:2011, Section 4.15 (temporal tables), Section 7.6 (table reference `FOR SYSTEM_TIME`)
- Kulkarni, K. & Michels, J.-E., "Temporal features in SQL:2011", ACM SIGMOD Record, Vol. 41, No. 3, 2012
- Oracle: [Flashback Query](https://docs.oracle.com/en/database/oracle/oracle-database/19/adfns/flashback.html)
- SQL Server: [Temporal Tables](https://learn.microsoft.com/en-us/sql/relational-databases/tables/temporal-tables)
- DB2: [Time Travel Query](https://www.ibm.com/docs/en/db2/11.5?topic=queries-time-travel)
- MariaDB: [System-Versioned Tables](https://mariadb.com/kb/en/system-versioned-tables/)
- PostgreSQL: [temporal_tables extension](https://github.com/arkhipov/temporal_tables)
- Snowflake: [Time Travel](https://docs.snowflake.com/en/user-guide/data-time-travel)
- BigQuery: [FOR SYSTEM_TIME AS OF](https://cloud.google.com/bigquery/docs/time-travel)
- CockroachDB: [AS OF SYSTEM TIME](https://www.cockroachlabs.com/docs/stable/as-of-system-time)
- TiDB: [Stale Read](https://docs.pingcap.com/tidb/stable/stale-read)
- OceanBase: [Flashback Query](https://en.oceanbase.com/docs/)
- Delta Lake: [Time Travel](https://docs.delta.io/latest/delta-batch.html#query-an-older-snapshot-of-a-table-time-travel)
- Apache Iceberg: [Time Travel and Rollback](https://iceberg.apache.org/docs/latest/spark-queries/#time-travel)
- Apache Hudi: [Time Travel Query](https://hudi.apache.org/docs/quick-start-guide#time-travel-query)
- Google Spanner: [Read Timestamp Bounds](https://cloud.google.com/spanner/docs/reads#timestamp-bounds)
- 相关文章: [时态表 (Temporal Tables)](./temporal-tables.md)
