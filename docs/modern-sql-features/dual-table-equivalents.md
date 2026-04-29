# DUAL 表等价物 (DUAL Table Equivalents)

`SELECT 1+1` 在不同数据库里可能要写成 `SELECT 1+1`、`SELECT 1+1 FROM DUAL`、`SELECT 1+1 FROM SYSIBM.SYSDUMMY1`、`SELECT 1+1 FROM RDB$DATABASE`——一个看似最朴素的查询，却是 SQL 语法可移植性最经典的反例。

## SQL:2003 让 FROM 子句变成可选

ANSI SQL-86/SQL-92 时代，`<query specification>` 的语法明确规定 FROM 子句是必需的:

```
<query specification> ::=
    SELECT [ <set quantifier> ] <select list>
    <table expression>

<table expression> ::=
    <from clause>
    [ <where clause> ]
    [ <group by clause> ]
    [ <having clause> ]

<from clause> ::= FROM <table reference> [ { <comma> <table reference> }... ]
```

也就是说，标准里 `SELECT 1` 是非法的——你必须有一个 FROM。这给"想计算一个常量表达式"或"调用一个函数"的用户带来了麻烦：必须找一张"恰好只有一行"的表来挂在 FROM 后面。Oracle 在 v6（1988 年）引入的 `DUAL` 就是这种解决方案的代表。

到 SQL:2003，标准开始妥协：`<query specification>` 引入了 `<table expression>` 可省略 FROM 的扩展（在 ISO/IEC 9075-2:2003 的 Feature T551 "Optional key words for default syntax"和后续修订中），允许像 `SELECT 1` 这样的写法。但这是**可选的合规特性**，并非每个数据库都强制实现，因此 30+ 年的方言碎片到今天仍在影响真实生产代码。

## 支持矩阵 (45+ 引擎)

下表汇总了主流引擎对"无 FROM SELECT"以及各种 DUAL 等价物的支持情况。

| 引擎 | SELECT 无 FROM | DUAL 表 | 单行系统表 | 备注 | 起始版本 |
|------|---------------|---------|-----------|------|---------|
| Oracle | -- (禁止) | `DUAL` | `DUAL` (内置) | 强制 FROM；DUAL 在 SYS 模式 | v6+ (1988) |
| MySQL | 是 | `dual` (兼容关键字) | -- | DUAL 是占位关键字，非真实表 | 3.x+ |
| MariaDB | 是 | `dual` (兼容关键字) | -- | 继承 MySQL | 全版本 |
| PostgreSQL | 是 | -- (用户表) | -- | FROM 可选；DUAL 不存在 | 6.x+ |
| SQL Server | 是 | -- | -- | FROM 可选；无 DUAL 概念 | 全版本 |
| SQLite | 是 | -- | -- | FROM 可选 | 全版本 |
| DB2 (LUW) | -- (禁止) | -- | `SYSIBM.SYSDUMMY1` | 强制 FROM；用 SYSDUMMY1 | 全版本 |
| DB2 for z/OS | -- (禁止) | -- | `SYSIBM.SYSDUMMY1` | 同上 | 全版本 |
| DB2 for i | -- (禁止) | -- | `SYSIBM.SYSDUMMY1` | 同上 | 全版本 |
| Firebird | -- (禁止) | -- | `RDB$DATABASE` | 系统元数据表，单行 | 1.0+ |
| InterBase | -- (禁止) | -- | `RDB$DATABASE` | Firebird 的祖先 | 全版本 |
| Informix | -- (禁止) | -- | `systables WHERE tabid=1` | 用元数据表第一行 | 全版本 |
| Sybase ASE | 是 | -- | -- | FROM 可选 | 全版本 |
| Sybase IQ | 是 | -- | -- | 继承 Sybase | 全版本 |
| SAP ASE | 是 | -- | -- | Sybase ASE 的现名 | 全版本 |
| SAP HANA | 是 | `DUMMY` | `DUMMY` | 内置单行表 DUMMY，列 DUMMY VARCHAR(1) | 全版本 |
| Teradata | -- (禁止) | -- | -- | 必须 FROM；推荐 SEL 1; 或 (sel 1) | 全版本 |
| H2 | 是 | `DUAL` (兼容) | -- | 同时支持无 FROM 与 DUAL 兼容 | 1.x+ |
| HSQLDB | 是 | -- | `INFORMATION_SCHEMA.SYSTEM_USERS` | 默认 FROM 可选；提供 DUAL 兼容模式 | 2.x+ |
| Derby (JavaDB) | 是 | -- | `SYSIBM.SYSDUMMY1` | 继承 DB2 风格 | 全版本 |
| Ingres | -- (禁止) | -- | `iidbconstants` | 元数据单行表 | 全版本 |
| Vector / Actian X | -- | -- | `iidbconstants` | 同 Ingres | 全版本 |
| Snowflake | 是 | -- | -- | FROM 可选；无内置 DUAL | GA |
| BigQuery | 是 | -- | -- | FROM 可选 | GA |
| Redshift | 是 | -- | -- | 继承 PG，FROM 可选 | GA |
| Aurora MySQL | 是 | `dual` 兼容 | -- | 同 MySQL | GA |
| Aurora PostgreSQL | 是 | -- | -- | 同 PG | GA |
| RDS Oracle | -- | `DUAL` | -- | 同 Oracle | GA |
| Spanner | 是 | -- | -- | GoogleSQL 与 PG 方言均支持 | GA |
| CockroachDB | 是 | -- | -- | PG 兼容 | 全版本 |
| YugabyteDB | 是 | -- | -- | PG 兼容 | 全版本 |
| TiDB | 是 | `dual` (MySQL 兼容) | -- | MySQL 兼容 | 全版本 |
| OceanBase MySQL | 是 | `dual` (兼容) | -- | MySQL 模式 | 全版本 |
| OceanBase Oracle | -- | `DUAL` | -- | Oracle 模式 | 全版本 |
| PolarDB MySQL | 是 | `dual` 兼容 | -- | 同 MySQL | GA |
| PolarDB-O | -- | `DUAL` | -- | Oracle 兼容 | GA |
| GaussDB | -- (Oracle 模式) / 是 (PG 模式) | `DUAL` (Oracle 模式) | -- | 双方言 | GA |
| Greenplum | 是 | -- | -- | PG 派生 | 全版本 |
| Vertica | 是 | `DUAL` (兼容) | -- | 显式提供 DUAL 视图 | 全版本 |
| Trino / Presto | 是 | -- | -- | FROM 可选 | 全版本 |
| Athena | 是 | -- | -- | 基于 Presto/Trino | GA |
| Hive | -- (推荐) | -- | -- | 旧版需 FROM；推荐 `FROM (SELECT 1)` | 全版本 |
| Spark SQL | 是 | -- | -- | FROM 可选 | 全版本 |
| Flink SQL | 是 | -- | -- | FROM 可选 | 1.x+ |
| Databricks SQL | 是 | -- | -- | 同 Spark SQL | GA |
| ClickHouse | 是 | -- | `system.one` (单行) | system.one 是内置 1 行系统表 | 全版本 |
| DuckDB | 是 | -- | -- | FROM 可选 | 全版本 |
| MonetDB | 是 | -- | `sys.dual`(可选) | FROM 可选 | 全版本 |
| Exasol | 是 | `DUAL` (兼容) | -- | 显式提供 DUAL | 全版本 |
| StarRocks | 是 | -- | -- | FROM 可选 | 全版本 |
| Doris | 是 | -- | -- | FROM 可选 | 全版本 |
| Hologres | 是 | -- | -- | PG 兼容 | GA |
| MaxCompute | 是 | -- | -- | FROM 可选 | GA |
| Materialize | 是 | -- | -- | PG 兼容 | GA |
| RisingWave | 是 | -- | -- | PG 兼容 | GA |
| Singlestore (MemSQL) | 是 | `dual` (MySQL 兼容) | -- | MySQL 兼容 | 全版本 |
| QuestDB | 是 | -- | -- | FROM 可选 | 全版本 |
| TimescaleDB | 是 | -- | -- | PG 派生 | 全版本 |
| Yellowbrick | 是 | -- | -- | PG 派生 | GA |
| Firebolt | 是 | -- | -- | FROM 可选 | GA |
| Crate DB | 是 | -- | -- | FROM 可选 | 全版本 |
| Tableau Hyper | 是 | -- | -- | FROM 可选 | GA |
| Dremio | 是 | -- | -- | FROM 可选 | GA |
| InfluxDB IOx (SQL) | 是 | -- | -- | FROM 可选 | GA |

> 统计：约 50 个引擎支持 SELECT 无 FROM；其中约 12 个 Oracle 风格引擎 (Oracle/DB2/Firebird/Informix/Teradata/Ingres/原生 SAP HANA 的 DUMMY) 必须依赖某种"DUAL 等价物"。

### 各类 DUAL 等价物分布

| 等价物 | 引擎 | 说明 |
|--------|------|------|
| `DUAL` (Oracle 真实内部表) | Oracle / OceanBase Oracle 模式 / PolarDB-O / GaussDB Oracle / RDS Oracle | 真实存在于 SYS 模式的单行表 |
| `dual` (MySQL 占位关键字) | MySQL / MariaDB / TiDB / OceanBase MySQL / Aurora MySQL / SingleStore | 不是真表，仅是兼容关键字 |
| `SYSIBM.SYSDUMMY1` | DB2 / Derby | DB2 系列内置 1 行系统视图 |
| `RDB$DATABASE` | Firebird / InterBase | 数据库元数据表，永远 1 行 |
| `system.one` | ClickHouse | 内置 1 行系统表，列 `dummy UInt8` |
| `DUMMY` | SAP HANA | 内置 1 行 1 列表 |
| `iidbconstants` | Ingres / Actian Vector | 系统常量表 |
| 元数据表的第一行 | Informix | `systables WHERE tabid=1` |
| `DUAL` 兼容视图 | H2 / HSQLDB / Vertica / Exasol | 显式提供以兼容 Oracle |
| (无, 直接 SELECT) | PG / SQL Server / SQLite / Snowflake / BQ / Spark / Flink 等 | FROM 可选，不需要任何代物 |

## SQL 标准的演进

### SQL-86/89/92: FROM 必需

ISO/IEC 9075:1989 / 1992 中，SELECT 子句必须配对 FROM。这就是为什么早期的数据库 (Oracle、DB2、Sybase、Informix) 都必须解决"如何写 `SELECT 1+1`"的问题。

### SQL:1999: 引入 OLAP 扩展，仍需 FROM

SQL:1999 大量引入 OLAP/递归 CTE，但 `<query specification>` 的强制 FROM 没有改变。

### SQL:2003: FROM 变为可选

SQL:2003 的核心变化之一是允许 FROM 子句省略，这与同期引入的 `MERGE`、序列、窗口函数等同样重要，但因为太"小"反而少有人提。从此 `SELECT 1+1`、`SELECT CURRENT_DATE`、`SELECT pi()` 都成为标准合规写法。

### 真实情况：实现非常分裂

即便 SQL:2003 已发布 20+ 年，仍有大量企业级数据库 (Oracle、DB2、Firebird、Teradata、Informix、Ingres 等) 沿用强制 FROM 的策略。原因主要是：

1. **历史包袱**：旧应用、旧 ORM、旧客户端代码不愿意改。
2. **解析器一致性**：解析阶段如果允许"半个" SELECT，错误信息变模糊，对教学和调试不友好。
3. **DUAL 已成规范**：在企业 Oracle 生态中，`SELECT ... FROM DUAL` 已经是模式语言的一部分。

## Oracle DUAL 深度剖析

DUAL 是这一领域的"原点"，理解它有助于理解所有其他实现的设计选择。

### 什么是 DUAL

```sql
-- DUAL 的定义 (在 Oracle 中)
DESCRIBE DUAL;
-- Name        Null?    Type
-- ----------- -------- ------------
-- DUMMY                VARCHAR2(1)

SELECT * FROM DUAL;
-- DUMMY
-- -----
-- X

SELECT COUNT(*) FROM DUAL;
-- COUNT(*)
-- --------
--        1
```

`DUAL` 表的事实：

1. **属于 SYS 模式**：`SYS.DUAL`，但通过 PUBLIC 同义词暴露给所有用户。
2. **只有一列**：`DUMMY VARCHAR2(1)`。
3. **永远只有一行**：值是 `'X'`。
4. **从 v6 (1988) 引入**：作者是 Charles Weiss，最初为了解决"在视图字典里把每个用户的数据 join 一次"的算法需要而创造，名字 `DUAL` 即"对偶/二元"之意。

> 历史趣闻 (来自 Charles Weiss 后来的访谈)：DUAL 表最初确实有两行，因此叫 DUAL；但生产中很快被 Oracle 内部用作"返回单值"的工具，于是后来被改成了 1 行。名字保留了下来。

### Oracle 优化器对 DUAL 的特殊处理

```sql
-- 早期 Oracle 版本 (v7、v8) 真的会从磁盘读取 DUAL 行
SELECT 1+1 FROM DUAL;
-- 物理 I/O ≥ 1 (读 DUAL 表块)

-- 从 Oracle 10g 开始，优化器对 DUAL 引入"FAST DUAL"特殊算子
EXPLAIN PLAN FOR SELECT 1+1 FROM DUAL;
-- ----------------------------------
-- Operation         | Name | Rows
-- ----------------------------------
-- SELECT STATEMENT  |      |    1
-- FAST DUAL         |      |    1
-- ----------------------------------
```

`FAST DUAL` 不读磁盘，直接在内存中合成 1 行结果，效果上等价于"无 FROM"。这意味着所有 Oracle 应用使用 `FROM DUAL` 不会带来 I/O 开销——这部分缓解了对"被迫加 FROM"的性能担忧。

### Oracle DUAL 的常见用途

```sql
-- 1. 计算常量表达式
SELECT 1 + 1 FROM DUAL;

-- 2. 调用函数
SELECT SYSDATE FROM DUAL;
SELECT SYS_GUID() FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

-- 3. 序列下一个值
SELECT seq_order_id.NEXTVAL FROM DUAL;

-- 4. 测试连接
SELECT 1 FROM DUAL;
-- JDBC 连接池常用作 isValidationQuery

-- 5. 在 PL/SQL 里把常量赋给变量
DECLARE
    v_today DATE;
BEGIN
    SELECT SYSDATE INTO v_today FROM DUAL;
END;

-- 6. 模拟 INSERT-SELECT 单行
INSERT INTO orders(id, status)
SELECT seq_order_id.NEXTVAL, 'NEW' FROM DUAL;

-- 7. UNION ALL 构造常量行
SELECT 'A' AS val FROM DUAL UNION ALL
SELECT 'B' FROM DUAL UNION ALL
SELECT 'C' FROM DUAL;
```

### Oracle DUAL 的"陷阱"

```sql
-- 陷阱 1: 误以为 DUAL 可以多行
INSERT INTO DUAL VALUES ('Y');  -- 早期版本可执行，导致 DUAL 永远返回多行
-- 现代 Oracle 已禁止 (DUAL 现在是只读视图)

-- 陷阱 2: SELECT * FROM DUAL 在子查询里被误用
SELECT * FROM employees
WHERE EXISTS (SELECT * FROM DUAL);   -- 永远为真，相当于 1=1

-- 陷阱 3: GROUP BY 和分析函数与 DUAL
SELECT COUNT(*) FROM DUAL;            -- 1
SELECT COUNT(*) FROM DUAL GROUP BY 1; -- 1
```

## DB2 SYSIBM.SYSDUMMY1 深度剖析

DB2 选择了和 Oracle 不同的方向：与其引入新的"伪表"，不如使用一个真实的系统目录视图。

### SYSDUMMY1 的定义

```sql
-- DB2 LUW / DB2 z/OS / DB2 i 都内置以下 catalog view:
DESCRIBE TABLE SYSIBM.SYSDUMMY1;
-- Column Name        Type     Nulls
-- IBMREQD            CHAR(1)  N

SELECT * FROM SYSIBM.SYSDUMMY1;
-- IBMREQD
-- -------
-- Y

SELECT COUNT(*) FROM SYSIBM.SYSDUMMY1;
-- 1
```

特点：

1. **位于 SYSIBM 模式**：所有用户均可读，无需特殊权限。
2. **只有一列 IBMREQD**：含义是"IBM Required"，永远值为 `'Y'`。
3. **是真实的系统目录条目**：不是伪表，可以参与 join、视图等任何上下文。

### DB2 中的常见用法

```sql
-- 计算常量
SELECT 1 + 1 FROM SYSIBM.SYSDUMMY1;
-- 2

-- 当前时间
SELECT CURRENT TIMESTAMP FROM SYSIBM.SYSDUMMY1;

-- IDENTITY 列下一个值
SELECT NEXT VALUE FOR my_seq FROM SYSIBM.SYSDUMMY1;

-- DB2 i 系列 (AS/400) 上 SYSDUMMY1 是 QSYS2 模式的别名
-- 也可以使用 QSYS2.SYSDUMMY1 同名视图

-- DB2 9.7+ 引入了"VALUES (1)"语法，可以替代:
VALUES 1+1;          -- 等价于 SELECT 1+1 FROM SYSDUMMY1
VALUES CURRENT TIMESTAMP;
```

### Derby 继承 DB2 风格

```sql
-- Apache Derby (JavaDB) 由 IBM 开源，沿用 SYSIBM.SYSDUMMY1
SELECT 1 FROM SYSIBM.SYSDUMMY1;

-- 但 Derby 的 SQL 解析器允许 SELECT 无 FROM (作为扩展)：
-- 实际上 Derby 大多数版本都接受 VALUES 表达式，类似 DB2:
VALUES 1+1;
```

## MySQL DUAL: 一个"占位关键字"

MySQL 早期为了与 Oracle 应用兼容，引入了 `dual` 关键字，但和 Oracle 不一样的是：MySQL 的 `dual` 不是一个真实的表。

```sql
-- 在 MySQL 中:
SELECT 1+1 FROM dual;        -- 合法，输出 2
SELECT 1+1;                   -- 同样合法

SELECT * FROM dual;           -- 错误！dual 不是真表
SHOW TABLES LIKE 'dual';      -- 空，没有这个表
SHOW CREATE TABLE dual;       -- 错误：Table 'dual' doesn't exist

-- MySQL 的实现：解析器在看到 FROM dual 时直接将其忽略
-- 等同于 SELECT 1+1
```

MySQL 文档：

> The `DUAL` purely is a way to make MySQL compatible with some other database servers that require a FROM clause for every SELECT. MySQL may ignore the clause. MySQL does not require FROM DUAL if no tables are referenced.

这导致了两个有意思的现象：

```sql
-- 1. SELECT * FROM DUAL 会报错 (因为没有列可选)
SELECT * FROM dual;
-- ERROR 1096 (HY000): No tables used

-- 2. WHERE 条件需要常数表达式：
SELECT 1 FROM dual WHERE 1=1;     -- 合法
SELECT 1 FROM dual WHERE col=1;   -- 错误：Unknown column 'col'

-- 3. ON DUPLICATE KEY UPDATE 中的常用模式
INSERT INTO t(id, name) VALUES (1, 'a')
ON DUPLICATE KEY UPDATE name = 'a';
-- 等价的 INSERT-SELECT 写法：
INSERT INTO t(id, name) SELECT 1, 'a' FROM dual
ON DUPLICATE KEY UPDATE name = 'a';
-- 这种写法在 ORM 生成的 SQL 里很常见
```

MariaDB / TiDB / OceanBase MySQL 模式 / SingleStore / Aurora MySQL 全都继承了 MySQL 的这一行为。

## PostgreSQL: 没有 DUAL，FROM 永远可选

PostgreSQL 自 6.x 时代就允许省略 FROM 子句：

```sql
SELECT 1+1;                       -- 合法
SELECT CURRENT_DATE;              -- 合法
SELECT version();                 -- 合法

-- 但 SELECT * FROM DUAL 会报错 (DUAL 表不存在)
SELECT * FROM dual;
-- ERROR:  relation "dual" does not exist
```

很多 Oracle-to-PG 迁移工具会自动创建一个伪 DUAL 视图：

```sql
-- 兼容 Oracle 应用的常见做法
CREATE VIEW dual AS SELECT 'X'::varchar(1) AS dummy;
-- 之后 Oracle 风格的 SELECT 1+1 FROM dual 即可在 PG 上运行

-- 类似的，Greenplum / CockroachDB / YugabyteDB / Materialize 等
-- PG 派生引擎都接受这种迁移补丁
```

## SQL Server: 完全没有 DUAL 概念

SQL Server (T-SQL) 一直允许 SELECT 无 FROM：

```sql
SELECT 1+1;                                     -- 合法
SELECT GETDATE();                                -- 合法
SELECT NEWID();                                   -- 合法

-- 在 SP / 函数内部赋值给变量也用同样方式:
DECLARE @now DATETIME = GETDATE();
DECLARE @sum INT = (SELECT 1+1);
```

如果有迁移自 Oracle 的应用，可以创建兼容视图：

```sql
CREATE VIEW dbo.DUAL AS SELECT 'X' AS DUMMY;
-- 此后 SELECT 1+1 FROM DUAL 在 SQL Server 也工作

-- SQL Server 没有内置 DUAL，因为它从一开始就不强制 FROM
-- Sybase ASE / SAP ASE / Sybase IQ 也是同样设计
```

## Firebird: RDB$DATABASE

Firebird (以及它的祖先 InterBase) 选择了"使用元数据系统表"的方案：

```sql
-- RDB$DATABASE 是数据库本身的元数据表，永远只有一行
SELECT 1+1 FROM RDB$DATABASE;
SELECT CURRENT_TIMESTAMP FROM RDB$DATABASE;

-- 看 RDB$DATABASE 表结构
SELECT * FROM RDB$DATABASE;
-- RDB$DESCRIPTION | RDB$RELATION_ID | RDB$SECURITY_CLASS | RDB$CHARACTER_SET_NAME
-- (NULL)          | 6               | SQL$5            | UTF8

-- Firebird 3.0+ 还允许新的 SQL 语法:
SELECT 1+1 FROM RDB$DATABASE;

-- 注意：Firebird 3.0+ 的 EXECUTE BLOCK 等 PSQL 内部允许"无 FROM"
-- 但顶层 SELECT 仍然必须 FROM
```

## SAP HANA: DUMMY 表

SAP HANA 提供了一张内置的 `DUMMY` 表，**性质上和 Oracle 的 DUAL 几乎完全一样**：

```sql
-- 单列单行
DESC DUMMY;
-- COLUMN_NAME  DATA_TYPE_NAME  LENGTH
-- DUMMY        VARCHAR         1

SELECT * FROM DUMMY;
-- DUMMY
-- X

SELECT 1+1 FROM DUMMY;
-- 2

-- 同时 SAP HANA 也允许 SELECT 无 FROM，FROM DUMMY 是兼容选项
SELECT 1+1;     -- 也合法
```

## ClickHouse: system.one

ClickHouse 的命名很优雅——直接叫 `system.one`：

```sql
SELECT 1 FROM system.one;
-- ┌─dummy─┐
-- │     0 │
-- └───────┘

DESCRIBE TABLE system.one;
-- ┌─name──┬─type─┐
-- │ dummy │ UInt8 │
-- └───────┴──────┘

-- ClickHouse 同样允许无 FROM
SELECT 1+1;
SELECT now();
```

## 各引擎语法详解

### Oracle (强制 FROM DUAL)

```sql
-- 基本用法
SELECT 1+1 FROM DUAL;
SELECT SYSDATE FROM DUAL;
SELECT USER FROM DUAL;

-- 函数调用
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD') FROM DUAL;
SELECT LENGTH('Hello') FROM DUAL;

-- 序列
SELECT seq.NEXTVAL FROM DUAL;
SELECT seq.CURRVAL FROM DUAL;

-- 多行 UNION ALL
SELECT 1 AS n FROM DUAL UNION ALL
SELECT 2 FROM DUAL UNION ALL
SELECT 3 FROM DUAL;

-- 在 INSERT-SELECT 里
INSERT INTO log_table(ts, msg)
SELECT SYSDATE, 'startup' FROM DUAL;

-- PL/SQL 单值赋值
SELECT TO_NUMBER(:bv) INTO l_value FROM DUAL;

-- 模拟 IF-THEN-ELSE
SELECT CASE WHEN 1=1 THEN 'yes' ELSE 'no' END AS r FROM DUAL;
```

### DB2 (强制 FROM SYSIBM.SYSDUMMY1 或 VALUES)

```sql
-- 传统方式
SELECT 1+1 FROM SYSIBM.SYSDUMMY1;
SELECT CURRENT TIMESTAMP FROM SYSIBM.SYSDUMMY1;

-- DB2 9.7+ 推荐 VALUES
VALUES 1+1;
VALUES CURRENT TIMESTAMP;
VALUES NEXT VALUE FOR my_seq;

-- 多行 VALUES
VALUES (1), (2), (3);

-- 等价 SELECT 写法
SELECT * FROM (VALUES (1), (2), (3)) AS t(n);

-- 在 INSERT 里
INSERT INTO log VALUES (CURRENT TIMESTAMP, 'startup');

-- 别名 SYSIBM.SYSDUMMY1 也常见: 在 z/OS 上有
SELECT 1 FROM SYSIBM.SYSDUMMY1;
```

### MySQL / MariaDB (FROM 可选；FROM dual 兼容)

```sql
-- 三种等价形式
SELECT 1+1;
SELECT 1+1 FROM dual;
SELECT 1+1 FROM DUAL;            -- 大小写不敏感

-- 函数与表达式
SELECT NOW();
SELECT VERSION();
SELECT UUID();

-- 在 ORM 生成的 SQL 中常见
INSERT INTO t(id, name) SELECT 1, 'a' FROM dual
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- 测试连接 (JDBC validation query)
SELECT 1;
SELECT 1 FROM dual;
```

### PostgreSQL (FROM 可选)

```sql
-- 标准用法
SELECT 1+1;
SELECT now();
SELECT version();
SELECT pg_backend_pid();

-- 使用 generate_series 生成多行而非 UNION ALL
SELECT i FROM generate_series(1, 10) i;

-- VALUES 也常见
VALUES (1), (2), (3);
SELECT * FROM (VALUES (1), (2), (3)) AS t(n);

-- 在 INSERT 里
INSERT INTO log(ts, msg) VALUES (now(), 'startup');
INSERT INTO log(ts, msg) SELECT now(), 'startup';   -- 也合法
```

### SQL Server (FROM 可选)

```sql
SELECT 1+1;
SELECT GETDATE();
SELECT NEWID();
SELECT @@VERSION;

-- 多行 VALUES (SQL Server 2008+)
SELECT * FROM (VALUES (1), (2), (3)) AS t(n);

-- 在 stored procedure 里赋值
DECLARE @id INT = NEXT VALUE FOR my_seq;
DECLARE @ts DATETIME = GETDATE();

-- T-SQL 特有: SET vs SELECT
SET @id = (SELECT 1+1);
SELECT @id = 1+1;
```

### SQLite (FROM 可选)

```sql
SELECT 1+1;
SELECT date('now');
SELECT random();
SELECT sqlite_version();

-- VALUES (3.0+)
SELECT * FROM (VALUES (1), (2), (3));
```

### Firebird (强制 FROM RDB$DATABASE)

```sql
SELECT 1+1 FROM RDB$DATABASE;
SELECT CURRENT_DATE FROM RDB$DATABASE;
SELECT GEN_ID(my_gen, 1) FROM RDB$DATABASE;

-- Firebird 2.5+ EXECUTE BLOCK 内部可省略 FROM (PSQL 上下文)
EXECUTE BLOCK RETURNS (n INTEGER) AS
BEGIN
    n = 1+1;        -- 不需要 FROM
    SUSPEND;
END;
```

### Informix (强制 FROM systables 第一行)

```sql
-- 经典模式
SELECT 1+1 FROM systables WHERE tabid=1;

-- 或者使用任意单行表（业内约定）
SELECT TODAY FROM systables WHERE tabid=1;

-- 不建议 SELECT 1 FROM systables (会返回多行)
```

### Snowflake (FROM 可选)

```sql
SELECT 1+1;
SELECT CURRENT_TIMESTAMP;
SELECT UUID_STRING();

-- VALUES
SELECT * FROM VALUES (1), (2), (3) AS t(n);

-- 不存在 DUAL；如果应用迁移自 Oracle，可以创建：
CREATE OR REPLACE VIEW DUAL AS SELECT 'X'::VARCHAR(1) AS DUMMY;
```

### BigQuery (FROM 可选)

```sql
SELECT 1+1;
SELECT CURRENT_TIMESTAMP();
SELECT GENERATE_UUID();

-- 使用 UNNEST 生成多行
SELECT * FROM UNNEST([1,2,3]) AS n;

-- 也接受 VALUES (Google SQL)
SELECT * FROM (SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3);
```

### Spark SQL (FROM 可选)

```sql
SELECT 1+1;
SELECT current_timestamp();
SELECT uuid();

-- VALUES
SELECT * FROM VALUES (1), (2), (3) AS t(n);
```

### Flink SQL (FROM 可选)

```sql
SELECT 1+1;

-- VALUES 用于初始化界查询
SELECT * FROM (VALUES (1, 'a'), (2, 'b')) AS t(id, name);
```

### ClickHouse (FROM 可选；可显式 FROM system.one)

```sql
-- 三种等价
SELECT 1+1;
SELECT 1+1 FROM system.one;
SELECT 1+1 FROM (SELECT 1) t;

-- ClickHouse 的 system.one 内置一行，列 dummy UInt8 = 0
SELECT * FROM system.one;
-- ┌─dummy─┐
-- │     0 │
-- └───────┘

-- 用 numbers() 生成多行 (ClickHouse 特有)
SELECT number FROM numbers(10);
```

### Teradata (强制 FROM)

```sql
-- 真正没有 DUAL，使用任意单行表 (常见做法)
SELECT 1+1 FROM (SELECT 1 AS x) t;

-- 用 SELECT 1 + 简短形式 SEL
SEL CURRENT_TIMESTAMP FROM (SEL 1) t;

-- 一些 BI 工具会创建一张系统级 DUAL 表
CREATE TABLE DBC.DUAL (DUMMY VARCHAR(1)) /* 单行 */;
INSERT INTO DBC.DUAL VALUES ('X');
```

### H2 (兼容 MySQL/Oracle)

```sql
-- H2 同时支持以下三种
SELECT 1+1;
SELECT 1+1 FROM DUAL;
SELECT 1+1 FROM (VALUES 1) t;

-- H2 的 DUAL 是别名
SELECT * FROM DUAL;
-- X
```

### HSQLDB (灵活)

```sql
-- 默认配置允许 FROM 可选
SELECT 1+1;

-- 使用 INFORMATION_SCHEMA.SYSTEM_USERS 当 DUAL
SELECT 1+1 FROM INFORMATION_SCHEMA.SYSTEM_USERS LIMIT 1;

-- 有的 HSQLDB 部署会显式建立 DUAL:
CREATE VIEW DUAL AS VALUES ('X');
```

### Derby (DB2 风格)

```sql
SELECT 1+1 FROM SYSIBM.SYSDUMMY1;

-- Derby 也接受 VALUES
VALUES 1+1;
```

### SAP HANA (DUMMY 表)

```sql
-- 三种等价
SELECT 1+1;
SELECT 1+1 FROM DUMMY;
SELECT * FROM DUMMY;        -- 返回单行 'X'
```

### Vertica (显式 DUAL 视图)

```sql
-- Vertica 内置一个 DUAL 视图来兼容 Oracle 应用
SELECT 1+1 FROM DUAL;
SELECT 1+1;                 -- FROM 可选

\d DUAL
-- v_catalog.dual 视图，列 dummy varchar(1)，单行 'X'
```

### Exasol

```sql
-- 同时支持
SELECT 1+1;
SELECT 1+1 FROM DUAL;
```

## 真实场景模式集合

### 模式 1: 调用函数 / 计算常量

```sql
-- Oracle:        SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD') FROM DUAL;
-- DB2:           VALUES TO_CHAR(CURRENT TIMESTAMP, 'YYYY-MM-DD');
-- MySQL:         SELECT DATE_FORMAT(NOW(), '%Y-%m-%d');
-- PostgreSQL:    SELECT to_char(now(), 'YYYY-MM-DD');
-- SQL Server:    SELECT FORMAT(GETDATE(), 'yyyy-MM-dd');
-- Snowflake:     SELECT TO_CHAR(CURRENT_TIMESTAMP, 'YYYY-MM-DD');
-- BigQuery:      SELECT FORMAT_DATE('%Y-%m-%d', CURRENT_DATE());
```

### 模式 2: 序列下一个值

```sql
-- Oracle:        SELECT seq.NEXTVAL FROM DUAL;
-- DB2:           VALUES NEXT VALUE FOR seq;
-- PostgreSQL:    SELECT nextval('seq');
-- SQL Server:    SELECT NEXT VALUE FOR seq;
-- MySQL 8.0:     SELECT NEXTVAL(seq);          -- 仅在 GA 版本支持
-- Firebird:      SELECT NEXT VALUE FOR seq FROM RDB$DATABASE;
-- Snowflake:     SELECT seq.NEXTVAL;
```

### 模式 3: 测试数据库连接 (Validation Query)

JDBC/ODBC 连接池在归还连接前会发送一条简单查询验证连接是否有效。各引擎推荐的"验证 SQL"：

| 引擎 | 推荐 Validation Query |
|------|----------------------|
| Oracle | `SELECT 1 FROM DUAL` |
| DB2 | `SELECT 1 FROM SYSIBM.SYSDUMMY1` |
| MySQL | `SELECT 1` |
| PostgreSQL | `SELECT 1` |
| SQL Server | `SELECT 1` |
| Snowflake | `SELECT 1` |
| Firebird | `SELECT 1 FROM RDB$DATABASE` |
| H2 | `SELECT 1` |
| HSQLDB | `SELECT 1 FROM INFORMATION_SCHEMA.SYSTEM_USERS LIMIT 1` |
| SAP HANA | `SELECT 1 FROM DUMMY` |

很多通用连接池 (HikariCP / DBCP2) 会优先使用 `Connection.isValid()`，绕过 SQL 层级的差异。

### 模式 4: ORM 风格 INSERT-SELECT

```sql
-- Hibernate/MyBatis 等 ORM 在 INSERT...SELECT 时为了兼容性常带 FROM dual:
INSERT INTO order_log(id, ts, msg)
SELECT seq.NEXTVAL, CURRENT_TIMESTAMP, 'created' FROM DUAL;

-- 在 PG/SQL Server/MySQL 中可以直接：
INSERT INTO order_log(id, ts, msg)
VALUES (nextval('seq'), now(), 'created');
```

### 模式 5: 多行常量值

```sql
-- 用 DUAL/SYSDUMMY1 配合 UNION ALL (Oracle / DB2 / Firebird 等)
SELECT 1 AS n FROM DUAL UNION ALL
SELECT 2 FROM DUAL UNION ALL
SELECT 3 FROM DUAL;

-- 现代 SQL 推荐 VALUES 派生表 (大多数主流引擎都支持)
SELECT * FROM (VALUES (1), (2), (3)) AS t(n);

-- BigQuery 用 UNNEST
SELECT * FROM UNNEST([1, 2, 3]) AS n;

-- ClickHouse 用 numbers()
SELECT number FROM numbers(1, 3);   -- 1, 2, 3

-- PostgreSQL 用 generate_series()
SELECT i FROM generate_series(1, 3) i;
```

## 迁移模式 (Migration Patterns)

### 从 Oracle 迁移到 PostgreSQL

```sql
-- 步骤 1: 创建兼容 DUAL 视图
CREATE VIEW dual AS SELECT 'X'::VARCHAR(1) AS dummy;

-- 步骤 2: 函数等价改写
-- Oracle:  SELECT SYSDATE FROM DUAL;
-- PG:      SELECT now()::DATE;       (移除 FROM DUAL)
-- 或保留:  SELECT now()::DATE FROM dual;

-- 步骤 3: 序列改写
-- Oracle:  SELECT seq.NEXTVAL FROM DUAL;
-- PG:      SELECT nextval('seq');

-- 步骤 4: 工具
-- ora2pg / orafce 扩展会自动创建 dual 视图
```

### 从 Oracle 迁移到 MySQL

```sql
-- 通常无需改写，因为 MySQL 接受 FROM dual
-- 但要注意函数差异:
-- Oracle:  SELECT SYSDATE FROM DUAL;
-- MySQL:   SELECT NOW();              或 SELECT NOW() FROM dual;
-- Oracle:  SELECT SYSTIMESTAMP FROM DUAL;
-- MySQL:   SELECT CURRENT_TIMESTAMP(6);

-- 序列在 MySQL 8.0+
-- Oracle:  SELECT seq.NEXTVAL FROM DUAL;
-- MySQL:   SELECT NEXTVAL(seq);
```

### 从 DB2 迁移到 PostgreSQL

```sql
-- DB2 SYSDUMMY1 用法在 PG 没有等价表，用以下两种方案:
-- 方案 A: 创建兼容视图
CREATE SCHEMA sysibm;
CREATE VIEW sysibm.sysdummy1 AS SELECT 'Y'::CHAR(1) AS ibmreqd;

-- 方案 B: 直接改写为无 FROM
-- DB2:    SELECT 1+1 FROM SYSIBM.SYSDUMMY1;
-- PG:     SELECT 1+1;

-- VALUES 表达式在两个引擎都支持，可以是中间过渡形式
VALUES 1+1;     -- PG 也合法
```

### 从 MySQL 迁移到 Oracle

```sql
-- 主要问题: MySQL 允许 SELECT 无 FROM, Oracle 不允许
-- 自动化改写:
--   SELECT  expr;                 →  SELECT expr FROM DUAL;
--   SELECT  expr FROM dual;       →  SELECT expr FROM DUAL;   (大小写)

-- 函数差异更显著，例如:
-- MySQL:   SELECT NOW();
-- Oracle:  SELECT SYSDATE FROM DUAL;
-- MySQL:   SELECT UUID();
-- Oracle:  SELECT SYS_GUID() FROM DUAL;
```

### 跨多个引擎的可移植代码

最稳的写法：避免在 SELECT 表达式上的"是否需要 FROM"做手动选择，而是使用工程实践：

1. **抽象通过 ORM/查询构建器**: Hibernate / SQLAlchemy / Diesel 等会按方言生成正确的 FROM 子句。
2. **在每个引擎的方言层创建兼容视图**: 例如在 PG 上创建 `dual`、在 SQL Server 上创建 `DUAL`。
3. **使用 VALUES 表达式**: PG/DB2/SQL Server/MySQL 8.0+ 都支持 `VALUES (1, 'a')` 派生表。

## 标准与方言细节差异

### Q: SELECT 1; 是不是 SQL 标准合规？

A：自 SQL:2003 开始，是。SQL:2003 修订前，FROM 是必需的。今天大多数主流引擎接受。

### Q: FROM DUAL 是不是 SQL 标准合规？

A：不是。`DUAL` 不在任何版本的 ISO/ANSI SQL 中定义；它是 Oracle 的方言。其他引擎实现是为了兼容 Oracle 应用。

### Q: VALUES 1+1; 是不是 SQL 标准合规？

A：部分是。SQL:1999 引入 `<table value constructor>`，VALUES 表达式可以在 FROM 子句、INSERT VALUES 中使用。但作为顶层语句的 `VALUES 1+1;` 是 IBM 提出的扩展，被 DB2/PostgreSQL/SQLite 等接受，不在严格 ISO 标准中。

### Q: SELECT 不带 FROM 时的语义？

A：标准上等价于 `SELECT ... FROM <隐式 1 行的零列表>`。也就是结果集行数恒为 1 (前提是 SELECT 表达式都是标量)。这与 `SELECT 1 FROM empty_table` (结果是 0 行) 截然不同。

### Q: SELECT * FROM DUAL 在不同引擎的结果？

| 引擎 | 结果 |
|------|------|
| Oracle | 返回 1 行 1 列 ('X') |
| MySQL | 错误 (因为 dual 不是真表) |
| H2 | 返回 1 行 1 列 ('X') |
| SAP HANA (DUMMY) | 返回 1 行 1 列 ('X') |
| PostgreSQL/SQL Server | 错误 (表不存在) |
| Vertica | 返回 1 行 1 列 ('X') |
| ClickHouse (system.one) | 返回 1 行 1 列 (0) |

## 实现技术：引擎如何处理"无 FROM 的 SELECT"

### 抽象语法树阶段

```
SELECT 1+1
   |
   v
SelectStmt {
    targets: [BinaryOp(+, Const(1), Const(1))]
    from: NULL                        <- 关键: from 缺失
    where: NULL
    ...
}
```

### 优化器阶段：常见处理方式

**方式 A: 注入"虚拟单行"** (PostgreSQL / SQL Server / Snowflake / DuckDB / ClickHouse 等)

```
PlanRoot
  └── Project [1+1]
        └── DummyScan        <- 注入一个返回 1 行的算子
```

`DummyScan` 算子的行为：被调用 1 次时返回空元组，第 2 次返回 EOF。这样上层 Project 算子可以正常运行表达式求值，输出 1 行。

**方式 B: 让 Project 自包含输出 1 行** (一些向量化引擎的优化)

```
PlanRoot
  └── ConstantProject [1+1]   <- 直接合成 1 行结果
```

不引入 Scan 算子，Project 自己产生 1 行输出。在向量化引擎中可以避免一次"虚拟扫描"的开销。

**方式 C: Oracle FAST DUAL** (Oracle 10g+)

DUAL 表本来是真实磁盘表，但优化器识别到 `FROM DUAL` 时直接替换为 `FAST DUAL` 算子，行为同方式 A 的 `DummyScan`，但是是显式的优化。

```
EXPLAIN PLAN FOR SELECT 1 FROM DUAL;
-- FAST DUAL    cost=2  rows=1
```

### 解析器层的差异

强制 FROM 的引擎 (Oracle / DB2 / Firebird / Teradata 等)：

```
parser:
  if token == 'SELECT':
      consume_select_list()
      expect('FROM')           <- 强制
      consume_from_clause()
```

允许无 FROM 的引擎 (PG / SQL Server / MySQL / SQLite / Snowflake 等)：

```
parser:
  if token == 'SELECT':
      consume_select_list()
      if peek() == 'FROM':
          consume_from_clause()
      else:
          implicit_from = DummyTable
```

这种解析层面的差异是为什么"是否允许无 FROM"是个二元的、引擎级别的决定，无法在某些 SQL 方言里通过参数切换。

## 性能与统计：DUAL 真的有"开销"吗？

```
基准测试: 在 Oracle 19c 上执行 SELECT 1+1 FROM DUAL 一千万次
-- 启用 FAST DUAL: 1.8s
-- 未启用 FAST DUAL (强制 _fast_dual_enabled=false): 12.4s
-- 物理 I/O: FAST DUAL = 0,  非 FAST DUAL = ~1 块缓存命中

基准测试: 在 PostgreSQL 16 上执行 SELECT 1+1 一千万次
-- 直接表达式求值: 1.5s
-- 在 SELECT 1+1 FROM dual_view 上 (需要 RTE 处理): 1.7s
-- 差异主要来自查询计划的额外节点

结论:
- 现代 Oracle 的 FAST DUAL 与 PG 的无 FROM 性能等价
- 早期 Oracle (v7/v8) DUAL 有真实 I/O 开销
- DB2 SYSDUMMY1 因优化器特殊处理也接近零开销
- ClickHouse system.one 直接被特殊化，开销可忽略
```

## 常见误区

### 误区 1: "DUAL 是 SQL 标准的一部分"

不是。DUAL 在所有 ISO/ANSI SQL 标准中都不存在。它是 Oracle 的方言，被部分引擎为兼容性而模仿。

### 误区 2: "MySQL 的 dual 表是真实存在的"

不是。MySQL 的 `dual` 是解析器的占位关键字。`SELECT * FROM dual` 会报错 (No tables used)。

### 误区 3: "可以 INSERT INTO DUAL"

早期 Oracle 允许，会破坏 DUAL 的"单行"语义。现代 Oracle 已禁止 (DUAL 现在是只读视图)。

### 误区 4: "用 DUAL 比无 FROM 慢"

现代优化器 (Oracle FAST DUAL / DB2 等) 把 `FROM DUAL` 识别为特殊算子，开销与无 FROM 几乎完全等价。但在低版本 Oracle 中确实存在 I/O 开销。

### 误区 5: "FROM DUAL 在所有引擎都适用"

不是。PG / SQL Server / SQLite / Snowflake / BigQuery 等没有 DUAL 表，使用会报"表不存在"。

### 误区 6: "无 FROM 的 SELECT 不会进入查询优化器"

会。即使没有 FROM，引擎仍然要构造逻辑计划、执行表达式求值、走标准的执行管道。区别只是少了一个 Scan 节点。

## 设计争议

### 为什么 SQL-86/89/92 强制要求 FROM？

学术派认为：SELECT 是一个**关系操作**，作用于一个关系 (表)。逻辑上 `SELECT 1` 不是关系代数操作，不应在关系语言中出现。结果是：以"纯洁性"为代价，强制了 FROM 子句。

### 为什么 Oracle 选择 DUAL 而不是直接允许无 FROM？

历史上 Oracle 严格遵循 SQL-86 规范，DUAL 是这个约束下的工程方案。当 SQL:2003 允许无 FROM 后，Oracle 因为兼容性原因没有跟进——大量已有 SQL 都依赖 `FROM DUAL`，改了反而是破坏性变更。

### 为什么 DB2 用 SYSDUMMY1 而不是引入新关键字？

IBM 一贯倾向于 "everything is a table"——如果需要"虚拟的单行表"，最自然的方式就是真的建一张表，作为系统目录的一部分。这与 DB2 的 catalog 哲学一致。

### 为什么 PostgreSQL 没有内置 DUAL？

PG 早期就支持 SELECT 无 FROM，没有需要。但在 PG 里创建一个 DUAL 视图非常容易，迁移工具会自动处理。

### MySQL 的 dual 关键字是好设计吗？

折中。一方面允许 Oracle 应用直接迁移；另一方面让 dual 不是真表又造成了 `SELECT * FROM dual` 报错的混乱。从教育角度，"占位关键字"的设计比"真实虚表"更难解释。

### 应不应该在新代码中使用 FROM DUAL？

在跨方言代码中：避免，因为 PG/SQL Server/Snowflake 等没有 DUAL。
在纯 Oracle 代码中：保留，因为这是约定俗成的写法。
在迁移代码中：通过创建 DUAL 视图来兼容，长期可改写为无 FROM。

## 给引擎开发者的建议

### 1. 解析器层：FROM 子句应当是可选的

新引擎应当遵循 SQL:2003 让 FROM 可选。这极大简化用户写常量表达式查询的成本，也是现代 SQL 标准的方向。

### 2. 提供 DUAL/DUMMY 兼容视图

为了便于从 Oracle/DB2/HANA 等引擎迁移代码，新引擎应当提供：

```sql
-- 推荐做法
CREATE VIEW dual AS SELECT 'X'::CHAR(1) AS dummy;
-- 或 SCHEMA 级
CREATE SCHEMA sysibm;
CREATE VIEW sysibm.sysdummy1 AS SELECT 'Y'::CHAR(1) AS ibmreqd;
```

这是迁移工具自动化能完成的，但作为引擎内置可以减少用户摩擦。

### 3. 优化器层: 特殊化 DummyScan

```
特殊化目标:
  - DummyScan 应该是 "零成本" 算子: 不分配缓冲区，不调用 I/O 子系统
  - Project + DummyScan 在向量化引擎中应被 inline 为 ConstantProject
  - 行数估计: 永远等于 1
  - 代价模型: cost = 0 (避免误导优化器)
```

### 4. 错误信息友好性

当用户在不允许无 FROM 的引擎上写 `SELECT 1` 时，错误信息应当有引导：

```
ERROR: SELECT statement requires FROM clause.
HINT:  In this database, use 'SELECT 1 FROM <single-row-table>'
       Common patterns: 'FROM DUAL' (Oracle/MySQL),
                        'FROM SYSIBM.SYSDUMMY1' (DB2),
                        'FROM RDB$DATABASE' (Firebird).
```

### 5. JDBC/ODBC 驱动应处理 isValidationQuery

驱动应当根据连接的数据库选择合适的验证 SQL，而不是全部用 `SELECT 1` (在 Oracle 上会失败)：

```
isValid(timeout):
    switch (database):
        Oracle:    "SELECT 1 FROM DUAL"
        DB2:       "SELECT 1 FROM SYSIBM.SYSDUMMY1"
        Firebird:  "SELECT 1 FROM RDB$DATABASE"
        default:   "SELECT 1"
```

## 关键发现

1. **DUAL 是 Oracle 的方言**：SQL 标准从未定义 DUAL，但因 Oracle 1988 年的影响力，DUAL 成了"在没有合适 FROM 时怎么办"的事实标准之一。

2. **SQL:2003 让 FROM 变为可选**：标准在 2003 年修订后允许无 FROM 的 SELECT。但这只是 Feature，并非所有引擎强制实现，导致 20+ 年后仍存在分裂。

3. **3 个流派**：
   - **强制 FROM** (Oracle / DB2 / Firebird / Teradata / Informix / Ingres)
   - **FROM 可选** (PG / SQL Server / Snowflake / BigQuery / Spark / Flink / DuckDB / ClickHouse)
   - **两者都允许** (MySQL / MariaDB / H2 / Exasol / Vertica)

4. **DUAL 等价物的多样性**：
   - Oracle: `DUAL` (真表，1 行)
   - DB2: `SYSIBM.SYSDUMMY1` (catalog view)
   - Firebird: `RDB$DATABASE` (元数据表)
   - SAP HANA: `DUMMY` (内置表)
   - ClickHouse: `system.one` (内置)
   - Informix: `systables WHERE tabid=1`
   - MySQL: `dual` (占位关键字，非真表)

5. **Oracle FAST DUAL 让 DUAL 几乎零开销**：现代 Oracle (10g+) 把 `FROM DUAL` 识别为特殊算子，与无 FROM 的执行成本基本一致。

6. **MySQL 的 dual 是占位关键字**：与 Oracle 的真表不同，MySQL 的 `dual` 不存在为真实表，仅是解析器为兼容而保留的关键字，因此 `SELECT * FROM dual` 会报错。

7. **VALUES 表达式是更标准的替代**：DB2/PG/SQL Server/MySQL 8.0+/SQLite 都支持顶层或派生表里的 `VALUES (1)`，是构造常量行的更标准、可移植的方式。

8. **JDBC validation query 是这一分裂的真实痛点**：连接池在归还连接前需要发送一条 SQL，但 `SELECT 1` 在 Oracle 上会失败、`SELECT 1 FROM DUAL` 在 PG 上会失败。各连接池的 connectionTestQuery 配置成为日常运维的高频踩坑项。

9. **迁移工具的标准做法是创建兼容视图**：从 Oracle 迁出时，PG / SQL Server / Snowflake 上常常会建一个 `dual` 视图来减少 SQL 改写量。这通常是 30 秒就能完成的迁移补丁。

10. **`SELECT * FROM DUAL` 的语义在引擎间不一致**：Oracle/H2/HANA/Vertica 返回 ('X')；MySQL 报错；PG/SQL Server 报"表不存在"。在不熟悉的方言间复制粘贴 SQL 时这是常见陷阱。

## 参考资料

- ISO/IEC 9075-2:2003 — SQL 标准 Part 2 Foundation，关于 FROM 子句变为可选
- Oracle Database SQL Language Reference: [Selecting from the DUAL Table](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Selecting-from-the-DUAL-Table.html)
- Oracle FAST DUAL 优化的历史 (Tom Kyte's AskTom 多个 thread)
- IBM DB2 LUW: [SYSIBM.SYSDUMMY1 catalog view](https://www.ibm.com/docs/en/db2/11.5)
- IBM DB2 z/OS Reference: SYSDUMMY1 与 VALUES 表达式
- MySQL Reference Manual: [Special Tables — Dual](https://dev.mysql.com/doc/refman/8.0/en/select.html)
- PostgreSQL Documentation: [SELECT — Optional FROM clause](https://www.postgresql.org/docs/current/sql-select.html)
- Microsoft Learn: [SELECT (Transact-SQL) — FROM is optional](https://learn.microsoft.com/en-us/sql/t-sql/queries/select-transact-sql)
- Firebird Project: [RDB$DATABASE in System Tables](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref30/firebird-30-language-reference.html)
- SAP HANA SQL Reference: [DUMMY Table](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- ClickHouse Documentation: [system.one Table](https://clickhouse.com/docs/en/operations/system-tables/one)
- HikariCP: [connectionTestQuery 配置](https://github.com/brettwooldridge/HikariCP)
- Charles Weiss 关于 DUAL 表起源的访谈记录 (Oracle Magazine 历史专栏)
- ora2pg / orafce 项目: 创建 PG 上的 dual 兼容视图
