# 自动提交模式 (Autocommit Modes)

每条 INSERT 都立即落盘还是等到 COMMIT？这是数据库使用者最容易踩坑的语义差异——同一段应用代码在 MySQL 上跑得好好的，迁到 Oracle 上突然丢数据，根因往往就是自动提交模式不同。

## 隐式事务边界与跨引擎差异

自动提交（Autocommit）决定了**事务的隐式边界**：

- **Autocommit ON**：每条 SQL 语句自动构成一个独立事务，执行成功后立即 COMMIT。无需显式 `BEGIN`/`COMMIT`。
- **Autocommit OFF**：第一条 SQL 隐式开启事务，必须显式 `COMMIT` 或 `ROLLBACK` 才能结束。这种模式称为 **chained mode**（连锁事务模式）。

关键事实：**默认值在不同引擎之间差异极大**，且这种差异会引发隐蔽的应用层 bug。

```
| 引擎          | 默认 autocommit |
|---------------|-----------------|
| MySQL         | ON              |
| PostgreSQL    | ON (libpq)      |
| Oracle        | OFF (唯一)      |
| SQL Server    | ON              |
| DB2           | ON (新版)       |
| SQLite        | ON              |
```

典型 ORM 引发的 bug 场景：

```python
# Django + Oracle: 应用直接执行 raw SQL 但没有 COMMIT
cursor.execute("UPDATE accounts SET balance = balance - 100 WHERE id = 1")
# 在 MySQL 上正常工作（自动提交），在 Oracle 上数据"消失"
# 实际上数据在事务中，连接关闭时被回滚
```

```java
// JDBC: connection.setAutoCommit() 默认值是 true
// 但若在事务中忘记 commit, 连接归还到池后下一个请求"看到"未提交数据
Connection conn = dataSource.getConnection();
// 应用 A: 调用 setAutoCommit(false) 后未恢复
conn.setAutoCommit(false);
// 应用 B: 从同一连接池获取连接, 默认认为 autocommit=true, 实际为 false
```

## SQL 标准定义

### SQL:1999 引入 SET AUTOCOMMIT

SQL:1999 标准在第 4.35.4 节中定义了 `SET SESSION CHARACTERISTICS` 子句，包含会话级的自动提交控制：

```sql
<set session characteristics statement> ::=
    SET SESSION CHARACTERISTICS AS <session characteristic list>

<session characteristic> ::=
    <session transaction characteristics>
  | <transaction mode>

-- 部分 SQL 方言扩展定义了直接的 SET AUTOCOMMIT 语法
SET AUTOCOMMIT ON | OFF
SET AUTOCOMMIT = 1 | 0
```

但需注意：**SQL 标准没有强制规定默认值**，各引擎可自由选择。这是历史遗留问题——不同数据库在标准化之前已经形成了各自的传统。

### 标准的关键语义

1. **事务的开始**：第一条语句执行时隐式开启事务（除非显式 `START TRANSACTION` / `BEGIN`）
2. **事务的结束**：`COMMIT`、`ROLLBACK`、连接断开（隐式回滚）、DDL（部分引擎隐式提交）
3. **DDL 与自动提交**：MySQL/Oracle 中 DDL 语句**总是**隐式提交，与 autocommit 设置无关；PostgreSQL 中 DDL 是事务性的，遵循 autocommit 设置

## 默认模式支持矩阵（45+ 引擎）

### 主流关系数据库

| 引擎 | 默认 autocommit | 关闭语法 | 事务性 DDL |
|------|----------------|---------|----------|
| MySQL | ON (since 4.0, 2003) | `SET autocommit = 0` | 否（DDL 隐式提交） |
| MariaDB | ON (继承 MySQL) | `SET autocommit = 0` | 否（DDL 隐式提交） |
| PostgreSQL | ON (libpq) | `\set AUTOCOMMIT off` (psql) | 是（DDL 完全事务性） |
| Oracle | **OFF** (since v6+) | 默认行为，`SET AUTOCOMMIT ON` 启用 | 否（DDL 隐式提交） |
| SQL Server | ON | `SET IMPLICIT_TRANSACTIONS ON` | 是（部分） |
| DB2 (LUW) | ON (新版本) | `UPDATE COMMAND OPTIONS USING C OFF` | 是（部分） |
| DB2 (z/OS) | OFF（chained 默认） | -- | 是 |
| SQLite | ON | `BEGIN` 显式开启事务 | 是 |
| Sybase ASE | OFF（chained 模式） | `SET CHAINED ON/OFF` | 是 |
| Informix | ON / OFF（取决于数据库类型） | `SET AUTOCOMMIT ON/OFF` | 部分 |
| Firebird | OFF (默认 BEGIN) | -- | 是 |
| Interbase | OFF | `SET AUTOCOMMIT ON` | 是 |
| H2 | ON | `SET AUTOCOMMIT FALSE` | 是 |
| HSQLDB | ON | `SET AUTOCOMMIT FALSE` | 是 |
| Derby | ON | -- | 是 |

### 云数据仓库

| 引擎 | 默认 autocommit | 关闭语法 | 备注 |
|------|----------------|---------|------|
| Snowflake | ON | `ALTER SESSION SET AUTOCOMMIT = FALSE` | 显式 BEGIN/COMMIT 优先 |
| BigQuery | 隐式（每语句独立） | 不适用（无显式事务跨语句） | DML 内部事务化 |
| Redshift | ON | `SET autocommit = OFF` | 类 PostgreSQL |
| Azure Synapse | OFF（隐式事务） | `SET IMPLICIT_TRANSACTIONS OFF` | 类 SQL Server |
| Databricks SQL | ON | -- | Delta 表事务化 |
| Firebolt | ON | -- | -- |
| Yellowbrick | ON | `SET autocommit = OFF` | 类 PostgreSQL |
| Vertica | ON | `SET SESSION AUTOCOMMIT TO OFF` | -- |
| Greenplum | ON | 类 PostgreSQL | -- |
| ClickHouse | 不适用 | 无真正事务（实验性） | 仅单语句原子性 |

### 分布式 / NewSQL 数据库

| 引擎 | 默认 autocommit | 关闭语法 | 备注 |
|------|----------------|---------|------|
| CockroachDB | ON | `SET autocommit_before_ddl = false` | 类 PostgreSQL |
| TiDB | ON | `SET autocommit = 0` | 兼容 MySQL |
| YugabyteDB | ON | `\set AUTOCOMMIT off` | YSQL 兼容 PG |
| OceanBase | ON | `SET autocommit = 0` | 兼容 MySQL/Oracle 双模 |
| Spanner | 默认事务化 | 通过客户端控制 | 强一致 |
| SingleStore | ON | `SET autocommit = 0` | 兼容 MySQL |
| VoltDB | 单语句事务 | 不适用 | 存储过程为主 |
| FaunaDB | 不适用 | 函数式事务 API | 文档型 |

### 流处理 / 实时 OLAP

| 引擎 | 默认 autocommit | 关闭语法 | 备注 |
|------|----------------|---------|------|
| Doris | ON | `SET autocommit = 0` | 兼容 MySQL |
| StarRocks | ON | `SET autocommit = 0` | 兼容 MySQL |
| Apache Druid | 不适用 | 无 SQL 事务 | INSERT 异步 |
| Pinot | 不适用 | 无 SQL 事务 | -- |
| Materialize | ON | 类 PostgreSQL | 流物化视图 |
| RisingWave | ON | 类 PostgreSQL | -- |
| Flink SQL | 不适用 | 流式无事务概念 | 检查点替代 |
| QuestDB | 不适用 | 时序数据 | 微批提交 |
| TimescaleDB | ON | 继承 PostgreSQL | -- |
| InfluxDB SQL | 不适用 | -- | -- |

### 嵌入式 / 内存数据库

| 引擎 | 默认 autocommit | 关闭语法 | 备注 |
|------|----------------|---------|------|
| DuckDB | ON | `BEGIN TRANSACTION` 显式开启 | 单进程事务 |
| MonetDB | ON | `START TRANSACTION` 显式开启 | -- |
| SAP HANA | ON | `SET AUTOCOMMIT OFF` (JDBC) | -- |
| Exasol | ON | `SET AUTOCOMMIT OFF` | -- |
| Apache IoTDB | 不适用 | -- | 时序 |

### 总览统计

```
默认 ON（绝大多数）:    ~38 个引擎
默认 OFF（罕见）:        Oracle, Sybase, Firebird, Interbase, DB2 z/OS（约 5 个）
不适用（无真正事务）:    ClickHouse, BigQuery, Druid, Pinot, Flink 等（约 8 个）
```

**Oracle 的默认 OFF 是几乎独一无二的设计选择**——这一历史决策直接导致了今天许多跨数据库迁移问题。

## 会话级 SET AUTOCOMMIT 语法对比

### 标准化路径：SET AUTOCOMMIT

```sql
-- MySQL / MariaDB / TiDB / OceanBase / Doris / StarRocks
SET autocommit = 0;        -- 关闭
SET autocommit = 1;        -- 开启
SET @@autocommit = 0;      -- 等价语法
SET SESSION autocommit = 0;
SET GLOBAL autocommit = 0; -- 全局默认（影响新会话）

-- 查看当前值
SELECT @@autocommit;
SHOW VARIABLES LIKE 'autocommit';
```

### Oracle：客户端控制

Oracle 服务端**没有**会话级的 autocommit 概念，autocommit 完全由客户端工具实现：

```sql
-- SQL*Plus
SET AUTOCOMMIT ON;
SET AUTOCOMMIT OFF;
SET AUTOCOMMIT IMMEDIATE;     -- 同 ON
SET AUTOCOMMIT 10;             -- 每 10 条 DML 后自动提交（罕见用法）

-- 查看
SHOW AUTOCOMMIT;

-- 注意：服务端层面 Oracle 始终是事务性的
-- 应用通过 JDBC/OCI 客户端 API 控制 autocommit
-- 例如 JDBC: connection.setAutoCommit(true) 等价于每条语句后插入 COMMIT
```

这一设计反映了 Oracle 的设计哲学：**事务是数据库的核心，不应被简化掉**。

### PostgreSQL：psql 客户端 + JDBC 区分

PostgreSQL 服务端也没有 autocommit 的概念——服务端总是要么在事务中（显式 BEGIN 之后），要么处于"自动提交"状态（每语句独立事务）：

```sql
-- psql 命令行客户端
\set AUTOCOMMIT off
\set AUTOCOMMIT on
\echo :AUTOCOMMIT             -- 查看

-- libpq C 接口：默认每语句独立事务（autocommit ON）
-- 用 PQexec("BEGIN") 显式开启事务

-- JDBC：connection.setAutoCommit(false)
-- 等价于发送 BEGIN
```

### SQL Server：双模式

SQL Server 有两种事务模式：

```sql
-- 模式 1：autocommit (默认)
INSERT INTO t VALUES (1);    -- 自动提交
INSERT INTO t VALUES (2);    -- 自动提交

-- 模式 2：implicit transactions (chained mode)
SET IMPLICIT_TRANSACTIONS ON;
INSERT INTO t VALUES (1);    -- 隐式开启事务，未提交
INSERT INTO t VALUES (2);    -- 同一事务内
COMMIT;                       -- 必须显式 COMMIT

-- 模式 3：explicit transactions（任一模式下都可使用）
BEGIN TRANSACTION;
INSERT INTO t VALUES (1);
COMMIT;
```

### DB2：CHAINED / UNCHAINED

DB2 同时支持 chained 和 unchained 模式：

```sql
-- z/OS DB2: 默认 chained 模式
-- 一旦开始 SELECT/INSERT，必须 COMMIT 或 ROLLBACK 才能结束事务

-- LUW DB2: 默认 autocommit ON（命令行）
db2 update command options using c off  -- 关闭 autocommit
db2 update command options using c on   -- 开启 autocommit

-- 应用层（CLI/JDBC）：
-- SQLSetConnectAttr(SQL_ATTR_AUTOCOMMIT, SQL_AUTOCOMMIT_OFF)
```

### Sybase ASE：CHAINED 关键字

Sybase 是 chained mode 概念的经典代表：

```sql
SET CHAINED ON;        -- 进入 chained 模式（每语句开始事务）
SET CHAINED OFF;       -- unchained 模式（每语句立即提交，autocommit）

-- T-SQL 风格：BEGIN TRANSACTION 显式开启事务
BEGIN TRAN;
INSERT INTO t VALUES (1);
COMMIT;

-- 注意：CHAINED ON 时不能在事务内执行某些命令
```

### SQLite：autocommit + BEGIN

```sql
-- SQLite 默认 autocommit ON
-- 没有 SET AUTOCOMMIT 语法，通过 BEGIN/COMMIT 切换

INSERT INTO t VALUES (1);    -- autocommit
BEGIN;                        -- 显式开启事务
INSERT INTO t VALUES (2);
INSERT INTO t VALUES (3);
COMMIT;                       -- 提交

-- 检查是否在 autocommit 状态
-- C API: sqlite3_get_autocommit(db)  返回 1 表示在 autocommit 状态
```

### Snowflake：会话变量

```sql
ALTER SESSION SET AUTOCOMMIT = FALSE;
ALTER SESSION SET AUTOCOMMIT = TRUE;

-- 显式事务始终优先：BEGIN/COMMIT 不受 AUTOCOMMIT 设置影响
BEGIN;
INSERT INTO t VALUES (1);
INSERT INTO t VALUES (2);
COMMIT;

-- 全局默认（账户级）
ALTER ACCOUNT SET AUTOCOMMIT = FALSE;
```

### CockroachDB / YugabyteDB：兼容 PostgreSQL

```sql
-- CockroachDB
SET autocommit_before_ddl = false;   -- DDL 不再自动提交事务
BEGIN;
CREATE TABLE t (id INT);             -- 在事务内
INSERT INTO t VALUES (1);
COMMIT;

-- YugabyteDB (YSQL): 完全兼容 PostgreSQL
\set AUTOCOMMIT off
```

## 各引擎自动提交语义详解

### MySQL：ON 默认（since 4.0，2003）

MySQL 在 4.0 版本（2003 年）将 autocommit 默认值改为 ON，主要原因是简化 Web 应用开发——LAMP 时代大量应用是无状态短连接，每语句独立提交避免了"忘记 COMMIT"的问题。

```sql
-- 默认行为：每语句独立事务
INSERT INTO orders VALUES (1, 100);   -- 立即落盘
INSERT INTO orders VALUES (2, 200);   -- 立即落盘
-- 即使第二条失败，第一条也已提交

-- 关闭 autocommit（隐式事务）
SET autocommit = 0;
INSERT INTO orders VALUES (3, 300);   -- 隐式 BEGIN
INSERT INTO orders VALUES (4, 400);
COMMIT;                                -- 显式提交两条

-- DDL 永远隐式提交（重要！）
SET autocommit = 0;
INSERT INTO orders VALUES (5, 500);   -- 隐式 BEGIN
CREATE TABLE temp (id INT);            -- 隐式 COMMIT 之前的事务！
                                       -- 然后再隐式提交 CREATE
-- 此时 INSERT 已经提交，无法回滚

-- 临时切换到事务模式
START TRANSACTION;                     -- 强制开启事务
INSERT INTO orders VALUES (6, 600);
ROLLBACK;                              -- 回滚（即使 autocommit=1 也有效）
```

**MySQL autocommit 与 InnoDB 锁的关系**：autocommit ON 时每语句结束立即释放行锁；autocommit OFF 时锁持续到 COMMIT/ROLLBACK，可能加剧锁竞争。

### PostgreSQL：客户端层概念

PostgreSQL 的设计是：**服务端没有"autocommit 模式"**——服务端只关心当前是否在事务中。autocommit 是客户端协议层的封装：

```
客户端发送      服务端行为
-----------      -----------
INSERT ...      隐式 BEGIN; INSERT; COMMIT;  (autocommit ON)
BEGIN; INSERT;  显式 BEGIN; INSERT; (等待后续语句)
COMMIT;         COMMIT 当前事务
```

```sql
-- libpq 默认 autocommit ON
-- psql 默认也是 ON
\set AUTOCOMMIT off
INSERT INTO orders VALUES (1, 100);   -- psql 自动发送 BEGIN
                                       -- 必须显式 COMMIT
COMMIT;

-- 在显式 BEGIN/COMMIT 块内：不受 AUTOCOMMIT 影响
\set AUTOCOMMIT on
BEGIN;
INSERT INTO orders VALUES (2, 200);
INSERT INTO orders VALUES (3, 300);
COMMIT;                                -- 两条共同提交

-- DDL 是事务性的（与 MySQL/Oracle 不同）
BEGIN;
CREATE TABLE temp (id INT);
INSERT INTO temp VALUES (1);
ROLLBACK;                              -- 表不会被创建
```

### Oracle：autocommit OFF 的文化与历史原因

Oracle 自 v6（1988 年）起就采用**默认 autocommit OFF** 的设计，这一选择背后有深刻的历史与文化原因：

**1. 设计哲学：事务是核心**

Oracle 诞生于 OLTP 时代，主要客户是金融、电信等高一致性要求行业。设计者认为**每个 DML 都应该在显式事务中**，自动提交会让程序员"不思考事务"。

**2. 历史兼容：与 IBM DB2 z/OS 一致**

Oracle 早期版本受 IBM 大型机数据库影响——DB2 z/OS 也是 chained mode 默认。CODASYL 时代的数据库管理员习惯于显式事务。

**3. 一致性原则**

Oracle 主张：**应用代码不应依赖数据库默认值**。所有事务都应显式管理，避免在不同环境下行为不一致。

**4. 实际影响**

```sql
-- Oracle 服务端：不存在 autocommit 设置
INSERT INTO orders VALUES (1, 100);
-- 此时数据在事务中，未提交
-- 其他会话看不到这条数据

-- 必须显式 COMMIT
COMMIT;
-- 或显式 ROLLBACK
ROLLBACK;

-- 客户端 SQL*Plus 可设置（仍是客户端发送 COMMIT）
SET AUTOCOMMIT ON;
INSERT INTO orders VALUES (2, 200);
-- SQL*Plus 自动在后面附加 COMMIT;

-- DDL 在 Oracle 中隐式提交（与 MySQL 同）
INSERT INTO orders VALUES (3, 300);
CREATE TABLE temp (id INT);            -- 隐式 COMMIT 之前的 INSERT
-- 此时 INSERT 已提交
```

**Oracle 文档的措辞**："Oracle Database commits the current transaction implicitly under the following conditions: Before any Data Definition Language (DDL) statement, Normal end of a session, On issuing a COMMIT statement..."

### SQL Server：autocommit + IMPLICIT_TRANSACTIONS

SQL Server 的双模式设计：

```sql
-- 模式 A: autocommit (默认)
-- 等价于 SET IMPLICIT_TRANSACTIONS OFF
INSERT INTO orders VALUES (1, 100);   -- 立即提交
INSERT INTO orders VALUES (2, 200);   -- 立即提交

-- 模式 B: implicit transactions (chained)
SET IMPLICIT_TRANSACTIONS ON;
INSERT INTO orders VALUES (3, 300);   -- 自动 BEGIN
INSERT INTO orders VALUES (4, 400);   -- 同一事务
COMMIT;                                -- 显式提交

-- 检查当前模式
DBCC USEROPTIONS;                      -- 查看会话选项

-- 在显式 BEGIN/COMMIT 块内，两种模式行为相同
BEGIN TRANSACTION;
INSERT INTO orders VALUES (5, 500);
COMMIT;
```

**SET IMPLICIT_TRANSACTIONS 的关键语句**：以下 SQL Server 语句会**自动开启事务**（在 implicit transactions 模式下）：

```
ALTER TABLE        DELETE             FETCH
GRANT              INSERT             OPEN
REVOKE             SELECT             TRUNCATE TABLE
UPDATE             CREATE             DROP
```

### DB2：CHAINED / UNCHAINED 模式

```sql
-- DB2 z/OS: 默认 chained 模式
-- 类似 Oracle 的设计：所有 DML 隐式开始事务

-- DB2 LUW: 命令行 autocommit ON 默认
db2 +c "INSERT INTO orders VALUES (1, 100)"
-- +c 标志临时关闭 autocommit
-- -c 标志开启 autocommit

-- 应用程序中通过 CLI/JDBC 控制
-- C: SQLSetConnectAttr(hdbc, SQL_ATTR_AUTOCOMMIT, (SQLPOINTER)SQL_AUTOCOMMIT_OFF, 0);
-- Java: connection.setAutoCommit(false);

-- 显式事务（始终可用）
BEGIN ATOMIC
    INSERT INTO orders VALUES (1, 100);
    INSERT INTO orders VALUES (2, 200);
END;
```

### SQLite：通过 BEGIN 切换

```sql
-- SQLite 总是 autocommit ON
-- 没有"关闭 autocommit"的开关

INSERT INTO orders VALUES (1, 100);   -- 立即提交
INSERT INTO orders VALUES (2, 200);   -- 立即提交

-- 唯一方式：显式 BEGIN
BEGIN TRANSACTION;                     -- 进入"非 autocommit"状态
INSERT INTO orders VALUES (3, 300);
INSERT INTO orders VALUES (4, 400);
COMMIT;                                -- 回到 autocommit 状态

-- BEGIN IMMEDIATE: 立即获取写锁
BEGIN IMMEDIATE;
-- BEGIN EXCLUSIVE: 排他锁
BEGIN EXCLUSIVE;

-- C API 检查:
-- int sqlite3_get_autocommit(sqlite3*);  // 1=autocommit, 0=in transaction
```

### Snowflake：可配置 autocommit

```sql
-- 默认 ON
INSERT INTO orders VALUES (1, 100);   -- 立即提交

-- 关闭
ALTER SESSION SET AUTOCOMMIT = FALSE;
INSERT INTO orders VALUES (2, 200);   -- 隐式 BEGIN
INSERT INTO orders VALUES (3, 300);
COMMIT;

-- Snowflake 特殊：DDL 隐式提交（类 MySQL）
ALTER SESSION SET AUTOCOMMIT = FALSE;
INSERT INTO orders VALUES (4, 400);
CREATE TABLE temp (id INT);            -- 提交之前的事务

-- 显式事务始终优先
ALTER SESSION SET AUTOCOMMIT = TRUE;
BEGIN;                                 -- 即使 autocommit=ON 也开启显式事务
INSERT INTO orders VALUES (5, 500);
INSERT INTO orders VALUES (6, 600);
COMMIT;
```

### ClickHouse：无真正事务

ClickHouse 不支持传统意义上的多语句事务（实验性功能除外）：

```sql
-- 单个 INSERT 是原子的（max_insert_block_size 内）
INSERT INTO events VALUES (1, 'a'), (2, 'b'), (3, 'c');  -- 全部成功或全部失败

-- 多语句"事务"（仅限同一连接）
SET implicit_transaction = 1;          -- 实验性
BEGIN TRANSACTION;
INSERT INTO events ...;
INSERT INTO events ...;
COMMIT;                                -- 实际上每个语句仍可能独立可见
```

ClickHouse 设计为分析型数据库，吞吐量优先，弱事务隔离换取写入性能。

### MariaDB：完全继承 MySQL

```sql
-- MariaDB 完全兼容 MySQL 的 autocommit 模型
SET autocommit = 0;
SET autocommit = 1;
SELECT @@autocommit;

-- DDL 语句也是隐式提交
-- InnoDB / Aria / MyRocks 引擎遵循相同语义
```

### CockroachDB：PostgreSQL 兼容

```sql
-- 默认 autocommit ON（兼容 PG）
-- 但 CockroachDB 是分布式的，事务跨节点

SET autocommit_before_ddl = false;     -- 关闭 DDL 自动提交（CRDB 22+）

BEGIN;
CREATE TABLE t (id INT);
INSERT INTO t VALUES (1);
COMMIT;                                -- 整个事务跨节点 2PC
```

### TiDB：MySQL 兼容

```sql
-- 完全兼容 MySQL 的 SET autocommit 语法
SET autocommit = 0;
SET autocommit = 1;

-- 但 TiDB 内部是分布式 OCC（乐观并发控制）
-- autocommit=1 时每语句一个迷你事务
-- 大事务可能因冲突重试失败
```

### YugabyteDB：YSQL 接口

```sql
-- YSQL（PostgreSQL 兼容接口）
\set AUTOCOMMIT off

-- YCQL（Cassandra 兼容接口）：无 SQL 事务概念
```

### OceanBase：双模兼容

```sql
-- MySQL 兼容模式
SET autocommit = 0;

-- Oracle 兼容模式
-- 默认 autocommit OFF（与 Oracle 一致）
COMMIT;
```

## JDBC：connection.setAutoCommit() 与默认值

JDBC 规范明确定义 `Connection.getAutoCommit()` 的**默认值是 true**：

```java
// JDBC 标准默认值
Connection conn = DriverManager.getConnection(url, user, pass);
boolean isAutoCommit = conn.getAutoCommit();   // 默认 true

// 标准模式：autocommit ON
conn.setAutoCommit(true);
PreparedStatement ps = conn.prepareStatement("INSERT INTO orders VALUES (?, ?)");
ps.setInt(1, 1);
ps.setInt(2, 100);
ps.executeUpdate();                            // 立即提交

// 关闭 autocommit
conn.setAutoCommit(false);
ps.executeUpdate();                            // 隐式 BEGIN
ps.executeUpdate();
conn.commit();                                 // 显式提交

// 关键点：Oracle JDBC 也是默认 autocommit=true
// 这与 Oracle 服务端默认 OFF 相反
// JDBC 驱动通过自动发送 COMMIT 实现
```

### JDBC 默认值的隐患

```java
// 连接池场景的常见 bug
DataSource ds = new HikariDataSource(...);

// 应用 A
Connection conn = ds.getConnection();
conn.setAutoCommit(false);                     // 关闭 autocommit
conn.prepareStatement("INSERT...").executeUpdate();
// 忘记调用 conn.commit() 或 conn.setAutoCommit(true)
conn.close();                                  // 归还到池
                                               // HikariCP 默认会回滚未提交事务

// 应用 B（同一连接池）
Connection conn = ds.getConnection();          // 获取同一物理连接
boolean ac = conn.getAutoCommit();             // 期望 true，实际为 false！
conn.prepareStatement("INSERT...").executeUpdate();
conn.close();                                  // 数据丢失（被回滚）
```

**最佳实践**：连接池配置中强制重置 autocommit。HikariCP 的 `autoCommit` 属性默认为 true，归还连接前会重置；但 c3p0/DBCP 行为不同。

### 各 JDBC 驱动差异

```java
// MySQL Connector/J
// - 默认 autocommit=true（JDBC 标准）
// - useAutoCommit URL 参数可影响初始值

// PostgreSQL JDBC
// - 默认 autocommit=true
// - autosave URL 参数与 SAVEPOINT 配合

// Oracle JDBC (ojdbc)
// - 默认 autocommit=true（即使 Oracle 服务端默认 OFF）
// - 驱动在每个 executeUpdate() 后发送 COMMIT
// - autoCommitSpecCompliant 控制 batch 行为

// Microsoft JDBC for SQL Server
// - 默认 autocommit=true
// - 通过 SET IMPLICIT_TRANSACTIONS ON 切换

// SQLite JDBC
// - 默认 autocommit=true
// - setAutoCommit(false) 等价于发送 BEGIN
```

## ORM 与自动提交模式的交互

ORM 框架通常**强制关闭** autocommit，因为 ORM 需要在事务中执行多个相关操作（关联加载、级联保存）。

### Hibernate / JPA

```java
// JPA 标准：每个 EntityManager 操作都在事务中
@PersistenceContext
private EntityManager em;

@Transactional
public void transfer(Long fromId, Long toId, BigDecimal amount) {
    Account from = em.find(Account.class, fromId);
    Account to = em.find(Account.class, toId);

    from.setBalance(from.getBalance().subtract(amount));
    to.setBalance(to.getBalance().add(amount));
    // 事务提交时自动 flush 所有变更
}

// Hibernate 通过 connection.setAutoCommit(false) 实现
// 即使数据库默认 autocommit=ON，Hibernate 也会强制关闭
```

### Django ORM

```python
# Django 默认每个 HTTP 请求一个事务（atomic_requests=True）
from django.db import transaction

# 显式事务
with transaction.atomic():
    Account.objects.filter(id=1).update(balance=F('balance') - 100)
    Account.objects.filter(id=2).update(balance=F('balance') + 100)
# 自动 COMMIT，异常时 ROLLBACK

# 但 raw SQL 是危险的
from django.db import connection
cursor = connection.cursor()
cursor.execute("UPDATE accounts SET balance = balance - 100 WHERE id = 1")
# 在 atomic 块外，依赖数据库的 autocommit 设置
# 在 Oracle 上可能不会立即生效
```

### SQLAlchemy

```python
from sqlalchemy import create_engine

# SQLAlchemy 默认 autocommit=False（"begin once"模式）
engine = create_engine("postgresql://...")
with engine.connect() as conn:
    conn.execute(text("INSERT INTO orders VALUES (1, 100)"))
    conn.commit()                              # 必须显式 commit

# 旧版 autocommit 模式（已废弃）
# engine = create_engine("postgresql://...", isolation_level="AUTOCOMMIT")

# 显式事务
with engine.begin() as conn:                   # 自动 commit/rollback
    conn.execute(text("INSERT ..."))
```

### Spring 事务管理

```java
@Service
public class TransferService {
    @Autowired
    private DataSource dataSource;

    @Transactional                             // Spring AOP 拦截
    public void transfer(Long fromId, Long toId, BigDecimal amount) {
        // 方法开始：connection.setAutoCommit(false)
        jdbcTemplate.update("UPDATE accounts SET balance = balance - ? WHERE id = ?",
                            amount, fromId);
        jdbcTemplate.update("UPDATE accounts SET balance = balance + ? WHERE id = ?",
                            amount, toId);
        // 方法结束：connection.commit() + setAutoCommit(true)
    }
}

// 危险的 @Transactional 嵌套
@Transactional(propagation = Propagation.REQUIRES_NEW)
public void newTx() { ... }  // 会创建新连接（或新事务），autocommit 切换可能引发问题
```

### MyBatis

```xml
<!-- MyBatis SqlSessionFactory 配置 -->
<environment id="production">
    <transactionManager type="JDBC"/>
    <!-- 默认每个 SqlSession 独立事务 -->
</environment>

<!-- 应用代码 -->
<insert id="insertOrder">
    INSERT INTO orders VALUES (#{id}, #{amount})
</insert>
```

```java
SqlSession session = sqlSessionFactory.openSession();      // autoCommit=false 默认
try {
    OrderMapper mapper = session.getMapper(OrderMapper.class);
    mapper.insertOrder(order);
    session.commit();                          // 必须显式 commit
} finally {
    session.close();
}

// openSession(true)：autocommit=true
SqlSession session = sqlSessionFactory.openSession(true);
mapper.insertOrder(order);                     // 立即提交
```

## ORM 引发的隐蔽 Bug

### Bug 1: 长事务

```python
# Django 视图函数
@transaction.atomic
def long_running_view(request):
    user = User.objects.get(id=request.user.id)
    # 调用外部 API（可能耗时几秒）
    result = external_api.call()
    user.update(...)
    return JsonResponse(result)
# 事务持续整个 HTTP 请求，可能持有行锁数秒
# 高并发下导致连接池耗尽 + 数据库锁等待
```

### Bug 2: 连接复用

```java
// 错误：在 @Transactional 方法内调用 raw JDBC
@Transactional
public void wrongPattern() {
    repository.save(entity1);                  // Hibernate 事务

    // 直接获取新连接（脱离事务上下文）
    try (Connection conn = dataSource.getConnection()) {
        conn.createStatement().execute("INSERT INTO log VALUES (...)");
        // 这是另一个连接！autocommit=true，立即提交
        // 即使外层事务回滚，log 已落盘
    }
}
```

### Bug 3: Oracle 上忘记 COMMIT

```python
# 跨数据库迁移的经典 bug
import cx_Oracle

conn = cx_Oracle.connect("user/pass@db")
cursor = conn.cursor()

cursor.execute("UPDATE accounts SET balance = balance - 100 WHERE id = 1")
# Python DB-API 默认 autocommit=False
# Oracle 服务端也是事务模式
conn.close()
# 连接关闭 → 隐式 ROLLBACK → 数据"丢失"

# 正确做法
conn.commit()
conn.close()
```

```python
# 同样代码在 MySQL 上"看起来"工作
import mysql.connector

conn = mysql.connector.connect(...)
cursor = conn.cursor()
cursor.execute("UPDATE accounts SET balance = balance - 100 WHERE id = 1")
conn.close()
# Python DB-API 默认 autocommit=False
# 但某些 MySQL 驱动连接关闭时不会回滚
# 加上 InnoDB 默认隔离级别 REPEATABLE READ 的特殊行为
# 数据可能"看起来"已写入
```

### Bug 4: 长连接 + autocommit 切换

```java
// HikariCP 连接池
HikariConfig config = new HikariConfig();
config.setAutoCommit(true);                    // 池层面默认 autocommit=true

DataSource ds = new HikariDataSource(config);

// 应用代码
try (Connection conn = ds.getConnection()) {
    conn.setAutoCommit(false);                 // 切换为 false
    // ... 业务逻辑 ...
    conn.commit();
    // 注意：HikariCP 在归还时会重置 autocommit 回 true
    // 但若中途异常未到 commit，需要 conn.rollback()
}
```

### Bug 5: 隐式 DDL 提交

```sql
-- MySQL 中的隐式提交陷阱
START TRANSACTION;
INSERT INTO orders VALUES (1, 100);
INSERT INTO orders VALUES (2, 200);

-- 突然来一句 DDL
ALTER TABLE orders ADD COLUMN created_at TIMESTAMP;
-- 隐式 COMMIT 之前的两条 INSERT！
-- 然后 ALTER 也立即生效

INSERT INTO orders VALUES (3, 300);
ROLLBACK;
-- 只回滚第三条 INSERT
-- 前两条 INSERT 已被 DDL 提交
```

```sql
-- PostgreSQL 中 DDL 是事务性的
BEGIN;
INSERT INTO orders VALUES (1, 100);
ALTER TABLE orders ADD COLUMN created_at TIMESTAMP;
INSERT INTO orders VALUES (2, 200);
ROLLBACK;
-- 全部回滚：表结构未改，两条 INSERT 都未生效
```

## DDL 与 Autocommit 的交互矩阵

| 引擎 | DDL 行为 | 事务内 DDL 后续 DML |
|------|---------|-------------------|
| MySQL/MariaDB | DDL **隐式提交** | DDL 后开启新隐式事务 |
| Oracle | DDL **隐式提交**（前后各一次） | DDL 后开启新事务 |
| SQL Server | DDL **事务性**（部分 DDL） | 同事务内继续 |
| PostgreSQL | DDL **完全事务性** | 同事务内继续 |
| DB2 | DDL **完全事务性** | 同事务内继续 |
| SQLite | DDL **事务性** | 同事务内继续 |
| Snowflake | DDL **隐式提交** | DDL 后开启新事务 |
| CockroachDB | DDL **事务性**（受配置） | 受 `autocommit_before_ddl` 影响 |
| Redshift | DDL **事务性** | 同事务内继续 |
| ClickHouse | 无事务概念 | 不适用 |

PostgreSQL 的事务性 DDL 是一大优势——可以在事务内安全测试 schema 变更，失败时整体回滚。

## Chained Mode（连锁事务模式）

Chained mode 起源于 Sybase / SQL Server 的设计，含义是：**事务首尾相连**——前一个事务结束时，下一个事务自动开始（一旦执行 DML/DDL）。

### Sybase ASE / SQL Server 历史

```sql
-- Sybase: SET CHAINED ON
SET CHAINED ON;

-- 第一个事务
INSERT INTO t VALUES (1);              -- 事务 1 自动开始
INSERT INTO t VALUES (2);
COMMIT;                                -- 事务 1 结束

-- 第二个事务自动开始
SELECT * FROM t;                       -- 事务 2 自动开始
COMMIT;                                -- 事务 2 结束

-- 与 unchained 模式（autocommit）对比
SET CHAINED OFF;
INSERT INTO t VALUES (1);              -- 立即提交（独立事务）
SELECT * FROM t;                       -- 立即结束（独立事务）
```

### Chained Mode 的优缺点

**优点**：
- 默认行为强迫程序员思考事务边界
- 减少"忘记 BEGIN"导致的数据不一致
- 与早期 OLTP 应用模式契合

**缺点**：
- 简单查询也开启事务，资源浪费
- 对短连接 Web 应用不友好
- 跨数据库代码迁移困难

### 现代支持情况

```
| 引擎 | Chained Mode 支持 |
|------|------------------|
| Sybase ASE | 原生（`SET CHAINED ON`） |
| SQL Server | `SET IMPLICIT_TRANSACTIONS ON` 等价 |
| Oracle | 默认行为（无需额外设置） |
| DB2 z/OS | 默认行为 |
| Azure Synapse | 类 SQL Server |
| 其他主流引擎 | 不直接支持，通过 autocommit=OFF 模拟 |
```

## 设计争议与思考

### 默认 ON 还是 OFF？

```
论点 A（默认 ON）：
+ 简化简单场景，符合 Web/REST 应用模式
+ 避免"忘记 COMMIT"导致的数据滞留
+ 单语句即原子，对新手友好
- 容易让人忽视事务的重要性
- 多语句事务需要显式 BEGIN

论点 B（默认 OFF）：
+ 强制思考事务边界，减少 bug
+ 与 OLTP/金融应用一致
+ 多语句事务无需 BEGIN
- 简单查询也开启事务，浪费资源
- 跨引擎迁移困难（行为差异大）
- "忘记 COMMIT" 直接丢数据
```

### Oracle 的"特立独行"代价

Oracle 默认 OFF 在过去 30 年成为大量应用迁移痛点：

- 从 MySQL/PG 迁移到 Oracle：忘记 COMMIT 导致数据"丢失"
- 从 Oracle 迁移到 MySQL：依赖事务的代码可能行为变化（DDL 在 Oracle 中隐式提交，迁移到 MySQL 还是隐式提交，但显式事务边界可能不同）
- ORM 框架必须维护针对每个数据库的方言适配

### 标准化进程

SQL 标准在这一问题上**模糊处理**：定义了 SET TRANSACTION 但没有强制默认值。这导致：

1. 各厂商保持自己的传统
2. JDBC 等中间层通过 `setAutoCommit()` 抽象
3. 应用代码不应依赖默认值——**必须显式设置**

### DDL 隐式提交的争议

MySQL/Oracle 的 DDL 隐式提交是历史限制（早期实现简化），但在现代数据库中已不必要。PostgreSQL 证明**事务性 DDL 可以工程实现**——通过将 catalog 修改也纳入 MVCC。

```
事务性 DDL 优势：
+ 多个 DDL 可原子回滚（migration 安全）
+ DDL 失败不会留下不一致的中间状态
+ schema 变更可与 DML 同事务

实现复杂度：
- catalog 表也需要 MVCC
- DDL 期间的查询需要快照隔离
- 锁升级策略复杂
```

## 关键发现 (Key Findings)

### 1. Oracle 默认 OFF 的独特性

在 45+ 主流引擎中，**只有 Oracle、Sybase、Firebird、DB2 z/OS 等少数引擎默认 OFF**。这种历史选择影响深远——
- ORM 框架必须为每种数据库定制 autocommit 处理逻辑
- 跨数据库迁移成本显著
- 培训文档必须强调"在 Oracle 上记得 COMMIT"

### 2. JDBC 的统一抽象

JDBC 规范明确 `connection.getAutoCommit() == true` 为默认值，**与底层数据库无关**：
- Oracle JDBC 驱动会在每个 DML 后发送 COMMIT，使 Oracle"看起来"是 autocommit
- 这一抽象大大降低了应用层复杂度
- 但 Oracle 服务端仍是事务模式，性能特征不变

### 3. ORM 几乎都强制关闭 autocommit

Hibernate、Django、SQLAlchemy、Spring `@Transactional` 等 ORM 框架在执行业务方法时都会调用 `setAutoCommit(false)`：
- 因为 ORM 需要原子性的多语句操作
- ORM 自己管理事务生命周期
- 应用层避免直接接触 autocommit 设置

### 4. DDL 行为是另一个隐藏变量

即使 autocommit 行为相同，DDL 行为也可能完全不同：
- MySQL/Oracle/Snowflake：DDL 隐式提交
- PostgreSQL/DB2/SQL Server：DDL 事务性
- 这意味着"在事务内执行 DDL"的语义跨引擎不同

### 5. ClickHouse 等分析型引擎根本没有事务

近年涌现的分析型引擎（ClickHouse、Pinot、Druid 等）**没有真正的多语句事务**：
- 单语句原子性 + 弱一致性换取吞吐量
- autocommit 概念不适用
- 应用层需要不同的容错设计

### 6. 连接池放大了 autocommit 的复杂度

HikariCP/c3p0 等连接池必须在归还连接时**重置** autocommit 状态：
- HikariCP 默认 `autoCommit=true` 并强制重置
- c3p0 通过 `autoCommitOnClose` 控制
- DBCP 通过 `defaultAutoCommit` + `enableAutoCommitOnReturn` 控制
- 配置不当会导致连接污染

### 7. 隐式事务边界是分布式数据库的难点

CockroachDB、TiDB、Spanner 等分布式数据库的 autocommit=ON 模式下：
- 每个语句一个迷你事务，跨节点 2PC 开销显著
- 高并发场景建议显式批量事务
- TiDB 引入"自动事务重试"缓解 OCC 冲突

### 8. autocommit 与隔离级别的交互

autocommit=ON 时每语句独立事务，**隔离级别基本不重要**（无并发可见性问题）。
autocommit=OFF 时长事务跨多个语句，隔离级别决定其他事务的可见性，对应用语义影响巨大。

### 9. 客户端工具与服务端的语义错位

PostgreSQL 服务端没有"autocommit"开关——这是 psql、JDBC 等**客户端协议层**的封装。
Oracle 服务端没有 autocommit——是 SQL*Plus / OCI / JDBC **客户端**实现的。
理解这一点对调试和性能分析至关重要：服务端日志只看得到 BEGIN/COMMIT，看不到客户端的 autocommit 切换。

### 10. autocommit 切换不是免费操作

从 ON 切到 OFF（或反之）涉及：
- 客户端发送 `SET autocommit = X` 语句
- 服务端会话状态变更
- 当前事务可能被强制提交或回滚（取决于引擎）

频繁切换 autocommit（如某些 ORM 实现）会导致性能下降。

## 引擎选型建议

| 场景 | 推荐设置 | 原因 |
|------|---------|------|
| Web 短连接应用 | autocommit=ON | 简化代码，单语句原子 |
| OLTP 长事务 | autocommit=OFF | 显式控制事务边界 |
| 数据迁移 | autocommit=OFF | 大批量提交一次，性能优 |
| 分析查询 | autocommit=ON | 只读查询无需事务 |
| ORM 框架 | 框架管理（通常 OFF） | 框架强制事务化 |
| 连接池 | 显式重置（ON） | 避免连接污染 |
| 跨数据库代码 | 始终显式管理 | 不依赖默认值 |

## 对引擎开发者的建议

### 1. 提供清晰的默认值文档

无论选择 ON 还是 OFF，**必须在主文档首页**明确说明，并附上 JDBC/ODBC 驱动的默认行为对照。

### 2. 客户端协议清晰区分

服务端协议中明确区分：
- "新事务边界"（implicit BEGIN）
- "显式事务"（explicit BEGIN）
- "自动提交"（每语句独立事务）

避免 PostgreSQL 那样的隐式封装造成调试困扰。

### 3. DDL 事务化

新引擎应优先实现**事务性 DDL**：
- catalog 表纳入 MVCC
- 提供安全的 schema 迁移能力
- 与现代 DevOps 流程契合

### 4. 显式提示长事务

当一个事务持续时间过长（如 > 30 秒）：
- 在错误日志中警告
- 暴露监控指标（idle in transaction）
- 配置自动 abort（PG 的 `idle_in_transaction_session_timeout`）

### 5. 连接池友好

会话级状态（包括 autocommit）应在 reset connection 命令中可一次性清除：
- MySQL 的 `COM_RESET_CONNECTION`
- PostgreSQL 的 `DISCARD ALL`
- 避免连接归还后状态污染

### 6. DBA 工具支持

提供监控视图：
- 当前会话 autocommit 状态
- 长时间未提交事务列表
- 锁等待与 autocommit 关联分析

## 总结对比矩阵

### 默认行为速查

| 引擎 | autocommit 默认 | DDL 事务化 | 特殊机制 |
|------|----------------|-----------|---------|
| MySQL | ON | 否 | DDL 隐式提交 |
| MariaDB | ON | 否 | 同 MySQL |
| PostgreSQL | ON (libpq) | 是 | 服务端无 autocommit 概念 |
| Oracle | OFF | 否 | 服务端无 autocommit，客户端模拟 |
| SQL Server | ON | 部分 | IMPLICIT_TRANSACTIONS 切换 |
| DB2 LUW | ON | 是 | CHAINED/UNCHAINED 模式 |
| DB2 z/OS | OFF | 是 | 默认 chained |
| SQLite | ON | 是 | 通过 BEGIN 切换 |
| Snowflake | ON | 否 | DDL 隐式提交 |
| ClickHouse | 不适用 | 不适用 | 无真正事务 |
| BigQuery | 不适用 | 不适用 | 单语句独立 |
| CockroachDB | ON | 可配置 | 兼容 PG |
| TiDB | ON | 否 | 兼容 MySQL |
| Sybase ASE | OFF (chained) | 是 | SET CHAINED ON/OFF |
| Firebird | OFF | 是 | 显式 BEGIN |

### 应用层最佳实践

```
1. 始终显式设置 autocommit（不依赖默认值）
2. 使用 ORM 时遵循框架的事务模型
3. 连接池配置中明确 autocommit 默认值
4. 跨数据库代码使用 JDBC/ODBC 等抽象层
5. 长事务监控与超时配置
6. DDL 操作单独提交（避免与 DML 混合）
7. 单元测试覆盖事务边界场景
```

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-2, Section 4.35.4 (Session characteristics)
- MySQL: [autocommit, Commit, and Rollback](https://dev.mysql.com/doc/refman/8.0/en/innodb-autocommit-commit-rollback.html)
- PostgreSQL: [Transactions in psql](https://www.postgresql.org/docs/current/app-psql.html)
- Oracle: [COMMIT and Implicit Transactions](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/COMMIT.html)
- SQL Server: [SET IMPLICIT_TRANSACTIONS](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-implicit-transactions-transact-sql)
- DB2: [Autocommit feature](https://www.ibm.com/docs/en/db2/11.5?topic=clp-autocommit-feature)
- SQLite: [Autocommit Mode](https://www.sqlite.org/c3ref/get_autocommit.html)
- Snowflake: [Autocommit](https://docs.snowflake.com/en/sql-reference/parameters#autocommit)
- JDBC API: [Connection.setAutoCommit()](https://docs.oracle.com/javase/8/docs/api/java/sql/Connection.html#setAutoCommit-boolean-)
- Sybase ASE: [Chained and Unchained Transaction Modes](https://infocenter.sybase.com/help/index.jsp?topic=/com.sybase.help.ase_15.0.transactions/html/transaxs/transaxs49.htm)
- HikariCP: [Configuration - autoCommit](https://github.com/brettwooldridge/HikariCP)
- Hibernate: [Transactions and Concurrency](https://docs.jboss.org/hibernate/orm/current/userguide/html_single/Hibernate_User_Guide.html#transactions)
- Django: [Database Transactions](https://docs.djangoproject.com/en/stable/topics/db/transactions/)
- SQLAlchemy: [Transaction Isolation Level](https://docs.sqlalchemy.org/en/20/core/connections.html#setting-transaction-isolation-levels-including-dbapi-autocommit)
- C.J. Date, "An Introduction to Database Systems" (8th ed., 2003), Chapter 16: Transaction Management
- Jim Gray, Andreas Reuter, "Transaction Processing: Concepts and Techniques" (1992)
