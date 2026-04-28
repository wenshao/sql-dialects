# 不可见列 (Invisible Columns)

`SELECT *` 是数据库 API 的隐式契约——但当一张表加了一列后，所有依赖 `SELECT *` 的代码都要重新审视。不可见列让你在不破坏旧客户端的前提下扩展 schema，是在线 DDL 演进的关键武器。

## 核心概念

### 什么是不可见列？

**不可见列 (Invisible Column)**：列的物理数据存储在表中，可以通过显式列名访问，但 `SELECT *` **不会**返回该列。它对应用程序"隐藏"，对显式查询"可见"。

```sql
-- Oracle / MySQL 通用语义
CREATE TABLE employees (
    id          NUMBER PRIMARY KEY,
    name        VARCHAR2(100),
    salary      NUMBER,
    audit_token VARCHAR2(64) INVISIBLE   -- 不可见列
);

-- SELECT * 不返回 audit_token
SELECT * FROM employees;
-- 仅输出: id, name, salary

-- 显式列名才能访问
SELECT id, name, audit_token FROM employees;
-- 输出: id, name, audit_token

-- INSERT 时如果不显式列出，必须有默认值
INSERT INTO employees VALUES (1, 'Alice', 5000);                      -- 跳过 audit_token
INSERT INTO employees (id, name, salary, audit_token)                  -- 显式赋值
    VALUES (2, 'Bob', 6000, 'tok_xyz');
```

### 与相关概念的区别

| 概念 | 物理存储 | SELECT * 可见 | 显式列名可见 | 默认值要求 | 典型引擎 |
|------|---------|-------------|------------|-----------|---------|
| INVISIBLE 列 | 是 | **否** | 是 | INSERT 时需默认值或显式赋值 | Oracle, MySQL, MariaDB |
| HIDDEN 列 | 是 | **否** | 是 | 类似 INVISIBLE | Hive, SAP HANA |
| 系统隐藏列 | 是（引擎管理） | **否** | 部分（如 ROWID/CTID） | 用户不可写 | 几乎所有引擎 |
| 计算列 | 否（VIRTUAL）/是（STORED） | 是 | 是 | 不需要（自动计算） | 多数引擎 |
| 视图列裁剪 | 是（基表中） | 否（视图中） | 否（视图中） | 不需要 | 所有支持 VIEW 的引擎 |
| 列权限隐藏 | 是 | 取决于权限 | 取决于权限 | -- | 多数引擎 |
| 加密/脱敏列 | 是 | 是（加密/脱敏后） | 是（加密/脱敏后） | -- | Oracle TDE, MySQL Mask |

关键差异：**SELECT * 是否返回**和**INSERT 时是否要求默认值**是区分用户态不可见列与系统隐藏列、视图技术、列权限的核心维度。

## 没有 SQL 标准定义

与 `TABLESAMPLE`、`MERGE`、`PIVOT` 等语法不同，**SQL 标准 (ISO/IEC 9075) 从未定义 INVISIBLE 列概念**。这是一个由商业数据库厂商独立发明、各自演化的特性：

- Oracle 12c R1 (2013) 首次引入 `INVISIBLE` 列关键字
- Hive 0.10 (2013) 引入 HIDDEN/虚拟列概念（用于内部列如 INPUT__FILE__NAME）
- SAP HANA 引入 `HIDE` 列选项（用于 calculated column 等场景）
- MariaDB 10.3 (2018) 跟进，使用相同的 `INVISIBLE` 关键字
- MySQL 8.0.23 (2021 年 1 月) 较晚跟进，同样使用 `INVISIBLE` 但语义略不同
- PostgreSQL、SQL Server、Snowflake、BigQuery 等至今没有原生 INVISIBLE 列

由于缺少标准约束，各引擎的语法、SELECT * 行为、默认值要求、可见性切换 API 都不一致。跨引擎迁移时必须逐一验证。

## 支持矩阵（综合）

### INVISIBLE 列支持

| 引擎 | 关键字 | 创建语法 | SELECT * 跳过 | 显式列可访问 | 版本 |
|------|--------|----------|---------------|-------------|------|
| Oracle | `INVISIBLE` | `col TYPE INVISIBLE` | 是 | 是 | 12c R1 (2013) |
| MySQL | `INVISIBLE` | `col TYPE INVISIBLE` | 是 | 是 | 8.0.23 (2021-01) |
| MariaDB | `INVISIBLE` | `col TYPE INVISIBLE` | 是 | 是 | 10.3.3 (2018-03) |
| PostgreSQL | -- | 不原生支持（用视图模拟） | -- | -- | 无原生 |
| SQL Server | -- | 不原生支持（用视图模拟） | -- | -- | 无原生 |
| DB2 | `IMPLICITLY HIDDEN` | `col TYPE IMPLICITLY HIDDEN` | 是 | 是 | LUW 10.1+, z/OS 10+ |
| SQLite | -- | 不支持 | -- | -- | 无原生 |
| Snowflake | -- | 不支持（可用 MASKING POLICY 部分模拟） | -- | -- | 无原生 |
| BigQuery | -- | 不支持 | -- | -- | 无原生 |
| Redshift | -- | 不支持 | -- | -- | 无原生 |
| DuckDB | -- | 不支持 | -- | -- | 无原生 |
| ClickHouse | -- | 不支持（有 ALIAS / MATERIALIZED 列变体） | -- | -- | 无原生 |
| Trino | -- | 不支持（连接器透传） | -- | -- | 无原生 |
| Presto | -- | 同 Trino | -- | -- | 无原生 |
| Spark SQL | -- | 不支持 | -- | -- | 无原生 |
| Hive | `HIDDEN` (内部) | 仅引擎内部用，用户不可创建 | 是（系统列） | 是（特定列） | 0.10+ (2013) |
| Flink SQL | -- | 不支持 | -- | -- | 无原生 |
| Databricks | -- | 不支持 | -- | -- | 无原生 |
| Teradata | -- | 不支持 | -- | -- | 无原生 |
| Greenplum | -- | 继承 PG，不支持 | -- | -- | 无原生 |
| CockroachDB | -- | 不支持（有 NOT VISIBLE 索引但无列级） | -- | -- | 无原生 |
| TiDB | `INVISIBLE`（仅索引） | 列级**不支持** | -- | -- | 无原生（列级） |
| OceanBase | `INVISIBLE` | `col TYPE INVISIBLE`（MySQL 模式） | 是 | 是 | 4.x（兼容 MySQL） |
| YugabyteDB | -- | 继承 PG，不支持 | -- | -- | 无原生 |
| SingleStore | -- | 不支持 | -- | -- | 无原生 |
| Vertica | -- | 不支持 | -- | -- | 无原生 |
| Impala | -- | 不支持 | -- | -- | 无原生 |
| StarRocks | -- | 不支持（有 HIDDEN 系统列如 `__op`） | -- | -- | 无原生 |
| Doris | -- | 不支持（有 HIDDEN 系统列如 `__DORIS_DELETE_SIGN__`） | -- | -- | 无原生 |
| MonetDB | -- | 不支持 | -- | -- | 无原生 |
| CrateDB | -- | 不支持（有系统级 `_id` / `_score`） | -- | -- | 无原生 |
| TimescaleDB | -- | 继承 PG，不支持 | -- | -- | 无原生 |
| QuestDB | -- | 不支持 | -- | -- | 无原生 |
| Exasol | -- | 不支持 | -- | -- | 无原生 |
| SAP HANA | `HIDDEN` | `col TYPE HIDDEN` | 是 | 是 | 1.0+ |
| Informix | -- | 不支持 | -- | -- | 无原生 |
| Firebird | -- | 不支持 | -- | -- | 无原生 |
| H2 | -- | 不支持 | -- | -- | 无原生 |
| HSQLDB | -- | 不支持 | -- | -- | 无原生 |
| Derby | -- | 不支持 | -- | -- | 无原生 |
| Amazon Athena | -- | 继承 Trino，不支持 | -- | -- | 无原生 |
| Azure Synapse | -- | 不支持 | -- | -- | 无原生 |
| Google Spanner | -- | 不支持 | -- | -- | 无原生 |
| Materialize | -- | 不支持 | -- | -- | 无原生 |
| RisingWave | -- | 不支持（有 HIDDEN 内部列如 `_row_id`） | -- | -- | 无原生 |
| InfluxDB (SQL) | -- | 不支持 | -- | -- | 无原生 |
| DatabendDB | -- | 不支持 | -- | -- | 无原生 |
| Yellowbrick | -- | 不支持 | -- | -- | 无原生 |
| Firebolt | -- | 不支持 | -- | -- | 无原生 |

> 统计：约 6 个引擎原生支持用户态 INVISIBLE/HIDDEN 列（Oracle、MySQL、MariaDB、DB2、SAP HANA、OceanBase）；约 5 个引擎有内部 HIDDEN 系统列但用户不能创建（Hive、StarRocks、Doris、CrateDB、RisingWave）；多数 OLTP/分析引擎不支持，常以视图、列权限或 MASKING POLICY 替代。

### INSERT 默认值与显式赋值要求

| 引擎 | INSERT 不指定列 | INSERT 显式列名 | 必须有 DEFAULT | NOT NULL + INVISIBLE |
|------|----------------|---------------|----------------|----------------------|
| Oracle | 跳过（须有默认或允许 NULL） | 必须显式列出 INVISIBLE 列 | 否（可允许 NULL） | 必须有 DEFAULT 否则报错 |
| MySQL 8.0 | 跳过（默认 NULL 或 DEFAULT） | 显式列名才接受值 | 否 | 必须有 DEFAULT |
| MariaDB | 跳过 | 显式列名接受值 | 否 | 必须有 DEFAULT |
| DB2 | 跳过 | 显式列名接受值 | 否 | 必须有 DEFAULT |
| SAP HANA | 跳过 | 显式列名接受值 | 否 | 必须有 DEFAULT |
| OceanBase | 跳过 | 显式列名接受值 | 否 | 必须有 DEFAULT |

关键约束：所有支持 INVISIBLE 的引擎都遵循同一原则——`INSERT INTO t VALUES (...)` 形式（不列出列名）会跳过 INVISIBLE 列，因此该列必须满足"NULL、DEFAULT、IDENTITY、generated"之一才能不阻塞旧 INSERT 语句。

### ALTER COLUMN VISIBLE/INVISIBLE 切换

| 引擎 | 语法 | 切换是否需重写表 | 元数据级 vs 数据级 |
|------|------|-----------------|-------------------|
| Oracle | `ALTER TABLE t MODIFY (col VISIBLE)` / `INVISIBLE` | 否（仅元数据） | 元数据 |
| MySQL 8.0 | `ALTER TABLE t ALTER COLUMN col SET INVISIBLE` / `VISIBLE` | 否（仅元数据，INSTANT） | 元数据 |
| MariaDB | `ALTER TABLE t MODIFY col TYPE INVISIBLE` | 否 | 元数据 |
| DB2 | `ALTER TABLE t ALTER COLUMN col SET HIDDEN` / `NOT HIDDEN` | 否 | 元数据 |
| SAP HANA | `ALTER TABLE t ALTER (col TYPE HIDDEN)` | 否 | 元数据 |
| OceanBase | `ALTER TABLE t ALTER COLUMN col SET INVISIBLE` / `VISIBLE` | 否 | 元数据 |

切换 INVISIBLE 状态都是元数据级操作，不需要重写表数据，是高效的在线 DDL 操作。

### 系统列 vs 用户标记的不可见列

| 维度 | 用户态 INVISIBLE 列 | 系统隐藏列 |
|------|-------------------|-----------|
| 创建方 | DBA/开发者 | 引擎自动创建 |
| 用户可写 | 是（显式赋值） | 否（只读） |
| `SELECT *` | 跳过 | 跳过 |
| 显式列名访问 | 是 | 是（部分） |
| 典型例子 | 审计列、过渡列 | Oracle ROWID、PG ctid、MySQL DB_ROW_ID |
| 切换可见性 | 是 | 否 |

### 系统级 HIDDEN 列举例

| 引擎 | 系统列名 | 含义 | 用户访问 |
|------|---------|------|---------|
| Oracle | `ROWID` / `ROWNUM` | 物理行地址 / 行号 | 可显式 SELECT |
| PostgreSQL | `ctid` / `xmin` / `xmax` / `oid` | 物理位置 / 事务版本 | 可显式 SELECT |
| MySQL InnoDB | `DB_ROW_ID` / `DB_TRX_ID` / `DB_ROLL_PTR` | 隐式主键/事务ID/UNDO 指针 | 通常不可访问 |
| Hive | `INPUT__FILE__NAME` / `BLOCK__OFFSET__INSIDE__FILE` / `ROW__OFFSET__INSIDE__BLOCK` | 输入文件名 / 块偏移 | 可显式 SELECT |
| Spark SQL | `_metadata` (file_path, file_name, ...) | 文件元数据 | 显式访问（3.1+） |
| Doris | `__DORIS_DELETE_SIGN__` / `__DORIS_VERSION_COL__` | 删除标记 / 版本 | 部分可访问 |
| StarRocks | `__op` (UPSERT/DELETE) | 主键模型操作类型 | 仅导入时使用 |
| RisingWave | `_row_id` / `_rw_timestamp` | 行 ID / 时间戳 | 内部 |
| CrateDB | `_id` / `_score` / `_version` | 文档 ID / 评分 / 版本 | 可显式 SELECT |
| ClickHouse | `_part` / `_partition_id` / `_sample_factor` | 分区元数据 | 可显式 SELECT |

这些系统隐藏列是引擎实现的副产品，与用户态 INVISIBLE 列概念不同——用户不能创建它们，也不能改变它们的可见性。

### 元数据查询与可观测性

| 引擎 | 查询视图 | 状态字段 |
|------|---------|---------|
| Oracle | `USER_TAB_COLUMNS.HIDDEN_COLUMN` | `YES` / `NO` |
| MySQL | `INFORMATION_SCHEMA.COLUMNS.EXTRA` | `INVISIBLE` 或空 |
| MariaDB | `INFORMATION_SCHEMA.COLUMNS.IS_VISIBLE` | `YES` / `NO` |
| DB2 | `SYSCAT.COLUMNS.HIDDEN` | `I` (implicitly hidden) / `N` |
| SAP HANA | `SYS.TABLE_COLUMNS.IS_HIDDEN` | `TRUE` / `FALSE` |
| OceanBase | `INFORMATION_SCHEMA.COLUMNS.EXTRA` | `INVISIBLE` 或空 |

## Oracle：12c INVISIBLE 列深度剖析

Oracle 是首个在主流数据库中引入 INVISIBLE 列的厂商，其语义被后续多数引擎参考。

### 创建 INVISIBLE 列

```sql
-- 直接创建带 INVISIBLE 的表
CREATE TABLE employees (
    id          NUMBER PRIMARY KEY,
    name        VARCHAR2(100),
    salary      NUMBER,
    audit_token VARCHAR2(64) INVISIBLE,
    created_at  TIMESTAMP DEFAULT SYSTIMESTAMP INVISIBLE
);

-- 给现有表添加 INVISIBLE 列
ALTER TABLE employees ADD (
    soft_delete CHAR(1) DEFAULT 'N' INVISIBLE
);

-- 把已有列设为 INVISIBLE
ALTER TABLE employees MODIFY (created_at INVISIBLE);

-- 恢复 VISIBLE
ALTER TABLE employees MODIFY (created_at VISIBLE);
```

### SELECT * 行为

```sql
-- SELECT * 跳过 INVISIBLE 列
SELECT * FROM employees;
--    ID NAME       SALARY
-- ----- ---------- ------
--     1 Alice        5000

-- 显式列名访问
SELECT id, name, audit_token, created_at FROM employees;
--    ID NAME       AUDIT_TOKEN     CREATED_AT
-- ----- ---------- --------------- ----------
--     1 Alice      tok_abc         2024-01-01

-- DESCRIBE 也不显示 INVISIBLE 列
DESC employees;
-- Name   Null?    Type
-- ID     NOT NULL NUMBER
-- NAME            VARCHAR2(100)
-- SALARY          NUMBER

-- 但 SET COLINVISIBLE ON 后可以显示
SET COLINVISIBLE ON;
DESC employees;
-- Name        Null?    Type
-- ID          NOT NULL NUMBER
-- NAME                 VARCHAR2(100)
-- SALARY               NUMBER
-- AUDIT_TOKEN (INVISIBLE) VARCHAR2(64)
-- CREATED_AT  (INVISIBLE) TIMESTAMP
```

### INSERT 行为

```sql
-- 不列出列名的 INSERT：跳过 INVISIBLE 列
INSERT INTO employees VALUES (1, 'Alice', 5000);
-- audit_token, created_at 取默认值（NULL 或 DEFAULT）

-- 显式列名：可以为 INVISIBLE 列赋值
INSERT INTO employees (id, name, salary, audit_token)
    VALUES (2, 'Bob', 6000, 'tok_xyz');

-- 注意：如果 INVISIBLE 列是 NOT NULL 且无 DEFAULT
-- 不列出列名的 INSERT 会报错 ORA-01400 (cannot insert NULL)
ALTER TABLE employees ADD (
    important_field VARCHAR2(100) NOT NULL  -- 需要 DEFAULT
);
-- 添加 NOT NULL 列必须给 DEFAULT，无论 INVISIBLE 与否

ALTER TABLE employees MODIFY (important_field INVISIBLE);
INSERT INTO employees VALUES (3, 'Carol', 7000);
-- 报错: ORA-01400, important_field 没有默认值
```

### 列序与 INVISIBLE

```sql
-- INVISIBLE 列在内部"列序号"上保留位置
-- 但 SELECT * 时被跳过

-- 创建表
CREATE TABLE t (a INT, b INT INVISIBLE, c INT);

-- INSERT VALUES (1, 2)
-- 不能 INSERT 3 个值 (1, 2, 3) ——因为 b 是 INVISIBLE
INSERT INTO t VALUES (1, 3);    -- a=1, c=3, b=NULL
INSERT INTO t (a, b, c) VALUES (10, 20, 30);

-- SELECT *
SELECT * FROM t;
--   A   C
-- --- ---
--   1   3
--  10  30

-- 显式
SELECT a, b, c FROM t;
--   A    B    C
-- --- ---- ----
--   1 NULL    3
--  10   20   30

-- 当 INVISIBLE 列变 VISIBLE，列序按内部序号恢复
ALTER TABLE t MODIFY (b VISIBLE);
SELECT * FROM t;
--   A    B    C
-- --- ---- ----
--   1 NULL    3
--  10   20   30
-- b 出现在 a 和 c 之间
```

### 字典视图

```sql
-- 查询哪些列是 INVISIBLE
SELECT column_name, hidden_column, virtual_column
FROM user_tab_columns
WHERE table_name = 'EMPLOYEES';

-- COLUMN_NAME     HIDDEN_COLUMN VIRTUAL_COLUMN
-- --------------- ------------- --------------
-- ID              NO            NO
-- NAME            NO            NO
-- SALARY          NO            NO
-- AUDIT_TOKEN     YES           NO
-- CREATED_AT      YES           NO

-- ALL_TAB_COLS（包含 HIDDEN）vs ALL_TAB_COLUMNS（仅 VISIBLE）
SELECT COUNT(*) FROM user_tab_columns WHERE table_name = 'EMPLOYEES';
-- 3 (仅可见)
SELECT COUNT(*) FROM user_tab_cols WHERE table_name = 'EMPLOYEES';
-- 5 (含 INVISIBLE)
```

### 重要限制

```sql
-- 1. 不能在外部表上使用 INVISIBLE
CREATE TABLE ext_t (...) ORGANIZATION EXTERNAL ...
    -- 不允许 INVISIBLE 列

-- 2. 集群表的 cluster key 不能是 INVISIBLE
-- 3. 临时表的 INVISIBLE 列在 12.2+ 才支持
-- 4. 主键、外键、唯一约束的列可以是 INVISIBLE
--    但显然 PK 用 INVISIBLE 不太常见

-- 5. INVISIBLE 列可以建索引（包括函数索引）
CREATE INDEX idx_audit ON employees(audit_token);
```

## MySQL：8.0.23 INVISIBLE 列

MySQL 在 2021 年 1 月发布的 8.0.23 版本中引入了 INVISIBLE 列特性。

### 基本语法

```sql
-- 创建表时声明 INVISIBLE
CREATE TABLE products (
    id          INT PRIMARY KEY,
    name        VARCHAR(100),
    price       DECIMAL(10,2),
    audit_log   JSON INVISIBLE,
    legacy_col  VARCHAR(50) DEFAULT '' INVISIBLE
);

-- ADD COLUMN 时 INVISIBLE
ALTER TABLE products ADD COLUMN
    deprecated_field INT DEFAULT 0 INVISIBLE;

-- 切换可见性
ALTER TABLE products ALTER COLUMN audit_log SET INVISIBLE;
ALTER TABLE products ALTER COLUMN audit_log SET VISIBLE;

-- 在 MODIFY 中也可
ALTER TABLE products MODIFY COLUMN audit_log JSON VISIBLE;
```

### SELECT 行为

```sql
-- SELECT * 跳过
SELECT * FROM products;
-- +----+--------+-------+
-- | id | name   | price |
-- +----+--------+-------+
-- |  1 | Apple  | 5.00  |
-- +----+--------+-------+

-- 显式访问
SELECT id, name, audit_log, legacy_col FROM products;

-- DESCRIBE 显示 EXTRA 列含 INVISIBLE
SHOW COLUMNS FROM products;
-- +-----------+--------------+------+-----+---------+-----------+
-- | Field     | Type         | Null | Key | Default | Extra     |
-- +-----------+--------------+------+-----+---------+-----------+
-- | id        | int          | NO   | PRI | NULL    |           |
-- | name      | varchar(100) | YES  |     | NULL    |           |
-- | price     | decimal(10,2)| YES  |     | NULL    |           |
-- | audit_log | json         | YES  |     | NULL    | INVISIBLE |
-- +-----------+--------------+------+-----+---------+-----------+

-- INFORMATION_SCHEMA
SELECT TABLE_NAME, COLUMN_NAME, EXTRA
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'mydb' AND EXTRA LIKE '%INVISIBLE%';
```

### INSERT 行为

```sql
-- 不列出列名：跳过 INVISIBLE 列
INSERT INTO products VALUES (1, 'Apple', 5.00);

-- 显式列名：接受 INVISIBLE 列的值
INSERT INTO products (id, name, price, audit_log)
    VALUES (2, 'Banana', 3.00, JSON_OBJECT('user', 'admin'));

-- 注意：MySQL 不允许 INSERT INTO products VALUES (1, 'Apple', 5.00, NULL)
-- 因为 INVISIBLE 列不在 VALUES 默认列表里

-- INSERT ... SELECT 也遵循"列名匹配"规则
INSERT INTO products SELECT * FROM products_backup;
-- 这里 SELECT * 不返回 INVISIBLE 列，所以新行的 INVISIBLE 列也是默认值
```

### MySQL 默认可见性差异

```sql
-- MySQL 文档明确说明：
-- 1. 列默认 VISIBLE
-- 2. INVISIBLE 不影响外部和内部应用程序的列存储
-- 3. 隐式列引用（如 INSERT VALUES 不列名）跳过 INVISIBLE 列

-- 关键点：MySQL 的 SELECT * 完全不返回 INVISIBLE 列
-- 与某些会话变量切换方案不同，MySQL 没有"全局开关让 SELECT * 包含 INVISIBLE 列"

-- 但 INSERT IGNORE / REPLACE 都遵循同样的规则
```

### MySQL 8.0.23 的限制

```sql
-- 1. 至少有一个 VISIBLE 列
-- 一张表的所有列不能全部 INVISIBLE
ALTER TABLE single_col_table MODIFY COLUMN col1 INT INVISIBLE;
-- 报错: ER_INVISIBLE_NEED_AT_LEAST_ONE_VISIBLE

-- 2. 主键列可以 INVISIBLE
-- 但显式 SELECT * 时仍然不返回，可能让应用混淆
CREATE TABLE t (
    id INT PRIMARY KEY INVISIBLE,    -- 合法但反直觉
    name VARCHAR(100)
);

-- 3. 生成列也可以 INVISIBLE
CREATE TABLE t (
    a INT,
    b INT,
    c INT GENERATED ALWAYS AS (a + b) INVISIBLE
);

-- 4. 索引可以包含 INVISIBLE 列
CREATE INDEX idx_audit ON products(audit_log(100));
-- 索引继续工作，优化器可以选择
```

## MariaDB：10.3 INVISIBLE 列（更早）

MariaDB 在 10.3.3（2018-03）就引入了 INVISIBLE 列，**比 MySQL 8.0.23 早了 3 年**。

### 基本语法

```sql
-- 与 MySQL 语法几乎相同
CREATE TABLE orders (
    id          INT PRIMARY KEY,
    amount      DECIMAL(10,2),
    audit_data  TEXT INVISIBLE
);

-- 添加 INVISIBLE 列
ALTER TABLE orders ADD COLUMN created_at TIMESTAMP DEFAULT NOW() INVISIBLE;

-- 切换
ALTER TABLE orders MODIFY COLUMN audit_data TEXT VISIBLE;
```

### MariaDB 三种可见性

MariaDB 的实现比 MySQL 更细分，将列的"可见性"分为多种状态：

```sql
-- 元数据
SELECT COLUMN_NAME, IS_VISIBLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'orders';

-- 实际上在 MariaDB 内部 (VCOL_INVISIBLE_*)
-- VCOL_INVISIBLE_USER (1):  用户标记的 INVISIBLE
-- VCOL_INVISIBLE_SYSTEM (2): 系统隐藏列（如临时列）
-- VCOL_INVISIBLE_FULL (3):   完全隐藏（用户无法访问）
```

### MariaDB 与 MySQL 的细节差异

```sql
-- 1. MariaDB 不存在"至少一个 VISIBLE 列"的限制
--    可以创建全 INVISIBLE 列的表（虽然没有意义）

-- 2. MariaDB INSERT 行为与 MySQL 一致

-- 3. MariaDB 在 SHOW CREATE TABLE 输出中保留 INVISIBLE 关键字
SHOW CREATE TABLE orders;
-- CREATE TABLE `orders` (
--   `id` int(11) NOT NULL,
--   `amount` decimal(10,2) DEFAULT NULL,
--   `audit_data` text DEFAULT NULL INVISIBLE,
--   ...

-- 4. MariaDB 兼容 Oracle 的 INVISIBLE 关键字定位（列定义后）
ALTER TABLE orders MODIFY audit_data TEXT INVISIBLE;
```

## DB2：IMPLICITLY HIDDEN 列

DB2（LUW 10.1+, z/OS 10+）使用不同的关键字 `IMPLICITLY HIDDEN`，但语义相似。

```sql
-- 创建 IMPLICITLY HIDDEN 列
CREATE TABLE customers (
    id          INTEGER PRIMARY KEY,
    name        VARCHAR(100),
    masked_ssn  VARCHAR(11) IMPLICITLY HIDDEN,
    audit_ts    TIMESTAMP DEFAULT CURRENT TIMESTAMP IMPLICITLY HIDDEN
);

-- ADD COLUMN
ALTER TABLE customers ADD COLUMN
    soft_deleted CHAR(1) DEFAULT 'N' IMPLICITLY HIDDEN;

-- 切换可见性
ALTER TABLE customers ALTER COLUMN masked_ssn SET HIDDEN;
ALTER TABLE customers ALTER COLUMN masked_ssn SET NOT HIDDEN;

-- 元数据查询
SELECT COLNAME, HIDDEN
FROM SYSCAT.COLUMNS
WHERE TABNAME = 'CUSTOMERS';
-- HIDDEN = 'I' 表示 IMPLICITLY HIDDEN
-- HIDDEN = 'N' 表示正常列
```

### DB2 的特殊语义

```sql
-- 1. SELECT * 排除 HIDDEN 列（与 Oracle/MySQL 一致）
SELECT * FROM customers;

-- 2. INSERT VALUES 也跳过 HIDDEN 列
INSERT INTO customers VALUES (1, 'Alice');

-- 3. SELECT * INTO（DB2 特有）
SELECT * INTO target_table FROM customers;
-- target_table 不包含 HIDDEN 列

-- 4. LOAD 工具的 HIDDEN 行为（DB2 实用程序级）
-- 默认 LOAD 命令不加载 HIDDEN 列，需要显式选项
```

## SAP HANA：HIDE 列选项

SAP HANA 使用 `HIDDEN` 关键字（部分文档作 `HIDE`），常用于计算列、聚合视图、虚拟表场景。

```sql
-- 创建 HIDDEN 列
CREATE TABLE sensor_data (
    sensor_id   INTEGER,
    timestamp   TIMESTAMP,
    value       DECIMAL,
    raw_signal  VARBINARY HIDDEN
);

-- ALTER COLUMN
ALTER TABLE sensor_data ALTER (raw_signal VARBINARY HIDDEN);
ALTER TABLE sensor_data ALTER (raw_signal VARBINARY);   -- 取消 HIDDEN

-- 元数据
SELECT COLUMN_NAME, IS_HIDDEN
FROM SYS.TABLE_COLUMNS
WHERE TABLE_NAME = 'SENSOR_DATA';
```

### HANA 的特别用途

SAP HANA 的 HIDDEN 列大量用于 calculation view 和 attribute view，作为内部计算的中间结果。普通业务表上较少用，但语义与 Oracle/MySQL 一致：`SELECT *` 跳过、显式列名可访问。

## OceanBase：MySQL 兼容模式 INVISIBLE

OceanBase 4.x 在 MySQL 兼容模式下完全实现了 MySQL 8.0.23+ 的 INVISIBLE 列语法。

```sql
-- MySQL 模式下，与 MySQL 完全一致
CREATE TABLE orders (
    id          BIGINT PRIMARY KEY,
    amount      DECIMAL(15,2),
    trace_id    VARCHAR(64) INVISIBLE
);

-- 切换
ALTER TABLE orders ALTER COLUMN trace_id SET VISIBLE;
ALTER TABLE orders ALTER COLUMN trace_id SET INVISIBLE;

-- Oracle 模式下，使用 Oracle 语法
ALTER TABLE orders MODIFY (trace_id VARCHAR2(64) INVISIBLE);
```

OceanBase 是分布式数据库中目前唯一完整实现 INVISIBLE 列的产品。

## Hive：HIDDEN/INTERNAL 系统列

Hive 0.10+ 引入的 HIDDEN 概念与 Oracle/MySQL 不同——它是引擎内部使用的虚拟列，**用户不能创建**，但可以显式查询。

### Hive 内置虚拟列

```sql
-- 这些列在每张表中都存在，但 SELECT * 不返回
SELECT
    INPUT__FILE__NAME,
    BLOCK__OFFSET__INSIDE__FILE,
    ROW__OFFSET__INSIDE__BLOCK,
    *
FROM hive_table
LIMIT 5;
-- INPUT__FILE__NAME              | BLOCK__OFFSET | ROW__OFFSET | col1 | col2 | ...
-- hdfs://nn/path/to/file/000000_0 | 0             | 0           | a    | 1    |
-- hdfs://nn/path/to/file/000000_0 | 0             | 1           | b    | 2    |

-- ACID 表的隐藏列
SELECT
    ROW__ID,                     -- 行 ID
    *
FROM acid_table;
```

### Hive 与用户态 INVISIBLE 列的区别

```
Hive 不允许用户：
1. CREATE TABLE t (col INT HIDDEN)        -- 不支持
2. ALTER TABLE t MODIFY col HIDDEN        -- 不支持

但 Hive 提供：
1. 系统级隐藏列（INPUT__FILE__NAME 等）
2. 通过视图模拟：CREATE VIEW v AS SELECT col_a, col_b FROM t

替代方案：
- ACL/列权限：GRANT SELECT(col_a, col_b) ON t TO user
- View：CREATE VIEW masked_t AS SELECT id, name FROM t  -- 不暴露 audit_log
```

## PostgreSQL：无原生支持

PostgreSQL 至今（17+）没有原生的 INVISIBLE 列概念。社区曾多次讨论，但因 SQL 标准不定义、且 `SELECT *` 行为变化可能破坏外部工具，提案均未通过。

### 替代方案 1：视图 + 列裁剪

```sql
-- 基表包含敏感/审计列
CREATE TABLE employees (
    id          SERIAL PRIMARY KEY,
    name        TEXT,
    salary      NUMERIC,
    audit_token TEXT,
    deleted_at  TIMESTAMP
);

-- 视图只暴露应用使用的列
CREATE VIEW employees_v AS
    SELECT id, name, salary FROM employees WHERE deleted_at IS NULL;

-- 应用查询视图，"看不到" audit_token 和 deleted_at
SELECT * FROM employees_v;
```

### 替代方案 2：列权限（GRANT）

```sql
-- 创建只读用户看不到敏感列
CREATE ROLE app_user;
GRANT SELECT (id, name, salary) ON employees TO app_user;
-- audit_token 和 deleted_at 没有 GRANT，app_user 不能查询

-- 但 SELECT * 会报错（缺少权限）
SET ROLE app_user;
SELECT * FROM employees;
-- 报错: permission denied for table employees

-- 必须显式列出有权限的列
SELECT id, name, salary FROM employees;
-- 工作正常
```

### 替代方案 3：列顺序调整

```sql
-- PG 不允许像 Oracle 那样动态隐藏列
-- 但可以将"过渡列"放在表末尾，让应用习惯只 SELECT 业务列
-- 这只是约定，不是强制

-- 在 PG 中删除中间列后调整顺序，需要重建表
ALTER TABLE t DROP COLUMN old_col;     -- 列号被回收
-- 新加的列总是在末尾
```

### 替代方案 4：扩展（experimental）

```sql
-- 一些第三方扩展（如 hidden_columns）尝试实现
-- 但都不在官方 PG 仓库中，生态不完善
```

PG 用户的实际做法：在事务期间用视图屏蔽过渡列，等迁移完成后再修改基表。

## SQL Server：无原生支持

SQL Server 也没有原生的 INVISIBLE 列。但 T-SQL 提供以下替代：

### 替代方案 1：视图

```sql
-- 与 PG 相同模式
CREATE VIEW dbo.employees_v AS
    SELECT id, name, salary FROM dbo.employees;
-- audit_token 在视图里看不到
```

### 替代方案 2：列权限（DENY）

```sql
-- DENY SELECT on specific columns
DENY SELECT ON dbo.employees(audit_token, deleted_at) TO AppRole;

-- AppRole 用户的 SELECT * 直接报错
-- 必须显式列出有权限的列
```

### 替代方案 3：DYNAMIC DATA MASKING（脱敏）

```sql
-- SQL Server 2016+
ALTER TABLE employees ALTER COLUMN ssn ADD MASKED WITH (FUNCTION = 'default()');
-- 列依然在 SELECT * 中返回，但内容被脱敏
-- 这不是真正的"INVISIBLE"

-- 优点：透明
-- 缺点：列依然存在，外部工具仍能感知到 schema
```

## CockroachDB：列级不支持，仅索引级

CockroachDB 22.2+ 引入了 `NOT VISIBLE` 索引（`CREATE INDEX ... NOT VISIBLE`），但**没有列级的 INVISIBLE 概念**。

```sql
-- 仅支持索引级
CREATE INDEX idx_email ON users (email) NOT VISIBLE;

-- 列级不支持
ALTER TABLE users ALTER COLUMN ssn SET NOT VISIBLE;
-- 不支持，CockroachDB 报语法错误
```

CockroachDB 的设计哲学是"避免与 SQL 标准不一致的扩展"，因此即使索引级 NOT VISIBLE 也是经过谨慎权衡才加入的。

## Snowflake / BigQuery / 现代云数仓：不支持

```sql
-- Snowflake：无 INVISIBLE 列
-- 替代方案 1: 视图
CREATE VIEW v AS SELECT col_a, col_b FROM t;

-- 替代方案 2: MASKING POLICY (列级动态脱敏)
CREATE MASKING POLICY hide_audit AS (val STRING) RETURNS STRING ->
    CASE WHEN CURRENT_ROLE() IN ('ADMIN') THEN val
         ELSE NULL END;

ALTER TABLE t MODIFY COLUMN audit_token
    SET MASKING POLICY hide_audit;
-- 列依然在 SELECT * 中返回，但非 ADMIN 角色看到 NULL

-- BigQuery：无 INVISIBLE 列
-- 替代方案：AUTHORIZED VIEW + 列级访问控制（IAM）

-- Redshift：无 INVISIBLE 列
-- 替代方案：视图 / GRANT 列权限（仅 RA3 节点支持列级 GRANT）
```

## ClickHouse：ALIAS / MATERIALIZED 列变体

ClickHouse 没有 INVISIBLE 列，但其 `ALIAS` 和 `MATERIALIZED` 列具有部分相似行为：

```sql
-- ALIAS 列：不存储，仅在查询时计算（类似 PG 的 generated virtual）
CREATE TABLE events (
    user_id UInt64,
    event_time DateTime,
    event_date Date ALIAS toDate(event_time)   -- ALIAS 不存储
);

-- SELECT * 行为
SELECT * FROM events;
-- ALIAS 列默认不返回（与 INVISIBLE 类似）
-- 但注意：MATERIALIZED 列也默认不返回 SELECT *

-- 显式访问
SELECT user_id, event_time, event_date FROM events;

-- MATERIALIZED 列：物理存储，但 INSERT 时不能赋值，SELECT * 也不返回
CREATE TABLE events (
    user_id UInt64,
    event_time DateTime,
    event_date Date MATERIALIZED toDate(event_time)
);
-- INSERT INTO events VALUES (1, now())   -- 合法，event_date 自动计算
-- INSERT INTO events VALUES (1, now(), today())  -- 报错：MATERIALIZED 不能写
```

ClickHouse 的 ALIAS/MATERIALIZED 解决了部分场景，但缺少"普通存储列但 SELECT * 跳过"的能力。

## 用例 1：零停机列重命名

INVISIBLE 列最经典的用例——在不停机的情况下重命名列。

### Oracle / MySQL 通用流程

```sql
-- 阶段 0: 现状
CREATE TABLE users (
    id INT PRIMARY KEY,
    user_email VARCHAR(255)        -- 准备改名为 email
);

-- 阶段 1: 添加新列名（INVISIBLE，不影响 SELECT *）
ALTER TABLE users ADD COLUMN email VARCHAR(255) INVISIBLE;

-- 阶段 2: 双写：应用代码同时写两列
-- INSERT INTO users (id, user_email, email) VALUES (1, 'a@b.c', 'a@b.c');
-- UPDATE users SET user_email = ?, email = ? WHERE id = ?

-- 阶段 3: 回填历史数据
UPDATE users SET email = user_email WHERE email IS NULL;
COMMIT;

-- 阶段 4: 应用代码切换到读 email（依然双写）
-- SELECT email FROM users WHERE id = ?

-- 阶段 5: 切换可见性
ALTER TABLE users ALTER COLUMN email SET VISIBLE;
ALTER TABLE users ALTER COLUMN user_email SET INVISIBLE;

-- 阶段 6: 应用代码停止写 user_email
-- INSERT INTO users (id, email) VALUES (?, ?)

-- 阶段 7: 观察一周后删除旧列
ALTER TABLE users DROP COLUMN user_email;
```

每个阶段都是元数据级操作，可瞬间完成，且**任意阶段都可回滚**。

### 对比传统重命名的痛点

```sql
-- 传统方案：直接 RENAME COLUMN
ALTER TABLE users RENAME COLUMN user_email TO email;
-- 问题：
-- 1. 所有依赖 user_email 的代码瞬间失效
-- 2. 没有缓冲期，错误难以回滚
-- 3. 部分老连接的预编译语句缓存失效

-- INVISIBLE 方案的优势：
-- 1. 添加和切换都是渐进的
-- 2. 任意阶段可以回滚（变更前的代码继续工作）
-- 3. 应用部署可以分批，不需要瞬间一致
```

## 用例 2：隐藏弃用列

```sql
-- 场景：legacy 列 status_code 被 status_v2 替代
-- 不能立即 DROP（旧报表依赖）
-- 但希望：新代码不再 SELECT * 时返回它

ALTER TABLE orders ALTER COLUMN status_code SET INVISIBLE;

-- 效果：
-- 1. 旧报表 SELECT status_code FROM orders 继续工作
-- 2. 新代码 SELECT * FROM orders 不再看到 status_code
-- 3. 新功能不会"无意中"依赖弃用列
-- 4. 可以观察一段时间，看是否还有引用

-- 监控查询频率
-- 通过 V$SQL（Oracle）或 performance_schema（MySQL）追踪
-- 确认无引用后再 DROP COLUMN
```

## 用例 3：审计列与元数据列

```sql
-- 场景：每行都需要存储审计信息（创建人、修改时间、版本号）
-- 但应用代码不应感知这些列（避免误用）

CREATE TABLE products (
    id          INT PRIMARY KEY,
    name        VARCHAR(100),
    price       DECIMAL(10,2),
    -- 应用关心的列结束 --

    -- 审计列：INVISIBLE
    created_by  VARCHAR(50) DEFAULT USER INVISIBLE,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP INVISIBLE,
    updated_by  VARCHAR(50) DEFAULT USER INVISIBLE,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                ON UPDATE CURRENT_TIMESTAMP INVISIBLE,
    version     INT DEFAULT 1 INVISIBLE,
    tenant_id   INT INVISIBLE,
    soft_delete CHAR(1) DEFAULT 'N' INVISIBLE
);

-- 应用 INSERT：清爽
INSERT INTO products VALUES (1, 'Apple', 5.00);

-- 应用 SELECT *：清爽
SELECT * FROM products;
-- +----+--------+-------+
-- | id | name   | price |
-- +----+--------+-------+

-- 审计/合规查询：显式访问
SELECT id, name, created_by, updated_at FROM products;

-- 触发器维护
CREATE TRIGGER trg_products_audit
    BEFORE UPDATE ON products
    FOR EACH ROW
BEGIN
    SET NEW.updated_by = USER();
    SET NEW.updated_at = CURRENT_TIMESTAMP;
    SET NEW.version = OLD.version + 1;
END;
```

INVISIBLE 列把"业务字段"和"基础设施字段"隔离，让代码 review 更清晰。

## 用例 4：数据脱敏与多租户

```sql
-- 场景：单表存储多租户数据，tenant_id 列对应用透明（用 RLS 自动过滤）
-- 但 SELECT * 不应返回 tenant_id（避免应用直接操作）

CREATE TABLE shared_data (
    id          INT PRIMARY KEY,
    payload     JSON,
    tenant_id   INT INVISIBLE         -- 多租户隔离列
);

-- 应用 SELECT *：看不到 tenant_id
SELECT * FROM shared_data;

-- 行级安全（RLS）/ 视图自动过滤
-- 应用永远不需要写 WHERE tenant_id = ?

-- DML 操作通过触发器自动赋值 tenant_id
```

## 用例 5：测试列与 A/B 实验

```sql
-- 临时列用于 A/B 测试，不希望污染 SELECT *
ALTER TABLE users ADD COLUMN
    experiment_group VARCHAR(20) DEFAULT 'control' INVISIBLE;

-- 实验代码显式访问
UPDATE users SET experiment_group = 'variant_a' WHERE id MOD 2 = 0;
SELECT id, experiment_group, COUNT(*) FROM events
    JOIN users USING (id) GROUP BY 1, 2;

-- 实验结束后删除列，对应用零影响
ALTER TABLE users DROP COLUMN experiment_group;
```

## 用例 6：旧版兼容字段

```sql
-- 场景：SaaS 升级，新版本不再使用某字段
-- 但部分老客户的客户端依赖该字段
-- 不能删除，但希望默认隐藏

ALTER TABLE customers ALTER COLUMN legacy_phone_format SET INVISIBLE;

-- 新代码 SELECT * 不返回 legacy_phone_format
-- 老代码继续 SELECT customer.legacy_phone_format 也工作
-- 等所有老客户升级后再 DROP
```

## 用例 7：Generated 列与 INVISIBLE 配合

```sql
-- 场景：从 JSON 提取的虚拟列，用于查询优化
-- 但不希望应用直接访问（应该用 JSON 字段）

CREATE TABLE events (
    id INT PRIMARY KEY,
    payload JSON,
    -- 用于索引的提取列，不希望 SELECT * 返回
    user_id INT GENERATED ALWAYS AS (JSON_EXTRACT(payload, '$.user_id')) INVISIBLE,
    event_type VARCHAR(50) GENERATED ALWAYS AS
        (JSON_UNQUOTE(JSON_EXTRACT(payload, '$.type'))) INVISIBLE
);

-- 索引利用 INVISIBLE 列
CREATE INDEX idx_user_event ON events(user_id, event_type);

-- 查询时用 JSON 字段，但优化器透过 generated column 选择索引
SELECT * FROM events
WHERE JSON_EXTRACT(payload, '$.user_id') = 1234;
-- 优化器会自动重写为 user_id = 1234 并使用 idx_user_event
```

## 工程实践与坑

### 坑 1：ORM 与 ActiveRecord 模式

许多 ORM（如 Rails ActiveRecord、Django ORM、Eloquent）默认 `SELECT *`，**正是 INVISIBLE 列的核心适用场景**。但要注意：

```sql
-- ORM 内部缓存 schema
-- 第一次连接时 SHOW COLUMNS（不显示 INVISIBLE 默认值）
-- ORM 不知道这些列存在
-- 当应用切换列可见性时，ORM 缓存可能失效
-- 必须重启应用或重新加载 schema 缓存
```

最佳实践：变更可见性后，**主动通知所有应用实例重连/重载 schema**。

### 坑 2：备份与导出工具

```sql
-- mysqldump 默认参数：不包含 INVISIBLE 列的数据
mysqldump --databases mydb > backup.sql
-- 备份的 INSERT 语句不会包含 INVISIBLE 列的值

-- 解决：使用 --column-statistics=0 + 显式列名
-- 或在备份前临时把列设为 VISIBLE

-- pg_dump 不存在此问题（PG 没有 INVISIBLE 概念）

-- expdp/impdp (Oracle) 默认包含 INVISIBLE 列
-- 但导出脚本要正确处理 hidden_column 字典字段
```

### 坑 3：物化视图 / 缓存

```sql
-- 物化视图基于 SELECT 创建
CREATE MATERIALIZED VIEW mv AS
    SELECT * FROM employees;
-- mv 中没有 INVISIBLE 列

-- 之后切换可见性
ALTER TABLE employees ALTER COLUMN audit_log SET VISIBLE;
-- mv 不会自动有 audit_log 列
-- 必须 DROP + CREATE MV

-- 同理：基于 SELECT * 的视图、缓存表都受影响
```

### 坑 4：约束与索引

```sql
-- INVISIBLE 列上的索引继续工作
CREATE INDEX idx_audit ON t(audit_token);
-- 优化器在 WHERE audit_token = ? 时仍然使用此索引

-- INVISIBLE 列上的外键约束继续生效
ALTER TABLE child ADD COLUMN
    parent_id INT INVISIBLE,
    CONSTRAINT fk_parent FOREIGN KEY (parent_id) REFERENCES parent(id);

-- INVISIBLE 列的唯一性约束继续生效
ALTER TABLE users ADD COLUMN
    legacy_id INT UNIQUE INVISIBLE;
-- 重复的 legacy_id 仍会报唯一性冲突
```

### 坑 5：ALTER 添加 INVISIBLE 列的默认值要求

```sql
-- 添加 NOT NULL 列必须有 DEFAULT
-- INVISIBLE 也不例外
ALTER TABLE t ADD COLUMN
    new_col INT NOT NULL DEFAULT 0 INVISIBLE;

-- 没 DEFAULT 时报错
ALTER TABLE t ADD COLUMN new_col INT NOT NULL INVISIBLE;
-- 报错: 缺少 DEFAULT

-- 因为旧的 INSERT VALUES (...) 不列出列名，会跳过此列
-- 必须有 DEFAULT 才能填充新行
```

### 坑 6：DESCRIBE / 客户端工具显示

```sql
-- Oracle SQL*Plus
SET COLINVISIBLE ON;
DESC employees;
-- 显示 INVISIBLE 列

-- MySQL 客户端
SHOW FULL COLUMNS FROM employees;
-- 在 EXTRA 字段显示 INVISIBLE

-- DB2 db2 命令
DESCRIBE TABLE customers SHOW DETAIL;
-- 显示 IMPLICITLY HIDDEN 标记

-- 第三方工具（DBeaver / Navicat / DataGrip）
-- 默认通常不显示 INVISIBLE 列
-- 需要在表属性中查看，或刷新元数据
```

### 坑 7：跨引擎迁移

```
Oracle → MySQL：
  - 关键字相同（INVISIBLE）
  - 切换语法不同（MODIFY vs ALTER COLUMN）
  - INSERT 行为一致

MariaDB → MySQL：
  - 语法兼容（同 INVISIBLE）
  - 但 MySQL 要求"至少一个 VISIBLE 列"

DB2 → 其他：
  - 关键字 IMPLICITLY HIDDEN 不通用
  - 必须改写为 INVISIBLE

PG → 任何 INVISIBLE 引擎：
  - 必须重新设计：从视图模式改为 INVISIBLE 列
  - 注意外部工具的 schema 缓存
```

## 性能影响

```sql
-- INVISIBLE 列的开销
-- 1. 存储：与普通列完全相同（INVISIBLE 只是元数据标记）
-- 2. INSERT/UPDATE/DELETE：与普通列完全相同
-- 3. SELECT *：略快（少返回一列的数据）
-- 4. 索引维护：INVISIBLE 列上的索引正常维护

-- 切换可见性的开销
-- 元数据级，瞬间完成（不重写表）
-- 但需要：
--   1. 短暂的元数据锁（毫秒级）
--   2. 客户端 schema 缓存失效

-- vs 视图方案：
-- 视图每次 SELECT 解析时增加一层 rewrite，几乎无性能损失
-- 但需要应用使用视图而非表（命名冲突管理）

-- vs 列权限方案：
-- 权限检查在解析阶段，无运行时开销
-- 但 SELECT * 直接报错，需要应用代码列出列名
```

## 替代方案对比

| 方案 | 实现复杂度 | 应用代码改动 | SELECT * 行为 | 灵活性 |
|------|-----------|------------|--------------|-------|
| INVISIBLE 列 | 低（DDL 一条） | 无 | 透明跳过 | 高（可切换） |
| 视图 | 中（CREATE VIEW） | 改表名为视图名 | 视图层定义 | 中（重新创建） |
| 列权限 GRANT/DENY | 低 | SELECT * 报错时改 | 报错或跳过 | 中（按角色） |
| MASKING POLICY | 中 | 无 | 返回脱敏值 | 高（条件） |
| Generated VIRTUAL 列 | 低 | 无 | 取决于引擎 | 低 |
| 应用层裁剪 | 高 | ORM/代码改动 | 视实现 | 高 |

## 关键发现

### 1. INVISIBLE 列是"非标准但事实趋同"的特性

虽然 SQL 标准从未定义，但 Oracle 12c (2013)、MariaDB 10.3 (2018)、MySQL 8.0.23 (2021) 三家主流引擎使用了**完全相同的 INVISIBLE 关键字**和**几乎一致的语义**。这种"无标准但趋同"的现象在 SQL 生态中并不常见，反映出该特性的明确价值。DB2 的 `IMPLICITLY HIDDEN` 和 SAP HANA 的 `HIDDEN` 是同一概念的不同命名。

### 2. INVISIBLE vs 系统隐藏列：根本不同

INVISIBLE 列是用户态特性，由开发者主动声明；系统隐藏列（Oracle ROWID、PG ctid、MySQL DB_ROW_ID、Hive INPUT__FILE__NAME）是引擎实现的副产品，用户既不能创建也不能改变可见性。两者**功能上有相似（SELECT * 跳过、显式访问可）**，但**意图和管理模式完全不同**。

### 3. 现代云数仓为何不支持 INVISIBLE

Snowflake、BigQuery、Redshift、Databricks 等云数仓都不支持 INVISIBLE 列，主要原因：
- 元数据层不可变（schema 变更通常需要 immutable copy）
- 客户端工具高度依赖 SHOW COLUMNS 的标准结果
- 替代方案（视图、MASKING POLICY、IAM 列权限）已经覆盖大多数场景
- 列存储的 schema 演化模型与 INVISIBLE 不完全匹配

### 4. PostgreSQL 与 SQL Server 的设计取舍

两个最主流的开源/商业 OLTP 数据库都没有原生 INVISIBLE 列，反映出同一设计哲学：**SQL 标准不定义就不实现，宁可让用户用视图和列权限组合**。PG 用户的实践通常是"视图 + 列权限 + 临时迁移表"组合。

### 5. INVISIBLE 不是脱敏

INVISIBLE 让列对 `SELECT *` 不可见，但**显式列名访问完全无障碍**。如果目标是真正的"敏感数据保护"，应使用：
- 列加密（TDE / 应用层加密）
- DYNAMIC DATA MASKING（SQL Server / Oracle Data Redaction）
- 列权限 DENY
- 行级安全 RLS

INVISIBLE 是**模式管理**工具，不是**安全**工具。

### 6. CockroachDB 的取舍：列级 NOT VISIBLE 缺席

CockroachDB 实现了索引级 NOT VISIBLE 但**没有列级**——其设计哲学倾向于"避免与 SQL 标准不一致"，列级 INVISIBLE 因 SELECT * 行为与标准冲突，被有意排除。这与 Oracle/MySQL 实用主义路线形成鲜明对比。

### 7. 分布式 OLTP 的实现挑战

OceanBase 是少数完整实现 INVISIBLE 列的分布式 OLTP 数据库。TiDB 虽然实现了 INVISIBLE 索引，但**没有 INVISIBLE 列**。原因可能涉及分布式 schema 同步的复杂度——所有节点必须一致地"知道"哪些列是 INVISIBLE，否则 SELECT * 在不同节点返回不同结果。

### 8. INVISIBLE 是 ORM 时代的解决方案

`SELECT * FROM table` 是 ORM 的默认行为。在没有 INVISIBLE 时，每次添加列都可能引发数据传输浪费、网络拥塞、客户端崩溃。INVISIBLE 列让"添加新列对旧应用零影响"变成现实，这是它最重要的价值。Oracle 在 2013 年引入此特性时，正是 Java EE 与 Hibernate 时代的高峰，需求驱动非常明确。

### 9. SELECT * 是公共 API 的隐式契约

INVISIBLE 列特性的存在，证明了一件事：**SELECT * 不是简单的"返回所有列"，而是数据库与应用的隐式契约**。在大型系统中，这个契约的稳定性甚至比单条查询的语义还重要。INVISIBLE 列让 DBA 能在不破坏契约的前提下演化 schema。

### 10. 默认值要求是统一的

所有支持 INVISIBLE 的引擎，在添加 NOT NULL INVISIBLE 列时**必须给 DEFAULT**。原因：旧的 INSERT VALUES（不列出列名）会跳过 INVISIBLE 列，没 DEFAULT 就违反 NOT NULL 约束。这是一致的设计选择。

### 11. Hive 的"HIDDEN"是不同概念

Hive 的 HIDDEN/INTERNAL 列指 INPUT__FILE__NAME 等系统级虚拟列，用户**不能创建**自己的 HIDDEN 列。从命名上易与 Oracle/MySQL 的 INVISIBLE 列混淆，但实际是引擎内部的虚拟列机制（更接近 PG ctid 概念）。

### 12. 切换可见性是元数据级操作

所有支持 INVISIBLE 的引擎，VISIBLE/INVISIBLE 切换都是**元数据级操作**，不需要重写表数据，瞬间完成。这是它能成为"在线 DDL"利器的关键——若需要重写数据，价值就大打折扣。

## 总结对比矩阵

### 主流引擎能力对比

| 能力 | Oracle | MySQL 8.0 | MariaDB 10.3 | DB2 | SAP HANA | OceanBase | PostgreSQL | SQL Server |
|------|--------|-----------|-------------|-----|----------|-----------|-----------|-----------|
| INVISIBLE 关键字 | INVISIBLE | INVISIBLE | INVISIBLE | IMPLICITLY HIDDEN | HIDDEN | INVISIBLE | -- | -- |
| 创建语法 | 是 | 是 | 是 | 是 | 是 | 是 | 视图 | 视图 |
| 切换可见性 | MODIFY | ALTER SET | MODIFY | ALTER SET | ALTER | ALTER SET | -- | -- |
| 元数据级切换 | 是 | 是 | 是 | 是 | 是 | 是 | -- | -- |
| INSERT 默认跳过 | 是 | 是 | 是 | 是 | 是 | 是 | -- | -- |
| 至少 1 VISIBLE 列限制 | 否 | 是 | 否 | 否 | 否 | 是 | -- | -- |
| 主键可 INVISIBLE | 是 | 是 | 是 | 是 | 是 | 是 | -- | -- |
| 索引正常工作 | 是 | 是 | 是 | 是 | 是 | 是 | -- | -- |
| 首次引入 | 2013 (12c) | 2021 (8.0.23) | 2018 (10.3) | 10.1 | 早期 | 4.x | 无原生 | 无原生 |

### 场景推荐

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| Oracle 生态 | INVISIBLE | 最早实现，最成熟 |
| MySQL 8.0+ | INVISIBLE | 标准方案，与 Oracle 几乎一致 |
| MariaDB | INVISIBLE | 比 MySQL 早 3 年支持 |
| DB2 | IMPLICITLY HIDDEN | 关键字不同，语义同 |
| 分布式 OLTP | OceanBase INVISIBLE | 唯一完整实现的分布式 |
| PostgreSQL 场景 | 视图 + 列权限 | 无原生支持 |
| SQL Server 场景 | 视图 + DENY | 无原生支持 |
| 云数仓（Snowflake/BQ） | MASKING POLICY / 视图 | 无原生支持 |
| 数据脱敏需求 | 列加密 / 脱敏，**非 INVISIBLE** | INVISIBLE 不阻止显式访问 |
| 在线列重命名 | INVISIBLE 双写迁移 | 经典模式 |
| 审计/元数据列 | INVISIBLE 一次声明 | 应用代码无感 |

## 参考资料

- Oracle: [Invisible Columns](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ALTER-TABLE.html)
- Oracle 12c New Features: [Invisible Columns](https://docs.oracle.com/database/121/NEWFT/chapter12101.htm)
- MySQL 8.0.23 Release Notes: [Invisible Columns](https://dev.mysql.com/doc/relnotes/mysql/8.0/en/news-8-0-23.html)
- MySQL Reference: [Invisible Columns](https://dev.mysql.com/doc/refman/8.0/en/invisible-columns.html)
- MariaDB: [Invisible Columns](https://mariadb.com/kb/en/invisible-columns/)
- DB2 LUW: [IMPLICITLY HIDDEN columns](https://www.ibm.com/docs/en/db2)
- SAP HANA SQL Reference: [HIDDEN columns](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- OceanBase: [INVISIBLE 列](https://en.oceanbase.com/docs/)
- Hive: [Virtual Columns](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+VirtualColumns)
- PostgreSQL: [Schema Privileges](https://www.postgresql.org/docs/current/ddl-priv.html)
- SQL Server: [Dynamic Data Masking](https://learn.microsoft.com/en-us/sql/relational-databases/security/dynamic-data-masking)
- ClickHouse: [Default Expressions](https://clickhouse.com/docs/en/sql-reference/statements/create/table#default_values)
- 相关文章: [不可见索引 (Invisible/Unusable Indexes)](./invisible-indexes.md)
- 相关文章: [生成列 (Generated/Computed Columns)](./generated-columns.md)
- Markus Winand: "Modern SQL: Invisible Columns" (2014)
