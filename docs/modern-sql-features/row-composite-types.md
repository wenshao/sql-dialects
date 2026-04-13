# 行类型与复合类型 (Row and Composite Types)

关系模型把"行"当作一等公民，但绝大多数 SQL 方言却让程序员只能把行拆成一个个标量列来处理——直到 SQL:1999 把 ROW 类型写进标准。行类型与复合类型架起了纯关系世界与面向记录的应用世界之间的桥梁：它让你可以把一整行作为表达式传来传去，可以用 `(a, b) = (1, 2)` 写优雅的多列比较，可以让函数返回一个结构化的元组，也可以在列里嵌套一整张子表。本文系统梳理 ROW 与复合类型在 45+ 数据库中的支持现状。

本文聚焦"行作为值"这一核心语义；与之相关的 ARRAY/MAP/STRUCT 集合细节请参见 `array-collection-types.md`，原子类型（INT/VARCHAR 等）的方言映射请参见 `data-type-mapping.md`。

## 为什么需要行类型

考虑一个最朴素的需求：分页。绝大多数初学者会写：

```sql
SELECT * FROM events ORDER BY ts, id LIMIT 20 OFFSET 10000;
```

`OFFSET` 在数据量大时是 O(N) 的，深翻页的代价随偏移量线性增长。**keyset 分页**才是工业标准答案：用上一页最后一行的"游标"作为下一页的起点。但游标通常是复合的（比如 `(ts, id)`）：

```sql
-- 没有行类型时，必须手工展开
SELECT * FROM events
WHERE ts > ?
   OR (ts = ? AND id > ?)
ORDER BY ts, id LIMIT 20;

-- 有行类型时
SELECT * FROM events
WHERE (ts, id) > (?, ?)
ORDER BY ts, id LIMIT 20;
```

这两个写法的差异不仅仅是"少打几个字"。在第二种写法里，优化器可以非常清楚地看到"我要查找复合键 `(ts, id)` 上的下一个键"，复合索引可以被精确利用；在第一种写法里，OR 子句的展开可能让优化器误判索引利用率，特别是在 MySQL、SQL Server 这类对 OR 处理不佳的引擎上。

类似的场景还有很多：

- 多列 IN：`(a, b) IN ((1,2), (3,4))`
- 多列子查询：`(a, b) = (SELECT x, y FROM t WHERE ...)`
- 多列赋值：`UPDATE t SET (a, b) = (SELECT x, y FROM s WHERE ...)`
- 函数返回多值：`SELECT * FROM split_name('Doe, John') AS (last TEXT, first TEXT)`
- 嵌套数据：把"地址"作为一个字段而不是把 street/city/zip 拆成三列

行类型与复合类型就是为了让这些原本需要"绕"的写法变得自然而然。它让 SQL 在记录层面具备了和应用语言一样的表达力——而这恰恰是关系代数从一开始就允诺的能力。

## SQL 标准定义

### SQL:1999 ROW 类型

SQL:1999 第二部分（Foundation）正式引入两类与"行"相关的设施。

```sql
-- 1) 匿名行类型与行构造器（ROW constructor）
ROW (1, 'hello', TRUE)
(1, 'hello', TRUE)              -- 简写形式

-- 2) ROW 作为字段类型
CREATE TABLE t (
    id    INTEGER,
    addr  ROW(street VARCHAR(40), city VARCHAR(20), zip CHAR(5))
);

-- 3) 多列比较 / 多列赋值
SELECT * FROM orders WHERE (cust_id, order_date) = (?, ?);
UPDATE t SET (a, b) = (SELECT x, y FROM s WHERE ...);
```

### SQL:2003 CREATE TYPE ... AS

SQL:2003 进一步引入命名复合类型（structured user-defined type）：

```sql
CREATE TYPE address_t AS (
    street VARCHAR(40),
    city   VARCHAR(20),
    zip    CHAR(5)
);

CREATE TABLE customer (
    id   INTEGER,
    home address_t
);

SELECT (home).city FROM customer;          -- 字段访问
SELECT home.city   FROM customer;          -- 在某些方言中等价
```

标准约定的关键语义：

1. **行类型是结构化值类型**：可以出现在 SELECT、WHERE、函数参数、返回值等任何表达式位置。
2. **字段访问**：`row_value.field_name` 或 `(row_value).field_name`（带括号是为了避免与表名歧义）。
3. **NULL 行 vs 全 NULL 行**：`ROW(NULL, NULL)` 与 `NULL` 是两个不同的值。
4. **行比较是字典序**（lexicographic），与字符串比较类似。
5. **DISTINCT TYPE**：仅是已有类型的强类型别名，不属于复合类型范畴（DB2 概念）。
6. **ROW 类型的相等**：要求字段数相同、字段类型可比较；命名结构化类型还要求类型名一致。

### 与 SQL:2016 行模式匹配的关系

SQL:2016 引入 `MATCH_RECOGNIZE`，把"一序列行"当作一等公民进行模式匹配——这是行类型在时序/事件分析里的延伸。本文的支持矩阵包含 ROW 模式匹配一项，但深入语法请参考独立专题。

## 支持矩阵（综合）

### ROW 构造器与多列比较

| 引擎 | `ROW(...)` | `(a, b)` 简写 | 行比较 `(a,b)=(1,2)` | 字典序比较 `<`, `>` | IN 多列 | 行解包赋值 |
|------|-----------|---------------|----------------------|---------------------|---------|------------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | 是 (UPDATE) |
| MySQL | 是 | 是 | 是 | 是 | 是 | -- |
| MariaDB | 是 | 是 | 是 | 是 | 是 | -- |
| SQLite | -- | 是 | 是 | 是 | 是 | -- |
| Oracle | -- | 是 (受限) | 是 | -- | 是 | -- |
| SQL Server | -- | -- | -- | -- | -- | -- |
| DB2 | -- | -- | -- | -- | 是 (子查询) | -- |
| Snowflake | -- | -- | -- | -- | 是 | -- |
| BigQuery | -- (用 STRUCT) | 是 (STRUCT) | 是 (STRUCT) | -- | 是 | -- |
| Redshift | -- | -- | -- | -- | 是 | -- |
| DuckDB | 是 (ROW=STRUCT) | 是 | 是 | 是 | 是 | -- |
| ClickHouse | -- (Tuple) | 是 (元组) | 是 | 是 | 是 | -- |
| Trino | 是 | 是 | 是 | 是 | 是 | -- |
| Presto | 是 | 是 | 是 | 是 | 是 | -- |
| Spark SQL | -- (struct) | -- | 是 | 是 | 是 | -- |
| Hive | -- (named_struct) | -- | -- | -- | 是 | -- |
| Flink SQL | 是 | 是 | 是 | 是 | 是 | -- |
| Databricks | -- (struct) | -- | 是 | 是 | 是 | -- |
| Teradata | -- | -- | -- | -- | 是 | -- |
| Greenplum | 是 | 是 | 是 | 是 | 是 | 是 |
| CockroachDB | 是 | 是 | 是 | 是 | 是 | 是 |
| TiDB | 是 | 是 | 是 | 是 | 是 | -- |
| OceanBase | 是 | 是 | 是 | 是 | 是 | -- |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 是 |
| SingleStore | 是 | 是 | 是 | 是 | 是 | -- |
| Vertica | 是 | 是 | 是 | 是 | 是 | -- |
| Impala | -- | -- | -- | -- | 是 | -- |
| StarRocks | -- (struct) | -- | -- | -- | 是 | -- |
| Doris | -- (struct) | -- | -- | -- | 是 | -- |
| MonetDB | -- | -- | -- | -- | 是 | -- |
| CrateDB | -- (object) | -- | -- | -- | -- | -- |
| TimescaleDB | 是 | 是 | 是 | 是 | 是 | 是 |
| QuestDB | -- | -- | -- | -- | -- | -- |
| Exasol | -- | -- | -- | -- | -- | -- |
| SAP HANA | -- | -- | -- | -- | 是 | -- |
| Informix | 是 (ROW) | -- | -- | -- | -- | -- |
| Firebird | -- | -- | -- | -- | -- | -- |
| H2 | 是 | 是 | 是 | 是 | 是 | -- |
| HSQLDB | 是 | 是 | 是 | 是 | 是 | -- |
| Derby | -- | -- | -- | -- | -- | -- |
| Amazon Athena | 是 | 是 | 是 | 是 | 是 | -- |
| Azure Synapse | -- | -- | -- | -- | -- | -- |
| Google Spanner | -- (STRUCT) | 是 (STRUCT) | -- | -- | 是 | -- |
| Materialize | 是 | 是 | 是 | 是 | 是 | -- |
| RisingWave | 是 | 是 | 是 | 是 | 是 | -- |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | -- |
| Databend | -- (Tuple) | 是 | 是 | 是 | 是 | -- |
| Yellowbrick | 是 | 是 | 是 | 是 | 是 | 是 |
| Firebolt | -- | -- | -- | -- | 是 | -- |

> 说明：MySQL/MariaDB 的 `ROW()` 仅在 IN/比较语境与子查询改写中可用，不能作为列类型或函数返回值。SQLite 不支持 `ROW` 关键字，但接受括号简写形式的多列比较。

### 命名复合类型 / 结构化类型 (CREATE TYPE ... AS)

| 引擎 | 命名复合类型 | 语法 | 作为列类型 | 字段访问 | 嵌套 |
|------|--------------|------|-----------|----------|------|
| PostgreSQL | 是 | `CREATE TYPE t AS (a INT, b TEXT)` | 是 | `(col).a` | 是 |
| Oracle | 是 (Object) | `CREATE TYPE t AS OBJECT (a NUMBER, b VARCHAR2(20))` | 是 | `col.a` | 是 |
| DB2 | 是 (Structured) | `CREATE TYPE t AS (a INT, b VARCHAR(20)) NOT FINAL` | 是（典型表层级） | 方法风格 | 是 |
| SQL Server | -- (用 TVP / 用户定义表类型) | -- | -- | -- | -- |
| MySQL | -- | -- | -- | -- | -- |
| MariaDB | -- | -- | -- | -- | -- |
| SQLite | -- | -- | -- | -- | -- |
| Snowflake | -- (用 OBJECT/VARIANT) | -- | OBJECT 列 | `col:a` | 是 |
| BigQuery | -- (用 STRUCT 结构字面) | `STRUCT<a INT64, b STRING>` | 是 | `col.a` | 是 |
| Redshift | -- (SUPER) | -- | SUPER 列 | `col.a` | 是 |
| DuckDB | -- (用 STRUCT) | `STRUCT(a INT, b VARCHAR)` | 是 | `col.a` | 是 |
| ClickHouse | -- (NamedTuple) | `Tuple(a Int32, b String)` | 是 | `col.a` | 是 |
| Trino | -- (用 ROW) | `ROW(a INT, b VARCHAR)` | 是 | `col.a` | 是 |
| Presto | -- (用 ROW) | `ROW(a INT, b VARCHAR)` | 是 | `col.a` | 是 |
| Spark SQL | -- (用 StructType) | `STRUCT<a:INT,b:STRING>` | 是 | `col.a` | 是 |
| Hive | -- (用 STRUCT) | `STRUCT<a:INT,b:STRING>` | 是 | `col.a` | 是 |
| Flink SQL | -- (用 ROW) | `ROW<a INT, b STRING>` | 是 | `col.a` | 是 |
| Databricks | -- (用 STRUCT) | `STRUCT<a:INT,b:STRING>` | 是 | `col.a` | 是 |
| Teradata | 是 (UDT Structured) | `CREATE TYPE t AS (...) INSTANTIABLE` | 是 | 方法 | 是 |
| Greenplum | 是 (继承 PG) | 同 PG | 是 | `(col).a` | 是 |
| CockroachDB | -- | -- | -- | -- | -- |
| TiDB | -- | -- | -- | -- | -- |
| OceanBase | 是 (兼容 Oracle) | `CREATE TYPE t AS OBJECT (...)` | 是 | `col.a` | 是 |
| YugabyteDB | 是 (继承 PG) | 同 PG | 是 | `(col).a` | 是 |
| SingleStore | -- | -- | -- | -- | -- |
| Vertica | -- | -- | -- | -- | -- |
| Impala | -- (用 STRUCT) | `STRUCT<a:INT,b:STRING>` | 是 | `col.a` | 是 |
| StarRocks | -- (用 STRUCT) | `STRUCT<a INT, b STRING>` | 是 | `col.a` | 是 |
| Doris | -- (用 STRUCT) | `STRUCT<a:INT,b:STRING>` | 是 | `col.a` | 是 |
| MonetDB | -- | -- | -- | -- | -- |
| CrateDB | -- (用 OBJECT) | `OBJECT AS (a INT, b TEXT)` | 是 | `col['a']` | 是 |
| TimescaleDB | 是 (继承 PG) | 同 PG | 是 | `(col).a` | 是 |
| QuestDB | -- | -- | -- | -- | -- |
| Exasol | -- | -- | -- | -- | -- |
| SAP HANA | -- | -- | -- | -- | -- |
| Informix | 是 (Named ROW) | `CREATE ROW TYPE t (...)` | 是 | `col.a` | 是 |
| Firebird | -- | -- | -- | -- | -- |
| H2 | -- | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- | -- |
| Amazon Athena | -- (ROW/STRUCT) | `ROW(a INT, b VARCHAR)` | 是 | `col.a` | 是 |
| Azure Synapse | -- | -- | -- | -- | -- |
| Google Spanner | -- (STRUCT 仅查询) | `STRUCT<a INT64, b STRING>` | -- (不能存储) | `col.a` | 是 |
| Materialize | 是 (继承 PG) | 同 PG | 是 | `(col).a` | 是 |
| RisingWave | 是 (struct) | `STRUCT<a INT, b VARCHAR>` | 是 | `(col).a` | 是 |
| InfluxDB (SQL) | -- | -- | -- | -- | -- |
| Databend | -- (Tuple) | `Tuple(Int32, String)` | 是 | `col.1` | 是 |
| Yellowbrick | 是 (继承 PG) | 同 PG | 是 | `(col).a` | 是 |
| Firebolt | -- | -- | -- | -- | -- |

> 注：很多分析型引擎（DuckDB / ClickHouse / Spark / Hive / Trino / BigQuery / Snowflake）选择直接复用一个嵌套数据类型（STRUCT / ROW / Tuple / OBJECT）作为列类型，而不引入"命名复合类型"DDL。这与 PostgreSQL 学院派的 `CREATE TYPE` 路线形成两条平行的演化线。

### 行作为函数参数 / 返回值

| 引擎 | 行作为函数返回 | 表函数 (TVF) | 标量函数返回行 | 表值参数 (TVP) |
|------|----------------|--------------|----------------|----------------|
| PostgreSQL | 是 (`RETURNS table_name`) | `RETURNS TABLE(...)` | 是 | -- (用复合类型) |
| Oracle | 是 (Object) | Pipelined Function | 是 | -- |
| SQL Server | -- | `RETURNS TABLE` | -- | 是 (TVP) |
| DB2 | 是 | `RETURNS TABLE(...)` | 是 | -- |
| MySQL | -- | -- | -- | -- |
| MariaDB | -- | -- | -- | -- |
| SQLite | -- | 虚表 | -- | -- |
| Snowflake | OBJECT/VARIANT | `RETURNS TABLE(...)` | 是 | -- |
| BigQuery | STRUCT | `RETURNS TABLE<...>` | 是 | -- |
| Redshift | SUPER | -- | -- | -- |
| DuckDB | STRUCT | `RETURNS TABLE(...)` | 是 | -- |
| ClickHouse | Tuple | -- | 是 | -- |
| Trino / Presto | ROW | -- | 是 | -- |
| Spark SQL | StructType | -- | 是 | -- |
| Hive | STRUCT | UDTF | 是 | -- |
| Flink SQL | ROW | TableFunction | 是 | -- |
| Databricks | STRUCT | -- | 是 | -- |
| Teradata | 是 | TVF | 是 | -- |
| Greenplum | 是 | 是 | 是 | -- |
| CockroachDB | -- | -- | -- | -- |
| TiDB | -- | -- | -- | -- |
| OceanBase | 是 (Oracle 兼容) | Pipelined | 是 | -- |
| YugabyteDB | 是 | 是 | 是 | -- |
| SingleStore | -- | -- | -- | -- |
| Vertica | -- | UDX/UDTF | -- | -- |
| Impala | STRUCT | -- | -- | -- |
| StarRocks | STRUCT | -- | -- | -- |
| Doris | STRUCT | -- | -- | -- |
| MonetDB | -- | TVF | -- | -- |
| CrateDB | -- | -- | -- | -- |
| TimescaleDB | 是 | 是 | 是 | -- |
| QuestDB | -- | -- | -- | -- |
| Exasol | -- | -- | -- | -- |
| SAP HANA | -- | TVF | -- | -- |
| Informix | 是 | -- | 是 | -- |
| Firebird | -- | 存储过程 | -- | -- |
| H2 | -- | 是 | -- | -- |
| HSQLDB | -- | 是 | -- | -- |
| Derby | -- | 是 | -- | -- |
| Amazon Athena | ROW | -- | 是 | -- |
| Azure Synapse | -- | -- | -- | 部分 |
| Google Spanner | STRUCT | -- | 是 | -- |
| Materialize | 是 | -- | 是 | -- |
| RisingWave | STRUCT | -- | 是 | -- |
| InfluxDB (SQL) | -- | -- | -- | -- |
| Databend | Tuple | -- | -- | -- |
| Yellowbrick | 是 | 是 | 是 | -- |
| Firebolt | -- | -- | -- | -- |

### 行作为列值（嵌套行）

| 引擎 | 列直接存 ROW | 嵌套层数 | 物理形态 |
|------|--------------|----------|---------|
| PostgreSQL | 是 | 任意 | 行存，TOAST |
| Oracle | 是 (OBJECT) | 任意 | 行存，REF |
| DB2 | 是 (Structured) | 任意 | 行存 |
| BigQuery | 是 | 任意 | 列存 (Capacitor/Dremel) |
| Snowflake | OBJECT/VARIANT | 任意 | 半结构化列存 |
| DuckDB | 是 | 任意 | 列存（Arrow 兼容） |
| ClickHouse | 是 (NamedTuple) | 任意 | 子列分量列存 |
| Spark SQL | 是 | 任意 | Parquet/ORC 列存 |
| Trino | 是 | 任意 | 取决于连接器 |
| Flink SQL | 是 | 任意 | 行/列均可 |
| StarRocks | 是 | 任意 | 列存 |
| Doris | 是 | 任意 | 列存 |
| Impala | 是 (Parquet) | 任意 | 列存 |
| Hive | 是 | 任意 | 列存/行存 |
| 其他 OLTP | 否或半结构化 JSON 替代 | -- | -- |

### 行模式匹配 (Row Pattern Recognition, SQL:2016)

| 引擎 | `MATCH_RECOGNIZE` | 备注 |
|------|--------------------|------|
| Oracle | 是 | 12c+ 完整支持 |
| Snowflake | 是 | GA |
| Trino / Presto | 是 | 较完整 |
| Flink SQL | 是 | 流模式核心特性 |
| Vertica | 部分 (`EVENT_NAME`/`MATCH_ID` 风格) | 早期实现 |
| Teradata | 是 | -- |
| SingleStore | -- | -- |
| 其他 | -- | 大多数数据库不支持 |

> 行模式匹配并不属于"行类型本身"的范畴，但它是 SQL 标准中处理"一序列行"作为一等公民的另一面，故在此一并列出。详见独立专题。

### 行字面量类型推断对比

| 引擎 | `(1, 'a', TRUE)` 推断为 | 默认字段名 |
|------|--------------------------|-----------|
| PostgreSQL | `record`（匿名 RECORD） | `f1, f2, f3`（用 `AS t(f1 ...)` 显式命名） |
| BigQuery | `STRUCT<INT64, STRING, BOOL>` | 无名（位置访问）或 `_field_1...` |
| DuckDB | `STRUCT(v1 INT, v2 VARCHAR, v3 BOOLEAN)` 或 `ROW` | `v1, v2, v3` |
| Trino / Presto | `row(integer, varchar(1), boolean)` | `field0, field1, field2` |
| ClickHouse | `Tuple(UInt8, String, Bool)` | 数字位置 `.1, .2, .3` |
| Spark SQL | `struct<col1:int, col2:string, col3:boolean>` | `col1, col2, col3` |
| Snowflake | 不支持匿名行字面量，需要 `OBJECT_CONSTRUCT` | -- |
| MySQL | 仅在比较语境合法，无独立类型 | -- |
| Flink SQL | `ROW<EXPR$0 INT, EXPR$1 STRING, EXPR$2 BOOLEAN>` | `EXPR$N` |

匿名字段名（`col1`、`_field_1`、`f1`）是大多数引擎规避命名冲突的方式，但这意味着你**没法**先 `SELECT (1, 'a')` 再 `WHERE (.field1) = ...`——必须在构造时显式命名。

## 详解：主流引擎实现

### PostgreSQL：复合类型的圣地

PostgreSQL 是 SQL 世界里把复合类型推得最远的引擎。每张表自动创建一个同名复合类型；用户也可以显式 `CREATE TYPE ... AS`：

```sql
-- 1) 显式命名复合类型
CREATE TYPE address AS (
    street TEXT,
    city   TEXT,
    zip    CHAR(5)
);

CREATE TABLE customer (
    id   SERIAL PRIMARY KEY,
    name TEXT,
    home address
);

INSERT INTO customer (name, home)
VALUES ('Alice', ROW('1 Main', 'Springfield', '00000')::address);

-- 2) 字段访问必须加括号（否则与表名歧义）
SELECT (home).city, name FROM customer;

-- 3) 把整张表的"行"作为值
SELECT customer FROM customer;            -- 整行作为一个复合值
SELECT (customer).name FROM customer;     -- 等价于 SELECT name

-- 4) 行构造器
SELECT ROW(1, 'a', TRUE);                 -- 匿名行
SELECT (1, 'a', TRUE);                    -- 简写

-- 5) 行比较
SELECT * FROM t WHERE (a, b) = (1, 2);
SELECT * FROM t WHERE (a, b) > (1, 2);    -- 字典序

-- 6) 行解包赋值
UPDATE t SET (a, b) = (SELECT x, y FROM s WHERE s.id = t.id);

-- 7) 函数返回行
CREATE FUNCTION min_max(arr INT[]) RETURNS RECORD AS $$
    SELECT min(x), max(x) FROM unnest(arr) AS x;
$$ LANGUAGE SQL;

SELECT * FROM min_max(ARRAY[3,1,4,1,5,9]) AS t(lo INT, hi INT);

-- 8) 函数返回命名复合类型
CREATE FUNCTION get_addr(cid INT) RETURNS address AS $$
    SELECT home FROM customer WHERE id = cid;
$$ LANGUAGE SQL;

SELECT (get_addr(1)).city;
```

PostgreSQL 还有一个很特别的能力：表名本身可作为函数调用 `c.home` ↔ `home(c)`，这在 ORM 与函数组合上非常方便。

PostgreSQL 复合类型的几个细节坑：

- **括号必需**：`SELECT customer.home.city FROM customer` 会被误判为 schema.table.column，必须写 `SELECT (customer.home).city FROM customer`。
- **行 NULL 与全 NULL 行**：`ROW(NULL, NULL) IS NULL` 在 PG 里是 TRUE，但 `(SELECT ROW(NULL, NULL)) IS DISTINCT FROM NULL` 是 FALSE——这是历史遗留。
- **隐式表行类型**：`SELECT t FROM t` 实际是 `SELECT ROW(t.*) FROM t`，输出的是文本形式 `(1,'a',true)`。
- **嵌套**：`CREATE TYPE addr_book AS (home address, work address)` 完全合法。

### Oracle：Object Type 与 PL/SQL RECORD

Oracle 走的是面向对象路线。SQL 层面上的复合类型必须通过 `CREATE TYPE ... AS OBJECT`：

```sql
-- SQL 层：对象类型
CREATE OR REPLACE TYPE address_t AS OBJECT (
    street VARCHAR2(40),
    city   VARCHAR2(20),
    zip    CHAR(5)
);
/

CREATE TABLE customer (
    id   NUMBER PRIMARY KEY,
    home address_t
);

INSERT INTO customer VALUES (1, address_t('1 Main', 'Springfield', '00000'));
SELECT c.home.city FROM customer c;       -- 注意：必须加表别名
```

`VARRAY` 与 `NESTED TABLE` 在此基础上提供集合，方法（MEMBER FUNCTION）使其更像 OO：

```sql
CREATE TYPE address_t AS OBJECT (
    street VARCHAR2(40),
    city   VARCHAR2(20),
    zip    CHAR(5),
    MEMBER FUNCTION format RETURN VARCHAR2
);
/

CREATE TYPE BODY address_t AS
    MEMBER FUNCTION format RETURN VARCHAR2 IS
    BEGIN
        RETURN street || ', ' || city || ' ' || zip;
    END;
END;
/

SELECT c.home.format() FROM customer c;
```

PL/SQL 层另有一套**RECORD**：

```sql
DECLARE
    TYPE addr_rec IS RECORD (
        street VARCHAR2(40),
        city   VARCHAR2(20)
    );
    a addr_rec;
BEGIN
    a.street := '1 Main';
    a.city   := 'Springfield';
END;
/
```

PL/SQL RECORD 仅在过程式语境里存在，不能直接出现在 SQL 列里——这是 Oracle 与 PostgreSQL 设计哲学最大的差别。要让 PL/SQL RECORD 与 SQL 层互通，必须要么用 `%ROWTYPE` 绑定到表行，要么显式构造 OBJECT 实例。

```sql
DECLARE
    r customer%ROWTYPE;     -- 隐式继承表的所有列
BEGIN
    SELECT * INTO r FROM customer WHERE id = 1;
    DBMS_OUTPUT.PUT_LINE(r.name);
END;
/
```

`%ROWTYPE` 是 Oracle PL/SQL 里"行作为值"的最自然写法，但一旦离开 PL/SQL 块就不再有效。

### SQL Server：用 TVP 替代复合类型

SQL Server 没有 SQL 层的 ROW/复合类型，但提供了**用户定义表类型**（User-Defined Table Type）作为表值参数（Table-Valued Parameters）：

```sql
CREATE TYPE AddressList AS TABLE (
    street NVARCHAR(40),
    city   NVARCHAR(20),
    zip    CHAR(5)
);

CREATE PROCEDURE InsertAddresses @addrs AddressList READONLY
AS
BEGIN
    INSERT INTO customer_address(street, city, zip)
    SELECT street, city, zip FROM @addrs;
END;
```

这种方式只能"面向参数"使用，不能在 SELECT 表达式里把行当作值传递。SQL Server 的多列 IN 只能改写成多个布尔条件，因为它**不支持 `(a,b) = (1,2)` 行比较**：

```sql
-- SQL Server 不支持
SELECT * FROM t WHERE (a, b) IN ((1, 2), (3, 4));

-- 必须改写成
SELECT * FROM t WHERE (a = 1 AND b = 2) OR (a = 3 AND b = 4);

-- 或者用临时表 / VALUES 子句
SELECT t.* FROM t
JOIN (VALUES (1, 2), (3, 4)) AS v(a, b)
  ON t.a = v.a AND t.b = v.b;
```

第三种 `VALUES` JOIN 是 SQL Server 社区的事实标准，但它已经远离了"行类型作为表达式"的优雅初衷。

SQL Server 还提供 CLR User-Defined Types，可以用 .NET 类型扩展 SQL，但这是一种"绕道而行"的方案，与 SQL 标准的复合类型理念差距甚远。

### DB2：Structured Type 与 Distinct Type

DB2 提供两类 UDT：

1. **DISTINCT TYPE**：基于已有原子类型的强类型别名，例如 `CREATE DISTINCT TYPE us_dollar AS DECIMAL(9,2) WITH COMPARISONS;` —— 不属于复合类型范畴，目的是类型隔离（避免把美元当成欧元参与计算）。
2. **STRUCTURED TYPE**：真正的结构化类型，允许继承（`UNDER`）、方法（`METHOD`）：

```sql
CREATE TYPE address_t AS (
    street VARCHAR(40),
    city   VARCHAR(20),
    zip    CHAR(5)
) NOT FINAL;

CREATE TYPE us_address_t UNDER address_t AS (state CHAR(2)) NOT FINAL;
```

不过 DB2 的结构化类型在表列里使用通常需要 `WITH OPTIONS` 与 reference table，工程上偏重，远不如 PG 的复合类型轻量。DB2 也没有标准的 `(a,b) = (1,2)` 行比较，但支持 `WHERE (a,b) IN (SELECT ...)`。

### ClickHouse：Tuple 与 Named Tuple

ClickHouse 把"行"建模为 `Tuple(...)`：

```sql
-- 匿名 Tuple
SELECT (1, 'a', true)              -- 类型 Tuple(UInt8, String, Bool)
SELECT tupleElement((1,'a'), 1)    -- 1
SELECT (1,'a').1                   -- 1，下标从 1 开始

-- 22.x 起的 Named Tuple：可命名字段
CREATE TABLE events (
    id  UInt64,
    ctx Tuple(user_id UInt64, ip String, device String)
) ENGINE = MergeTree ORDER BY id;

SELECT ctx.user_id, ctx.ip FROM events;

-- 嵌套
CREATE TABLE t (
    rec Tuple(
        name String,
        addr Tuple(city String, zip String)
    )
) ENGINE = MergeTree ORDER BY tuple();

SELECT rec.addr.city FROM t;
```

ClickHouse 的 Tuple 是**列存的"分量列"**：每个字段实际作为独立的子列存储，因此 `ctx.user_id` 可以单独读、单独压缩、单独编码——这是 PostgreSQL 行存复合类型不具备的列存优势。

ClickHouse 还有一个特殊的 `Nested` 类型，本质上是 `Array(Tuple(...))` 的语法糖，对应"一行里嵌一张子表"的常见模式：

```sql
CREATE TABLE orders (
    order_id UInt64,
    items Nested(
        sku String,
        qty UInt32,
        price Decimal(10, 2)
    )
) ENGINE = MergeTree ORDER BY order_id;

SELECT order_id, items.sku, items.qty FROM orders;
```

### DuckDB：STRUCT 即 ROW

DuckDB 把 ROW 与 STRUCT 视为同一概念的两种语法：

```sql
SELECT {'a': 1, 'b': 'hello'}                   -- struct 字面量
SELECT row(1, 'hello')                           -- 等价
SELECT struct_pack(a := 1, b := 'hello')         -- 命名构造

CREATE TABLE t (
    rec STRUCT(a INT, b VARCHAR)
);
INSERT INTO t VALUES ({'a': 1, 'b': 'hi'});

SELECT rec.a FROM t;
SELECT rec.* FROM t;                             -- 解包字段
```

DuckDB 的 STRUCT 与 LIST、MAP 互相组合可以表达任意嵌套结构（类似 Parquet/Arrow 的逻辑模型）。例如：

```sql
SELECT [{'name': 'Alice', 'age': 30},
        {'name': 'Bob',   'age': 25}] AS people;

SELECT unnest(people, recursive := true) FROM ...;
```

DuckDB 把 STRUCT 与 ROW 视作同义词，是分析型嵌入式数据库最优雅的"行 = 列存嵌套"的实现。

### Snowflake：OBJECT / VARIANT

Snowflake 没有 SQL 标准的 ROW，而是用半结构化的 `OBJECT`/`VARIANT` 表达"行/记录"语义：

```sql
SELECT OBJECT_CONSTRUCT('a', 1, 'b', 'hello');    -- {"a":1,"b":"hello"}
SELECT v:a::INT FROM (SELECT PARSE_JSON('{"a":1}') v);

CREATE TABLE t (rec OBJECT);
INSERT INTO t SELECT OBJECT_CONSTRUCT('id', 1, 'name', 'Alice');
SELECT rec:name::STRING FROM t;
```

OBJECT 是**无 schema** 的（值即元数据），与 PostgreSQL 复合类型的强 schema 思路完全相反。Snowflake 也没有 `(a,b) = (1,2)` 行比较语法。Snowflake 的设计哲学是"半结构化优先"——在 ELT 场景里灵活，但在强类型校验上完全把责任转嫁给上游或下游工具。

### BigQuery：STRUCT 是一等公民

BigQuery 的 `STRUCT<...>` 直接对应 ROW，并且是查询语言内置的核心类型：

```sql
SELECT STRUCT(1 AS id, 'Alice' AS name) AS person;
SELECT STRUCT<a INT64, b STRING>(1, 'x');

CREATE TABLE dataset.t (
    person STRUCT<id INT64, name STRING>
);

SELECT person.name FROM dataset.t;

-- 多列比较 / 解包
SELECT * FROM dataset.t WHERE STRUCT(person.id, person.name) = STRUCT(1, 'Alice');
SELECT (id, name) FROM UNNEST([STRUCT(1,'a'), STRUCT(2,'b')]);
```

STRUCT 与 ARRAY 自由嵌套（`ARRAY<STRUCT<...>>`）是 BigQuery"列存 + 嵌套"模型的核心。这一模型的来源是 Google 的 Dremel / Capacitor 论文：嵌套字段直接列存，无需展开成关系模型。

BigQuery 的 STRUCT 字段访问可以用 `.` 操作符，但不能像 PG 那样把整张表的行作为复合值传出。

### Spark SQL / Databricks：StructType

Spark SQL 的 `StructType` 是 DataFrame schema 的基本组成单元：

```sql
CREATE TABLE t (
    person STRUCT<id:INT, name:STRING>
) USING parquet;

SELECT person.name FROM t;
SELECT named_struct('a', 1, 'b', 'x') AS rec;
SELECT struct(1, 'x') AS rec;     -- 字段名 col1, col2
```

`STRUCT` 是一等列类型，可与 `ARRAY`、`MAP` 嵌套；但 Spark SQL **没有** `CREATE TYPE` 这类命名复合类型 DDL——所有结构都是匿名的。

DataFrame API 里的 `StructType` 是 Catalyst 优化器的内置类型，编译期已知字段顺序与类型，因此可以做向量化执行；这是 Spark / Databricks 处理嵌套数据的核心。

### Trino / Presto：ROW 类型完整支持

Trino/Presto 是分析型引擎里 SQL 标准 ROW 类型支持最完整的：

```sql
SELECT ROW(1, 'a', true) AS rec;
SELECT CAST(ROW(1, 'a') AS ROW(id INT, name VARCHAR));

CREATE TABLE t (
    person ROW(id INT, name VARCHAR)
) WITH (format = 'PARQUET');

SELECT person.id, person.name FROM t;
SELECT person FROM t WHERE person = ROW(1, 'Alice');
```

Trino 也支持完整的字典序行比较 `(a, b) < (1, 2)` 与 IN 列表 `(a, b) IN ((1,2),(3,4))`，是 BigQuery/Snowflake 这类 OLAP 巨头之外少有的"标准派"分析引擎。

### Flink SQL：ROW 类型与流处理

Flink SQL 的 ROW 类型是事件结构的核心：

```sql
CREATE TABLE clicks (
    user_id BIGINT,
    payload ROW<
        page STRING,
        referrer STRING,
        ts TIMESTAMP(3)
    >
) WITH ('connector' = 'kafka', ...);

SELECT user_id, payload.page, payload.ts FROM clicks;
SELECT ROW(user_id, payload.page) AS uk FROM clicks;
```

Flink 的 ROW 可以由 Avro/Protobuf/JSON 反序列化器自动派生，是流式 ETL 处理结构化事件的基础设施。

### CockroachDB：PG 兼容的 ROW

CockroachDB 完整支持 PostgreSQL 的行构造、行比较、行解包 UPDATE：

```sql
SELECT (a, b) FROM t WHERE (a, b) > (1, 2);
UPDATE t SET (a, b) = (SELECT x, y FROM s WHERE id = t.id);
```

但 **不支持** `CREATE TYPE ... AS (composite)` —— CockroachDB 只实现了 ENUM，复合类型至今没有。这是 PG 兼容路线的一大缺口。

### TiDB / OceanBase / SingleStore：MySQL 风格

这一群 NewSQL 引擎延续 MySQL 的"仅在比较语境支持 ROW"，没有命名复合类型 DDL，但能做行比较与多列 IN，配合复合索引可以实现高性能 keyset 分页。OceanBase 的 Oracle 兼容模式额外支持 `CREATE TYPE OBJECT`。

## ROW 比较语义：字典序的细节

SQL 标准把行比较定义为**字典序**（lexicographic / pairwise）。这是看似简单、用错就翻车的语义。

### 基本规则

```sql
-- (a1, a2, ..., an)  op  (b1, b2, ..., bn)
```

按从左到右逐个比较：

1. 找到第一个 `ai ≠ bi` 的位置，结果由该位置决定（`ai op bi`）。
2. 若所有都相等，则两行相等。
3. 若任何参与决定的 `ai` 或 `bi` 是 NULL，结果通常是 NULL（"unknown"），具体规则因运算符而异。

```sql
(1, 2) < (1, 3)        -- TRUE，第二位 2 < 3 决定
(1, 2) < (2, 1)        -- TRUE，第一位 1 < 2 决定
(1, 2) = (1, 2)        -- TRUE
(1, 2) <> (1, 3)       -- TRUE
(1, NULL) = (1, NULL)  -- NULL，注意不是 TRUE
(1, NULL) < (2, 0)     -- TRUE，第一位就决定，NULL 不参与
(1, NULL) < (1, 0)     -- NULL，必须看第二位，NULL 比较未知
```

### 一个常见用法：keyset 分页

```sql
-- 第一页
SELECT * FROM events ORDER BY ts, id LIMIT 20;

-- 下一页：用最后一行的 (ts, id) 作为游标
SELECT * FROM events
WHERE (ts, id) > (?, ?)
ORDER BY ts, id LIMIT 20;
```

这等价于：

```sql
WHERE ts > ?
   OR (ts = ? AND id > ?)
```

但显著简洁，并且优化器能直接利用 `(ts, id)` 复合索引。**然而**：

- PostgreSQL、MySQL、MariaDB、SQLite、CockroachDB、TiDB、OceanBase、Trino、Vertica 等都能利用复合索引。
- SQL Server **不支持**这种语法，只能写展开形式。
- Oracle 支持语法但优化器对索引利用并不总是理想。
- ClickHouse 支持元组比较，但分区/排序键的利用要看具体表达式。

### NULL 排序约定

在使用行比较做 keyset 分页时，必须保证排序列 NOT NULL，否则第一个 NULL 会让游标"卡住"——这一点比单列分页更隐蔽。

### MySQL 的特殊规则

MySQL 接受 `ROW(1,2) = (SELECT a, b FROM t)`，但 `(a, b) IN ((1,2), (3,4))` 并不会用到 `(a,b)` 上的复合索引（除非至少 5.7+ 的优化器版本，且取决于统计信息）。这是 MySQL 历史上的著名痛点。

### SQLite 的"小惊喜"

SQLite 自 3.15.0 起支持行值比较，并能利用复合索引。这让 SQLite 成为同时支持 `(a,b)=(1,2)` 与 keyset 分页索引利用的最小数据库——而 SQL Server 这种企业级产品反而不支持。

### 混合升降序的行比较

SQL 标准并未规定 `(a, b) > (1, 2)` 在 ORDER BY 是 `a ASC, b DESC` 时如何表达。实际上行比较只支持"全部同方向"。如果你要的是混合方向的游标（例如最新时间戳的最小 id），必须手工展开：

```sql
ORDER BY ts DESC, id ASC

WHERE ts < ?
   OR (ts = ? AND id > ?)
```

这是 keyset 分页一个常被忽视的边界条件。

## 与 ARRAY / MAP / STRUCT 的关系

`array-collection-types.md` 已经详细讨论了集合类型。这里简要厘清边界：

| 类型 | 数据形态 | 长度 | 字段名 | 典型用途 |
|------|---------|------|--------|----------|
| ARRAY | 同质元素序列 | 可变 | -- (按下标) | 列表、向量 |
| MAP | 键值对 | 可变 | -- (按 key) | 字典 |
| STRUCT / ROW | 异质字段 | 固定 | 是 | 记录、嵌套行 |

很多引擎让这三者可以自由嵌套：`ARRAY<STRUCT<a:INT, b:STRING>>` 是 BigQuery、Spark、DuckDB 的"标配嵌套行"，相当于"在一行里嵌入一张子表"。这是 ROW 类型与"集合即列"模型的关键交汇点。

### "嵌套表 vs 嵌套行"

值得注意的是，`ARRAY<STRUCT>` 与"再开一张子表 + 外键"在表达力上等价，但在物理存储与查询路径上完全不同：

- **关系范式**：用外键展开成两张表，符合第三范式；JOIN 代价随数据增长。
- **嵌套范式**：用嵌套数组直接存在父行里；列存引擎可直接向量化扫描嵌套字段，没有 JOIN。

BigQuery、Spark、DuckDB 等都把"嵌套范式"作为列存的核心抽象。这从根本上改变了 schema 设计的权衡——而 ROW 类型正是嵌套范式得以存在的语法基础。

## 关键发现

1. **两条演化路线**。SQL 标准（PostgreSQL/Oracle/DB2/Informix/Teradata）走"先有命名复合类型 + 实例"的学院派；分析型引擎（BigQuery/Spark/DuckDB/ClickHouse/Trino/Snowflake）走"匿名 ROW/STRUCT/Tuple 即列类型"的实用派。两条路线在工程上各有所长——前者类型严谨，后者列存友好。

2. **MySQL 阵营的"阉割版" ROW**。MySQL/MariaDB 的 `ROW()` 仅是为了让 `IN`、子查询比较有合法语法，**根本无法**作为列类型、变量类型或函数返回类型存在。这与他们对 `WITH RECURSIVE`、`JSON_TABLE` 等迟到的支持一脉相承——OLTP 阵营长期低估"行作为值"的工程意义。

3. **SQL Server 的缺位最显眼**。一个支持 TVP、表值函数、CLR UDT 的企业级数据库，居然连 `(a,b) = (1,2)` 都不支持——这导致 .NET 生态里 keyset 分页、批量 UPSERT 都必须手写展开 SQL，至今是 EF Core 等 ORM 难以优雅生成的痛点。

4. **SQLite 的隐藏宝石**。SQLite 自 3.15 起的行值支持非常完整，能够利用复合索引做 keyset 分页。一个嵌入式数据库在这一点上压过 SQL Server。

5. **ClickHouse Named Tuple 的列存基因**。22.x 引入的 Named Tuple 在语法上很像 PostgreSQL 复合类型，但底层每个字段是独立列存的。这让"嵌套 = 减速"的传统直觉在分析型场景下被打破：嵌套字段单独读、单独压缩、单独索引。

6. **DuckDB 把 ROW 当 STRUCT**。DuckDB 没有为"ROW"和"STRUCT"分别建模，两者就是同一类型的两种语法。这种统一让 SQL 接近 Parquet/Arrow 的物理模型，是分析型嵌入式数据库最优雅的一笔。

7. **Snowflake 走 schemaless 路线**。Snowflake 用 `OBJECT/VARIANT` 取代了所有结构化类型——值自带 schema，强类型 `CREATE TYPE` 完全缺席。这让 Snowflake 在 ELT 场景里灵活，但在 BI 报表的列校验层面把成本转嫁给了下游工具。

8. **行模式匹配是另一个故事**。`MATCH_RECOGNIZE`（SQL:2016）让"一序列行"成为一等表达对象，是 ROW 类型在时序/流场景的延伸。Oracle、Snowflake、Trino、Flink 是这一特性的主要拥趸；绝大多数 OLTP 引擎仍然停在最古典的标量列模型里。

9. **PostgreSQL 是唯一全栈赢家**。从 SQL:1999 ROW 构造器、字典序比较、行解包 UPDATE，到 SQL:2003 命名复合类型、表自动派生类型、表名作函数、`RETURNS RECORD/TABLE`——PostgreSQL 把"行作为值"的能力做到了最完整。其代价是"加括号"的字段访问语法 `(col).field`，是 SQL 学习者最常被绊倒的语法之一。

10. **Oracle 的 SQL/PLSQL 鸿沟**。PL/SQL 的 RECORD 与 SQL 层的 OBJECT TYPE 是两套不互通的复合机制——这是 Oracle 双层架构的历史遗留。要把 RECORD 从过程层送进 SQL 层，必须手工构造对象类型实例。

11. **行类型 + 复合索引 = 优雅 OLTP**。对 OLTP 工作负载，`(a, b) > (?, ?)` 配合 `(a, b)` 复合索引是 keyset 分页的最佳实践之一——但只有支持行比较 + 优化器友好的少数引擎能完整发挥（PG、SQLite、MySQL 8+、CockroachDB、TiDB、Vertica）。这是一个被大多数应用层架构师忽视、却能立竿见影提升性能与代码质量的特性。

12. **嵌套范式重塑 schema 设计**。`ARRAY<STRUCT<...>>` 取代 1:N 表 + JOIN，是列存分析引擎的核心抽象。这种"行里嵌行"的能力直接来自 ROW/STRUCT 类型的存在；没有它，BigQuery/Spark/DuckDB 的嵌套数据模型根本无法成立。

13. **45+ 引擎可以划成五个阵营**：
    - **PG 系**（PG/Greenplum/Yugabyte/CockroachDB/Materialize/RisingWave/TimescaleDB/Yellowbrick）：行 + 复合 + 字典序齐全。
    - **MySQL 系**（MySQL/MariaDB/TiDB/OceanBase/SingleStore）：仅有行比较与简单 IN，没有复合类型 DDL。
    - **企业 OO**（Oracle/DB2/Informix/Teradata）：命名结构化类型走对象路线，门槛高。
    - **分析嵌套**（BigQuery/Snowflake/DuckDB/ClickHouse/Spark/Hive/Trino/Presto/Impala/StarRocks/Doris/Athena/Databricks）：用 STRUCT/ROW/Tuple/OBJECT 表达嵌套行。
    - **缺位派**（SQL Server/H2 部分版本/Firebird/Derby/Exasol/QuestDB/Firebolt 等）：连 `(a,b)=(1,2)` 都不支持，行类型几乎完全缺失。

行类型是 SQL 标准里最优雅、最被忽视、也最考验引擎设计哲学的一组特性。从 keyset 分页到嵌套 JSON 摄入，从 ORM 友好性到列存优化，"行作为值"早已不是学术问题——它是衡量一个数据库是否真正把关系模型当回事的试金石。
