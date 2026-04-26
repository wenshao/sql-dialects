# ON COMMIT 动作 (ON COMMIT Actions)

事务提交是 SQL 引擎中最具仪式感的瞬间——`COMMIT` 这一行短短六个字符的背后,引擎要决定多少东西的命运:临时表里的行要留下还是清空?物化视图要不要立刻同步?延迟的外键约束此刻才被检查,失败的话整个事务被拽回重做。`ON COMMIT` 子句正是这一连串生命周期决策的语法入口。它不像 `JOIN` 那样在每个查询里出现,但只要你的工作负载里有"会话级中间表"、"严格新鲜度的物化视图"、"批量加载之间的循环外键",就一定会遇到它。本文系统对比 45+ 数据库的 `ON COMMIT` 行为——临时表的数据生命周期、物化视图的同步刷新、约束的延迟检查与即时检查的切换。

相关阅读:[临时表与表变量](temporary-tables.md) 覆盖临时表本身的语法与作用域;[物化视图刷新策略](materialized-view-refresh.md) 覆盖 ON COMMIT 之外的所有刷新模型(定时、增量、连续 dataflow)。

## 为什么 ON COMMIT 是个"小语法、大语义"的关键字

`ON COMMIT` 在 SQL 标准中只占几个语法位置,但每一处都对应一个不平凡的引擎实现决策:

```
ON COMMIT 出现的三个地方                          引擎需要回答的问题

1. CREATE TEMPORARY TABLE ... ON COMMIT { ... }   提交后这张表里的数据怎么办?
   ├─ DELETE ROWS                                 - 清空数据但保留表定义
   ├─ PRESERVE ROWS                               - 数据保留到会话结束
   └─ DROP                                        - 表定义连同数据一起销毁

2. CREATE MATERIALIZED VIEW ... REFRESH ON COMMIT 提交时是否同步刷新 MV?
   ├─ ON COMMIT (Oracle/DB2/OceanBase)            - 同事务内完成 MV 更新
   └─ ON DEMAND/SCHEDULE (默认)                   - 异步刷新

3. CREATE TABLE ... CONSTRAINT ... DEFERRABLE     约束何时被检查?
   ├─ INITIALLY IMMEDIATE                         - 每条 DML 后立即检查
   ├─ INITIALLY DEFERRED                          - 直到 COMMIT 才检查
   └─ SET CONSTRAINTS ALL DEFERRED                - 会话内动态切换
```

这三处的共同点:它们都把"提交"这个事件当作一个**钩子**(hook),让用户在事务边界注入额外语义。区别只在于钩子上挂的动作不同——清空数据、刷新视图、检查约束。

这个设计哲学源自 ANSI/ISO SQL 标准对**事务原子性**的扩展:既然 `COMMIT` 是事务的语义边界,那么所有依赖事务边界的状态转换都应该统一在这个事件上挂载。Oracle 的 `ON COMMIT REFRESH` 物化视图直接复用了 SQL:1992 临时表的关键字;PostgreSQL 的 `DEFERRABLE` 约束本质上也是"提交时执行检查动作"。理解 `ON COMMIT` 这个统一框架,比记忆每个引擎的具体语法更重要。

## SQL 标准对 ON COMMIT 的定义

### SQL:1992 引入临时表的 ON COMMIT

ANSI/ISO SQL:1992 (Section 4.3) 首次引入会话临时表 (session temporary table) 概念,标准语法如下:

```sql
<temporary table declaration> ::=
    DECLARE LOCAL TEMPORARY TABLE <module qualified local table name>
        <table element list>
        [ ON COMMIT { PRESERVE | DELETE } ROWS ]

<created temporary table> ::=
    CREATE { GLOBAL | LOCAL } TEMPORARY TABLE <table name>
        <table element list>
        [ ON COMMIT { PRESERVE | DELETE } ROWS ]
```

标准只定义了两个动作:

- **`ON COMMIT DELETE ROWS`**:事务提交时清空表中所有行(标准默认值)
- **`ON COMMIT PRESERVE ROWS`**:事务提交时保留行,直到会话结束才清空

注意这是 **SQL 标准的默认值**——`DELETE ROWS`,但实际实现中只有 Oracle、DB2 等少数 RDBMS 严格遵守这个默认。PostgreSQL 选择了 `PRESERVE ROWS` 作为更"友好"的默认,SQL Server 则完全不支持这个子句(其 `#temp` 始终是 PRESERVE 语义)。

### 标准未定义的扩展

SQL 标准从未定义以下扩展,但它们在工业界广泛存在:

- **`ON COMMIT DROP`**:PostgreSQL 引入,事务结束后删除整个表
- **`ON COMMIT DROP DEFINITION` / `ON COMMIT PRESERVE DEFINITION`**:Oracle 18c+ 私有临时表(PTT)使用,控制 DDL 的生命周期
- **物化视图的 `REFRESH ON COMMIT`**:ISO SQL 从未定义物化视图,因此其 ON COMMIT 语义完全是厂商扩展
- **`SET CONSTRAINTS ALL { DEFERRED | IMMEDIATE }`**:SQL:1992 定义了延迟约束,各厂商实现差异巨大

### SQL:2003 重新整理

SQL:2003 把 `LOCAL TEMPORARY` 与 `GLOBAL TEMPORARY` 的语义进一步澄清,明确了"DDL 持久性"与"数据可见性"是两个独立维度——这是后续章节 Oracle GTT vs SQL Server `#temp` 行为差异的根源。

## 支持矩阵(45+ 引擎)

### 矩阵 1:临时表 ON COMMIT 子句

| 引擎 | 支持 ON COMMIT | DELETE ROWS | PRESERVE ROWS | DROP | 默认值 |
|------|--------------|-------------|---------------|------|--------|
| Oracle | 是 | 是 | 是 | 是(PTT 的 DROP DEFINITION) | DELETE ROWS |
| PostgreSQL | 是 | 是 | 是 | 是 | PRESERVE ROWS |
| SQL Server | 否 | -- | -- | -- | -- (始终 PRESERVE) |
| MySQL | 否 | -- | -- | -- | -- (会话结束清空) |
| MariaDB | 否 | -- | -- | -- | -- |
| SQLite | 否 | -- | -- | -- | -- |
| DB2 (LUW) | 是 | 是 | 是 | -- | DELETE ROWS |
| Snowflake | 否 | -- | -- | -- | -- (会话结束) |
| BigQuery | 否 | -- | -- | -- | -- (脚本结束) |
| Redshift | 是(继承 PG)| 是 | 是 | 是 | PRESERVE ROWS |
| DuckDB | 否 | -- | -- | -- | -- |
| ClickHouse | 否 | -- | -- | -- | -- |
| Trino | 否(无原生临时表)| -- | -- | -- | -- |
| Presto | 否 | -- | -- | -- | -- |
| Spark SQL | 否(临时视图)| -- | -- | -- | -- |
| Databricks | 否 | -- | -- | -- | -- |
| Hive | 否 | -- | -- | -- | -- |
| Teradata | 是(GTT) | 是 | 是 | -- | DELETE ROWS |
| Greenplum | 是(继承 PG)| 是 | 是 | 是 | PRESERVE ROWS |
| CockroachDB | 部分 | 否 | 是 | 否 | PRESERVE ROWS(仅) |
| TiDB | 是 | 是 | 是 | -- | DELETE ROWS(GTT) |
| OceanBase | 是 | 是 | 是 | -- | DELETE ROWS |
| YugabyteDB | 是(继承 PG)| 是 | 是 | 是 | PRESERVE ROWS |
| Vertica | 是 | 是 | 是 | -- | DELETE ROWS |
| SAP HANA | 是(仅 GTT) | 是 | 是 | -- | DELETE ROWS |
| Informix | 否 | -- | -- | -- | -- |
| Firebird | 是 | 是 | 是 | -- | DELETE ROWS |
| H2 | 是 | 是 | 是 | -- | DELETE ROWS |
| HSQLDB | 是 | 是 | 是 | -- | DELETE ROWS |
| Derby | 是 | 是 | 是 | -- | DELETE ROWS |
| MonetDB | 是 | 是 | 是 | -- | DELETE ROWS |
| Exasol | 否(无原生临时表)| -- | -- | -- | -- |
| SingleStore | 否 | -- | -- | -- | -- |
| PolarDB | 是(GTT) | 是 | 是 | -- | DELETE ROWS |
| GaussDB | 是 | 是 | 是 | -- | DELETE ROWS |
| Citus | 是(继承 PG) | 是 | 是 | 是 | PRESERVE ROWS |
| TimescaleDB | 是(继承 PG) | 是 | 是 | 是 | PRESERVE ROWS |
| QuestDB | 否 | -- | -- | -- | -- |
| StarRocks | 否 | -- | -- | -- | -- |
| Doris | 否 | -- | -- | -- | -- |
| MaxCompute | 否 | -- | -- | -- | -- |
| ByConity | 否 | -- | -- | -- | -- |
| Umbra | 否(继承 PG 但缺 ON COMMIT)| -- | -- | -- | -- |
| VoltDB | 否 | -- | -- | -- | -- |
| Materialize | 否 | -- | -- | -- | -- |
| RisingWave | 否 | -- | -- | -- | -- |
| Yellowbrick | 是 | 是 | 是 | 是 | PRESERVE ROWS |
| Firebolt | 否 | -- | -- | -- | -- |

> 统计:约 22 个引擎实现了某种形式的 `ON COMMIT` 临时表子句,约 23 个完全不支持。注意默认值的分歧——SQL 标准要求 `DELETE ROWS`,但 PostgreSQL 系列(以及继承它的 Greenplum、Redshift、Yugabyte、Citus、TimescaleDB)选择了 `PRESERVE ROWS`,这是历史最大的"实现 vs 标准"分歧之一。

### 矩阵 2:物化视图 ON COMMIT REFRESH

| 引擎 | 物化视图存在 | ON COMMIT REFRESH | 支持版本 | 同步粒度 |
|------|------------|------------------|---------|---------|
| Oracle | 是 | 是 | 9i+ | 事务级(可选 12c+ 语句级) |
| PostgreSQL | 是 | 否 | -- | -- (仅手动 REFRESH) |
| SQL Server | 索引视图(本质等价)| 是(隐式) | 2000+ | 每行 |
| DB2 | 是(MQT) | 是(`REFRESH IMMEDIATE`)| v8+ | 事务级 |
| Snowflake | 是 | 否 | -- | 后台异步 |
| BigQuery | 是 | 否 | -- | 后台异步 |
| Redshift | 是 | 否 | -- | 手动或自动调度 |
| MySQL | 否(无 MV)| -- | -- | -- |
| MariaDB | 否 | -- | -- | -- |
| SQLite | 否 | -- | -- | -- |
| DuckDB | 否 | -- | -- | -- |
| ClickHouse | 是(触发器式)| 事实上是(每个 INSERT)| 早期 | INSERT 块 |
| Trino | 是 | 否 | -- | -- |
| Presto | 部分 | 否 | -- | -- |
| Spark SQL | 否(Delta 代替)| -- | -- | -- |
| Hive | 是 | 否 | -- | -- |
| Databricks | 是(DLT) | 否(管道驱动)| -- | -- |
| Teradata | 是(Join Index)| 是(隐式) | 早期 | 事务级 |
| Greenplum | 是 | 否(继承 PG)| -- | -- |
| CockroachDB | 是 | 否 | -- | -- |
| TiDB | 否 | -- | -- | -- |
| OceanBase | 是 | 是(Oracle 兼容模式)| 4.x+ | 事务级 |
| YugabyteDB | 是 | 否(继承 PG)| -- | -- |
| StarRocks | 异步 MV / 同步 MV | 同步 MV 是隐式 ON COMMIT 性质 | 2.4+ | 表级 |
| Doris | 同步 MV | 隐式 ON COMMIT 性质 | -- | 表级 |
| Vertica | Projection(非传统 MV)| 隐式 | -- | 写入时 |
| Impala | 否 | -- | -- | -- |
| TimescaleDB | 连续聚合 | 否 | -- | -- |
| QuestDB | 是 | 否 | -- | -- |
| Materialize | 是 | 事实上是(连续 dataflow)| GA | 流式 |
| RisingWave | 是 | 事实上是 | GA | 流式 |
| SAP HANA | Calculation View(非传统 MV)| 部分 ON COMMIT 视图 | 1.0+ | 视图级 |
| Azure Synapse | 索引视图 | 是(隐式) | GA | 每行 |

> 统计:**真正的"`REFRESH ON COMMIT` 子句"只有 Oracle、DB2、OceanBase 三家有完整的语法支持**(Teradata Join Index、SQL Server 索引视图、流式系统是"事实上 ON COMMIT"但没有这个关键字)。这是 ON COMMIT MV 的"工业现实":它的代价(写入路径上同步执行 MV 维护)足够高,以至于绝大部分引擎选择不支持。

### 矩阵 3:延迟约束 (DEFERRABLE Constraints)

| 引擎 | DEFERRABLE | INITIALLY DEFERRED | SET CONSTRAINTS | 适用约束类型 |
|------|-----------|--------------------|----------------|------------|
| PostgreSQL | 是 | 是 | 是 | UNIQUE, FK, EXCLUDE, CHECK(部分) |
| Oracle | 是 | 是 | 是 | UNIQUE, FK, PK, CHECK |
| SQL Server | 否 | -- | -- | -- (始终 IMMEDIATE) |
| MySQL | 否 | -- | -- | -- (8.0+ 仅 FK 部分) |
| MariaDB | 否 | -- | -- | -- |
| SQLite | 是(部分) | 是 | 否 | FK |
| DB2 | 否(直到 11.5)/ 是(11.5+部分) | 部分 | 部分 | FK(11.5+) |
| Snowflake | 否 | -- | -- | -- |
| BigQuery | 否 | -- | -- | -- |
| Redshift | 否 | -- | -- | -- (FK 不强制) |
| DuckDB | 否 | -- | -- | -- |
| ClickHouse | 否 | -- | -- | -- |
| Trino | -- | -- | -- | -- |
| Spark SQL | 否 | -- | -- | -- |
| Hive | 否(约束声明性的) | -- | -- | -- |
| Teradata | 否 | -- | -- | -- |
| Greenplum | 是(继承 PG)| 是 | 是 | UNIQUE, FK, EXCLUDE |
| CockroachDB | 否 | -- | -- | -- |
| TiDB | 否 | -- | -- | -- |
| OceanBase | 是(Oracle 兼容模式) | 是 | 是 | UNIQUE, FK, PK, CHECK |
| YugabyteDB | 是(继承 PG) | 是 | 是 | UNIQUE, FK, EXCLUDE |
| Vertica | 否 | -- | -- | -- |
| SAP HANA | 否 | -- | -- | -- |
| Informix | 是 | 是 | 是 | FK |
| Firebird | 否 | -- | -- | -- |
| H2 | 部分 | 否 | 是(SET REFERENTIAL_INTEGRITY) | FK 全局开关 |
| HSQLDB | 否 | -- | -- | -- |
| Derby | 是(部分) | 否 | -- | FK |
| MonetDB | 否 | -- | -- | -- |
| Exasol | 否 | -- | -- | -- |
| SingleStore | 否 | -- | -- | -- |
| PolarDB | 是(MySQL 模式有限制 / PG 模式完整)| 是 | 是 | UNIQUE, FK |
| GaussDB | 是 | 是 | 是 | UNIQUE, FK |
| Citus | 是(继承 PG) | 是 | 是 | UNIQUE, FK |
| TimescaleDB | 是(继承 PG) | 是 | 是 | UNIQUE, FK |
| Materialize | 否 | -- | -- | -- |
| RisingWave | 否 | -- | -- | -- |
| Yellowbrick | 是 | 是 | 是 | UNIQUE, FK |
| Firebolt | 否 | -- | -- | -- |
| QuestDB | 否 | -- | -- | -- |
| StarRocks | 否 | -- | -- | -- |
| Doris | 否 | -- | -- | -- |

> 统计:支持 `DEFERRABLE` 约束的引擎不到 15 个,且其中半数是 PostgreSQL 派生(Greenplum、Yugabyte、Citus、TimescaleDB、Redshift)。SQL Server 这个"主流"数据库直到最新版本 (2022) 都不支持 `DEFERRABLE`——这是它在多步约束维护场景被诟病的一个主要原因。

### 矩阵 4:SET CONSTRAINTS 动态切换

| 引擎 | SET CONSTRAINTS ALL DEFERRED | SET CONSTRAINTS ALL IMMEDIATE | 单独命名约束 |
|------|------------------------------|------------------------------|------------|
| PostgreSQL | 是 | 是 | 是 |
| Oracle | 是 | 是 | 是(`SET CONSTRAINT` 单数) |
| SQL Server | 否 | 否 | 否 |
| DB2 | 是(`SET INTEGRITY` 类似)| 是 | 部分 |
| MySQL | 否(8.0+ 仅 `SET FOREIGN_KEY_CHECKS=0` 全局)| -- | 否 |
| Greenplum | 是 | 是 | 是 |
| YugabyteDB | 是 | 是 | 是 |
| OceanBase | 是 | 是 | 是 |
| GaussDB | 是 | 是 | 是 |
| H2 | 是(`SET REFERENTIAL_INTEGRITY`)| 是 | 否 |
| Informix | 是 | 是 | 是 |
| SQLite | 否(`PRAGMA defer_foreign_keys`) | -- | 否 |

## SQL 标准临时表分类与 ON COMMIT 的关系

### LOCAL vs GLOBAL TEMPORARY 的标准定义

SQL 标准把临时表分为两类,这是理解 ON COMMIT 行为的前提:

```
┌─────────────────────────────────────────────────────┐
│  LOCAL TEMPORARY TABLE                              │
│  - DDL: 会话级(模块级,标准上更细)                  │
│  - 数据: 会话级                                     │
│  - ON COMMIT 控制: 提交时数据如何处理               │
│  - 类比: 局部变量                                   │
├─────────────────────────────────────────────────────┤
│  GLOBAL TEMPORARY TABLE (GTT)                       │
│  - DDL: 全局持久(数据字典常驻)                      │
│  - 数据: 会话级隔离(每个会话看到自己的数据)         │
│  - ON COMMIT 控制: 提交时数据如何处理               │
│  - 类比: 全局表模板,会话私有数据                    │
└─────────────────────────────────────────────────────┘
```

`ON COMMIT` 子句对两种临时表都适用,但实际意义不同:

- 对 **LOCAL TEMP**:`ON COMMIT DROP` 只是把"会话结束才清理"的时机提前到"事务结束"
- 对 **GLOBAL TEMP**:`ON COMMIT DELETE ROWS` 是真正控制数据生命周期的核心,因为表定义已经永久存在,只有数据是会话级的

Oracle 是这个分类的"教科书实现"——`CREATE GLOBAL TEMPORARY TABLE` 就是 SQL 标准的 GTT,DDL 持久化到 SYS 字典,数据通过 `ON COMMIT DELETE/PRESERVE ROWS` 控制。SQL Server 的 `#temp` 和 `##temp` **不属于 SQL 标准的 LOCAL/GLOBAL 模型**——SQL Server 的"全局临时表"是数据共享的(其他会话能看到同一份数据),与标准的"DDL 共享、数据隔离"完全不同。

### 各引擎对临时表 ON COMMIT 的语法实现

#### PostgreSQL:三种动作完整支持

PostgreSQL 是 SQL 标准 ON COMMIT 的最完整实现之一,三个动作都支持:

```sql
-- DELETE ROWS:事务提交后清空数据,保留表定义到会话结束
CREATE TEMP TABLE t1 (id INT, value TEXT) ON COMMIT DELETE ROWS;

BEGIN;
INSERT INTO t1 VALUES (1, 'a');
SELECT count(*) FROM t1;  -- 1 行
COMMIT;
SELECT count(*) FROM t1;  -- 0 行(数据被清空,表仍存在)

-- PRESERVE ROWS:默认值,数据保留到会话结束
CREATE TEMP TABLE t2 (id INT) ON COMMIT PRESERVE ROWS;

-- DROP:事务结束后整个表被删除(连定义)
CREATE TEMP TABLE t3 (id INT) ON COMMIT DROP;

BEGIN;
CREATE TEMP TABLE t3 (id INT) ON COMMIT DROP;
INSERT INTO t3 VALUES (1);
COMMIT;
SELECT * FROM t3;  -- 错误:table "t3" does not exist
```

PostgreSQL 默认是 `PRESERVE ROWS`,这违背了 SQL 标准的 `DELETE ROWS` 默认。原因是 PostgreSQL 早期没有 GTT,临时表全是 LOCAL 语义,`PRESERVE ROWS` 对会话级临时表更"自然"。

#### Oracle:GTT 的标准实现

Oracle 的 `CREATE GLOBAL TEMPORARY TABLE` 是 SQL 标准 GTT 的代表实现:

```sql
-- 默认 DELETE ROWS
CREATE GLOBAL TEMPORARY TABLE temp_orders (
    order_id   NUMBER PRIMARY KEY,
    customer_id NUMBER,
    amount     NUMBER(10,2)
) ON COMMIT DELETE ROWS;

-- 显式 PRESERVE ROWS:数据保留到会话结束
CREATE GLOBAL TEMPORARY TABLE temp_session_cache (
    cache_key   VARCHAR2(100) PRIMARY KEY,
    cache_value CLOB
) ON COMMIT PRESERVE ROWS;
```

Oracle GTT 的 DDL 持久化在 `DBA_TABLES`/`SYS.OBJ$`,所有会话共享同一份定义,但每个会话拥有独立的临时段(temporary segment)存放数据。`ON COMMIT DELETE ROWS` 在 commit 时只是把当前会话的临时段截断,几乎是 O(1) 操作,不需要逐行 DELETE 的开销。

Oracle 18c+ 引入**私有临时表 (Private Temporary Table, PTT)**,这是真正的会话级 DDL 临时表:

```sql
-- 必须以 ORA$PTT_ 前缀开头
CREATE PRIVATE TEMPORARY TABLE ora$ptt_temp_data (
    id    NUMBER,
    value VARCHAR2(200)
) ON COMMIT DROP DEFINITION;

-- ON COMMIT PRESERVE DEFINITION:DDL 保留到会话结束(数据也保留)
CREATE PRIVATE TEMPORARY TABLE ora$ptt_session_data (
    id NUMBER
) ON COMMIT PRESERVE DEFINITION;
```

PTT 的 `ON COMMIT DROP DEFINITION` 是 Oracle 特有的扩展——表的 DDL 在事务结束时一起销毁,不只是数据。这是为了避免应用程序为短暂的中间结果在数据字典里留下遗骸(GTT 的 DDL 是永久的)。

#### SQL Server:不支持 ON COMMIT,语义被硬编码

SQL Server 完全不支持 `ON COMMIT` 子句。`#temp` 表始终是 PRESERVE 语义——事务提交后数据保留,直到创建会话结束才被销毁:

```sql
-- 没有 ON COMMIT 子句
CREATE TABLE #temp_orders (
    order_id INT PRIMARY KEY,
    amount   DECIMAL(10,2)
);

BEGIN TRAN;
INSERT INTO #temp_orders VALUES (1, 100);
COMMIT;
SELECT * FROM #temp_orders;  -- 1 行(数据保留)
```

如果需要 `DELETE ROWS` 语义,SQL Server 用户必须手动:

```sql
-- 模拟 ON COMMIT DELETE ROWS
BEGIN TRAN;
INSERT INTO #temp_orders VALUES (1, 100);
-- ... 业务逻辑 ...
TRUNCATE TABLE #temp_orders;  -- 显式清空
COMMIT;
```

或者使用**表变量** `@table`,它在批处理结束时自动销毁,且**不参与事务**(回滚不会撤销数据):

```sql
DECLARE @temp TABLE (id INT, value VARCHAR(100));
BEGIN TRAN;
INSERT INTO @temp VALUES (1, 'a');
ROLLBACK;
SELECT * FROM @temp;  -- 1 行!表变量不受 ROLLBACK 影响
```

这是 SQL Server 用户经常踩的坑:从 PostgreSQL/Oracle 迁移过来的应用,期待 `ON COMMIT DELETE ROWS`,SQL Server 上"莫名其妙"数据保留——必须重新设计为显式 TRUNCATE 或使用 `@table`。

#### DB2:DGTT 与 CGTT 双轨制

DB2 LUW 把临时表分两种:**Declared Global Temporary Table (DGTT)** 和 **Created Global Temporary Table (CGTT)**:

```sql
-- DGTT:会话级 DDL,不写系统目录
DECLARE GLOBAL TEMPORARY TABLE session.temp_orders (
    order_id   INT,
    customer_id INT,
    amount     DECIMAL(10,2)
)
ON COMMIT DELETE ROWS         -- 提交时清空
WITH REPLACE                  -- 如果同会话已有同名表,先删除
NOT LOGGED;                   -- 不写日志(性能)

-- CGTT:DDL 持久,类似 Oracle GTT
CREATE GLOBAL TEMPORARY TABLE temp_template (
    id    INT,
    value VARCHAR(200)
) ON COMMIT PRESERVE ROWS;
```

DB2 的 `WITH REPLACE` 选项是个实用扩展——同一会话中重复 DECLARE 同名 DGTT 时,不需要先 DROP。这在存储过程里反复创建临时表的场景很方便。

#### Teradata:VOLATILE TABLE vs GLOBAL TEMPORARY

Teradata 把会话级临时表叫做 **Volatile Table** (会话级 DDL,不进字典),把标准的 GTT 叫做 **Global Temporary Table**:

```sql
-- Volatile:类似 SQL Server #temp,但支持 ON COMMIT
CREATE VOLATILE TABLE temp_orders (
    order_id   INT,
    customer_id INT,
    amount     DECIMAL(10,2)
)
ON COMMIT DELETE ROWS  -- 默认值
PRIMARY INDEX (order_id);

-- GTT:DDL 持久
CREATE GLOBAL TEMPORARY TABLE gt_orders (
    order_id   INT,
    amount     DECIMAL(10,2)
)
ON COMMIT PRESERVE ROWS;
```

Teradata 默认 `DELETE ROWS`,与 SQL 标准一致。`VOLATILE` 是性能极好的会话级临时表,常用于 ETL 中间结果。

#### CockroachDB:仅支持 PRESERVE ROWS

CockroachDB 实现了 PostgreSQL 兼容的临时表,但 ON COMMIT 只支持 `PRESERVE ROWS`(且需要启用实验特性):

```sql
SET experimental_enable_temp_tables = 'on';

-- 只能 PRESERVE ROWS
CREATE TEMP TABLE temp_orders (
    order_id INT PRIMARY KEY,
    amount   DECIMAL(10,2)
) ON COMMIT PRESERVE ROWS;

-- 以下会报错:
-- CREATE TEMP TABLE t (id INT) ON COMMIT DELETE ROWS;
-- ERROR: ON COMMIT DELETE ROWS is not yet supported
```

这是分布式数据库实现 ON COMMIT 的难点之一——需要在 commit 时跨多个 Range 协调清理动作,实现复杂。CockroachDB 选择只支持最简单的语义。

#### TiDB:全局临时表完整支持

TiDB 5.3+ 引入了完整的临时表支持,GTT 行为对齐 Oracle:

```sql
-- 本地临时表(数据仅在 TiDB Server 内存)
CREATE TEMPORARY TABLE temp_local (
    id    INT PRIMARY KEY,
    value VARCHAR(200)
);

-- 全局临时表(DDL 持久,数据事务级)
CREATE GLOBAL TEMPORARY TABLE temp_global (
    id    INT PRIMARY KEY,
    value VARCHAR(200)
) ON COMMIT DELETE ROWS;  -- TiDB 必须显式声明,因为 GLOBAL TEMP 默认行为是 DELETE
```

TiDB 的 GTT 是分布式数据库中较罕见的对齐 SQL 标准 GTT 语义的实现——DDL 持久化到 TiKV 元数据,数据按事务隔离,不写 TiKV 主存储。

#### MySQL / MariaDB / SQLite / Snowflake:都不支持 ON COMMIT

这几个引擎都没有 `ON COMMIT` 子句,临时表的语义是"会话/连接结束时清空":

```sql
-- MySQL
CREATE TEMPORARY TABLE temp_orders (
    order_id INT,
    amount   DECIMAL(10,2)
);
-- 没有 ON COMMIT 选项,会话结束后表自动销毁

-- Snowflake
CREATE TEMPORARY TABLE temp_orders (
    order_id INT,
    amount   NUMBER(10,2)
);
-- 同样,会话结束清理
```

这些引擎中实现"事务级清空"的唯一方法是显式 `TRUNCATE` 或 `DROP`:

```sql
-- MySQL 中模拟 ON COMMIT DELETE ROWS
START TRANSACTION;
INSERT INTO temp_orders VALUES (...);
-- ... 业务逻辑 ...
TRUNCATE TABLE temp_orders;
COMMIT;
```

## 物化视图的 ON COMMIT REFRESH

### Oracle 的 ON COMMIT REFRESH:9i 引入,工业最早完整实现

Oracle 9i (2001) 是第一个把 `REFRESH ON COMMIT` 做成生产可用功能的关系数据库:

```sql
-- 创建 MV LOG (FAST REFRESH 的前提)
CREATE MATERIALIZED VIEW LOG ON orders
WITH ROWID, SEQUENCE, PRIMARY KEY (order_id, region_id, amount, ordered_at)
INCLUDING NEW VALUES;

-- 创建 ON COMMIT 物化视图
CREATE MATERIALIZED VIEW sales_daily
BUILD IMMEDIATE
REFRESH FAST ON COMMIT
ENABLE QUERY REWRITE
AS
SELECT
    region_id,
    TRUNC(ordered_at) AS day,
    COUNT(*)   AS order_count,
    SUM(amount) AS revenue,
    COUNT(amount) AS amount_count  -- FAST REFRESH 聚合 MV 必需
FROM orders
GROUP BY region_id, TRUNC(ordered_at);
```

`ON COMMIT` 的执行流程:

```
应用            Oracle Server                MV LOG                MV
 │                 │                           │                   │
 ├── INSERT ────→  │                           │                   │
 │                 ├── 写 orders               │                   │
 │                 ├── 写 MLOG$_ORDERS ───────→│                   │
 │                                                                 │
 ├── COMMIT ────→  │                           │                   │
 │                 ├── 读 MV LOG 增量          │                   │
 │                 ├── 计算增量聚合更新 ────────────────────────────→│
 │                 ├── 清理 MV LOG                                  │
 │                 ├── 写 redo                                      │
 │                 ├── 释放锁                                       │
 │                 └── 返回 OK                                      │
 │                                                                 │
```

### ON COMMIT REFRESH 的限制

Oracle 对哪些 MV 可以 `ON COMMIT REFRESH` 有严格要求:

1. **必须能 FAST REFRESH** —— 因为 commit 时执行 COMPLETE 刷新代价不可接受。FAST 的所有要求都适用:
   - MV LOG 必须存在,且包含必要的列(ROWID/SEQUENCE/聚合列)
   - 聚合 MV 必须包含 `COUNT(*)`
   - `SUM(x)` 必须配 `COUNT(x)`(用于 NULL 处理与可逆维护)
   - JOIN MV 中所有源表都要有 MV LOG

2. **不能跨数据库** —— `ON COMMIT` 只能在单库内,不支持远程表的 dblink

3. **基表的 DML 性能受影响** —— 每次 commit 都触发 MV 维护,事务持续时间显著增长。Oracle 文档警告:OLTP 表上加 `REFRESH ON COMMIT` MV 可能让 INSERT 性能下降 50%-300%

4. **死锁风险** —— 如果两个事务同时修改 MV 涉及的多张基表,commit 时的 MV 维护可以构成新的死锁窗口

### Oracle 12c+:语句级 vs 事务级 MV

Oracle 12c 引入了 `STATEMENT` 级 MV,这是 `ON COMMIT` 之外的"更同步"选项:

```sql
CREATE MATERIALIZED VIEW sales_running_total
REFRESH FAST ON STATEMENT  -- 每条 DML 后立即刷新
AS
SELECT region_id, SUM(amount) AS total
FROM orders
GROUP BY region_id;
```

`ON STATEMENT` 与 `ON COMMIT` 的区别:

| 维度 | ON COMMIT | ON STATEMENT |
|------|-----------|-------------|
| 触发时机 | 事务提交 | 每条 DML 之后 |
| 同事务内可见性 | 否(同事务的查询看不到 MV 更新)| 是 |
| 死锁可能性 | 中 | 高(每条 DML 都加 MV 锁) |
| 实现复杂度 | 中 | 高 |
| 适用场景 | 高频小事务 | 同事务内需要 MV 反映自己变更 |

`ON STATEMENT` 主要用于一些自连接/递归查询场景,实际生产用的少。

### DB2 的 REFRESH IMMEDIATE

DB2 把 ON COMMIT MV 叫做 **MQT (Materialized Query Table) with REFRESH IMMEDIATE**:

```sql
CREATE TABLE sales_daily AS (
    SELECT
        region_id,
        DATE(ordered_at) AS day,
        SUM(amount)      AS revenue,
        COUNT(*)         AS order_count
    FROM orders
    GROUP BY region_id, DATE(ordered_at)
)
DATA INITIALLY DEFERRED
REFRESH IMMEDIATE        -- 事务提交时立即刷新
ENABLE QUERY OPTIMIZATION;
```

DB2 与 Oracle 的实现核心相似——staging table 捕获基表变更,commit 时增量应用到 MV。但 DB2 把这个表显式暴露给用户(可以查询 staging 表内容),Oracle MV LOG 是隐藏的内部对象。

### SQL Server 索引视图:语义上的 ON COMMIT

SQL Server 的"索引视图" (Indexed View) 没有 `ON COMMIT` 关键字,但**语义上等价于"每条 DML 同步触发"**——比 Oracle 的 ON COMMIT 还要严格:

```sql
CREATE VIEW dbo.sales_daily
WITH SCHEMABINDING  -- 必须 SCHEMABINDING
AS
SELECT
    region_id,
    CAST(ordered_at AS DATE) AS day,
    SUM(amount)              AS revenue,
    COUNT_BIG(*)             AS order_count  -- COUNT_BIG 必需
FROM dbo.orders
GROUP BY region_id, CAST(ordered_at AS DATE);

-- 创建唯一聚集索引使其"物化"
CREATE UNIQUE CLUSTERED INDEX ix_sales_daily_clu
    ON dbo.sales_daily (region_id, day);
```

行为:任何对 `dbo.orders` 的 INSERT/UPDATE/DELETE 都会**在同一语句内**同步更新 `sales_daily` 的索引数据。这是比 Oracle ON COMMIT 还要"激进"的同步——根本不等到 commit。

代价:严格的限制(`WITH SCHEMABINDING`、不能用某些函数、JOIN 必须 inner、聚合必须含 `COUNT_BIG`、确定性函数)和写入放大(每行 INSERT 都触发 MV 维护)。

### OceanBase 的 Oracle 兼容 ON COMMIT MV

OceanBase 4.x 在 Oracle 兼容模式下完整实现了 `REFRESH FAST ON COMMIT`:

```sql
-- OceanBase Oracle 模式
CREATE MATERIALIZED VIEW sales_daily
REFRESH FAST ON COMMIT
AS
SELECT region_id, COUNT(*), SUM(amount), COUNT(amount)
FROM orders
GROUP BY region_id;
```

这是迁移 Oracle 工作负载到 OceanBase 的关键能力。在 MySQL 模式下,OceanBase 的 MV 支持较弱,不支持 ON COMMIT。

### PostgreSQL 与其他引擎:为什么不支持 ON COMMIT MV?

PostgreSQL 至今(17)不支持 `REFRESH ON COMMIT`。设计取舍:

1. **PostgreSQL MV 是全量重算模型** —— 没有"增量维护"机制(MVCC 让 IVM 实现复杂),所以 ON COMMIT 必然是 COMPLETE,代价不可接受
2. **生态用 `pg_ivm` 扩展弥补** —— 第三方扩展实现了 IVM,但仍不支持 ON COMMIT
3. **未来方向** —— PostgreSQL 社区曾多次讨论 IVM,但因为补丁规模庞大、影响 MVCC 内核,一直未合入主线

Snowflake、BigQuery 等云数仓不需要 ON COMMIT,因为它们的"自动维护"已经在后台做了——查询时还能用 query-time merge 看到最新结果,等价于"事实上的 ON COMMIT"。

### 流式数据库:Materialize / RisingWave 的"事实 ON COMMIT"

Materialize 和 RisingWave 的物化视图是基于 differential dataflow 的连续维护,在概念上比 ON COMMIT 还要激进——基表变更**毫秒级**沿 dataflow 传播到 MV:

```sql
-- Materialize / RisingWave
CREATE MATERIALIZED VIEW sales_daily AS
SELECT
    region_id,
    date_trunc('day', ordered_at) AS day,
    SUM(amount) AS revenue
FROM orders
GROUP BY region_id, date_trunc('day', ordered_at);
```

这里没有 ON COMMIT 子句,但效果是"基表事务提交后,MV 几乎立刻反映新结果"。代价是所有 MV 状态常驻内存/磁盘,适合实时分析场景,不适合传统 ETL 批量。

## 延迟约束 (Deferred Constraints) 与 ON COMMIT

### SQL 标准定义

SQL:1992 定义了延迟约束的语法:

```sql
-- 创建 DEFERRABLE 约束
CREATE TABLE child (
    id        INT PRIMARY KEY,
    parent_id INT,
    CONSTRAINT fk_parent FOREIGN KEY (parent_id) REFERENCES parent(id)
        DEFERRABLE INITIALLY { IMMEDIATE | DEFERRED }
);

-- 会话内动态切换
SET CONSTRAINTS ALL { DEFERRED | IMMEDIATE };
SET CONSTRAINTS fk_parent { DEFERRED | IMMEDIATE };
```

三个关键概念:

- **`DEFERRABLE`**:声明约束**可以**被延迟检查,默认仍是 IMMEDIATE
- **`INITIALLY DEFERRED`**:声明约束**默认**是 DEFERRED 状态
- **`SET CONSTRAINTS ALL DEFERRED`**:在会话内临时把所有 DEFERRABLE 约束改为 DEFERRED 状态,直到 COMMIT 才检查

### PostgreSQL DEFERRABLE 约束

PostgreSQL 自 6.1 (1997) 就支持 DEFERRABLE 约束,是开源数据库中最早的实现:

```sql
-- 创建 DEFERRABLE 外键
CREATE TABLE orders (id INT PRIMARY KEY);
CREATE TABLE order_items (
    id       INT PRIMARY KEY,
    order_id INT NOT NULL,
    CONSTRAINT fk_order FOREIGN KEY (order_id) REFERENCES orders(id)
        DEFERRABLE INITIALLY DEFERRED
);

-- 现在可以反向插入
BEGIN;
INSERT INTO order_items (id, order_id) VALUES (1, 100);  -- 100 还不存在
INSERT INTO orders (id) VALUES (100);                     -- 现在创建
COMMIT;  -- 这里才检查 fk_order,通过

-- 如果约束违反:
BEGIN;
INSERT INTO order_items (id, order_id) VALUES (2, 999);  -- 999 不存在
COMMIT;  -- ERROR: insert or update on table "order_items" violates foreign key
```

PostgreSQL 唯一性约束也支持 DEFERRABLE:

```sql
CREATE TABLE positions (
    id    INT PRIMARY KEY,
    pos   INT,
    CONSTRAINT uq_pos UNIQUE (pos) DEFERRABLE INITIALLY DEFERRED
);

INSERT INTO positions VALUES (1, 100), (2, 200);

-- 交换两个位置(IMMEDIATE 模式下违反唯一约束)
BEGIN;
UPDATE positions SET pos = 200 WHERE id = 1;  -- 临时违反
UPDATE positions SET pos = 100 WHERE id = 2;  -- 恢复唯一性
COMMIT;  -- 通过
```

这是 DEFERRABLE 唯一约束的经典用例——位置/排序号交换,IMMEDIATE 模式必须借助临时占位值。

### Oracle DEFERRABLE 约束

Oracle 的 DEFERRABLE 约束语义与 PostgreSQL 几乎完全一致:

```sql
CREATE TABLE departments (
    dept_id   NUMBER PRIMARY KEY,
    parent_id NUMBER,
    CONSTRAINT fk_parent FOREIGN KEY (parent_id) REFERENCES departments(dept_id)
        DEFERRABLE INITIALLY DEFERRED
);

-- 自引用插入(创建组织树)
INSERT INTO departments (dept_id, parent_id) VALUES (1, 2);
INSERT INTO departments (dept_id, parent_id) VALUES (2, 1);  -- 循环引用
COMMIT;  -- 通过

-- 单约束切换
SET CONSTRAINT fk_parent IMMEDIATE;  -- 注意 Oracle 用 SET CONSTRAINT(单数)
SET CONSTRAINTS ALL DEFERRED;        -- 多个用复数
```

Oracle 还允许在事务级别动态切换:

```sql
ALTER SESSION SET CONSTRAINTS = DEFERRED;  -- 整个会话
```

### SQL Server:不支持 DEFERRABLE,变通方案有限

SQL Server 是主流商业数据库中**唯一不支持** `DEFERRABLE` 约束的。要实现"延迟检查"只能:

```sql
-- 方案 1:禁用约束(开销大,影响其他事务)
ALTER TABLE order_items NOCHECK CONSTRAINT fk_order;
INSERT INTO order_items VALUES (1, 100);
INSERT INTO orders VALUES (100);
ALTER TABLE order_items CHECK CONSTRAINT fk_order;  -- 重新启用并检查

-- 方案 2:全局开关(危险,影响并发会话)
SET FOREIGN_KEY_CHECKS = 0;  -- 这是 MySQL 语法,SQL Server 没有

-- 方案 3:重新设计表结构,使用应用层校验
```

这是 SQL Server 的长期痛点。微软在多个 Connect/Feedback 上承认这个问题但未排上路线图。

### MySQL:几乎没有 DEFERRABLE 支持

MySQL/InnoDB 不支持 `DEFERRABLE` 约束。唯一能"延迟"外键检查的方法是全局变量:

```sql
SET FOREIGN_KEY_CHECKS = 0;
-- 任意操作,FK 不检查
INSERT INTO order_items (id, order_id) VALUES (1, 999);
SET FOREIGN_KEY_CHECKS = 1;
-- 注意:重新启用时 NOT 验证现有数据,违反约束的行残留!
```

这与 SQL 标准的 DEFERRABLE 完全不同——`FOREIGN_KEY_CHECKS = 0` 只是"绕过"而非"延迟",而且影响整个会话(其他事务的检查也被影响)。

### SQLite 的 PRAGMA defer_foreign_keys

SQLite 的实现介于两者之间:

```sql
-- 启用外键检查
PRAGMA foreign_keys = ON;

-- 在事务内延迟外键检查
BEGIN;
PRAGMA defer_foreign_keys = ON;  -- 仅当前事务内有效
INSERT INTO order_items VALUES (1, 999);
INSERT INTO orders VALUES (999);
COMMIT;  -- 这时才检查
```

`PRAGMA defer_foreign_keys = ON` 是事务级开关,COMMIT 后自动重置。这模拟了 `SET CONSTRAINTS ALL DEFERRED` 的效果,但只针对外键,不支持唯一约束等其他约束类型。

### 延迟约束在批量加载场景的应用

延迟约束最大的实用价值在 **ETL 批量加载** 中——多张相关表的数据需要原子性加载,但 IMMEDIATE 模式下 INSERT 顺序受外键约束:

```sql
-- 批量加载父子表(使用延迟约束)
BEGIN;
SET CONSTRAINTS ALL DEFERRED;

-- 任意顺序加载,不受外键约束
COPY order_items FROM '/data/items.csv' CSV;     -- 引用了未加载的 order_id
COPY orders      FROM '/data/orders.csv' CSV;    -- 现在加载父表
COPY customers   FROM '/data/customers.csv' CSV; -- 同样

COMMIT;  -- 一次性检查所有约束
```

如果不用延迟约束,必须按依赖顺序逐表加载(customers → orders → order_items),且无法用并行加载。

### 性能与陷阱

#### 延迟约束的性能代价

- **PostgreSQL/Oracle**:每条 DML 仍然记录"待检查"信息(称为 deferred trigger queue),COMMIT 时一次性扫描所有待检查项。如果事务内有大量插入,这个队列可能消耗显著内存
- **检查代价不变**:延迟只是改变检查时机,不减少检查工作量。10 万条 INSERT 延迟到 COMMIT 检查,与每条 INSERT 立即检查,总计算量相近
- **错误回滚代价高**:延迟检查发现违反时,整个事务必须回滚——10 万条 INSERT 全部撤销,代价远高于 IMMEDIATE 模式下早早失败

#### 死锁风险

```sql
-- Session 1
BEGIN;
SET CONSTRAINTS ALL DEFERRED;
INSERT INTO order_items VALUES (1, 100);
-- 持有 order_items 的行锁,但因为延迟,不立即检查 orders(100)

-- Session 2
BEGIN;
INSERT INTO orders VALUES (100);
-- 持有 orders 的行锁

-- Session 1
COMMIT;
-- 现在检查 fk_order → 需要读 orders(100),被 Session 2 锁住
-- 等待 Session 2

-- Session 2
COMMIT;
-- 不需要新锁,直接 commit
-- Session 1 解锁后可以继续 commit

-- 但如果两个 session 互相等待,就是死锁
```

### 各引擎延迟约束语法对比

```sql
-- PostgreSQL / Oracle / OceanBase / GaussDB / Yugabyte / Greenplum / Citus / Yellowbrick
ALTER TABLE child ADD CONSTRAINT fk
    FOREIGN KEY (pid) REFERENCES parent(id)
    DEFERRABLE INITIALLY DEFERRED;
SET CONSTRAINTS ALL DEFERRED;

-- SQLite
PRAGMA foreign_keys = ON;
BEGIN;
PRAGMA defer_foreign_keys = ON;

-- MySQL (变通)
SET FOREIGN_KEY_CHECKS = 0;
-- ... DML ...
SET FOREIGN_KEY_CHECKS = 1;

-- DB2 11.5+
ALTER TABLE child ADD CONSTRAINT fk
    FOREIGN KEY (pid) REFERENCES parent(id)
    NOT ENFORCED;  -- DB2 的语法不同,而是 NOT ENFORCED
-- DB2 11.5+ 加入了部分 DEFERRABLE 语法

-- H2 (全局开关,非真正延迟)
SET REFERENTIAL_INTEGRITY FALSE;
-- ... DML ...
SET REFERENTIAL_INTEGRITY TRUE;

-- SQL Server (无 DEFERRABLE,只能临时禁用)
ALTER TABLE child NOCHECK CONSTRAINT fk;
-- ... DML ...
ALTER TABLE child WITH CHECK CHECK CONSTRAINT fk;
```

## 实战:三个 ON COMMIT 经典场景

### 场景 1:批量加载循环外键

```sql
-- 银行账户系统:account 与 last_transaction 互相外键
CREATE TABLE account (
    account_id          INT PRIMARY KEY,
    last_transaction_id INT,
    CONSTRAINT fk_last_tx FOREIGN KEY (last_transaction_id)
        REFERENCES transaction(transaction_id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE transaction (
    transaction_id INT PRIMARY KEY,
    account_id     INT NOT NULL,
    amount         DECIMAL(15,2),
    CONSTRAINT fk_account FOREIGN KEY (account_id)
        REFERENCES account(account_id)
        DEFERRABLE INITIALLY DEFERRED
);

-- 同时加载,COMMIT 时验证
BEGIN;
INSERT INTO account VALUES (1, 1001);
INSERT INTO transaction VALUES (1001, 1, 500.00);
COMMIT;  -- 两个 FK 同时检查,通过
```

### 场景 2:Oracle GTT 用作存储过程中间结果

```sql
-- 创建一次,所有会话使用
CREATE GLOBAL TEMPORARY TABLE staging_orders (
    order_id    NUMBER,
    customer_id NUMBER,
    amount      NUMBER(10,2)
) ON COMMIT DELETE ROWS;

-- 存储过程
CREATE OR REPLACE PROCEDURE process_daily_orders AS
BEGIN
    -- 加载数据到 GTT
    INSERT INTO staging_orders
    SELECT order_id, customer_id, amount
    FROM raw_orders
    WHERE DATE(created_at) = TRUNC(SYSDATE);

    -- 复杂计算
    UPDATE summary_table s
    SET s.total = s.total + (
        SELECT SUM(amount) FROM staging_orders WHERE customer_id = s.customer_id
    );

    COMMIT;  -- 同时清空 staging_orders,避免下次执行残留
END;
/
```

### 场景 3:MV ON COMMIT 维护实时聚合

```sql
-- Oracle:实时维护订单汇总
CREATE MATERIALIZED VIEW LOG ON orders
    WITH ROWID, SEQUENCE (region_id, amount) INCLUDING NEW VALUES;

CREATE MATERIALIZED VIEW region_revenue
REFRESH FAST ON COMMIT
AS
SELECT region_id,
       COUNT(*) AS order_count,
       SUM(amount) AS revenue,
       COUNT(amount) AS amount_count  -- FAST 必需
FROM orders
GROUP BY region_id;

-- 查询永远新鲜
SELECT * FROM region_revenue;  -- 总是最新结果

-- 但 INSERT 性能下降
INSERT INTO orders VALUES (...);  -- 比无 MV 时慢 30-100%
COMMIT;  -- commit 时间比无 MV 时长
```

## ON COMMIT 在分布式数据库的挑战

分布式数据库实现 ON COMMIT 比单机难得多,因为:

```
单机 ON COMMIT DELETE ROWS:
  COMMIT 时:把临时段标记为可回收 → O(1)

分布式 ON COMMIT DELETE ROWS:
  COMMIT 时需要跨多个节点协调:
  1. 通知所有持有该临时表数据的节点
  2. 各节点本地清理
  3. 协调清理元数据
  4. 处理节点故障(部分清理失败如何处理?)
```

CockroachDB 选择只支持 PRESERVE ROWS(避免分布式清理协调);TiDB 通过把临时表数据放在 TiDB Server 内存(非 TiKV)来简化;Snowflake/BigQuery 不支持 ON COMMIT(因为它们的事务模型不适合精细的 commit hook)。

### ON COMMIT MV 在分布式更难

OceanBase 是少数实现分布式 ON COMMIT MV 的引擎,代价是:

- 每次基表事务必须协调 MV 节点的更新
- 跨节点死锁概率显著增加
- 性能开销可能让分布式优势消失

OceanBase 的实现限制了 MV 与基表必须在同一 zone/tenant,以减少跨节点开销。

## 对引擎开发者的实现建议

### 1. ON COMMIT DELETE ROWS 的高效实现

```
反模式: COMMIT 时遍历表执行 DELETE
  代价: O(N) IO, 大表 commit 时间不可接受

推荐路径:
  1. 临时表数据放在独立的 segment/file
  2. ON COMMIT DELETE ROWS = 标记 segment 为可回收(O(1))
  3. 后续访问时自动跳过被回收的内容
  4. 后台异步释放空间

Oracle 的实现就是这个思路:每个会话的 GTT 数据在临时表空间的独立 segment,
COMMIT 时只是把 segment 标记可回收,不需要逐行 DELETE。
```

### 2. ON COMMIT MV 维护的事务集成

```
关键决策点:
  - MV 维护是否在用户事务内?
    YES: 用户能立即看到 MV 更新,但 commit 时间增加
    NO:  最终一致,commit 时间不变(但失去 ON COMMIT 语义)

  - MV 维护失败如何处理?
    严格语义: 整个事务回滚(Oracle 默认)
    宽松语义: MV 标记为陈旧,事务仍 commit

实现建议:
  - 把 MV 维护代码插入到 commit pipeline 的 prepare 阶段
  - 提供 session 级开关让用户可以在性能关键场景临时关闭
  - 对死锁要有快速检测和清晰错误信息
```

### 3. DEFERRABLE 约束的延迟检查队列

```
设计要点:
  - 每个事务维护一个待检查队列(deferred trigger queue)
  - 每条 DML 后,把违反检查请求放入队列(而非立即检查)
  - COMMIT 时统一扫描队列

PostgreSQL 实现细节:
  - 用 trigger 系统统一表达约束检查
  - DEFERRED trigger 在 commit 前的一个 invocation 里执行
  - 检查失败时,事务标记为不可 commit,执行 ROLLBACK

性能优化:
  - 队列中的重复检查请求合并(同一行多次 UPDATE)
  - 大事务的队列内存限制(避免 OOM)
  - 提供 SET LOCAL deferred_trigger_queue_size 等会话级控制
```

### 4. SQL 标准 vs 工业实现的取舍

```
SQL 标准 ON COMMIT DELETE ROWS 是默认值,但许多引擎选择了 PRESERVE ROWS:

PostgreSQL: PRESERVE ROWS (友好)
Oracle:     DELETE ROWS  (标准)
DB2:        DELETE ROWS  (标准)
Teradata:   DELETE ROWS  (标准)

建议:
  - 新引擎应明确文档化默认值
  - 如果选择非标准默认,提供配置项允许切换
  - 在 EXPLAIN 输出中标明 ON COMMIT 行为
```

### 5. 测试要点

```
ON COMMIT DELETE ROWS 测试:
  - 事务内 INSERT + COMMIT,验证清空
  - 事务内 INSERT + ROLLBACK,验证回滚后数据消失
  - 嵌套事务/savepoint 中的行为
  - 并发会话不应互相影响(GTT 数据隔离)

DEFERRABLE 约束测试:
  - INITIALLY DEFERRED 默认延迟到 commit
  - SET CONSTRAINTS 切换在事务内生效
  - COMMIT 时违反应回滚整个事务
  - 并发事务的延迟检查不应死锁(简单情况)

ON COMMIT MV 测试:
  - INSERT/UPDATE/DELETE 后 commit,MV 立即反映变更
  - 事务回滚后 MV 不更新
  - 多张基表的复合事务,MV 一致性
  - 并发事务中的 MV 维护正确性
```

## 关键发现

1. **`ON COMMIT` 是 SQL:1992 引入临时表时定义的关键字,标准默认值是 `DELETE ROWS`**。但实际工业界默认值分歧大——Oracle/DB2/Teradata 严格遵守标准,PostgreSQL 系列(PG/Greenplum/Yugabyte/Citus/TimescaleDB/Redshift)选择了 `PRESERVE ROWS` 作为更"友好"的默认。这是 SQL 标准与实现差异最显著的案例之一。

2. **45+ 引擎中,真正实现完整临时表 `ON COMMIT` 子句的约 22 个**。SQL Server、MySQL、SQLite、Snowflake、BigQuery、DuckDB 等"主流"引擎都不支持——它们的临时表只有"会话结束清空"这一种语义,需要事务级清空时只能手动 `TRUNCATE`。

3. **`REFRESH ON COMMIT` 物化视图的工业实现极少**——只有 Oracle、DB2、OceanBase 三家有完整的语法支持。SQL Server 索引视图是"语义等价"但没有这个关键字,Snowflake/BigQuery 用后台异步替代,流式数据库(Materialize/RisingWave)是"事实上 ON COMMIT"。这反映了一个工业现实:同步 MV 维护的代价太高,绝大部分引擎选择最终一致性。

4. **PostgreSQL 是 `DEFERRABLE` 约束开源实现的标杆,Oracle 是商业领域的标杆**。SQL Server 至今(2022)不支持 DEFERRABLE 约束,这是它的长期痛点。MySQL 只能通过全局开关 `FOREIGN_KEY_CHECKS=0` 变通(且不是延迟而是绕过)。

5. **延迟约束的真实价值在 ETL 与循环外键场景**——批量加载多张相关表时,DEFERRABLE 让加载顺序不再受外键拓扑约束;银行账户与 last_transaction 互相引用的循环外键也只有 DEFERRABLE 才能优雅处理。

6. **分布式数据库实现 ON COMMIT 异常困难**——CockroachDB 只支持 PRESERVE ROWS,TiDB 把数据放 TiDB Server 内存绕过分布式清理,云数仓直接放弃 ON COMMIT。这是 ON COMMIT 在云原生时代的尴尬:它的语义假设了"集中协调的 commit",分布式架构下代价不成比例。

7. **Oracle GTT 默认 `ON COMMIT DELETE ROWS` 是迁移工程师最常踩的坑**——从 PostgreSQL/SQL Server 迁移过来,以为临时表数据会保留到会话结束,结果发现每次 commit 后查不到数据。反向迁移(Oracle → PG)同样有坑——PG 默认 PRESERVE ROWS,导致以前依赖 commit 自动清空的逻辑不再正确。

8. **`ON COMMIT DROP` 是 PostgreSQL 引入的"超集"语义**——SQL 标准只有 DELETE/PRESERVE,DROP 是 PG 扩展。优势是"用完即焚",不在 catalog 里留遗骸,适合短期脚本场景。Oracle 18c+ PTT 的 `ON COMMIT DROP DEFINITION` 是同一思想的不同语法表达。

9. **ON COMMIT MV 的 INSERT 性能开销巨大**(Oracle 报告 30-300% 下降)。这让 ON COMMIT MV 不适合 OLTP 主表,通常用于汇总/字典维度等低写入频率的辅助表。云原生时代的"自动后台维护 + 查询时融合"(Snowflake/BigQuery)是更现代的解法。

10. **`SET CONSTRAINTS ALL DEFERRED` 是会话级动态切换工具**,但被严重低估。许多 ETL 框架在 batch load 内手动 disable/enable 约束,其实 PostgreSQL/Oracle 都有更优雅的 SET CONSTRAINTS 切换。后者不需要 DDL 权限,且自动在事务边界恢复。

## 参考资料

- ISO/IEC 9075-2:1992 §11.5 (Temporary table descriptors)
- ISO/IEC 9075-2:2003 §11.4 (Table definition with ON COMMIT)
- PostgreSQL: [CREATE TABLE - ON COMMIT](https://www.postgresql.org/docs/current/sql-createtable.html)
- PostgreSQL: [SET CONSTRAINTS](https://www.postgresql.org/docs/current/sql-set-constraints.html)
- Oracle: [Materialized View ON COMMIT REFRESH](https://docs.oracle.com/en/database/oracle/oracle-database/19/dwhsg/refreshing-materialized-views.html)
- Oracle: [CREATE GLOBAL TEMPORARY TABLE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-TABLE.html)
- Oracle: [Constraints DEFERRABLE](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/data-integrity.html)
- DB2: [Materialized Query Tables (MQT)](https://www.ibm.com/docs/en/db2/11.5?topic=tables-materialized-query)
- DB2: [Declared Global Temporary Tables](https://www.ibm.com/docs/en/db2/11.5?topic=tables-declared-temporary)
- SQL Server: [Indexed Views](https://learn.microsoft.com/en-us/sql/relational-databases/views/create-indexed-views)
- SQL Server: [Temporary Tables](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-table-transact-sql)
- Teradata: [VOLATILE TABLE](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Data-Definition-Language-Detailed-Topics)
- TiDB: [Temporary Tables](https://docs.pingcap.com/tidb/stable/temporary-tables)
- OceanBase: [ON COMMIT 物化视图](https://www.oceanbase.com/docs/)
- CockroachDB: [Temporary Tables](https://www.cockroachlabs.com/docs/stable/temporary-tables.html)
- SQLite: [Defer Foreign Keys](https://www.sqlite.org/pragma.html#pragma_defer_foreign_keys)
- ClickHouse: [Materialized Views](https://clickhouse.com/docs/en/sql-reference/statements/create/view)
- Materialize: [Materialized Views](https://materialize.com/docs/sql/create-materialized-view/)
