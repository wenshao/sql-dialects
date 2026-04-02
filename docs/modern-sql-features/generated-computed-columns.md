# 生成列与计算列 (Generated and Computed Columns)

由表达式自动派生的列——在不引入数据冗余的前提下实现反范式化。生成列允许将计算逻辑下沉到 DDL 层面，使每一行数据自动维护派生值，无需应用层额外编码。这一特性在 SQL:2003 标准中正式引入，各引擎在语法关键字、存储语义和表达式限制上存在显著差异。

## SQL 标准

SQL:2003 (ISO/IEC 9075-2:2003) Section 11.4 定义了 **generation clause**:

```sql
-- SQL:2003 标准语法
column_name data_type GENERATED ALWAYS AS (expression) [STORED | VIRTUAL]
```

标准要求：
- 表达式必须是确定性的 (deterministic)
- 不能包含子查询、聚合函数或窗口函数
- 不能引用其他生成列（标准未明确，各引擎实现不同）
- 用户不能直接 INSERT 或 UPDATE 生成列的值

SQL:2003 同时引入了 **identity column** 语法 `GENERATED { ALWAYS | BY DEFAULT } AS IDENTITY`，作为序列自增的标准化方案。

## 支持矩阵

### STORED 与 VIRTUAL 支持

| 引擎 | STORED | VIRTUAL | 版本 | 语法关键字 |
|------|--------|---------|------|-----------|
| PostgreSQL | 支持 | 不支持 | 12+ | `GENERATED ALWAYS AS (...) STORED` |
| MySQL | 支持 | 支持 (默认) | 5.7.6+ | `[GENERATED ALWAYS] AS (...) {VIRTUAL\|STORED}` |
| MariaDB | 支持 | 支持 (默认) | 5.2+ / 10.2+ | `{GENERATED ALWAYS\|} AS (...) {VIRTUAL\|STORED\|PERSISTENT}` |
| SQLite | 支持 | 支持 (默认) | 3.31.0+ | `[GENERATED ALWAYS] AS (...) {VIRTUAL\|STORED}` |
| Oracle | 不支持 | 支持 (仅) | 11g R1+ | `[column_name] [type] AS (expr) [VIRTUAL]` |
| SQL Server | 支持 (PERSISTED) | 支持 (默认) | 2005+ | `AS (expr) [PERSISTED]` |
| DB2 (LUW) | 支持 | 不支持 | 9.5+ | `GENERATED ALWAYS AS (expr)` |
| Snowflake | 不支持 | 不支持 | - | 无原生支持（用 VIEW / SECURE VIEW 替代） |
| BigQuery | 不支持 | 不支持 | - | 无原生支持（用 VIEW 替代） |
| Redshift | 不支持 | 不支持 | - | 无原生支持 |
| DuckDB | 支持 | 支持 | 0.8.0+ | `[GENERATED ALWAYS] AS (expr) [VIRTUAL\|STORED]` |
| ClickHouse | 支持 (MATERIALIZED) | 支持 (ALIAS) | 20.1+ | `MATERIALIZED expr` / `ALIAS expr` |
| Trino | 不支持 | 不支持 | - | 无原生支持 |
| Presto | 不支持 | 不支持 | - | 无原生支持 |
| Spark SQL | 支持 | 不支持 | 3.3+ (Delta Lake) | `GENERATED ALWAYS AS (expr)` |
| Hive | 不支持 | 不支持 | - | 无原生支持 |
| Flink SQL | 支持 | 支持 | 1.12+ | `column_name AS expr` (VIRTUAL) / `GENERATED ALWAYS AS (expr)` |
| Databricks | 支持 | 不支持 | Runtime 10.4+ | `GENERATED ALWAYS AS (expr)` (Delta Lake) |
| Teradata | 不支持 | 不支持 | - | 无原生支持（用 VIEW 替代） |
| Greenplum | 支持 | 不支持 | 7+ (PG12 base) | `GENERATED ALWAYS AS (...) STORED` (继承 PostgreSQL) |
| CockroachDB | 支持 | 支持 | 22.1+ | `AS (expr) STORED` / `AS (expr) VIRTUAL` (22.2+) |
| TiDB | 支持 | 支持 (默认) | 2.1+ | `[GENERATED ALWAYS] AS (expr) {VIRTUAL\|STORED}` |
| OceanBase | 支持 | 支持 | MySQL 模式 3.x+ | `[GENERATED ALWAYS] AS (expr) {VIRTUAL\|STORED}` |
| YugabyteDB | 支持 | 不支持 | 2.13+ | `GENERATED ALWAYS AS (expr) STORED` (继承 PostgreSQL) |
| SingleStore | 支持 | 不支持 | 7.0+ | `AS (expr) PERSISTED` / `AS (expr) COMPUTED` |
| Vertica | 不支持 | 不支持 | - | 无原生支持（用 expressions in VIEW/projection） |
| Impala | 不支持 | 不支持 | - | 无原生支持 |
| StarRocks | 支持 | 不支持 | 3.1+ | `AS (expr)` (generated column) |
| Doris | 不支持 | 不支持 | - | 无原生支持（2.1+ 有 variant 类型但非生成列） |
| MonetDB | 不支持 | 不支持 | - | 无原生支持 |
| CrateDB | 支持 | 不支持 | 4.0+ | `GENERATED ALWAYS AS (expr)` |
| TimescaleDB | 支持 | 不支持 | (PG12+ base) | `GENERATED ALWAYS AS (...) STORED` (继承 PostgreSQL) |
| QuestDB | 不支持 | 不支持 | - | 无原生支持 |
| Exasol | 支持 | 支持 | 7.0+ | `[type] DEFAULT expr` (virtual) / 物化需通过 VIEW |
| SAP HANA | 支持 | 不支持 | 2.0 SPS 03+ | `GENERATED ALWAYS AS (expr)` |
| Informix | 不支持 | 不支持 | - | 无原生支持（用 VIEW 替代） |
| Firebird | 支持 | 支持 | 3.0+ | `GENERATED ALWAYS AS (expr)` / `COMPUTED [BY] (expr)` |
| H2 | 支持 | 支持 | 1.4+ | `GENERATED ALWAYS AS (expr)` / `AS (expr)` |
| HSQLDB | 支持 | 不支持 | 2.5+ | `GENERATED ALWAYS AS (expr)` |
| Derby | 支持 | 不支持 | 10.5+ | `GENERATED ALWAYS AS (expr)` |
| Amazon Athena | 不支持 | 不支持 | - | 无原生支持（基于 Trino/Presto） |
| Azure Synapse | 不支持 | 不支持 | - | 无原生支持（与 SQL Server 计算列不同） |
| Google Spanner | 支持 | 不支持 | 2021+ | `type GENERATED ALWAYS AS (expr) STORED` |
| Materialize | 不支持 | 不支持 | - | 增量视图引擎，不支持表级生成列 |
| RisingWave | 不支持 | 不支持 | - | 流式处理引擎，不支持传统生成列 |
| InfluxDB | 不支持 | 不支持 | - | 时序数据库，无 SQL DDL 生成列 |
| Databend | 支持 | 支持 | 1.2+ | `type GENERATED ALWAYS AS (expr) {VIRTUAL\|STORED}` |
| Yellowbrick | 不支持 | 不支持 | - | 无原生支持 |
| Firebolt | 不支持 | 不支持 | - | 无原生支持 |

### 语法关键字变体

不同引擎使用不同的关键字来表达相同的概念：

| 概念 | 标准 SQL | 变体关键字 | 使用引擎 |
|------|---------|-----------|---------|
| 物理存储生成列 | `GENERATED ALWAYS AS (...) STORED` | `STORED` | MySQL, MariaDB, SQLite, PostgreSQL, CockroachDB, DuckDB |
| | | `PERSISTED` | SQL Server, SingleStore |
| | | `MATERIALIZED` | ClickHouse |
| | | `PERSISTENT` | MariaDB (旧语法别名) |
| | | `GENERATED ALWAYS AS (...)` (仅此，隐含 STORED) | DB2, Derby, SAP HANA, HSQLDB |
| 虚拟生成列 | `GENERATED ALWAYS AS (...) VIRTUAL` | `VIRTUAL` | MySQL, MariaDB, SQLite, Oracle, DuckDB |
| | | `AS (expr)` (无 PERSISTED 关键字) | SQL Server |
| | | `ALIAS` | ClickHouse |
| | | `COMPUTED [BY]` | Firebird (旧语法) |
| | | `column AS expr` | Flink SQL |

### 表达式限制

| 引擎 | 仅确定性 | 子查询 | UDF | 引用其他生成列 | 引用其他表 |
|------|---------|--------|-----|-------------|-----------|
| PostgreSQL | 是 (IMMUTABLE) | 不允许 | 仅 IMMUTABLE 函数 | 不允许 | 不允许 |
| MySQL | STORED: 是; VIRTUAL: 否 | 不允许 | 不允许 (8.0.13+ 内部函数扩展) | 不允许 | 不允许 |
| MariaDB | STORED: 是; VIRTUAL: 否 | 不允许 | 不允许 | 不允许 (10.2.8+ 部分支持) | 不允许 |
| SQLite | 是 | 不允许 | 不允许 | 不允许 | 不允许 |
| Oracle | 是 (DETERMINISTIC) | 不允许 | 仅 DETERMINISTIC UDF | 允许 (链式引用) | 不允许 |
| SQL Server | 索引/PERSISTED: 是 | 不允许 | 仅确定性 UDF | 允许 (链式引用) | 不允许 |
| DB2 | 是 | 不允许 | 仅 DETERMINISTIC UDF | 不允许 | 不允许 |
| ClickHouse | 否 (MATERIALIZED 允许 now() 等) | 不允许 | 允许 | 允许 | 不允许 |
| CockroachDB | 是 (IMMUTABLE/STABLE) | 不允许 | 仅 IMMUTABLE UDF | 不允许 | 不允许 |
| TiDB | STORED: 是; VIRTUAL: 否 | 不允许 | 不允许 | 不允许 | 不允许 |
| DuckDB | 是 | 不允许 | 允许 | 允许 | 不允许 |
| Spark SQL | 是 | 不允许 | 不允许 | 不允许 | 不允许 |
| Google Spanner | 是 | 不允许 | 不允许 | 允许 | 不允许 |
| H2 | 是 | 不允许 | 仅 DETERMINISTIC UDF | 允许 | 不允许 |
| Firebird | 是 | 不允许 | 不允许 | 不允许 | 不允许 |

### 索引与约束支持

| 引擎 | 生成列索引 | 生成列做 PRIMARY KEY | 生成列做 FOREIGN KEY 引用 | ALTER TABLE ADD 生成列 |
|------|----------|--------------------|-----------------------|----------------------|
| PostgreSQL | 支持 (STORED) | 不支持 | 支持 (STORED) | 支持 (需回填) |
| MySQL | 支持 (STORED + VIRTUAL) | 不支持 | 不支持 | 支持 (VIRTUAL 即时; STORED 回填) |
| MariaDB | 支持 (STORED + VIRTUAL) | 不支持 | 不支持 | 支持 |
| SQLite | 支持 | 不支持 | 不支持 | 不支持 (SQLite ALTER TABLE 限制) |
| Oracle | 支持 (VIRTUAL) | 不支持 | 不支持 | 支持 (即时) |
| SQL Server | 支持 (PERSISTED + 非 PERSISTED) | 支持 (PERSISTED, 确定性) | 支持 (PERSISTED) | 支持 |
| DB2 | 支持 | 不支持 | 支持 | 支持 (需 REORG) |
| ClickHouse | 支持 (MATERIALIZED) | 不适用 (无主键约束) | 不适用 | 支持 |
| CockroachDB | 支持 (STORED + VIRTUAL) | 不支持 | 支持 (STORED) | 支持 |
| TiDB | 支持 (STORED + VIRTUAL) | 不支持 | 不支持 | 支持 |
| DuckDB | 支持 | 不支持 | 不支持 | 支持 |
| Spark SQL / Databricks | 不适用 (无传统索引) | 不适用 | 不适用 | 支持 |
| Google Spanner | 支持 (STORED) | 支持 (STORED) | 支持 (STORED) | 支持 (需回填) |
| SingleStore | 支持 (PERSISTED) | 支持 (PERSISTED) | 支持 (PERSISTED) | 支持 |
| StarRocks | 支持 | 不支持 | 不适用 | 支持 |
| H2 | 支持 | 不支持 | 不支持 | 支持 |
| Firebird | 支持 (STORED 3.0+) | 不支持 | 不支持 | 支持 |
| SAP HANA | 支持 | 不支持 | 不支持 | 支持 |
| CrateDB | 支持 | 不支持 | 不适用 (无外键) | 支持 |

### 类型推断 vs 显式声明

| 引擎 | 类型推断 | 显式声明 | 说明 |
|------|---------|---------|------|
| PostgreSQL | 不支持 | 必须显式声明 | 数据类型必须写在 GENERATED ALWAYS AS 之前 |
| MySQL | 支持 (可省略类型) | 支持 | 省略时从表达式推断 |
| MariaDB | 支持 (可省略类型) | 支持 | 省略时从表达式推断 |
| SQLite | 支持 (动态类型) | 支持 | SQLite 本身是动态类型 |
| Oracle | 支持 (自动推断) | 可选 | 类型可省略，从表达式推断 |
| SQL Server | 支持 (自动推断) | 不支持 (无需写类型) | 计算列类型完全由表达式决定 |
| DB2 | 不支持 | 必须显式声明 | 数据类型必须写 |
| ClickHouse | 支持 (自动推断) | 可选 | MATERIALIZED/ALIAS 可省略类型 |
| CockroachDB | 支持 (自动推断) | 可选 | 类型从表达式推断 |
| TiDB | 支持 (可省略类型) | 支持 | 兼容 MySQL |
| DuckDB | 支持 (自动推断) | 可选 | 类型可省略 |
| Google Spanner | 不支持 | 必须显式声明 | 类型必须写 |
| Spark SQL | 支持 (自动推断) | 可选 | Delta Lake 生成列 |
| H2 | 支持 (自动推断) | 可选 | 类型可省略 |

## 各引擎详细语法

### PostgreSQL 12+

PostgreSQL 仅支持 STORED 生成列。表达式中的函数必须标记为 `IMMUTABLE`。

```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    -- 仅 STORED，类型必须显式声明
    full_name VARCHAR(101) GENERATED ALWAYS AS (first_name || ' ' || last_name) STORED,
    email VARCHAR(200),
    email_domain VARCHAR(100) GENERATED ALWAYS AS (split_part(email, '@', 2)) STORED,
    -- JSONB 提取
    profile JSONB,
    city TEXT GENERATED ALWAYS AS ((profile ->> 'city')) STORED
);

-- 支持在 STORED 生成列上创建索引
CREATE INDEX idx_full_name ON users (full_name);

-- 不支持 VIRTUAL，但可用表达式索引替代
CREATE INDEX idx_lower_email ON users (lower(email));

-- ALTER TABLE 添加生成列（需回填所有现有行）
ALTER TABLE users ADD COLUMN name_length INT GENERATED ALWAYS AS (length(first_name) + length(last_name)) STORED;
```

PostgreSQL 不支持 VIRTUAL 列的原因：
1. 元组格式假设每列都有物理存储
2. 表达式索引 (`CREATE INDEX ON t ((a + b))`) 已覆盖主要场景
3. VIEW 可作为替代方案
4. 需修改存储层、执行器、pg_dump、逻辑复制等多个组件

PostgreSQL 17 仍未支持 VIRTUAL 列，社区有活跃的补丁在开发中。

### MySQL 5.7.6+

MySQL 默认生成 VIRTUAL 列。`GENERATED ALWAYS` 关键字可省略。

```sql
CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    -- VIRTUAL（默认）: 查询时计算
    full_name VARCHAR(101) GENERATED ALWAYS AS (CONCAT(first_name, ' ', last_name)) VIRTUAL,
    -- 也可省略 GENERATED ALWAYS
    full_name_v2 VARCHAR(101) AS (CONCAT(first_name, ' ', last_name)) VIRTUAL,
    -- STORED: 写入时计算并持久化
    email VARCHAR(200),
    email_domain VARCHAR(100) GENERATED ALWAYS AS (SUBSTRING_INDEX(email, '@', -1)) STORED,
    -- JSON 提取
    profile JSON,
    city VARCHAR(100) AS (JSON_UNQUOTE(JSON_EXTRACT(profile, '$.city'))) VIRTUAL
);

-- VIRTUAL 列可以建 B-tree 和全文索引
CREATE INDEX idx_full_name ON users(full_name);

-- MySQL 8.0.13+: VIRTUAL 列支持 DEFAULT 表达式 (非 GENERATED)
-- 注意: VIRTUAL 生成列不能有 DEFAULT 值
-- 注意: BEFORE INSERT 触发器看不到 VIRTUAL 列的值
```

MySQL 的限制：
- 生成列不能引用其他生成列
- 不能使用子查询、存储程序、用户变量
- VIRTUAL 列允许非确定性函数，STORED 列不允许
- InnoDB VIRTUAL 列不支持作为外键

### MariaDB 5.2+ / 10.2+

MariaDB 是最早支持虚拟列的开源数据库 (5.2.0, 2010 年)，比 MySQL 5.7 早数年。

```sql
CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    -- VIRTUAL（默认）
    full_name VARCHAR(101) AS (CONCAT(first_name, ' ', last_name)) VIRTUAL,
    -- PERSISTENT / STORED (两个关键字等价)
    email VARCHAR(200),
    email_domain VARCHAR(100) AS (SUBSTRING_INDEX(email, '@', -1)) PERSISTENT,
    -- 10.2+: 也接受 STORED 关键字
    email_user VARCHAR(100) AS (SUBSTRING_INDEX(email, '@', 1)) STORED
);

-- MariaDB 10.2+: 虚拟列索引
CREATE INDEX idx_full_name ON users(full_name);

-- MariaDB 特有: PERSISTENT 是 MariaDB 自有关键字
-- STORED 是后来为兼容 MySQL 5.7+ 添加的别名
```

### SQLite 3.31.0+

SQLite 默认为 VIRTUAL。`GENERATED ALWAYS` 关键字可省略。

```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    -- VIRTUAL（默认）
    full_name TEXT GENERATED ALWAYS AS (first_name || ' ' || last_name) VIRTUAL,
    -- 也可省略 GENERATED ALWAYS
    full_name_v2 TEXT AS (first_name || ' ' || last_name),
    -- STORED
    data_json TEXT,
    category TEXT GENERATED ALWAYS AS (json_extract(data_json, '$.category')) STORED
);

-- SQLite 限制: ALTER TABLE 不支持添加生成列
-- ALTER TABLE users ADD COLUMN new_gen TEXT AS (...);  -- 不支持
```

SQLite 的特殊限制：
- ALTER TABLE ADD COLUMN 不支持生成列
- 表达式不能使用子查询
- 不能引用其他生成列
- 不能使用非确定性函数

### Oracle 11g R1+

Oracle 称之为 "Virtual Column"。仅支持 VIRTUAL（不支持 STORED）。

```sql
CREATE TABLE users (
    id NUMBER GENERATED BY DEFAULT AS IDENTITY,
    first_name VARCHAR2(50),
    last_name VARCHAR2(50),
    -- 虚拟列: 类型可省略（自动推断）
    full_name VARCHAR2(101) AS (first_name || ' ' || last_name),
    -- 显式写 VIRTUAL 关键字
    email VARCHAR2(200),
    email_domain VARCHAR2(100) AS (SUBSTR(email, INSTR(email, '@') + 1)) VIRTUAL
);

-- 虚拟列可以创建索引
CREATE INDEX idx_full_name ON users(full_name);

-- Oracle 杀手级功能: 虚拟列做分区键
CREATE TABLE orders (
    order_id NUMBER,
    order_date DATE,
    order_month NUMBER AS (EXTRACT(MONTH FROM order_date))
) PARTITION BY LIST (order_month) (
    PARTITION p_q1 VALUES (1, 2, 3),
    PARTITION p_q2 VALUES (4, 5, 6),
    PARTITION p_q3 VALUES (7, 8, 9),
    PARTITION p_q4 VALUES (10, 11, 12)
);

-- 虚拟列可以引用其他虚拟列（链式引用）
CREATE TABLE calc (
    a NUMBER,
    b NUMBER,
    c NUMBER AS (a + b),
    d NUMBER AS (c * 2)  -- 引用另一个虚拟列 c
);

-- 12c+: 虚拟列可以使用 DETERMINISTIC UDF
CREATE FUNCTION tax_rate(amount NUMBER) RETURN NUMBER DETERMINISTIC IS
BEGIN RETURN amount * 0.08; END;
/
ALTER TABLE orders ADD tax_amount NUMBER AS (tax_rate(total_amount));
```

### SQL Server 2005+ (计算列)

SQL Server 使用 "Computed Column" 术语。默认为非 PERSISTED（类似 VIRTUAL），添加 `PERSISTED` 关键字后持久化。

```sql
CREATE TABLE users (
    id INT IDENTITY(1,1) PRIMARY KEY,
    first_name NVARCHAR(50),
    last_name NVARCHAR(50),
    -- 非 PERSISTED（默认）: 查询时计算
    full_name AS (first_name + N' ' + last_name),
    -- PERSISTED: 物理存储
    email NVARCHAR(200),
    email_domain AS (RIGHT(email, LEN(email) - CHARINDEX(N'@', email))) PERSISTED
);

-- 非 PERSISTED 和 PERSISTED 都可以建索引
-- 但索引列表达式必须是确定性的
CREATE INDEX idx_full_name ON users(full_name);

-- SQL Server 特有: 计算列可以做 PRIMARY KEY
CREATE TABLE t (
    a INT NOT NULL,
    b INT NOT NULL,
    c AS (a + b) PERSISTED NOT NULL,
    PRIMARY KEY (c)
);

-- 计算列可以引用其他计算列
CREATE TABLE calc (
    a INT,
    b INT,
    c AS (a + b),
    d AS (a + b + 1)  -- 可以使用相同基础列
);

-- 计算列可以作为 FOREIGN KEY 引用目标（PERSISTED 且确定性）
-- 计算列也可以做 CHECK 约束
ALTER TABLE orders ADD total AS (quantity * price) PERSISTED;
ALTER TABLE orders ADD CONSTRAINT chk_total CHECK (total > 0);
```

### DB2 (LUW) 9.5+

DB2 仅支持 STORED 生成列。

```sql
CREATE TABLE users (
    id INT NOT NULL GENERATED ALWAYS AS IDENTITY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    -- GENERATED ALWAYS AS (隐含 STORED)
    full_name VARCHAR(101) GENERATED ALWAYS AS (first_name || ' ' || last_name)
);

-- ALTER TABLE 添加生成列后需要 REORG
ALTER TABLE users ADD COLUMN name_len INT GENERATED ALWAYS AS (LENGTH(first_name) + LENGTH(last_name));
REORG TABLE users;

-- 支持索引
CREATE INDEX idx_full_name ON users(full_name);
```

### ClickHouse 20.1+

ClickHouse 使用 `MATERIALIZED`（写入时计算，物理存储）和 `ALIAS`（查询时计算，虚拟）。

```sql
CREATE TABLE users (
    id UInt64,
    first_name String,
    last_name String,
    -- MATERIALIZED: 写入时计算并存储
    full_name String MATERIALIZED concat(first_name, ' ', last_name),
    -- ALIAS: 查询时计算
    name_length UInt32 ALIAS length(first_name) + length(last_name),
    -- 类型可省略（自动推断）
    created_at DateTime DEFAULT now(),
    created_date Date MATERIALIZED toDate(created_at)
) ENGINE = MergeTree() ORDER BY id;

-- 关键差异: MATERIALIZED 列不包含在 SELECT * 中
SELECT * FROM users;           -- 不包含 full_name
SELECT *, full_name FROM users; -- 需要显式列出

-- ALIAS 列同样不在 SELECT * 中
SELECT *, name_length FROM users;

-- ClickHouse 允许非确定性表达式
-- MATERIALIZED now() 是合法的 (捕获插入时间)

-- ALTER TABLE 添加 MATERIALIZED 列
ALTER TABLE users ADD COLUMN upper_name String MATERIALIZED upper(first_name);
```

### DuckDB 0.8.0+

DuckDB 支持 VIRTUAL 和 STORED 生成列。

```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    first_name VARCHAR,
    last_name VARCHAR,
    -- VIRTUAL（默认）
    full_name VARCHAR GENERATED ALWAYS AS (first_name || ' ' || last_name),
    -- STORED
    email VARCHAR,
    email_domain VARCHAR GENERATED ALWAYS AS (split_part(email, '@', 2)) STORED
);

-- 类型可省略（自动推断）
CREATE TABLE calc (
    a INTEGER,
    b INTEGER,
    c GENERATED ALWAYS AS (a + b)
);

-- DuckDB 允许生成列引用其他生成列
CREATE TABLE chain (
    x INTEGER,
    y GENERATED ALWAYS AS (x * 2),
    z GENERATED ALWAYS AS (y + 1)  -- 引用生成列 y
);

-- ALTER TABLE 添加生成列
ALTER TABLE users ADD COLUMN name_len INTEGER GENERATED ALWAYS AS (length(first_name));
```

### CockroachDB 22.1+

CockroachDB 使用类似 PostgreSQL 的语法，但 22.2+ 扩展支持了 VIRTUAL 列。

```sql
CREATE TABLE users (
    id INT PRIMARY KEY DEFAULT unique_rowid(),
    first_name STRING,
    last_name STRING,
    -- STORED 生成列 (22.1+)
    full_name STRING AS (first_name || ' ' || last_name) STORED,
    -- VIRTUAL 生成列 (22.2+)
    name_length INT AS (length(first_name) + length(last_name)) VIRTUAL
);

-- 支持在 STORED 和 VIRTUAL 列上建索引
CREATE INDEX idx_full_name ON users (full_name);
CREATE INDEX idx_name_len ON users (name_length);

-- 表达式只能使用 IMMUTABLE 或 STABLE 函数
-- 不支持引用其他生成列
```

### TiDB 2.1+

TiDB 兼容 MySQL 语法，支持 VIRTUAL 和 STORED。

```sql
CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    -- VIRTUAL（默认）
    full_name VARCHAR(101) AS (CONCAT(first_name, ' ', last_name)) VIRTUAL,
    -- STORED
    email VARCHAR(200),
    email_domain VARCHAR(100) AS (SUBSTRING_INDEX(email, '@', -1)) STORED
);

-- TiDB 支持 VIRTUAL 和 STORED 列的索引
CREATE INDEX idx_full_name ON users(full_name);

-- TiDB 特有: VIRTUAL 列不支持外键
-- TiDB 不支持生成列引用其他生成列
```

### OceanBase (MySQL 模式)

OceanBase MySQL 模式兼容 MySQL 的生成列语法。

```sql
CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    full_name VARCHAR(101) GENERATED ALWAYS AS (CONCAT(first_name, ' ', last_name)) VIRTUAL,
    email VARCHAR(200),
    email_domain VARCHAR(100) GENERATED ALWAYS AS (SUBSTRING_INDEX(email, '@', -1)) STORED
);

-- 支持 VIRTUAL 和 STORED 列索引
CREATE INDEX idx_full_name ON users(full_name);
```

### Spark SQL / Databricks (Delta Lake)

Spark SQL 仅在 Delta Lake 表上支持生成列，且仅支持 STORED。

```sql
-- Databricks / Delta Lake
CREATE TABLE users (
    id BIGINT,
    first_name STRING,
    last_name STRING,
    full_name STRING GENERATED ALWAYS AS (concat(first_name, ' ', last_name)),
    event_date DATE GENERATED ALWAYS AS (CAST(event_timestamp AS DATE)),
    event_timestamp TIMESTAMP
) USING DELTA;

-- Delta Lake 生成列的主要用途: 分区列自动计算
CREATE TABLE events (
    event_id BIGINT,
    event_timestamp TIMESTAMP,
    event_date DATE GENERATED ALWAYS AS (CAST(event_timestamp AS DATE))
) USING DELTA
PARTITIONED BY (event_date);
-- 用户只需插入 event_timestamp，event_date 自动计算并用于分区
```

### Flink SQL 1.12+

Flink SQL 的生成列 (computed column) 语法独特：直接用 `AS` 表达式。

```sql
CREATE TABLE users (
    id BIGINT,
    first_name STRING,
    last_name STRING,
    -- Flink SQL 的计算列 (VIRTUAL)
    full_name AS CONCAT(first_name, ' ', last_name),
    -- 常见用途: 从事件时间提取水印
    event_time TIMESTAMP(3),
    proc_time AS PROCTIME(),           -- 处理时间
    event_date AS CAST(event_time AS DATE),
    -- 水印定义
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'users',
    'format' = 'json'
);

-- Flink SQL 计算列是 VIRTUAL 的 (不持久化)
-- 主要用于流式处理场景的时间属性计算
```

### SingleStore (MemSQL) 7.0+

SingleStore 使用 `PERSISTED` 和 `COMPUTED` 关键字。

```sql
CREATE TABLE users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    -- PERSISTED: 物理存储
    full_name VARCHAR(101) AS (CONCAT(first_name, ' ', last_name)) PERSISTED,
    -- COMPUTED: 非持久化 (查询时计算)
    name_length INT AS (CHAR_LENGTH(first_name) + CHAR_LENGTH(last_name)) COMPUTED
);

-- SingleStore 特有: PERSISTED 列可以做 PRIMARY KEY
CREATE TABLE computed_pk (
    a INT NOT NULL,
    b INT NOT NULL,
    pk INT AS (a * 1000 + b) PERSISTED,
    PRIMARY KEY (pk)
);

-- PERSISTED 列可以做 SHARD KEY
CREATE TABLE sharded (
    id BIGINT,
    region VARCHAR(10),
    shard_val INT AS (CRC32(region) % 8) PERSISTED,
    SHARD KEY (shard_val)
);
```

### Google Spanner 2021+

Spanner 仅支持 STORED 生成列，类型必须显式声明。

```sql
CREATE TABLE users (
    user_id INT64 NOT NULL,
    first_name STRING(50),
    last_name STRING(50),
    -- STORED 生成列（类型必须写）
    full_name STRING(101) NOT NULL GENERATED ALWAYS AS (first_name || ' ' || last_name) STORED,
    -- 生成列可以引用其他生成列
    name_upper STRING(101) GENERATED ALWAYS AS (UPPER(full_name)) STORED
) PRIMARY KEY (user_id);

-- Spanner 特有: 生成列可以做 PRIMARY KEY
CREATE TABLE events (
    event_id STRING(36) NOT NULL,
    event_date DATE NOT NULL GENERATED ALWAYS AS (EXTRACT(DATE FROM event_timestamp)) STORED,
    event_timestamp TIMESTAMP NOT NULL
) PRIMARY KEY (event_date, event_id);
-- 生成列做 PRIMARY KEY 用于自动分区

-- 支持索引
CREATE INDEX idx_full_name ON users(full_name);
```

### StarRocks 3.1+

StarRocks 支持 generated column，仅 STORED。

```sql
CREATE TABLE users (
    id BIGINT,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    full_name VARCHAR(101) AS (concat(first_name, ' ', last_name))
) ENGINE = OLAP
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8;

-- 主要用途: 自动物化计算结果，加速查询
-- ALTER TABLE 添加生成列
ALTER TABLE users ADD COLUMN name_len INT AS (length(first_name) + length(last_name));
```

### Firebird 3.0+

Firebird 支持两种语法：标准 `GENERATED ALWAYS AS` 和传统 `COMPUTED [BY]`。

```sql
CREATE TABLE users (
    id INTEGER NOT NULL PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    -- 标准语法 (3.0+)
    full_name VARCHAR(101) GENERATED ALWAYS AS (first_name || ' ' || last_name),
    -- 传统语法 (兼容旧版本)
    name_length INTEGER COMPUTED BY (CHAR_LENGTH(first_name) + CHAR_LENGTH(last_name))
);

-- COMPUTED BY 是 Firebird 从 InterBase 继承的传统语法
-- 两种语法都产生 VIRTUAL (查询时计算) 行为
-- Firebird 3.0+ 的 GENERATED ALWAYS AS 可以配合索引使用
```

### H2 1.4+

H2 同时支持 VIRTUAL 和 STORED 生成列。

```sql
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    -- 生成列（类型可省略）
    full_name VARCHAR(101) GENERATED ALWAYS AS (first_name || ' ' || last_name),
    -- 简写语法
    name_length AS (LENGTH(first_name) + LENGTH(last_name))
);

-- H2 允许生成列引用其他生成列
CREATE TABLE calc (
    a INT,
    b INT,
    c INT GENERATED ALWAYS AS (a + b),
    d INT GENERATED ALWAYS AS (c * 2)
);
```

### SAP HANA 2.0 SPS 03+

SAP HANA 仅支持 STORED 生成列。

```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    first_name NVARCHAR(50),
    last_name NVARCHAR(50),
    full_name NVARCHAR(101) GENERATED ALWAYS AS (first_name || ' ' || last_name)
);

-- ALTER TABLE 添加生成列
ALTER TABLE users ADD (name_len INTEGER GENERATED ALWAYS AS (LENGTH(first_name) + LENGTH(last_name)));
```

### CrateDB 4.0+

CrateDB 支持 STORED 生成列。

```sql
CREATE TABLE users (
    id BIGINT,
    first_name TEXT,
    last_name TEXT,
    full_name TEXT GENERATED ALWAYS AS (first_name || ' ' || last_name),
    created_at TIMESTAMP WITH TIME ZONE,
    created_month TIMESTAMP GENERATED ALWAYS AS (date_trunc('month', created_at))
);

-- CrateDB 的生成列可以做分区键
CREATE TABLE events (
    id BIGINT,
    event_time TIMESTAMP,
    event_month TIMESTAMP GENERATED ALWAYS AS (date_trunc('month', event_time))
) PARTITIONED BY (event_month);
```

### Databend 1.2+

Databend 支持 VIRTUAL 和 STORED 生成列。

```sql
CREATE TABLE users (
    id INT,
    first_name VARCHAR,
    last_name VARCHAR,
    full_name VARCHAR GENERATED ALWAYS AS (CONCAT(first_name, ' ', last_name)) VIRTUAL,
    email VARCHAR,
    email_domain VARCHAR GENERATED ALWAYS AS (SPLIT_PART(email, '@', 2)) STORED
);
```

### HSQLDB 2.5+ / Derby 10.5+

这两个 Java 嵌入式数据库都遵循 SQL 标准语法，仅支持 STORED。

```sql
-- HSQLDB
CREATE TABLE users (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    full_name VARCHAR(101) GENERATED ALWAYS AS (first_name || ' ' || last_name)
);

-- Derby
CREATE TABLE users (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    full_name VARCHAR(101) GENERATED ALWAYS AS (first_name || ' ' || last_name)
);
```

### Exasol 7.0+

Exasol 的生成列通过 `DEFAULT` 表达式实现，行为类似虚拟列。

```sql
CREATE TABLE users (
    id DECIMAL(18,0) IDENTITY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    -- DEFAULT 表达式（查询时计算，类似 VIRTUAL）
    full_name VARCHAR(101) DEFAULT first_name || ' ' || last_name
);
-- 注意: Exasol 的 DEFAULT 表达式可以引用其他列
-- 这与传统数据库 DEFAULT 只接受常量不同
```

## GENERATED IDENTITY 列 (自增标识列)

SQL:2003 标准除了生成列之外，还定义了 identity column 语法。各引擎的自增主键机制差异更大：

| 引擎 | 标准 IDENTITY 语法 | 专有语法 | 版本 |
|------|-------------------|---------|------|
| PostgreSQL | `GENERATED {ALWAYS\|BY DEFAULT} AS IDENTITY` | `SERIAL` / `BIGSERIAL` (旧) | 10+ (IDENTITY) |
| MySQL | 不支持 | `AUTO_INCREMENT` | 早期 |
| MariaDB | 不支持 | `AUTO_INCREMENT` | 早期 |
| SQLite | 不支持 | `INTEGER PRIMARY KEY` (隐式 ROWID) | 早期 |
| Oracle | `GENERATED {ALWAYS\|BY DEFAULT [ON NULL]} AS IDENTITY` | 序列 + 触发器 (旧) | 12c+ (IDENTITY) |
| SQL Server | `IDENTITY(seed, increment)` | 同左 | 早期 |
| DB2 | `GENERATED {ALWAYS\|BY DEFAULT} AS IDENTITY` | 同左 | 早期 |
| Snowflake | `IDENTITY(start, step)` / `AUTOINCREMENT` | 同左 | GA |
| BigQuery | 不支持 | 无 (通常用 `GENERATE_UUID()`) | - |
| DuckDB | `GENERATED ALWAYS AS IDENTITY` | 序列 | 0.8.0+ |
| ClickHouse | 不支持 | 无 (通常由客户端生成) | - |
| CockroachDB | `GENERATED {ALWAYS\|BY DEFAULT} AS IDENTITY` | `SERIAL` / `unique_rowid()` | 21.1+ |
| TiDB | 不支持 | `AUTO_INCREMENT` / `AUTO_RANDOM` | 早期 |
| OceanBase | MySQL 模式: `AUTO_INCREMENT`; Oracle 模式: `IDENTITY` | 同左 | 3.x+ |
| Google Spanner | 不支持 | 无 (UUID 或位反转序列) | - |
| SAP HANA | `GENERATED ALWAYS AS IDENTITY` | 同左 | 2.0+ |
| Firebird | `GENERATED ALWAYS AS IDENTITY` | 序列 + 触发器 (旧) | 3.0+ |
| H2 | `GENERATED ALWAYS AS IDENTITY` | `AUTO_INCREMENT` / `IDENTITY` | 2.0+ |
| HSQLDB | `GENERATED {ALWAYS\|BY DEFAULT} AS IDENTITY` | `IDENTITY` | 2.0+ |
| Derby | `GENERATED {ALWAYS\|BY DEFAULT} AS IDENTITY` | 同左 | 10.1+ |
| Exasol | `IDENTITY` / `DECIMAL IDENTITY` | 同左 | 早期 |
| SingleStore | 不支持 | `AUTO_INCREMENT` | 早期 |
| Greenplum | `GENERATED {ALWAYS\|BY DEFAULT} AS IDENTITY` | `SERIAL` (旧) | 7+ (PG12 base) |

```sql
-- SQL 标准 (SQL:2003)
CREATE TABLE orders (
    id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    amount DECIMAL(10,2)
);

-- GENERATED ALWAYS: 用户不能手动指定值
INSERT INTO orders (amount) VALUES (99.99);

-- GENERATED BY DEFAULT: 用户可以手动指定值
CREATE TABLE orders_v2 (
    id INT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    amount DECIMAL(10,2)
);
INSERT INTO orders_v2 (id, amount) VALUES (100, 99.99);  -- 手动指定 id

-- Oracle 12c+: BY DEFAULT ON NULL (NULL 时自动生成)
CREATE TABLE orders_v3 (
    id NUMBER GENERATED BY DEFAULT ON NULL AS IDENTITY,
    amount NUMBER(10,2)
);
INSERT INTO orders_v3 (id, amount) VALUES (NULL, 99.99);  -- id 自动生成
```

## STORED vs VIRTUAL 性能权衡

### 写入性能

| 场景 | STORED | VIRTUAL | 胜者 |
|------|--------|---------|-----|
| INSERT 吞吐量 | 需要额外计算并写入 | 无额外开销 | VIRTUAL |
| UPDATE 涉及依赖列 | 重新计算并写入 | 无额外开销 | VIRTUAL |
| BULK INSERT / COPY | 逐行计算，影响批量写入速度 | 无影响 | VIRTUAL |
| 存储空间 | 占用额外磁盘空间 | 零额外空间（除索引外） | VIRTUAL |

### 读取性能

| 场景 | STORED | VIRTUAL | 胜者 |
|------|--------|---------|-----|
| 简单 SELECT | 直接读取，零计算 | 每行实时计算 | STORED |
| 复杂表达式 | 直接读取 | 每次查询重算（如正则、JSON 解析） | STORED |
| SELECT * | 直接读取 | 所有 VIRTUAL 列都会触发计算 | STORED |
| 全表扫描 | 直接读取 | 百万行 × 表达式计算 | STORED |
| 索引查询 | 从索引直接取值 | MySQL/Oracle: 从索引取值（无需计算） | 平局 |

### 索引行为差异

VIRTUAL 列上的索引是一个精妙的实现：

```
VIRTUAL 列 + 索引:
- 列本身不占存储空间
- 但索引中物理存储了计算结果
- INSERT 时: 计算表达式 → 写入索引（不写列数据）
- WHERE virtual_col = 'x': 走索引查找
- SELECT virtual_col: 可能从索引取值，或实时计算

效果: 等同于 PostgreSQL 的表达式索引 (expression index)
CREATE INDEX idx ON t ((a + b));  -- PostgreSQL 表达式索引
```

### 实际选择建议

| 场景 | 推荐类型 | 原因 |
|------|---------|------|
| 读多写少，表达式复杂 | STORED | 避免重复计算，读性能最优 |
| 写多读少 | VIRTUAL | 不影响写入吞吐 |
| 需要索引且引擎只支持 STORED | STORED | PostgreSQL、DB2 等只支持 STORED |
| 简单拼接（如全名） | VIRTUAL | 计算代价极低 |
| JSON 字段提取并索引 | VIRTUAL + INDEX | MySQL/Oracle 中效果最佳 |
| 磁盘空间敏感 | VIRTUAL | 零额外存储 |
| 大批量 ETL 写入 | VIRTUAL 或不用生成列 | 避免 STORED 列的写入放大 |
| 分区键（Oracle） | VIRTUAL | Oracle 虚拟列可做分区键 |
| 分区键（Spanner/CrateDB） | STORED | 这些引擎要求 STORED |

### 性能陷阱

```sql
-- 陷阱 1: STORED 列的写入放大
-- 表有 10 个 STORED 生成列 → 每次 INSERT 额外计算 10 个表达式
-- 高写入场景慎用 STORED

-- 陷阱 2: SELECT * 触发 VIRTUAL 列计算
SELECT * FROM big_table;  -- 所有 VIRTUAL 列都会被计算
-- 改用显式列名: SELECT col1, col2 FROM big_table;

-- 陷阱 3: ClickHouse MATERIALIZED 列不在 SELECT * 中
SELECT * FROM ch_table;           -- 不包含 MATERIALIZED 列
SELECT *, mat_col FROM ch_table;  -- 需显式列出

-- 陷阱 4: ALTER TABLE ADD STORED 列需要回填
ALTER TABLE big_table ADD COLUMN gen_col INT GENERATED ALWAYS AS (a + b) STORED;
-- 对于有 1 亿行的表，需要逐行计算并写入，可能耗时数小时
-- VIRTUAL 列则是即时完成

-- 陷阱 5: 更新依赖列触发 STORED 列重算
UPDATE users SET first_name = '李' WHERE id = 1;
-- full_name (STORED) 自动重新计算
-- 如果有索引，索引也需要更新
```

## 关键发现

1. **语法分裂严重**: 同一概念至少有 6 种关键字变体 (STORED / PERSISTED / MATERIALIZED / PERSISTENT / VIRTUAL / ALIAS / COMPUTED BY)，移植 DDL 时需逐一转换。

2. **STORED vs VIRTUAL 能力不对称**: PostgreSQL/DB2/SAP HANA 只支持 STORED；Oracle 只支持 VIRTUAL；MySQL/MariaDB/SQL Server/CockroachDB 两者都支持。没有任何引擎完全对称地实现了这两种模式的所有功能。

3. **云原生数据仓库普遍不支持**: Snowflake、BigQuery、Redshift、Azure Synapse、Firebolt、Yellowbrick 等分析型引擎均不提供生成列，因为列式存储引擎更倾向于通过物化视图或 VIEW 来实现类似功能。

4. **流式引擎有独特实现**: Flink SQL 的计算列 (`col AS expr`) 主要用于时间属性计算和水印定义，与传统 RDBMS 的生成列目的不同。

5. **Oracle 的虚拟列做分区键**是独有的杀手级功能，允许按计算值自动分区而不占用存储空间。CrateDB 和 Spark SQL/Delta Lake 的生成列做分区键需要 STORED。

6. **SQL Server 是约束最灵活的引擎**: 计算列可以做 PRIMARY KEY (PERSISTED)、FOREIGN KEY 引用目标、CHECK 约束目标，且非 PERSISTED 列也支持索引（引擎自动物化索引值）。

7. **Google Spanner 允许生成列做 PRIMARY KEY**: 这在大多数引擎中不允许，Spanner 利用此特性实现自动分区键计算。

8. **ClickHouse 的 MATERIALIZED/ALIAS 有特殊的 SELECT * 行为**: 这两种列都不出现在 `SELECT *` 结果中，需要显式列出，这与所有其他引擎的行为截然不同。

9. **生成列的链式引用**（生成列引用另一个生成列）仅 Oracle、SQL Server、DuckDB、H2、Google Spanner 支持，PostgreSQL、MySQL、SQLite、CockroachDB 均不允许。

10. **ALTER TABLE ADD STORED 生成列的成本**: 对于大表，添加 STORED 列需要回填所有现有行，可能耗时很长；添加 VIRTUAL 列则通常是即时操作（仅修改元数据）。

## 参考资料

- SQL:2003 Standard (ISO/IEC 9075-2:2003) Section 11.4 - generation clause
- PostgreSQL: [Generated Columns](https://www.postgresql.org/docs/current/ddl-generated-columns.html)
- MySQL: [Generated Columns](https://dev.mysql.com/doc/refman/8.0/en/create-table-generated-columns.html)
- MariaDB: [Generated/Virtual Columns](https://mariadb.com/kb/en/generated-columns/)
- Oracle: [Virtual Columns](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-TABLE.html)
- SQL Server: [Computed Columns](https://learn.microsoft.com/en-us/sql/relational-databases/tables/specify-computed-columns-in-a-table)
- DB2: [Generated Columns](https://www.ibm.com/docs/en/db2/11.5?topic=expressions-generated-column)
- ClickHouse: [DEFAULT / MATERIALIZED / ALIAS](https://clickhouse.com/docs/en/sql-reference/statements/create/table#default_values)
- DuckDB: [Generated Columns](https://duckdb.org/docs/sql/statements/create_table#generated-columns)
- CockroachDB: [Computed Columns](https://www.cockroachlabs.com/docs/stable/computed-columns.html)
- TiDB: [Generated Columns](https://docs.pingcap.com/tidb/stable/generated-columns/)
- Google Spanner: [Generated Columns](https://cloud.google.com/spanner/docs/generated-column/how-to)
- Spark SQL / Delta Lake: [Generated Columns](https://docs.delta.io/latest/delta-batch.html#use-generated-columns)
- Flink SQL: [Computed Columns](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/create/#computed-column)
- SingleStore: [Computed Columns](https://docs.singlestore.com/cloud/reference/sql-reference/data-definition-language-ddl/create-table/)
- Firebird: [Computed Columns](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html)
- CrateDB: [Generated Columns](https://crate.io/docs/crate/reference/en/latest/general/ddl/generated-columns.html)
- SAP HANA: [Generated Columns](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20d58a5f75191014b2fe92141b7df228.html)
- StarRocks: [Generated Columns](https://docs.starrocks.io/docs/sql-reference/sql-statements/generated_columns/)
