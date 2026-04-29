# 默认值求值时机 (DEFAULT Value Evaluation)

`DEFAULT NOW()` 这一行 SQL 看似无害，却隐藏着引擎设计中最深刻的争议之一：默认值是 INSERT 时按行求值，还是按语句求值？是建表时就锁定？还是 ALTER TABLE 时即时生效，无需重写整张表？这些细节差异，让同一段 DDL 在不同数据库中产生完全不同的行为。

## SQL 标准的演变

### SQL:1992 — DEFAULT 子句的诞生

SQL:1992 (ISO/IEC 9075:1992) 在 §11.5 `<column definition>` 中正式定义 `DEFAULT clause`，允许列绑定一个默认值表达式：

```sql
<column definition> ::=
    <column name> <data type or domain name>
        [ <default clause> ]
        [ <column constraint definition>... ]

<default clause> ::= DEFAULT <default option>

<default option> ::=
      <literal>
    | <datetime value function>     -- CURRENT_DATE, CURRENT_TIME, CURRENT_TIMESTAMP
    | USER | CURRENT_USER | SESSION_USER | SYSTEM_USER
    | NULL
```

标准的关键约定：

1. DEFAULT 仅作用于 INSERT/UPDATE 中**列被显式省略或写为 `DEFAULT` 关键字**时
2. DEFAULT 表达式在执行 INSERT 时求值，**逻辑上一行求一次**
3. SQL:1992 仅允许字面量、几个特定函数 (`CURRENT_TIMESTAMP` 等)、`NULL`、用户名函数；**不允许任意子查询或调用普通函数**
4. 默认值类型必须可隐式赋值给列类型

### SQL:2003 — Generated Column 与扩展默认值

SQL:2003 (ISO/IEC 9075-2:2003) 在 §11.4 引入 `<identity column specification>`（IDENTITY 列）和 `<generation clause>`（生成列）：

```sql
<column definition> ::=
    <column name> <data type or domain name>
        [ <default clause> | <identity column specification> | <generation clause> ]

<generation clause> ::=
    GENERATED ALWAYS AS ( <value expression> )

<identity column specification> ::=
    GENERATED { ALWAYS | BY DEFAULT } AS IDENTITY
        [ ( <common sequence generator options> ) ]
```

SQL:2003 后续修订（SQL:2011, SQL:2016）中，主流引擎纷纷扩展 DEFAULT 子句，允许任意确定性表达式甚至非确定性函数作为默认值。

## 核心争议：DEFAULT 求值时机

### 三种语义

| 语义 | 描述 | 何时绑定 | 何时求值 |
|------|------|---------|---------|
| 编译时常量 | 建表时即固定为常量 | `CREATE TABLE` | DDL 解析时 |
| 每行求值 | 每行 INSERT 时独立求值 | 每行 | 每行 |
| 每语句求值 | 整个 INSERT 语句共享一次求值 | 语句开始 | 语句开始 |

主流关系数据库统一采用**每行求值**。但理解这一点对结果差异巨大：

```sql
-- 假设 t 列定义为 created_at TIMESTAMP DEFAULT NOW()
INSERT INTO t (data) SELECT generate_series(1, 1000000);
-- 每行求值：每行的 created_at 不同，相差几百毫秒到几秒
-- 每语句求值：所有行的 created_at 完全相同
```

差异在 UUID/RANDOM 等更明显：

```sql
CREATE TABLE t (id UUID DEFAULT gen_random_uuid(), data TEXT);
INSERT INTO t (data) VALUES ('a'), ('b'), ('c');
-- 每行求值：3 个不同的 UUID（这是想要的）
-- 每语句求值：3 行 id 相同（破坏 PK）
```

幸运的是，所有主流数据库的非确定性 DEFAULT 都是**每行求值**，但具体的实现细节（缓存粒度、并行度）和 `CURRENT_TIMESTAMP` 等"时间函数"的语义在 ANSI SQL 中是**语句开始时一次求值**——这就埋下了下一个坑。

### CURRENT_TIMESTAMP 的语义陷阱

ANSI SQL 标准规定：在同一 SQL 语句内，对 `CURRENT_TIMESTAMP` 的多次引用应返回**相同值**（语句一致性）。这意味着：

```sql
INSERT INTO log (event_time) SELECT CURRENT_TIMESTAMP FROM big_table;
-- 标准语义：所有行的 event_time 相同
-- 即使表有 1000 万行，CURRENT_TIMESTAMP 只求值一次

INSERT INTO log (event_time) VALUES (DEFAULT), (DEFAULT), (DEFAULT);
-- 列定义为 DEFAULT CURRENT_TIMESTAMP
-- 标准语义：3 行的 event_time 相同（语句开始时一次求值）
```

但当 DEFAULT 是 `NOW()`、`gen_random_uuid()` 等"非语句一致函数"时，求值时机才真正每行不同。这就是为什么 PostgreSQL 中 `now()` 与 `clock_timestamp()` 行为不同：前者按事务一次求值，后者按调用一次求值。

## 支持矩阵 (45+ 引擎)

### DEFAULT 子句基础支持

| 引擎 | DEFAULT 子句 | 常量字面量 | NOW/CURRENT_TIMESTAMP | UUID 生成器 | 任意表达式 | 默认值首次支持版本 |
|------|------------|----------|----------------------|------------|----------|-----------------|
| PostgreSQL | 是 | 是 | 是 | `gen_random_uuid()` 13+ | 是 | 6.0 (1996) |
| MySQL | 是 | 是 | 仅 TIMESTAMP/DATETIME (<8.0.13) / 全部列 (8.0.13+) | `UUID()` 8.0.13+ | 8.0.13+ | 3.x |
| MariaDB | 是 | 是 | 全部列 (10.2+) | `UUID()` 10.2+ | 10.2+ | 5.x |
| Oracle | 是 | 是 | 是 | `SYS_GUID()` | 12c+ 函数, 18c 序列 | 8i (1999) |
| SQL Server | 是 (DEFAULT 约束) | 是 | 是 | `NEWID()` / `NEWSEQUENTIALID()` | 是 | 6.x (1995) |
| SQLite | 是 | 是 | 是 (`CURRENT_TIMESTAMP`) | 应用层 | 3.x+ 限定括号表达式 | 1.x |
| DB2 | 是 | 是 | 是 | `GENERATE_UNIQUE()` | 是 | V7+ |
| Snowflake | 是 | 是 | 是 | `UUID_STRING()` | 是 (序列函数) | GA |
| BigQuery | 是 (2021+) | 是 | 是 (`CURRENT_TIMESTAMP()`) | `GENERATE_UUID()` | 是 | 2021 GA |
| Redshift | 是 | 是 | 是 | -- | 限定 | 继承 PG |
| DuckDB | 是 | 是 | 是 | `uuid()` | 是 | 0.3+ |
| ClickHouse | 是 (`DEFAULT`/`MATERIALIZED`/`ALIAS`) | 是 | 是 | `generateUUIDv4()` | 是 | 早期 |
| Trino | 仅有限支持 (依赖连接器) | 是 | 是 | -- | 视连接器 | 早期 |
| Presto | 视连接器 | 是 | 是 | -- | 视连接器 | -- |
| Spark SQL | 是 (3.4+) | 是 | 是 (3.4+) | -- (函数支持) | 3.4+ | 3.4 (2023) |
| Hive | 是 (3.0+) | 是 | 是 | -- | 受限 | 3.0 (2018) |
| Flink SQL | 是 (DDL) | 是 | 是 | -- | 是 | 1.10+ |
| Databricks | 是 | 是 | 是 | -- | 是 | GA |
| Teradata | 是 | 是 | `CURRENT_TIMESTAMP` | -- | 限定 | V2+ |
| Greenplum | 是 | 是 | 是 | 扩展 | 是 | 继承 PG |
| CockroachDB | 是 | 是 | 是 (`now()`) | `gen_random_uuid()` | 是 | 1.x+ |
| TiDB | 是 (兼容 MySQL) | 是 | 限制同 MySQL 8.0+ | `UUID()` | 5.0+ | 早期 |
| OceanBase | 是 (兼容 MySQL/Oracle) | 是 | 是 | `UUID()`/`SYS_GUID()` | 是 | 早期 |
| YugabyteDB | 是 (PG 兼容) | 是 | 是 | `gen_random_uuid()` | 是 | 继承 PG |
| SingleStore (MemSQL) | 是 | 是 | 是 (TIMESTAMP) | -- | 限定 | 早期 |
| Vertica | 是 | 是 | 是 | -- | 是 | 早期 |
| Impala | 是 (Kudu) | 是 | 是 | -- | 限定 | 2.x |
| StarRocks | 是 | 是 | 是 | -- | 是 (3.x+) | 早期 |
| Doris | 是 | 是 | 是 | -- | 是 (2.x+) | 早期 |
| MonetDB | 是 | 是 | 是 | -- | 是 | 早期 |
| CrateDB | 是 | 是 | 是 (`CURRENT_TIMESTAMP`) | `gen_random_text_uuid()` | 是 | 早期 |
| TimescaleDB | 是 (继承 PG) | 是 | 是 | 是 | 是 | 继承 PG |
| QuestDB | 是 (DDL) | 是 | 是 | -- | 限定 | 早期 |
| Exasol | 是 | 是 | 是 | -- | 限定 | 早期 |
| SAP HANA | 是 | 是 | 是 | `SYSUUID` 列函数 | 是 | 早期 |
| Informix | 是 | 是 | 是 | -- | 是 | 早期 |
| Firebird | 是 | 是 | 是 (`CURRENT_TIMESTAMP`) | `GEN_UUID()` | 是 | 1.x+ |
| H2 | 是 | 是 | 是 | `RANDOM_UUID()` | 是 | 早期 |
| HSQLDB | 是 | 是 | 是 | -- | 部分 | 早期 |
| Derby | 是 | 是 | 是 | -- | 限定 | 早期 |
| Amazon Athena | 视连接器 | 是 | 是 | -- | 视连接器 | -- |
| Azure Synapse | 是 | 是 | 是 | `NEWID()` | 是 | GA |
| Google Spanner | 是 | 是 | 是 (`CURRENT_TIMESTAMP()`) | `GENERATE_UUID()` | 是 | 2021+ |
| Materialize | 是 (CREATE TABLE) | 是 | 是 (`now()`) | -- | 限定 | 早期 |
| RisingWave | 是 | 是 | 是 | -- | 是 | 早期 |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | 不直接支持 |
| DatabendDB | 是 | 是 | 是 | -- | 是 | GA |
| Yellowbrick | 是 | 是 | 是 | -- | 是 | GA |
| Firebolt | 是 | 是 | 是 | -- | 限定 | GA |

> 注：表中"任意表达式"指 DEFAULT 是否允许嵌入函数调用、子表达式（多数引擎要求确定性、不引用其他列、不含 `SELECT`）。
>
> 统计：约 47 个引擎支持 DEFAULT 子句，其中约 38 个支持非确定性函数作为默认值；2018 年是分水岭——MySQL 8.0.13 (Oct 2018) 与 PostgreSQL 11 (Oct 2018) 同年发布的两项关键改进至今影响行业。

### 求值时机：每行 vs 每语句

| 引擎 | DEFAULT 中 NOW() 求值粒度 | DEFAULT 中 CURRENT_TIMESTAMP | DEFAULT 中 UUID 函数 | 备注 |
|------|--------------------------|----------------------------|--------------------|------|
| PostgreSQL | 每行 (`now()` 事务一致) | 每行但事务内一致 | 每行（每次调用） | `now()` = `transaction_timestamp()`，事务内多次调用返回同值，与多行 INSERT 一致。`clock_timestamp()` 真正每次不同 |
| MySQL | 每行 (`NOW(6)` 语句一致) | 语句一致（标准） | 每行 (`UUID()` 真正每次不同) | TIMESTAMP `DEFAULT CURRENT_TIMESTAMP` 在每行获得相同时间戳（同一语句） |
| MariaDB | 同 MySQL | 同 MySQL | 同 MySQL | -- |
| Oracle | 每行 | 每行（标准下语句一致，但 Oracle 实现更细粒度） | 每行 (`SYS_GUID()` 每次不同) | Oracle DEFAULT 在 Insert 时按行求值 |
| SQL Server | 每行 | 每行（语句一致） | 每行 (`NEWID()`/`NEWSEQUENTIALID()` 每行不同) | DEFAULT 约束按行求值 |
| SQLite | 每行 | 语句一致 | -- | -- |
| DB2 | 每行 | 语句一致 | 每行 | -- |
| Snowflake | 每行 (`CURRENT_TIMESTAMP()` 语句一致) | 语句一致 | 每行 (`UUID_STRING()` 每次不同) | -- |
| BigQuery | 每行 | 语句一致 | 每行 (`GENERATE_UUID()`) | -- |
| Redshift | 每行 | 语句一致 | -- | -- |
| DuckDB | 每行 | 语句一致 | 每行 | -- |
| ClickHouse | 每行 | 语句一致 | 每行 | INSERT 时为每行独立调用 |
| CockroachDB | 每行 (`now()` 事务一致) | 事务一致 | 每行 | -- |
| TiDB | 每行 | 语句一致 | 每行 | -- |
| OceanBase | 每行 | 语句一致 | 每行 | -- |
| Spark SQL | 每行 | 语句一致 | 每行 | -- |
| Hive | 每行 | 语句一致 | -- | -- |
| Greenplum | 每行 | 事务一致 | 每行 | -- |
| YugabyteDB | 每行 (PG 语义) | 事务一致 | 每行 | -- |
| Vertica | 每行 | 语句一致 | -- | -- |
| MariaDB | 同 MySQL | 同 MySQL | 同 MySQL | -- |
| StarRocks | 每行 | 语句一致 | -- | -- |
| Doris | 每行 | 语句一致 | -- | -- |
| H2 | 每行 | 语句一致 | 每行 | -- |
| Firebird | 每行 | 语句一致 | 每行 | -- |
| Spanner | 每行 | 语句一致 | 每行 | -- |
| Materialize | 每行 | 语句一致 | -- | -- |
| 其他多数 OLTP | 每行 | 语句一致 | 每行 | -- |

> 关键：所有主流引擎对 DEFAULT 中"非语句一致函数"（`UUID()`/`gen_random_uuid()`/`RANDOM()`/`clock_timestamp()`）都按**每行求值**；对"语句一致函数"（`CURRENT_TIMESTAMP`/`NOW()` 在标准下）的求值粒度受 SQL 标准约束，这是必须遵守的——否则会破坏单语句内时间戳一致性。

### ALTER TABLE ADD COLUMN ... DEFAULT 的执行成本

向已有大表添加带默认值的列，是 DBA 最常遇到的 DDL 性能问题之一。

| 引擎 | 常量 DEFAULT | 非常量 DEFAULT (如 NOW()) | NULL DEFAULT (无 DEFAULT 子句) | 优化版本 |
|------|------------|-------------------------|----------------------------|--------|
| PostgreSQL | 11+ 仅元数据 (instant) | 11+ 仅元数据 (instant) | 始终元数据 | 11 (2018-10) "fast default" |
| MySQL (InnoDB) | 8.0.12+ INSTANT (元数据) | 8.0.29+ 部分 (`INSTANT`) | INSTANT (8.0.12+) | 8.0.12 (2018-07) |
| MariaDB | 10.3+ INSTANT | 10.3+ 多数 | INSTANT (10.3+) | 10.3 (2018) |
| Oracle | 11g R1+ DEFAULT NULL 元数据；12c R1+ NOT NULL DEFAULT 元数据；12c R2+ NULL DEFAULT 元数据 | 12c+ 元数据 | 11g+ 元数据 | 12c (2014) |
| SQL Server | 2012+ 元数据 (Always)；可空与非空均支持 | 不支持 (重写) | 始终元数据 | 2012 (实际从 SQL 2005 起) |
| SQLite | 元数据 (无重写) | 元数据 (NOW() 是表达式默认) | 始终元数据 | 早期 |
| DB2 | LUW 9.7+ "stored default" 元数据 | 重写 | 始终元数据 | 9.7 (2009) |
| Snowflake | 元数据 (微分区不重写) | 元数据 | 元数据 | GA |
| BigQuery | 元数据 (列式) | 元数据 | 元数据 | -- |
| Redshift | 重写 (新 schema) | 重写 | 元数据 | -- |
| DuckDB | 元数据 | 元数据 | 元数据 | 早期 |
| ClickHouse | 元数据 (Lazy materialization) | 元数据 | 元数据 | 早期 |
| CockroachDB | 元数据 (PG 兼容) | 元数据 | 元数据 | 21.x+ |
| TiDB | 元数据 (兼容 8.0 INSTANT) | 元数据 (5.5+) | 元数据 | 5.x+ |
| OceanBase | 元数据 | 元数据 | 元数据 | 4.x+ |
| YugabyteDB | 元数据 | 元数据 | 元数据 | 继承 PG 11+ |
| Vertica | 重写部分列 | 重写 | 元数据 | -- |
| Greenplum | 7+ 继承 PG 11 fast default | 7+ 元数据 | 元数据 | 7.0 (基于 PG 12) |
| Spark SQL | 重写 (Delta/Iceberg 元数据) | 重写 | 元数据 | -- |
| Hive | 元数据 (3.0+) | 重写 | 元数据 | 3.0 |
| MonetDB | 重写 | 重写 | 元数据 | -- |
| H2 | 元数据 | 元数据 | 元数据 | 早期 |
| Firebird | 重写 | 重写 | 元数据 | -- |
| 其他列存/MPP | 通常元数据 | 视引擎 | 元数据 | -- |

> 经验原则：现代行存 OLTP 引擎（PG 11+、MySQL 8.0+、Oracle 12c+、SQL Server 2012+）都已实现"add column with default = metadata only"；大部分列存与 MPP 因每个微分区/段独立，添加列天然元数据操作；分析型 SQL on Hadoop（Spark/Hive 早期版本）仍可能触发重写。

## 各引擎深入

### PostgreSQL

**DEFAULT 求值**：每行求值，事务一致函数。

```sql
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,
    event_uuid UUID DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ DEFAULT now(),
    real_clock TIMESTAMPTZ DEFAULT clock_timestamp(),
    payload JSONB
);

-- now() 返回事务开始时间戳：同一事务内多次调用相同
-- transaction_timestamp() 同 now()
-- statement_timestamp() 当前语句开始时间
-- clock_timestamp() 真实墙钟（每次调用不同）
```

事务内的时间函数对比：

```sql
BEGIN;
SELECT now(), statement_timestamp(), clock_timestamp();  -- 三者基本相同
SELECT pg_sleep(2);
SELECT now(), statement_timestamp(), clock_timestamp();
-- now() 不变（事务一致）
-- statement_timestamp() 变化（每语句一次）
-- clock_timestamp() 几乎实时
COMMIT;
```

**ALTER TABLE ADD COLUMN ... DEFAULT — fast default since PG 11 (2018)**

PG 11 之前，添加带 DEFAULT 的列必须**重写整张表**：将每行物理写入新版本以填入默认值。对 100GB 表来说，这意味着锁住表数小时。

PG 11 的 `pg_attribute.atthasmissing` 与 `attmissingval` 引入"missing value"机制：

```sql
-- PG 11+: 仅元数据修改
ALTER TABLE huge_table ADD COLUMN tier TEXT DEFAULT 'standard';
-- 立即返回，无表重写
-- 已有行物理上没有 tier 字段，读时由 pg_attribute.attmissingval 填充

-- 对常量、不变量函数都适用
ALTER TABLE huge_table ADD COLUMN created_at TIMESTAMPTZ DEFAULT '2018-10-01';

-- 但下面这条仍触发重写（now() 是 STABLE，PG 会一次求值并存储为常量？实际：
-- now() 在 ALTER 时被视为非 volatile 中的稳定值，PG 11+ 会一次性求值并写入 attmissingval
ALTER TABLE huge_table ADD COLUMN created_at TIMESTAMPTZ DEFAULT now();
-- 实际行为：PG 11+ 将 now() 求值为常量，写入 missing value，元数据操作
-- 但 random() 等 VOLATILE 函数则需要重写（每行不同）
```

**volatility 决定 fast default 是否生效**：

```
volatility = IMMUTABLE   -> always fast default
volatility = STABLE       -> fast default (one-time eval, store as constant)
volatility = VOLATILE     -> table rewrite required
```

```sql
-- IMMUTABLE: fast default (常量字符串)
ALTER TABLE t ADD COLUMN c1 TEXT DEFAULT 'hello';

-- STABLE: fast default（一次求值，存为常量）
ALTER TABLE t ADD COLUMN c2 TIMESTAMPTZ DEFAULT now();

-- VOLATILE: 触发重写
ALTER TABLE t ADD COLUMN c3 INT DEFAULT (random() * 100)::int;
ALTER TABLE t ADD COLUMN c4 UUID DEFAULT gen_random_uuid();
-- gen_random_uuid 是 VOLATILE，需重写以保证每行不同
```

**ALTER TABLE 添加 NOT NULL 列**：PG 11+ 也支持 fast default。

```sql
-- 100GB 表上瞬间完成
ALTER TABLE big_log ADD COLUMN status TEXT NOT NULL DEFAULT 'pending';
```

### MySQL

**DEFAULT 求值**：每行求值。`CURRENT_TIMESTAMP` / `NOW()` 在同一语句内对所有行返回同值（语句一致），`UUID()` 每行不同。

**MySQL 8.0.13 (2018-10): 表达式默认值的革命**

8.0.13 之前，MySQL 的 DEFAULT 子句有严格限制：

```sql
-- MySQL 5.7 / 8.0.12 及之前
CREATE TABLE t (
    -- 仅 TIMESTAMP / DATETIME 可使用 CURRENT_TIMESTAMP
    created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    -- 字符列、数值列仅支持字面量
    name VARCHAR(50) DEFAULT 'unknown',
    counter INT DEFAULT 0,

    -- 下面在 8.0.13 之前会报错: "Invalid default value"
    id CHAR(36) DEFAULT (UUID()),                       -- 错误
    expires DATETIME DEFAULT (NOW() + INTERVAL 7 DAY),  -- 错误
    config JSON DEFAULT ('{"theme": "dark"}'),          -- 错误
    blob_col BLOB DEFAULT 'hello'                       -- 错误（BLOB/TEXT 不允许）
);
```

8.0.13+ 引入"表达式默认值"，支持任意确定性表达式（包括 BLOB/TEXT/JSON）：

```sql
-- MySQL 8.0.13+
CREATE TABLE t (
    -- UUID 主键自动生成
    id CHAR(36) DEFAULT (UUID()),

    -- 任意列都可使用 CURRENT_TIMESTAMP
    created VARCHAR(30) DEFAULT (CURRENT_TIMESTAMP()),

    -- 表达式
    expires DATETIME DEFAULT (NOW() + INTERVAL 7 DAY),
    config JSON DEFAULT (JSON_OBJECT('theme', 'dark')),
    text_col TEXT DEFAULT ('default content'),
    blob_col BLOB DEFAULT (X'DEADBEEF'),

    -- 引用其他列（注意：列必须在前面定义）
    -- 实际上 MySQL 不允许引用其他列在 DEFAULT 中
    PRIMARY KEY (id)
);
```

**关键语法要求**：表达式必须**用括号包围**（与字面量区分）：

```sql
-- 字面量：无需括号
CREATE TABLE t (a INT DEFAULT 0);

-- 表达式：必须用括号
CREATE TABLE t (id CHAR(36) DEFAULT (UUID()));      -- 正确
CREATE TABLE t (id CHAR(36) DEFAULT UUID());        -- 错误
```

**ON UPDATE CURRENT_TIMESTAMP — MySQL 独有自动更新**：

```sql
CREATE TABLE audit (
    id INT PRIMARY KEY,
    data TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- INSERT 时设置 updated_at = 当前时间
INSERT INTO audit (id, data) VALUES (1, 'a');
-- updated_at = 2026-04-29 12:00:00

-- UPDATE 时自动刷新
UPDATE audit SET data = 'b' WHERE id = 1;
-- updated_at = 当前时间

-- 仅当行实际改变时刷新（值未变化的 UPDATE 不刷新）
-- 限制：每个表最多一个 ON UPDATE CURRENT_TIMESTAMP 列
```

**MySQL ALTER TABLE ADD COLUMN — INSTANT (8.0.12+)**

8.0.12 引入 `ALGORITHM=INSTANT`，添加列默认元数据操作：

```sql
-- 8.0.12+
ALTER TABLE big_table ADD COLUMN status TEXT DEFAULT 'active';
-- 默认 ALGORITHM=INSTANT（如可行）

-- 显式指定
ALTER TABLE big_table ADD COLUMN expires DATETIME DEFAULT NOW(),
    ALGORITHM=INSTANT, LOCK=NONE;

-- INSTANT 限制：
-- 1. 仅可向表末尾添加列（8.0.29 起放宽，可在任意位置）
-- 2. 不支持 ROW_FORMAT=COMPRESSED
-- 3. 不支持包含 FULLTEXT 索引的表
-- 4. 一次最多支持 N 次 INSTANT ADD COLUMN（取决于 row format）

-- 8.0.29+ 进一步增强：
ALTER TABLE big_table ADD COLUMN name TEXT FIRST, ALGORITHM=INSTANT;
```

### MariaDB

继承 MySQL 早期分叉，独立演进：

- **MariaDB 10.2 (2017)**：先于 MySQL 引入"任意列默认值表达式"。
- **MariaDB 10.3 (2018)**：INSTANT ADD COLUMN（早于 MySQL 8.0.12 几个月）。

```sql
-- MariaDB 10.2+
CREATE TABLE t (
    id CHAR(36) DEFAULT UUID(),                       -- 无需括号（与 MySQL 不同）
    created DATETIME DEFAULT CURRENT_TIMESTAMP,        -- 任意列
    expires DATETIME DEFAULT (NOW() + INTERVAL 7 DAY)  -- 表达式
);

-- 唯一不一致：MariaDB 使用 UUID() 不需要括号
-- MySQL 必须 DEFAULT (UUID())
```

### Oracle

**DEFAULT 求值**：每行求值。

```sql
CREATE TABLE orders (
    id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_uuid VARCHAR2(36) DEFAULT SYS_GUID(),
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP,
    status VARCHAR2(20) DEFAULT 'pending'
);
```

**Oracle 12c R1 (2013) — Identity 列与 fast metadata default**：

```sql
-- 12c+ Identity 列（标准 SQL:2003）
CREATE TABLE t (
    id NUMBER GENERATED ALWAYS AS IDENTITY,
    name VARCHAR2(50)
);
-- 等同于序列 + 触发器，但语法标准化

-- 12c R1: 添加 NOT NULL DEFAULT 列瞬间完成
ALTER TABLE huge_table ADD col NUMBER DEFAULT 0 NOT NULL;
-- 已有行物理上无 col，读取时填充默认值

-- 12c R2 (2016): 扩展到允许 NULL 的列
ALTER TABLE huge_table ADD col NUMBER DEFAULT 0;  -- 12c R2+ 元数据

-- 12c+ DEFAULT 子句允许序列函数
CREATE SEQUENCE order_seq;
CREATE TABLE orders (
    id NUMBER DEFAULT order_seq.NEXTVAL,
    name VARCHAR2(50)
);
-- 18c 之前需要触发器，12c+ 可直接在 DEFAULT 引用 seq.NEXTVAL

-- 12c+ DEFAULT ON NULL：当 INSERT 提供 NULL 时也使用 DEFAULT
CREATE TABLE t (
    flag VARCHAR2(1) DEFAULT ON NULL 'N'
);
INSERT INTO t (flag) VALUES (NULL);
-- 标准语义会插入 NULL；ON NULL 子句会强制写入 'N'
```

### SQL Server

**DEFAULT 是约束 (Constraint)**：不是列属性，而是表上的命名约束。

```sql
-- 内联语法
CREATE TABLE Orders (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    OrderDate DATETIME2 DEFAULT SYSUTCDATETIME(),
    OrderUuid UNIQUEIDENTIFIER DEFAULT NEWID(),
    Status NVARCHAR(20) DEFAULT 'pending'
);

-- 显式约束语法（更易管理）
CREATE TABLE Orders (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    OrderDate DATETIME2 NOT NULL
        CONSTRAINT DF_Orders_OrderDate DEFAULT SYSUTCDATETIME(),
    OrderUuid UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT DF_Orders_OrderUuid DEFAULT NEWID(),
    Status NVARCHAR(20)
        CONSTRAINT DF_Orders_Status DEFAULT 'pending'
);

-- 后置添加约束
ALTER TABLE Orders ADD CONSTRAINT DF_Orders_Quantity DEFAULT 1 FOR Quantity;

-- 删除约束（必须知道约束名）
ALTER TABLE Orders DROP CONSTRAINT DF_Orders_Quantity;
```

**默认约束的延迟（NEWSEQUENTIALID）**：

```sql
-- NEWSEQUENTIALID() 仅可作为 DEFAULT 使用（不能在 SELECT 中调用）
CREATE TABLE t (
    id UNIQUEIDENTIFIER DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
    data NVARCHAR(MAX)
);
-- 生成的 UUID 是顺序的（基于 MAC 地址 + 时间戳），减少索引页分裂
-- 缺点：可预测，不适合公开 ID

-- NEWID() 完全随机，可任意位置使用
CREATE TABLE t2 (
    id UNIQUEIDENTIFIER DEFAULT NEWID() PRIMARY KEY,
    data NVARCHAR(MAX)
);
-- 完全随机但导致索引页分裂
```

**SQL Server 2012+ — Add Column with Default 是元数据操作**：

实际上从 SQL Server 2005 开始的 "Online DDL" 部分支持，2012 全面支持：

```sql
-- 即使是 NOT NULL 列、即使表有几亿行，仍是元数据操作（瞬间完成）
ALTER TABLE BigTable ADD NewCol NVARCHAR(50) NOT NULL DEFAULT 'unknown';

-- 内部实现：
-- 1. sys.system_internals_partition_columns 记录列的"默认值快照"
-- 2. 已存在的行物理上不存在该列
-- 3. SELECT 时引擎从元数据返回默认值
-- 4. UPDATE 触及行时才物理写入

-- 限制：DEFAULT 必须是运行时可求值的常量（NEWID() / SYSUTCDATETIME() 也行，但每行求值）
-- 等等？是的：NEWID() 仍每行不同，但元数据存储的是"调用 NEWID() 表达式"
-- 实际行为：列的元数据"虚拟"行返回 NEWID()，每次 SELECT 调用每行重新生成（不一致！）
-- 所以推荐：仅用真正的 deterministic 值作为 ADD COLUMN DEFAULT，
-- 或事后 UPDATE 物化非确定性值

-- 验证元数据 add column 是否完成
SELECT name, default_object_id, is_computed
FROM sys.columns
WHERE object_id = OBJECT_ID('BigTable');
```

### SQLite

**DEFAULT 求值**：每行求值。

SQLite 自 3.x 起支持表达式默认值，但**必须括起在括号中**：

```sql
CREATE TABLE log (
    id INTEGER PRIMARY KEY,
    -- 字面量
    level TEXT DEFAULT 'info',
    -- 时间戳函数（无括号）
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    -- 表达式（必须括号）
    expires_at DATETIME DEFAULT (datetime('now', '+7 days')),
    log_uuid TEXT DEFAULT (lower(hex(randomblob(16))))
);

-- SQLite 没有内置 UUID 函数，但可用 randomblob(16) + hex 模拟
```

**ALTER TABLE ADD COLUMN — 始终元数据**：

```sql
-- SQLite 的 ADD COLUMN 总是元数据操作（不重写）
ALTER TABLE huge_log ADD COLUMN status TEXT DEFAULT 'pending';
-- 立即完成

-- 但 ADD COLUMN 有限制：
-- 1. 不能添加 PRIMARY KEY 列
-- 2. 不能添加 UNIQUE 列
-- 3. 不能添加 NOT NULL 而无 DEFAULT 的列（除非表为空）
-- 4. DEFAULT 必须是常量（不能是 CURRENT_TIMESTAMP / 表达式）
ALTER TABLE huge_log ADD COLUMN created_at DATETIME DEFAULT CURRENT_TIMESTAMP;
-- 错误：non-constant default
-- 解决：先 ADD 普通列，再 UPDATE
ALTER TABLE huge_log ADD COLUMN created_at DATETIME;
UPDATE huge_log SET created_at = CURRENT_TIMESTAMP;
```

### CockroachDB

完全 PG 兼容的 DEFAULT 子句，包括 `gen_random_uuid()`：

```sql
CREATE TABLE accounts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT now(),
    balance DECIMAL DEFAULT 0
);

-- ALTER TABLE ADD COLUMN 总是元数据
ALTER TABLE accounts ADD COLUMN status TEXT DEFAULT 'active';
-- 元数据操作，瞬间完成
-- CockroachDB 的列存储是 KV 模型，添加列只是元数据修改

-- 表达式 DEFAULT 同 PG
CREATE TABLE t (
    expires_at TIMESTAMPTZ DEFAULT now() + INTERVAL '7 days'
);
```

### TiDB

兼容 MySQL 协议，DEFAULT 行为同 MySQL 8.0：

```sql
-- TiDB 5.0+ 支持 MySQL 8.0.13 风格的表达式默认值
CREATE TABLE t (
    id CHAR(36) DEFAULT (UUID()),
    created DATETIME DEFAULT CURRENT_TIMESTAMP,
    expires DATETIME DEFAULT (NOW() + INTERVAL 7 DAY)
);

-- ALTER TABLE 默认元数据
ALTER TABLE big_table ADD COLUMN status TEXT DEFAULT 'active';
-- TiDB 的 schema lease 机制保证元数据操作快速可见
```

### ClickHouse

**ClickHouse 的三种"默认值"机制**：

```sql
CREATE TABLE events (
    id UInt64,
    user_id UInt64,

    -- DEFAULT: 列存于物理上，INSERT 时未提供则填充
    timestamp DateTime DEFAULT now(),
    event_uuid UUID DEFAULT generateUUIDv4(),

    -- MATERIALIZED: 列总由表达式计算，物理写入；不能在 INSERT 时显式提供
    region_lower String MATERIALIZED lower(region),

    -- ALIAS: 不存储，每次 SELECT 时计算
    timestamp_year UInt16 ALIAS toYear(timestamp),

    region String
) ENGINE = MergeTree() ORDER BY (timestamp, id);

-- INSERT
INSERT INTO events (id, user_id, region) VALUES (1, 100, 'US');
-- timestamp = now() 求值
-- event_uuid = generateUUIDv4() 求值
-- region_lower = 'us' 自动填充（用户不能在 INSERT 中提供）
```

**ALTER TABLE ADD COLUMN — 元数据**：

```sql
-- ClickHouse 的列存储是逐列的稀疏文件，添加列就是创建新空目录
ALTER TABLE events ADD COLUMN session_id UUID DEFAULT generateUUIDv4();
-- 元数据操作，已有 part 不重写
-- 读取已有 part 时，缺失列由 DEFAULT 填充（lazy materialization）

-- 强制物化已有行
ALTER TABLE events MATERIALIZE COLUMN session_id;
```

### Snowflake

```sql
CREATE TABLE orders (
    id NUMBER AUTOINCREMENT PRIMARY KEY,
    order_uuid VARCHAR DEFAULT UUID_STRING(),
    created_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    status VARCHAR DEFAULT 'pending'
);

-- Snowflake 的 ALTER TABLE ADD COLUMN 是元数据
-- 微分区不重写，已有数据由元数据补默认值
ALTER TABLE orders ADD COLUMN region VARCHAR DEFAULT 'global';
-- 立即完成
```

**Snowflake 的特殊限制**：DEFAULT 表达式必须可在 DDL 编译时求值，不能引用其他列、不能调用 UDF。

### BigQuery

2021 年才正式支持 DEFAULT 子句：

```sql
CREATE TABLE mydataset.events (
    id INT64,
    event_uuid STRING DEFAULT GENERATE_UUID(),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    status STRING DEFAULT 'pending'
);

-- ALTER TABLE ADD COLUMN 元数据
ALTER TABLE mydataset.events
ADD COLUMN region STRING DEFAULT 'global';
```

### DuckDB

```sql
CREATE TABLE accounts (
    id BIGINT PRIMARY KEY,
    account_uuid UUID DEFAULT uuid(),
    created_at TIMESTAMP DEFAULT now(),
    balance DECIMAL(15,2) DEFAULT 0
);

-- DuckDB 的 DEFAULT 支持任意确定性表达式
CREATE TABLE t (
    expires_at TIMESTAMP DEFAULT now() + INTERVAL 7 DAY,
    -- 引用同一行的其他列：DuckDB 不支持
    -- 用 GENERATED 列代替
);
```

### Greenplum

继承 PG 11 fast default（Greenplum 7+ 基于 PG 12）：

```sql
-- Greenplum 6 (PG 9.4 base): ALTER ADD COLUMN with DEFAULT 重写表
-- Greenplum 7 (PG 12 base): fast default 生效

ALTER TABLE huge_fact ADD COLUMN region TEXT DEFAULT 'unknown';
-- Greenplum 7+ 仅元数据
```

### Spark SQL

3.4 引入 DEFAULT 列支持（DataSource v2）：

```sql
-- Spark SQL 3.4+
CREATE TABLE accounts (
    id BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    status STRING DEFAULT 'active'
) USING delta;

-- 实际生效依赖底层格式：
-- Delta Lake / Iceberg: 元数据存储 default，列添加是元数据
-- Parquet 直接表: 部分支持
```

### Hive

3.0+ 支持基本 DEFAULT：

```sql
-- Hive 3.0+
CREATE TABLE events (
    id BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status STRING DEFAULT 'active'
);
-- ACID 表（事务表）支持更完整
```

### Materialize

```sql
CREATE TABLE events (
    id BIGINT,
    received_at TIMESTAMP DEFAULT now(),
    payload TEXT
);
-- now() 在 Materialize 中也是事务时间戳
```

### Spanner

2021 起支持 DEFAULT 子句（GoogleSQL 方言）：

```sql
CREATE TABLE Events (
    Id INT64 NOT NULL,
    EventUuid STRING(36) DEFAULT (GENERATE_UUID()),
    CreatedAt TIMESTAMP DEFAULT (CURRENT_TIMESTAMP()),
    Status STRING(20) DEFAULT ('pending')
) PRIMARY KEY (Id);
```

## MySQL 8.0.13 表达式默认值深度分析

### 演进背景

MySQL 5.x 时代的 DEFAULT 限制非常严格，给开发带来诸多不便：

```sql
-- MySQL 5.7
CREATE TABLE users (
    id CHAR(36) PRIMARY KEY,                    -- 必须由应用生成 UUID
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- 仅 TIMESTAMP 列可以使用 CURRENT_TIMESTAMP
    -- DATETIME 列在 5.6.5+ 才支持 CURRENT_TIMESTAMP
    -- 字符列 / 数值列 / JSON 列绝不允许函数
    other_time DATETIME DEFAULT CURRENT_TIMESTAMP,  -- 5.6.5+
    config JSON  -- 不能有任何 DEFAULT
);
```

应用层不得不在 INSERT 时提供 UUID、JSON 默认值等：

```sql
INSERT INTO users (id, config) VALUES (UUID(), '{}');
```

### 8.0.13 的关键变化

[WL#9418: DEFAULT for non-traditional data types](https://dev.mysql.com/worklog/task/?id=9418)：

```sql
-- MySQL 8.0.13+
CREATE TABLE users (
    id CHAR(36) DEFAULT (UUID()) PRIMARY KEY,                     -- 任意类型 + UUID
    created_at DATETIME DEFAULT (NOW()),                          -- 任意时间列
    expires_at DATETIME DEFAULT (NOW() + INTERVAL 7 DAY),         -- 表达式
    profile JSON DEFAULT (JSON_OBJECT('theme', 'dark')),          -- JSON 默认值
    bio TEXT DEFAULT ('User has not written a bio'),              -- TEXT 默认值
    avatar BLOB DEFAULT (X'89504E47')                             -- BLOB 默认值（PNG header）
);
```

### 表达式默认值的限制

```sql
-- 1. 必须是确定性的或允许引擎按行求值
-- 2. 不能引用其他列
CREATE TABLE t (
    a INT,
    b INT DEFAULT (a + 1)  -- 错误：不能引用其他列
);

-- 3. 不能调用存储函数（用户自定义函数）
DELIMITER //
CREATE FUNCTION my_default() RETURNS INT DETERMINISTIC RETURN 42;
//
DELIMITER ;
CREATE TABLE t (
    a INT DEFAULT (my_default())  -- 错误：不能调用 stored function
);

-- 4. 不能使用 LOAD_FILE
CREATE TABLE t (
    data BLOB DEFAULT (LOAD_FILE('/etc/passwd'))  -- 错误
);

-- 5. 不能使用变量
CREATE TABLE t (
    a INT DEFAULT (@@global.max_connections)  -- 错误
);

-- 6. 表达式被 binlog 写入，复制时主从必须使用相同 SQL_MODE
-- 7. ALTER TABLE 改变 DEFAULT 表达式：仅元数据，旧行不变
```

### 求值时机

```sql
CREATE TABLE t (
    id INT PRIMARY KEY,
    uuid_col CHAR(36) DEFAULT (UUID()),
    ts_col DATETIME DEFAULT (NOW(6))
);

-- 多行 INSERT
INSERT INTO t (id) VALUES (1), (2), (3);
-- uuid_col: 3 个不同的 UUID（每行求值）
-- ts_col: 3 个相同的 NOW(6)（语句一致函数）

-- 但 NOW(6) 在 8.0.13 之前的语义没变，仍是语句一致
-- 这意味着：你不能用 NOW() 给每行不同的时间戳
-- 想要每行不同：用 SYSDATE(6) 而不是 NOW()
INSERT INTO t (id, ts_col) VALUES (1, DEFAULT), (2, DEFAULT), (3, DEFAULT);
-- 仍是 3 个相同的 NOW(6)
```

`NOW()` vs `SYSDATE()`:

```sql
-- NOW(): 语句开始时一次求值，整个语句一致
-- SYSDATE(): 每次调用真实求值（每行不同）

INSERT INTO t (id, ts_col) SELECT id, NOW(6) FROM big_table;
-- 所有行 ts_col 完全相同

INSERT INTO t (id, ts_col) SELECT id, SYSDATE(6) FROM big_table;
-- 每行 ts_col 不同（毫秒级差异）
```

但这有个**复制兼容性陷阱**：

```sql
-- statement-based replication 模式下：
-- NOW() 主从一致（语句重放时一次求值）
-- SYSDATE() 主从不一致（重放时间不同，结果不同）
-- 因此 SYSDATE() 在 SBR 模式下不安全
SET binlog_format = 'STATEMENT';
INSERT INTO t (id, ts_col) VALUES (1, SYSDATE(6));
-- WARNING: Statement is not safe to log in statement format
```

## PostgreSQL Fast Default 深度分析

### 重写问题的历史

PG 11 之前：

```sql
-- 100GB 表，添加一列
ALTER TABLE big_table ADD COLUMN new_col TEXT DEFAULT 'standard';
-- 问题：
-- 1. 锁表（ACCESS EXCLUSIVE）
-- 2. 重写整张表（每行物理写入新版本以填充 new_col）
-- 3. 100GB → 200GB 临时空间
-- 4. 数小时不可用
```

许多迁移要求"先 ADD COLUMN（无 DEFAULT），再 UPDATE 全表填值，最后 ALTER 设置 NOT NULL DEFAULT"，分批避免锁表。

### PG 11 (2018-10) Fast Default

引入 `pg_attribute.atthasmissing` 与 `attmissingval`：

```sql
-- PG 11+: 立即元数据操作
ALTER TABLE big_table ADD COLUMN new_col TEXT DEFAULT 'standard';
-- 无锁、无重写、瞬间返回

-- 内部：
-- 1. pg_attribute 新增一行：atthasmissing=true, attmissingval='standard'
-- 2. 已有 heap tuples 物理上不变，仍按旧 schema 存储
-- 3. SELECT 读取旧 tuple 时，发现缺少 new_col，从 attmissingval 取值
-- 4. UPDATE 该行时才会写入新 schema 的 tuple

-- 验证：
SELECT atthasmissing, attmissingval
FROM pg_attribute
WHERE attrelid = 'big_table'::regclass
  AND attname = 'new_col';
```

### Volatility 决定 Fast Default 是否生效

```sql
-- IMMUTABLE / STABLE: fast default
ALTER TABLE t ADD COLUMN c1 TEXT DEFAULT 'hello';                    -- IMMUTABLE
ALTER TABLE t ADD COLUMN c2 TIMESTAMPTZ DEFAULT now();               -- STABLE - 一次求值
ALTER TABLE t ADD COLUMN c3 INT DEFAULT (1 + 1);                     -- IMMUTABLE
ALTER TABLE t ADD COLUMN c4 TEXT DEFAULT current_user::text;         -- STABLE

-- VOLATILE: 仍然重写（PG 12+ 可用 generated 列规避）
ALTER TABLE t ADD COLUMN c5 UUID DEFAULT gen_random_uuid();          -- VOLATILE
-- 触发重写，因为每行 UUID 必须不同

-- 检查函数 volatility：
SELECT proname, provolatile
FROM pg_proc
WHERE proname IN ('now', 'gen_random_uuid', 'random');
-- now: s (STABLE)
-- gen_random_uuid: v (VOLATILE)
-- random: v (VOLATILE)
```

### 多次 ADD COLUMN

```sql
-- 多次 ADD 各自存自己的 missing value
ALTER TABLE t ADD COLUMN c1 TEXT DEFAULT 'a';   -- attmissingval='a'
ALTER TABLE t ADD COLUMN c2 INT DEFAULT 10;     -- attmissingval=10
ALTER TABLE t ADD COLUMN c3 BOOL DEFAULT false; -- attmissingval=false

-- ALTER TABLE 改变现有列的 DEFAULT 不会回填
ALTER TABLE t ALTER COLUMN c1 SET DEFAULT 'new';
-- 已有行 c1 仍是 'a'（attmissingval 不变）
-- 仅未来 INSERT 用新 DEFAULT
```

## DEFAULT vs 触发器：选择困境

许多场景两者都能实现，但有重要差异：

### DEFAULT 优势

```sql
-- 1. 性能：DEFAULT 在 INSERT 内部直接求值，比触发器快
-- 2. 优化器可见：DEFAULT 在 SELECT 中可被引用为 stored value
-- 3. 标准 SQL，易跨引擎迁移
-- 4. 不影响 RETURNING/OUTPUT 语义

CREATE TABLE t (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT now()
);
INSERT INTO t (data) VALUES ('a') RETURNING id, created_at;
-- DEFAULT 计算的值正确返回
```

### 触发器优势

```sql
-- 1. 可引用其他列、行其他字段
-- 2. 可执行复杂逻辑（CASE、查询、变量）
-- 3. 可访问 NEW / OLD（UPDATE 时）

CREATE OR REPLACE FUNCTION compute_full_name()
RETURNS TRIGGER AS $$
BEGIN
    NEW.full_name := NEW.first_name || ' ' || NEW.last_name;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_compute_full_name
BEFORE INSERT OR UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION compute_full_name();
-- DEFAULT 不能引用其他列
```

### 优先选择规则

| 场景 | 推荐 |
|------|------|
| 常量、单函数（NOW、UUID、随机） | DEFAULT |
| 引用其他列 | 触发器 / 生成列 (Computed Column) |
| 跨表查询 | 触发器（DEFAULT 不允许子查询） |
| 复杂业务逻辑 | 触发器 |
| 高性能写入路径 | DEFAULT（绕开触发器开销） |
| 不可变值（创建时锁定） | DEFAULT (`NOW()` 一次求值) |
| 可变值（更新时刷新） | 触发器（DEFAULT 不能在 UPDATE 触发，除 MySQL ON UPDATE） |

### 生成列 (Generated Column) 作为第三方案

```sql
-- PostgreSQL 12+
CREATE TABLE t (
    first_name TEXT,
    last_name TEXT,
    full_name TEXT GENERATED ALWAYS AS (first_name || ' ' || last_name) STORED
);

-- MySQL 5.7+
CREATE TABLE t (
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    full_name VARCHAR(101)
        GENERATED ALWAYS AS (CONCAT(first_name, ' ', last_name)) STORED
);

-- Oracle 11g+
CREATE TABLE t (
    first_name VARCHAR2(50),
    last_name VARCHAR2(50),
    full_name VARCHAR2(101) GENERATED ALWAYS AS (first_name || ' ' || last_name) VIRTUAL
);

-- 生成列与 DEFAULT 的核心区别：
-- DEFAULT: 仅在未提供值时求值，INSERT/UPDATE 后值固定
-- GENERATED: 总是按表达式求值，依赖列变化时自动更新
```

## CURRENT_TIMESTAMP 跨引擎一致性陷阱

```sql
-- 标准：CURRENT_TIMESTAMP 在同一 SQL 语句内返回相同值
-- 但实现上各引擎对"语句"的定义不同：

-- PostgreSQL:
-- now() = transaction_timestamp() = CURRENT_TIMESTAMP, 事务一致
-- statement_timestamp() 每语句一次
-- clock_timestamp() 每次调用都不同
SELECT now(), statement_timestamp(), clock_timestamp();

-- MySQL:
-- NOW() / CURRENT_TIMESTAMP: 语句一致（与标准一致）
-- SYSDATE(): 每次调用都不同（非标准）
-- 但默认 sql_mode 中 SYSDATE() 也变成语句一致（除非启用 --sysdate-is-now）

-- SQL Server:
-- GETDATE() / CURRENT_TIMESTAMP / SYSDATETIME(): 每次调用都不同
-- 注意：SQL Server 中 CURRENT_TIMESTAMP 不严格语句一致
SELECT CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP;
-- 三个值通常相同（因为执行太快），但理论上可不同

-- Oracle:
-- CURRENT_TIMESTAMP / SYSTIMESTAMP / SYSDATE
-- SYSDATE 每次调用按当前时间求值
-- CURRENT_TIMESTAMP 受 NLS 时区影响

-- 跨引擎可移植的事务一致 NOW():
-- PG: now()
-- MySQL: NOW(6)（不要用 SYSDATE）
-- Oracle: CURRENT_TIMESTAMP（事务级）
-- SQL Server: 没有事务一致版本，最接近 SYSDATETIME() 一次到变量
```

## ALTER TABLE 改变 DEFAULT 的语义

```sql
-- 1. ALTER COLUMN SET DEFAULT 不影响已有行
ALTER TABLE t ALTER COLUMN status SET DEFAULT 'inactive';
-- 已有行的 status 仍是旧值（'active' 等）
-- 仅未来未提供 status 的 INSERT 使用新默认值

-- 2. ALTER COLUMN DROP DEFAULT
ALTER TABLE t ALTER COLUMN status DROP DEFAULT;
-- 之后 INSERT 不提供 status 会报错（如果 NOT NULL）或写入 NULL

-- 3. PostgreSQL：DEFAULT 改变同时回填
-- 需要显式 UPDATE
UPDATE t SET status = 'inactive' WHERE status IS NULL;

-- 4. SQL Server：DEFAULT 是约束，需先 DROP 旧约束
ALTER TABLE t DROP CONSTRAINT DF_t_status;
ALTER TABLE t ADD CONSTRAINT DF_t_status DEFAULT 'inactive' FOR status;

-- 5. MySQL: 直接 ALTER MODIFY
ALTER TABLE t MODIFY COLUMN status VARCHAR(20) DEFAULT 'inactive';
-- 仅元数据变化，已有行不变
```

## 引擎实现建议

### 1. 求值时机的设计原则

```
CREATE TABLE t (
    col1 TYPE1 DEFAULT expr1,
    col2 TYPE2 DEFAULT expr2
);

-- 内部表示：
-- pg_attrdef / 类似的 catalog 表存储 (col_id -> default_expr_AST)
-- INSERT 路径：
--   1. 解析 INSERT，对每个未提供值的列查找 default_expr
--   2. 在 query rewrite 阶段或 plan 阶段把 DEFAULT 替换为 expr
--   3. expr 被表达式求值器按行调用

-- 优化：
-- - 常量 DEFAULT 在解析期就内联（避免每行调用）
-- - STABLE 函数在语句开始时一次求值并缓存
-- - VOLATILE 函数每行调用
```

### 2. ALTER TABLE ADD COLUMN 的元数据策略

```
-- Fast default 实现：
-- 1. catalog 中给列添加 missing_value 字段
-- 2. 物理 row format 仍按旧 schema
-- 3. 读路径检测列缺失，从 missing_value 填充
-- 4. 写路径（INSERT/UPDATE）按新 schema 写入

-- 触发条件：
-- - DEFAULT 是常量 → 直接存常量为 missing_value
-- - DEFAULT 是 STABLE 函数 → 一次求值后存为 missing_value
-- - DEFAULT 是 VOLATILE 函数 → 必须重写表（每行不同）
-- - 没有 DEFAULT → 隐式 NULL，无需 missing_value

-- 后续维护：
-- - VACUUM 时可能重写老页，把 missing_value 写入物理行
-- - DROP COLUMN 时只是元数据 hidden，不重写

-- 受限场景：
-- - 列存格式：通常天然元数据（按列存储，缺列空目录）
-- - 复制：missing_value 必须复制到所有副本
-- - 备份：需要包含 catalog 元数据
```

### 3. CURRENT_TIMESTAMP 语句一致性的实现

```
-- 在每个 SQL 语句执行开始时：
-- 1. 记录 statement_start_timestamp
-- 2. 在表达式求值器中，CURRENT_TIMESTAMP 直接返回此值
-- 3. 不重新调用系统时钟（避免性能开销和不一致）

-- 复制兼容性：
-- - SBR 模式下，重放时使用 binlog 中记录的时间戳
-- - RBR 模式下，时间戳已物化在行变更中
-- - 主从一致性要求 CURRENT_TIMESTAMP 行为可重放
```

### 4. 表达式 DEFAULT 的语法树存储

```
-- 不要存储 DEFAULT 的字符串形式（容易因 schema 变化失效）
-- 推荐存储 parsed AST + 序列化后的字节流：
-- - PG: pg_attrdef.adbin (nodeToString of expression AST)
-- - MySQL: 8.0 后存储 JSON 化的 expression
-- - 优点：跨版本兼容、易于操纵

-- 编译时处理：
-- 1. 解析 DEFAULT 表达式
-- 2. 类型检查（必须可隐式赋值给列类型）
-- 3. 验证不引用其他列、不调用 UDF（按引擎策略）
-- 4. 存储为 AST
```

### 5. UUID/序列号的并发分配

```
-- 高并发 INSERT 时：
-- - UUID 各行独立生成，无锁
-- - SERIAL/IDENTITY 需序列服务（PG 用 sequence、MySQL 用 InnoDB auto-inc lock）
-- - 序列号缓存（CACHE 子句）减少争用

-- 实现建议：
-- 1. 使用线程本地 PRNG 生成 UUID（避免锁）
-- 2. 序列号批量预分配（例如每次 1000 个）
-- 3. binlog/WAL 记录消耗的序列号范围（用于复制）
```

### 6. ALTER 改变 DEFAULT 的回填策略

```
-- 不应主动回填（语义上仅影响未来 INSERT）
-- 但 fast default 与 ALTER SET DEFAULT 的交互需注意：

-- PG: ALTER SET DEFAULT 不改变 attmissingval（保持旧行的"原默认值"）
-- 这是正确的：ADD COLUMN 时的默认值与后来改变的默认值是两个概念

-- 为新值显式回填：
UPDATE t SET col = new_default_value WHERE col IS NULL;
-- 或使用 NOT NULL DEFAULT 约束自然触发
```

### 7. 复制兼容性

```
-- DEFAULT 表达式必须在主从间求值一致：
-- - 字面量：自然一致
-- - now()/CURRENT_TIMESTAMP：SBR 重放时一次求值，RBR 物化结果
-- - UUID/RANDOM：必须用 RBR 模式（每行求值后写入 binlog）
-- - 用户定义函数：必须确定性（DETERMINISTIC 标记）

-- MySQL 强制：
-- - SBR 模式下 UUID()/SYSDATE() 等被标记 unsafe
-- - 警告或拒绝复制（取决于 binlog_format）

-- 引擎设计要点：
-- 1. 标记每个内置函数的 volatility
-- 2. SBR 时禁止 unsafe 函数（或自动切 RBR）
-- 3. RBR 时物化所有 DEFAULT 求值结果，与原始行一并写入 binlog
```

## 测试建议

```sql
-- 1. 时间戳一致性测试
INSERT INTO t (id) VALUES (1), (2), (3);  -- 验证 CURRENT_TIMESTAMP 是否相同
-- vs
INSERT INTO t (id, ts) VALUES (1, SYSDATE(6)), (2, SYSDATE(6)), (3, SYSDATE(6));
-- 验证 SYSDATE 是否每行不同

-- 2. UUID 唯一性测试
INSERT INTO t (data) SELECT 'x' FROM generate_series(1, 1000000);
SELECT COUNT(DISTINCT id) FROM t;  -- 应等于 1000000

-- 3. ALTER ADD COLUMN 性能测试
-- 1GB 表
ALTER TABLE big_table ADD COLUMN status TEXT DEFAULT 'pending';
-- 测量耗时：< 1 秒（fast default）vs > 30 秒（rewrite）

-- 4. STABLE vs VOLATILE
ALTER TABLE t ADD COLUMN c1 TIMESTAMPTZ DEFAULT now();          -- 应快速完成
ALTER TABLE t ADD COLUMN c2 UUID DEFAULT gen_random_uuid();     -- 应触发重写

-- 5. 跨复制一致性
-- 主库
INSERT INTO t (data) VALUES ('test');
-- 验证从库的 created_at / id 与主库完全一致（RBR）
```

## 关键发现

1. **SQL:1992 引入 DEFAULT，SQL:2003 扩展为生成列**：标准最初仅允许字面量与几个时间/用户函数；现代引擎几乎都支持任意确定性表达式。

2. **2018 是 DEFAULT 演进的关键年份**：MySQL 8.0.13 (Oct 2018) 解锁了"任意列 + 任意表达式"的 DEFAULT；PostgreSQL 11 (Oct 2018) 引入 fast default 让 ALTER ADD COLUMN 从"重写整张表"变成元数据操作。

3. **CURRENT_TIMESTAMP 是语句一致的（标准要求）**：在多行 INSERT 中所有行获得相同时间戳；这与 `gen_random_uuid()`/`UUID()`/`SYSDATE()` 等"每次调用真实求值"的函数不同。

4. **PostgreSQL 用 volatility 区分 fast default**：IMMUTABLE/STABLE 可元数据，VOLATILE 必须重写——这意味着 `gen_random_uuid()` 作为 ALTER ADD DEFAULT 仍需重写。

5. **MySQL 表达式 DEFAULT 必须括号包围**：`DEFAULT (UUID())` 正确，`DEFAULT UUID()` 报错；MariaDB 不强制括号（语法分支差异）。

6. **SQL Server 的 ALTER ADD COLUMN 一直是元数据**（自 2012/2014）：包括 NOT NULL DEFAULT，业界领先 PostgreSQL 6 年；但 DEFAULT 是命名约束，删除时需先 DROP CONSTRAINT。

7. **Oracle 12c 多步引入 fast default**：12c R1 支持 NOT NULL DEFAULT 元数据，12c R2 扩展到允许 NULL 的列；18c+ 允许 DEFAULT 中调用序列。

8. **MySQL ON UPDATE CURRENT_TIMESTAMP 是非标准但极常见**：每个表最多一个，会在行实际变化时刷新；其他引擎需要触发器实现。

9. **SQL Server NEWSEQUENTIALID 仅可作 DEFAULT 使用**：用于减少索引页分裂，但生成的 UUID 可预测；NEWID() 在所有位置可用但导致索引插入随机化。

10. **SQLite 的 ADD COLUMN DEFAULT 不允许 CURRENT_TIMESTAMP**：必须是真常量；非常量需先 ADD 普通列再 UPDATE。

11. **ClickHouse 的三种"默认"机制（DEFAULT/MATERIALIZED/ALIAS）超越标准**：DEFAULT 可被 INSERT 覆盖；MATERIALIZED 总是计算且不可覆盖；ALIAS 不存储仅 SELECT 时计算。

12. **CockroachDB / TiDB 通过元数据避免重写**：分布式 KV 模型天然支持 fast default；OceanBase / YugabyteDB 同样。

13. **DEFAULT vs 触发器选择规则**：常量与单函数用 DEFAULT（性能更好）；引用其他列必须用触发器或生成列；复杂业务逻辑用触发器。

14. **生成列 (GENERATED) 是 DEFAULT 的补充**：`STORED` 自动写入物理行，`VIRTUAL` 仅 SELECT 时计算；与 DEFAULT 互补——DEFAULT 仅一次求值固定，生成列追踪依赖列变化。

15. **复制兼容性约束 DEFAULT 函数选择**：MySQL 在 SBR 模式下禁用 `SYSDATE()/UUID()` 等 unsafe 函数；Oracle / PG 通过 RBR 物化结果到 binlog/WAL 解决。

16. **元数据 DEFAULT 的副作用**：ALTER SET DEFAULT 不影响已存行；fast default 的 missing value 与显式 SET DEFAULT 是不同 catalog 字段；理解二者有助于排查"列值为何与 DEFAULT 不一致"问题。

17. **2003 年至今 OLTP 数据库 DEFAULT 的演进**：从严格字面量 → 时间戳函数 → UUID 函数 → 任意确定性表达式 → JSON/BLOB 默认值 → fast default ALTER；近年趋势是消除 DDL 性能瓶颈，让 schema 演化更廉价。

18. **MPP 引擎与列存的天然优势**：Snowflake / BigQuery / ClickHouse 等列存引擎，添加列总是元数据操作（按列存储独立）；行存引擎需要专门的 fast default 机制。

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992, §11.5 column definition (DEFAULT clause)
- SQL:2003 标准: ISO/IEC 9075-2:2003, §11.4 (DEFAULT clause, generation clause)
- PostgreSQL: [CREATE TABLE / ALTER TABLE](https://www.postgresql.org/docs/current/sql-createtable.html)
- PostgreSQL 11 release notes (2018-10): [Fast default for ALTER TABLE ADD COLUMN](https://www.postgresql.org/docs/release/11.0/)
- MySQL: [Data Type Default Values](https://dev.mysql.com/doc/refman/8.0/en/data-type-defaults.html)
- MySQL WL#9418: DEFAULT for non-traditional data types (8.0.13)
- MySQL 8.0 INSTANT ADD COLUMN: [WL#11250](https://dev.mysql.com/worklog/task/?id=11250)
- MariaDB: [DEFAULT](https://mariadb.com/kb/en/default/)
- MariaDB INSTANT ALTER TABLE (10.3+): [Knowledge Base](https://mariadb.com/kb/en/innodb-online-ddl-overview/)
- Oracle: [CREATE TABLE column_definition](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-TABLE.html)
- Oracle 12c R2: [Fast default for nullable columns](https://docs.oracle.com/database/121/NEWFT/chapter12102.htm)
- SQL Server: [Default Constraints](https://learn.microsoft.com/en-us/sql/relational-databases/tables/specify-default-values-for-columns)
- SQLite: [CREATE TABLE column-def](https://www.sqlite.org/lang_createtable.html#dfltval)
- DB2: [Default values for columns](https://www.ibm.com/docs/en/db2/11.5?topic=values-default)
- Snowflake: [DEFAULT in column definitions](https://docs.snowflake.com/en/sql-reference/sql/create-table)
- BigQuery: [Default values for columns](https://cloud.google.com/bigquery/docs/default-values)
- ClickHouse: [DEFAULT / MATERIALIZED / ALIAS](https://clickhouse.com/docs/en/sql-reference/statements/create/table)
- DuckDB: [CREATE TABLE](https://duckdb.org/docs/sql/statements/create_table)
- CockroachDB: [DEFAULT expressions](https://www.cockroachlabs.com/docs/stable/default-value)
- Spark SQL 3.4: [DEFAULT column values](https://spark.apache.org/docs/3.4.0/sql-ref-syntax-ddl-create-table-datasource.html)
- TiDB: [Schema Lease](https://docs.pingcap.com/tidb/stable/online-ddl)
- Spanner: [DEFAULT column values](https://cloud.google.com/spanner/docs/reference/standard-sql/data-definition-language)
