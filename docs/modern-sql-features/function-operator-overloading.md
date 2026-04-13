# 函数与操作符重载 (Function and Operator Overloading)

同一个 `+` 号既能加整数、又能加字符串、还能合并 JSON 和拼接数组——这种"一名多义"的能力是现代 SQL 类型系统的基石。函数与操作符重载不仅是语法糖，更是数据库引擎扩展性的核心机制：从 PostgreSQL 的几何类型到 Oracle 的对象类型，从 PostGIS 的 `ST_*` 族函数到 pgvector 的 `<->` 距离操作符，无一不依赖重载。本文系统对比 45+ 数据库的函数与操作符重载能力。

## SQL 标准定义

### SQL:1999 用户定义例程

SQL:1999 (ISO/IEC 9075-2, Section 11) 引入了用户定义例程 (User-Defined Routines, UDR) 的概念，并显式支持函数名重载：

```sql
<routine_name> ::= [ <schema_name> "." ] <qualified_identifier>

-- 同一名称可对应多个例程，由参数类型 (parameter signature) 区分
CREATE FUNCTION add(a INTEGER, b INTEGER) RETURNS INTEGER ...
CREATE FUNCTION add(a DECIMAL, b DECIMAL) RETURNS DECIMAL ...
CREATE FUNCTION add(a VARCHAR, b VARCHAR) RETURNS VARCHAR ...
```

标准的关键概念：

1. **特征签名 (specific signature)**：例程由 (schema, name, parameter type list) 唯一标识
2. **特定名称 (SPECIFIC name)**：可显式指定一个不可重复的内部名，用于 `DROP FUNCTION SPECIFIC ...`
3. **最佳匹配规则 (most specific routine)**：调用解析时按参数可隐式转换的"距离"选择最匹配的例程
4. **不允许仅靠返回类型重载**：两个例程若参数列表相同但返回类型不同，是非法的

### SQL/MM 与多态

SQL/MM (ISO/IEC 13249) 在空间、全文、数据挖掘等部分定义了大量的多态例程模式，允许同名函数处理不同的几何类型 (POINT, LINESTRING, POLYGON)，实际上为 PostGIS 等扩展提供了模板。

### SQL:2003+ 的发展

* **数组与多集**：SQL:2003 引入 ARRAY/MULTISET 后，函数解析需考虑构造类型的协变；
* **结构化类型**：SQL:1999 Object Extensions (Part 2 + Part 9) 定义 `CREATE TYPE` 与 `METHOD`，在用户定义类型上重载方法是标准行为；
* **操作符重载**：SQL 标准本身**不**定义 `CREATE OPERATOR`，所有操作符重载都属于厂商扩展。PostgreSQL 是事实标准。

## 综合支持矩阵

### 函数名重载 (Function Name Overloading)

| 引擎 | 同名函数重载 | 解析方式 | 支持 SPECIFIC | 版本 |
|------|------------|---------|---------------|------|
| PostgreSQL | 是 | 参数类型 + 隐式转换距离 | 是 | 7.0+ |
| MySQL | 否 | -- | -- | 不支持 |
| MariaDB | 否 | -- | -- | 不支持 |
| SQLite | 否 (C API 可按 argc 区分) | 参数个数 | -- | -- |
| Oracle | 是 (仅在 PACKAGE 内) | 参数类型 | -- | 7.x+ |
| SQL Server | 否 (T-SQL UDF) / CLR 是 | -- | -- | -- |
| DB2 | 是 | 参数类型 | 是 (`SPECIFIC`) | 7.x+ |
| Snowflake | 是 | 参数类型 | -- | 2022+ |
| BigQuery | 是 | 参数类型 | -- | 2023+ |
| Redshift | 是 (继承 PG) | 参数类型 | -- | GA |
| DuckDB | 是 | 参数类型 | -- | 0.5+ |
| ClickHouse | 否 (UDF 全局唯一名) | -- | -- | -- |
| Trino | 是 (内置 + SQL UDF) | 参数类型 | -- | GA |
| Presto | 是 | 参数类型 | -- | GA |
| Spark SQL | 否 (Hive UDF 名唯一) / Scala API 是 | -- | -- | -- |
| Hive | 否 | -- | -- | -- |
| Flink SQL | 是 (Java/Scala UDF eval 多签名) | 参数类型 | -- | 1.x+ |
| Databricks | 同 Spark | -- | -- | -- |
| Teradata | 是 | 参数类型 | 是 (`SPECIFIC`) | V2R6+ |
| Greenplum | 是 (继承 PG) | 同 PG | 是 | GA |
| CockroachDB | 是 | 参数类型 | -- | 22.2+ |
| TiDB | 否 | -- | -- | -- |
| OceanBase | 是 (PL/SQL PACKAGE 内, Oracle 模式) | 参数类型 | -- | 2.x+ |
| YugabyteDB | 是 (继承 PG) | 同 PG | 是 | GA |
| SingleStore | 否 | -- | -- | -- |
| Vertica | 是 (UDx) | 参数类型 | -- | GA |
| Impala | 是 | 参数类型 | -- | 2.x+ |
| StarRocks | 否 | -- | -- | -- |
| Doris | 否 | -- | -- | -- |
| MonetDB | 是 | 参数类型 | -- | GA |
| CrateDB | 否 (UDF 名唯一) | -- | -- | -- |
| TimescaleDB | 是 (继承 PG) | 同 PG | 是 | GA |
| QuestDB | 否 | -- | -- | -- |
| Exasol | 否 (UDF 名唯一) | -- | -- | -- |
| SAP HANA | 是 (在 SQLScript) | 参数类型 | -- | 1.0+ |
| Informix | 是 | 参数类型 + 类型层次 | 是 (`SPECIFIC`) | 9.x+ |
| Firebird | 否 (但可用 PACKAGE) | -- | -- | -- |
| H2 | 否 | -- | -- | -- |
| HSQLDB | 否 | -- | -- | -- |
| Derby | 否 | -- | -- | -- |
| Amazon Athena | 是 (继承 Trino) | 参数类型 | -- | GA |
| Azure Synapse | 否 (T-SQL) | -- | -- | -- |
| Google Spanner | 否 | -- | -- | -- |
| Materialize | 是 (继承 PG) | 同 PG | 是 | GA |
| RisingWave | 是 (PG 兼容) | 同 PG | -- | GA |
| InfluxDB (SQL) | 否 | -- | -- | -- |
| DatabendDB | 否 | -- | -- | -- |
| Yellowbrick | 是 (继承 PG) | 同 PG | -- | GA |
| Firebolt | 否 | -- | -- | -- |

> 统计：约 24 个引擎支持函数名重载，约 25 个引擎不支持或仅在特定 API 下支持。

### 用户定义操作符 (CREATE OPERATOR)

| 引擎 | `CREATE OPERATOR` | 自定义符号 | 操作符属性 (COMMUTATOR/NEGATOR) | 索引绑定 |
|------|-------------------|-----------|------------------------------|---------|
| PostgreSQL | 是 | 任意符号组合 | 是 | 是 (OPERATOR CLASS) |
| MySQL / MariaDB | 否 | -- | -- | -- |
| SQLite | 否 | -- | -- | -- |
| Oracle | 是 (`CREATE OPERATOR`) | 标识符 | -- | 是 (`ODCIIndex`) |
| SQL Server | 否 (CLR 类型方法) | -- | -- | -- |
| DB2 | 是 (在 UDT 上) | 标识符 | -- | 是 (UDF index extension) |
| Snowflake | 否 | -- | -- | -- |
| BigQuery | 否 | -- | -- | -- |
| Redshift | 否 | -- | -- | -- |
| DuckDB | 否 (内置可重载) | -- | -- | -- |
| ClickHouse | 否 | -- | -- | -- |
| Trino / Presto | 否 | -- | -- | -- |
| Spark SQL / Databricks | 否 | -- | -- | -- |
| Hive / Flink | 否 | -- | -- | -- |
| Teradata | 否 (UDM 方法可重载) | -- | -- | -- |
| Greenplum | 是 (继承 PG) | 同 PG | 是 | 是 |
| CockroachDB | 否 | -- | -- | -- |
| TiDB / OceanBase | 否 | -- | -- | -- |
| YugabyteDB | 是 (继承 PG) | 同 PG | 是 | 是 |
| SingleStore | 否 | -- | -- | -- |
| Vertica | 否 | -- | -- | -- |
| Impala | 否 | -- | -- | -- |
| StarRocks / Doris | 否 | -- | -- | -- |
| MonetDB | 否 (内置 SQL) | -- | -- | -- |
| CrateDB | 否 | -- | -- | -- |
| TimescaleDB | 是 (继承 PG) | 同 PG | 是 | 是 |
| QuestDB / Exasol | 否 | -- | -- | -- |
| SAP HANA | 否 | -- | -- | -- |
| Informix | 是 (UDR + opclass) | 是 | -- | 是 |
| Firebird / H2 / HSQLDB / Derby | 否 | -- | -- | -- |
| Amazon Athena | 否 | -- | -- | -- |
| Azure Synapse | 否 | -- | -- | -- |
| Google Spanner | 否 | -- | -- | -- |
| Materialize | 部分 (继承 PG 部分) | -- | -- | -- |
| RisingWave | 否 | -- | -- | -- |
| InfluxDB | 否 | -- | -- | -- |
| DatabendDB | 否 | -- | -- | -- |
| Yellowbrick | 是 (继承 PG) | 同 PG | 是 | 是 |
| Firebolt | 否 | -- | -- | -- |

> 统计：仅约 8 个引擎提供完整的 `CREATE OPERATOR` 能力，其中 6 个是 PostgreSQL 衍生品。Oracle、DB2、Informix 是非 PG 阵营中的代表。

### 操作符重载 (重定义内置 +、-、= 等)

| 引擎 | 内置操作符可重载 | 用户类型重载 | 隐式转换可控 |
|------|----------------|-------------|------------|
| PostgreSQL | 是 (无符号保留) | 是 | 是 (`CREATE CAST`) |
| Oracle | 是 (TYPE 中 MAP/ORDER MEMBER) | 是 | 是 (`CREATE CAST` 仅 PL/SQL) |
| SQL Server | 否 (T-SQL); 是 (CLR UDT) | CLR 是 | 是 (`CREATE TYPE`) |
| DB2 | 是 (UDT) | 是 | 是 |
| Informix | 是 | 是 | 是 |
| Greenplum / TimescaleDB / Yellowbrick / YugabyteDB | 是 (继承 PG) | 是 | 是 |
| Materialize | 部分 | 部分 | 部分 |
| 其他所有 | 否 | -- | -- |

### 多态/泛型参数

| 引擎 | ANYELEMENT | ANYARRAY | ANYENUM | ANYNONARRAY | ANYRANGE | ANYCOMPATIBLE | VARIADIC |
|------|-----------|----------|---------|------------|----------|--------------|----------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 (9.2+) | 是 (13+) | 是 |
| Oracle | `SYS.ANYDATA` (近似) | -- | -- | -- | -- | -- | 否 |
| SQL Server | 否 (sql_variant 仅是动态类型) | -- | -- | -- | -- | -- | 否 |
| DB2 | -- | -- | -- | -- | -- | -- | -- |
| Snowflake | `VARIANT` (动态) | `ARRAY` (无类型) | -- | -- | -- | -- | 是 |
| BigQuery | `ANY TYPE` (UDF 模板) | -- | -- | -- | -- | -- | -- |
| DuckDB | `ANY` | `ANY[]` | -- | -- | -- | -- | 是 |
| Trino / Presto | 类型变量 (`T`) | `array(T)` | -- | -- | -- | -- | 是 |
| Spark SQL | 否 (UDF 通过 Scala 泛型) | -- | -- | -- | -- | -- | 是 |
| ClickHouse | -- | -- | -- | -- | -- | -- | 是 |
| Greenplum / TimescaleDB / YugabyteDB / Yellowbrick / Materialize | 是 (继承 PG) | 是 | 是 | 是 | 是 | 是 | 是 |
| CockroachDB | 部分 | 部分 | -- | -- | -- | -- | 是 |
| Vertica | 是 (UDx 多态) | -- | -- | -- | -- | -- | 是 |
| Flink SQL | `<T>` (Java 泛型) | -- | -- | -- | -- | -- | 是 |
| 其他 | -- | -- | -- | -- | -- | -- | -- |

### 默认参数值 (DEFAULT)

| 引擎 | 支持 | 语法关键字 | 末尾参数限制 |
|------|------|----------|-------------|
| PostgreSQL | 是 | `DEFAULT` / `=` | 是 |
| Oracle | 是 | `DEFAULT` | 否 (任意位置 + 命名) |
| SQL Server | 是 | `=` | 否 |
| DB2 | 是 | `DEFAULT` | 是 |
| MySQL / MariaDB | 否 | -- | -- |
| Snowflake | 是 | `DEFAULT` | 是 |
| BigQuery | 否 (UDF) | -- | -- |
| Redshift | 是 (继承 PG) | `DEFAULT` | 是 |
| DuckDB | 是 (宏) | `:=` | -- |
| ClickHouse | 否 | -- | -- |
| Trino / Presto | 否 (内置可有可选参数) | -- | -- |
| Spark SQL | 是 (内置 SQL UDF, 3.4+) | `DEFAULT` | 是 |
| Databricks | 是 | `DEFAULT` | 是 |
| Hive / Flink | 否 | -- | -- |
| Teradata | 是 | `DEFAULT` | 是 |
| Greenplum / Yugabyte / Timescale / Yellowbrick / Materialize | 是 | `DEFAULT` | 是 |
| CockroachDB | 是 | `DEFAULT` | 是 |
| TiDB / SingleStore / StarRocks / Doris | 否 | -- | -- |
| OceanBase | 是 (PL/SQL) | `DEFAULT` | 否 |
| Vertica | 是 | `DEFAULT` | 是 |
| Impala | 否 | -- | -- |
| MonetDB | 是 | `DEFAULT` | 是 |
| CrateDB / QuestDB / Exasol | 否 | -- | -- |
| SAP HANA | 是 | `DEFAULT` | 是 |
| Informix | 是 | `DEFAULT` | 是 |
| Firebird | 是 | `DEFAULT` / `=` | 是 |
| H2 / HSQLDB / Derby | 部分 | `DEFAULT` | -- |
| 其他云 | 否 | -- | -- |

### 命名参数 (Named/Keyword Arguments)

| 引擎 | 支持 | 语法 | 版本 |
|------|------|------|------|
| PostgreSQL | 是 | `name => value` 或 `name := value` | 9.0+ |
| Oracle | 是 | `name => value` | 早期 |
| SQL Server | 是 (仅 EXEC proc) | `@name = value` | 早期 |
| DB2 | 是 | `name => value` | 9.7+ |
| MySQL / MariaDB | 否 | -- | -- |
| SQLite | 否 | -- | -- |
| Snowflake | 是 | `name => value` (内置/UDF) | 2023+ |
| BigQuery | 是 (内置部分) | `name => value` | GA |
| Redshift | 是 (继承 PG) | `name := value` | GA |
| DuckDB | 是 | `name := value` | 0.5+ |
| ClickHouse | 否 | -- | -- |
| Trino / Presto | 是 (部分内置) | `name => value` | GA |
| Spark SQL | 是 (3.5+) | `name => value` | 3.5+ |
| Databricks | 是 | `name => value` | GA |
| Hive / Flink | 否 | -- | -- |
| Teradata | 是 | `USING name (...)` | GA |
| Greenplum / Yugabyte / Timescale / Yellowbrick / Materialize | 是 | 同 PG | GA |
| CockroachDB | 否 | -- | -- |
| TiDB / SingleStore / StarRocks / Doris | 否 | -- | -- |
| OceanBase | 是 (Oracle 模式) | `name => value` | GA |
| Vertica | 是 (内置部分) | `USING PARAMETERS name=value` | GA |
| Impala | 否 | -- | -- |
| MonetDB | 否 | -- | -- |
| CrateDB / QuestDB / Exasol | 否 | -- | -- |
| SAP HANA | 是 | `name => value` | GA |
| Informix | 否 | -- | -- |
| Firebird | 否 | -- | -- |
| H2 / HSQLDB / Derby | 否 | -- | -- |

### 操作符类与索引支持

| 引擎 | OPERATOR CLASS | OPERATOR FAMILY | 索引方法注册 |
|------|---------------|-----------------|-------------|
| PostgreSQL | 是 | 是 (8.3+) | 是 (B-tree, hash, GiST, GIN, SP-GiST, BRIN) |
| Oracle | 是 (Domain Index, ODCI) | -- | 是 |
| DB2 | 是 (Index Extensions) | -- | 是 |
| Informix | 是 (Virtual Index Interface) | -- | 是 |
| SQL Server | 否 (CLR 受限) | -- | -- |
| Greenplum / TimescaleDB / Yellowbrick / YugabyteDB | 是 (继承 PG) | 是 | 是 |
| 其他 | 否 | -- | -- |

> 统计：完整的可扩展索引接口仍是少数引擎的"奢侈品"。PostgreSQL 是唯一在开源世界中拥有完整 OPERATOR CLASS/FAMILY 体系的引擎。

## 详细引擎说明

### PostgreSQL：操作符重载的事实标准

PostgreSQL 的可扩展性是其 30 年长盛的核心。它的函数和操作符体系完全统一在一个目录之下：每一个内置 `+` 也只是 `pg_operator` 表里的一行，与用户定义的并无二致。

**函数名重载**：

```sql
CREATE FUNCTION area(circle)   RETURNS double precision AS '...' LANGUAGE C;
CREATE FUNCTION area(box)      RETURNS double precision AS '...' LANGUAGE C;
CREATE FUNCTION area(polygon)  RETURNS double precision AS '...' LANGUAGE C;

SELECT area('<(0,0),5>'::circle);
SELECT area('((0,0),(2,3))'::box);
```

调用解析按照以下顺序：

1. 收集所有同名函数；
2. 删除参数数量不匹配的；
3. 优先精确类型匹配；
4. 否则按隐式转换的"距离"（`pg_cast` 中 `c`/`a`/`i`）评分；
5. 若仍多个候选，则倾向 preferred 类型；
6. 若仍歧义，报错 `function ... is not unique`。

**多态类型族**：

| 类型变量 | 含义 |
|---------|------|
| `anyelement` | 任意类型 |
| `anyarray` | 任意数组，元素类型与 `anyelement` 一致 |
| `anynonarray` | 非数组的任意类型 |
| `anyenum` | 任意 ENUM |
| `anyrange` | 任意 range |
| `anymultirange` | 任意 multirange (14+) |
| `anycompatible*` | 一组参数共同的最近公共类型 |

```sql
CREATE FUNCTION array_first(anyarray) RETURNS anyelement AS $$
  SELECT $1[array_lower($1,1)];
$$ LANGUAGE sql;

SELECT array_first(ARRAY[1,2,3]);          -- 整数 1
SELECT array_first(ARRAY['a','b','c']);    -- 文本 'a'
```

### PostgreSQL CREATE OPERATOR 深入

PostgreSQL 允许任意"非字母"字符组成新操作符 (`+ - * / < > = ~ ! @ # % ^ & | ? \``)，最长 NAMEDATALEN-1 字符。一个完整的操作符定义示例：

```sql
-- 1. 先定义实现函数
CREATE FUNCTION complex_add(complex, complex) RETURNS complex
  AS 'MODULE_PATHNAME', 'complex_add'
  LANGUAGE C IMMUTABLE STRICT;

-- 2. 再定义操作符
CREATE OPERATOR + (
  LEFTARG    = complex,
  RIGHTARG   = complex,
  FUNCTION   = complex_add,
  COMMUTATOR = +,
  HASHES,
  MERGES
);
```

**关键属性**：

| 属性 | 含义 | 优化器作用 |
|------|------|----------|
| `LEFTARG`, `RIGHTARG` | 左右参数类型，二元必须都给 | 类型解析 |
| `FUNCTION` | 实现函数 | 实际计算 |
| `COMMUTATOR` | `a OP b == b OP' a` | 谓词重排序、索引可用性 |
| `NEGATOR` | `a OP b == NOT (a OP' b)` | NOT 谓词转换 |
| `RESTRICT` | 选择率估计函数 | 行数估算 |
| `JOIN` | 连接选择率估计函数 | 连接顺序 |
| `HASHES` | 该操作符可用于哈希连接 | 哈希连接 |
| `MERGES` | 该操作符可用于归并连接 | 归并连接 |

**OPERATOR CLASS 与 OPERATOR FAMILY**：

要让自定义类型能被索引使用，必须将一组操作符登记为 access method 的 opclass：

```sql
CREATE OPERATOR CLASS complex_abs_ops
  DEFAULT FOR TYPE complex USING btree AS
    OPERATOR  1  <  ,
    OPERATOR  2  <= ,
    OPERATOR  3  =  ,
    OPERATOR  4  >= ,
    OPERATOR  5  >  ,
    FUNCTION  1  complex_abs_cmp(complex, complex);
```

每种 access method 对操作符编号有固定语义：B-tree 用 1..5 表示比较顺序、hash 只需 1 (相等) 与一个 hash 函数、GiST/GIN/SP-GiST/BRIN 各有更复杂的策略号空间。

**OPERATOR FAMILY** (8.3+) 是 opclass 的超集，允许跨类型的操作符组合，例如让 `int4 < int8` 这种异构比较也能走索引：

```sql
CREATE OPERATOR FAMILY integer_ops USING btree;
ALTER OPERATOR FAMILY integer_ops USING btree
  ADD OPERATOR 1 < (int4, int8),
      OPERATOR 1 < (int8, int4),
      ...
```

PostGIS、pgvector、pg_trgm 等高知名度扩展，全都依赖这套 opclass/opfamily 机制。pgvector 的 `<->` (L2 距离)、`<#>` (内积)、`<=>` (余弦) 三个操作符及对应的 `vector_l2_ops`、`vector_ip_ops`、`vector_cosine_ops` opclass 是当代向量检索浪潮中的明星案例。

### Oracle：包内重载与对象类型方法

Oracle 在裸 SQL 层不支持 `CREATE FUNCTION` 重载（同名直接报 `ORA-00955`），但在 PACKAGE 内允许：

```sql
CREATE OR REPLACE PACKAGE math_pkg AS
  FUNCTION add (a NUMBER,  b NUMBER)  RETURN NUMBER;
  FUNCTION add (a VARCHAR2,b VARCHAR2) RETURN VARCHAR2;
END;
/
```

**对象类型方法重载**：

```sql
CREATE OR REPLACE TYPE money_t AS OBJECT (
  amount NUMBER, currency VARCHAR2(3),
  MAP MEMBER FUNCTION to_canonical RETURN NUMBER,
  MEMBER FUNCTION add(other money_t) RETURN money_t
);
```

`MAP MEMBER FUNCTION` 提供一个映射到标量的函数，使该对象在比较 (`=`、`<`、`>`)、`ORDER BY`、`DISTINCT` 时能像基本类型一样工作。`ORDER MEMBER FUNCTION` 是另一种方案：直接定义两两比较函数。一个类型最多有一个 MAP 或一个 ORDER。

**ANSI TYPE 操作符与 CREATE OPERATOR**：

Oracle 9i 引入了 `CREATE OPERATOR`，主要用于绑定到 Domain Index (ODCIIndex)：

```sql
CREATE OPERATOR contains
  BINDING (text_doc, VARCHAR2) RETURN NUMBER
  USING contains_impl;

-- 索引侧
CREATE INDEX idx_doc ON docs(body) INDEXTYPE IS ctxsys.context;

SELECT * FROM docs WHERE contains(body, 'oracle') > 0;
```

实际上 Oracle Text、Spatial、Multimedia、Machine Learning 大量使用这一机制，但语法面向"扩展开发者"而非普通用户。

### SQL Server：T-SQL 的局限与 CLR UDT 的弥补

T-SQL 函数**不**支持重载，且**没有** `CREATE OPERATOR`。要在自定义类型上获得操作符，唯一途径是 CLR User-Defined Type：

```csharp
[Serializable]
[SqlUserDefinedType(Format.Native)]
public struct Complex : INullable
{
    public Double Real;
    public Double Imaginary;
    public static Complex operator +(Complex a, Complex b) => ...;
    public static Complex Parse(SqlString s) { ... }
    public override string ToString() { ... }
}
```

```sql
CREATE TYPE dbo.Complex EXTERNAL NAME ComplexAsm.[Complex];
SELECT @c1 + @c2; -- T-SQL 自动桥接到 CLR 操作符
```

**重大限制**：SQL Server 2016 起 `clr enabled` 默认关闭，且 SQL Azure 完全禁用 CLR。这使得在云环境中操作符重载几乎不可用。EXEC 存储过程支持命名参数 (`@p = ...`)，函数调用不支持。

### DB2：UDT 上的丰富操作符体系

DB2 对 SQL:1999 的实现非常彻底。它允许在 DISTINCT TYPE / STRUCTURED TYPE 上定义同名函数和操作符：

```sql
CREATE DISTINCT TYPE us_dollar AS DECIMAL(15,2) WITH COMPARISONS;

CREATE FUNCTION "+" (us_dollar, us_dollar)
  RETURNS us_dollar
  SOURCE SYSIBM."+"(DECIMAL(15,2), DECIMAL(15,2));
```

`WITH COMPARISONS` 自动派生 `<`, `<=`, `=`, `>=`, `>`, `<>`，但算术操作符必须显式 `SOURCE` 到底层基类型。`SPECIFIC <name>` 可以为重载族中的每个个体起一个唯一名字以便 `DROP`。DB2 的 Index Extensions 允许将外部函数注册为索引可用谓词，是少数支持完整 OPERATOR CLASS 概念的非 PG 引擎之一。

### ClickHouse：极简的 UDF 哲学

ClickHouse 把性能放在首位，对扩展性持保守态度：

* `CREATE FUNCTION name AS (x, y) -> ...` 仅支持 lambda 形式 SQL UDF；
* 函数名全局唯一，不支持重载；
* 没有 `CREATE OPERATOR`；
* `executable` UDF 通过外部进程通信，但仍要求名称唯一；
* Aggregate Function Combinator (`-If`, `-Array`, `-State` 等) 通过命名约定模拟"多态"，但不是真正的重载。

### DuckDB：宏与函数重载

DuckDB 0.5 后支持 SQL macro (`CREATE MACRO`) 和函数重载，并允许多态参数 `ANY`：

```sql
CREATE MACRO add(a, b) AS a + b;
CREATE MACRO add(a, b, c) AS a + b + c;

CREATE MACRO clamp(x, lo := 0, hi := 1) AS
  CASE WHEN x < lo THEN lo WHEN x > hi THEN hi ELSE x END;

SELECT clamp(0.3);                -- 默认 lo=0, hi=1
SELECT clamp(5, lo := 0, hi := 10);
```

DuckDB 没有 `CREATE OPERATOR`，但内置的丰富类型 (LIST, STRUCT, MAP, UNION) 已经覆盖了大部分需求。

### Snowflake：2022 年补齐的重载

Snowflake 在 2022 年正式支持 SQL/JavaScript/Python/Java/Scala UDF 的同名重载：

```sql
CREATE OR REPLACE FUNCTION add(a INT, b INT) RETURNS INT
  AS $$ a + b $$;

CREATE OR REPLACE FUNCTION add(a STRING, b STRING) RETURNS STRING
  AS $$ a || b $$;
```

`SHOW USER FUNCTIONS` 会列出所有签名。Snowflake 不支持 `CREATE OPERATOR`，不允许重定义内置 `+`。命名参数 (`name => value`) 在内置函数中早已存在，2023 年扩展到 UDF 调用。

### BigQuery：2023 年的迟到者

BigQuery 直到 2023 年才支持 UDF 名称重载：同一 dataset 内可以有 `add(INT64, INT64)` 与 `add(STRING, STRING)` 共存。SQL UDF 还支持 `ANY TYPE` 参数实现模板：

```sql
CREATE FUNCTION mydataset.first_or_null(arr ANY TYPE) AS (
  IF(ARRAY_LENGTH(arr) > 0, arr[OFFSET(0)], NULL)
);
```

`ANY TYPE` 仅在 SQL UDF 中可用，JavaScript UDF 必须显式声明类型。BigQuery 不支持 `CREATE OPERATOR`，命名参数仅在少数内置函数 (如 `ML.PREDICT`) 中可用。

### Spark SQL & Databricks：UDF 重载之惑

Spark SQL 3.x 的核心问题：

* `CREATE FUNCTION foo AS 'com.example.MyUdf'` 注册的 Hive 风格 UDF **不**支持名称重载；
* Scala/Java API 中的 `udf()` 是函数对象，可以为不同签名注册不同名字；
* Spark 3.5 引入 SQL UDF (`CREATE FUNCTION foo(x INT) RETURNS INT RETURN x+1`)，仍不支持重载，但加入了默认参数和命名参数能力；
* Databricks Runtime 13+ 在 SQL UDF 上扩展了 `DEFAULT` 参数支持。

Spark 不支持 `CREATE OPERATOR`，这与其面向数据科学家的"宽表 + 管道"哲学一致。

## 函数解析算法对比

不同引擎的"找到正确的同名函数"过程差异巨大：

| 维度 | PostgreSQL | Oracle (PACKAGE) | DB2 | Snowflake |
|------|-----------|------------------|------|-----------|
| 精确匹配优先 | 是 | 是 | 是 | 是 |
| 隐式转换 | 是 (`pg_cast`) | 是 (Oracle 转换矩阵) | 是 (promotion 表) | 是 |
| 偏好类型 (preferred) | 是 | -- | -- | 部分 |
| 可变参数 (VARIADIC) | 是 | 否 (PL/SQL 用 collection) | 是 | 是 |
| 命名参数解析 | 是 | 是 | 是 | 是 (2023+) |
| 失败时的歧义提示 | 详细 | 中等 | 中等 | 中等 |

## 隐藏陷阱

1. **PostgreSQL 函数 vs 操作符的语义差异**：操作符的 `STRICT` 默认行为与 NULL 输入处理与函数不同，写 `CREATE OPERATOR` 时必须把 `FUNCTION` 设置成 `STRICT` 否则 `NULL OP x` 可能返回非预期值。
2. **Oracle PACKAGE 内重载的 SIGNATURE 兼容性**：PL/SQL 仅按"形参类型族"区分，`NUMBER(10,2)` 与 `NUMBER` 视为同种，过载时会报 `PLS-00307: too many declarations of ...`。
3. **PostgreSQL 多态函数返回类型必须可推导**：写一个 `RETURNS anyelement` 但参数中只有 `text` 是非法的——必须有一个 polymorphism 参数才能"种"返回类型。
4. **CREATE OPERATOR 的 `COMMUTATOR` 双向链接**：第一次定义时只需要前置声明，等两个操作符都创建后，PG 会自动回填两端的指针；漏掉会让优化器不能利用反向操作符。
5. **DB2 SOURCED FUNCTION 不能跨基类型**：`+` 必须 SOURCE 到完全匹配 base type 的底层算子，否则报 `SQLCODE -491`。
6. **Snowflake 重载与 SECURE UDF**：SECURE UDF 重载时所有版本必须同为 SECURE，混用会破坏权限模型。
7. **MySQL 的"伪重载"**：MySQL 没有真正的函数重载，但其 UDF 接口可以在 C 层根据 `argc` 分发——这是社区写 mysql-udf-* 库时的常见技巧，但对纯 SQL 层不可见。
8. **CockroachDB 与 YugabyteDB 的 PG 兼容差异**：YugabyteDB 因直接复用 PG 解析器，重载行为接近 1:1；CockroachDB 重写了 SQL 解析与 catalog，重载支持仅 22.2+ 才稳定，且 `OPERATOR CLASS` 至今不支持。
9. **ClickHouse 的 `combinator` 不可与 UDF 组合**：`-If` 等聚合修饰符仅作用于内置 aggregate function，不能用在 `CREATE FUNCTION` 定义的 UDF 上。

## 应用场景

### 1. 自定义类型的算术 (PostgreSQL + 复数)

```sql
CREATE TYPE complex AS (re double precision, im double precision);
CREATE FUNCTION complex_add(complex, complex) RETURNS complex AS $$
  SELECT ROW($1.re + $2.re, $1.im + $2.im)::complex;
$$ LANGUAGE sql IMMUTABLE STRICT;

CREATE OPERATOR + (
  LEFTARG = complex, RIGHTARG = complex,
  FUNCTION = complex_add, COMMUTATOR = +
);

SELECT (1,2)::complex + (3,4)::complex;  -- (4, 6)
```

### 2. 向量距离操作符 (pgvector)

```sql
CREATE EXTENSION vector;
SELECT id FROM items
ORDER BY embedding <-> '[0.1, 0.2, ...]'::vector
LIMIT 10;

CREATE INDEX ON items USING ivfflat (embedding vector_l2_ops) WITH (lists = 100);
```

### 3. 通用 array_first / array_last (多态)

```sql
CREATE FUNCTION array_last(anyarray) RETURNS anyelement AS $$
  SELECT $1[array_upper($1, 1)];
$$ LANGUAGE sql IMMUTABLE;
```

### 4. 调用方友好的命名参数 + 默认值

```sql
CREATE FUNCTION send_email(
  recipient text,
  subject   text,
  body      text,
  cc        text[] DEFAULT '{}',
  bcc       text[] DEFAULT '{}',
  priority  int    DEFAULT 5
) RETURNS bigint AS $$ ... $$ LANGUAGE plpgsql;

SELECT send_email(
  recipient => 'x@y.com',
  subject   => 'hello',
  body      => 'world',
  priority  => 1
);
```

### 5. Oracle 对象比较

```sql
CREATE TYPE money_t AS OBJECT (
  amount NUMBER, ccy VARCHAR2(3),
  MAP MEMBER FUNCTION normalized RETURN NUMBER
);
/
CREATE TYPE BODY money_t AS
  MAP MEMBER FUNCTION normalized RETURN NUMBER IS BEGIN
    RETURN amount * fx_rate(ccy);
  END;
END;
/
SELECT * FROM accounts ORDER BY balance;  -- 自动调用 normalized
```

### 6. DuckDB 宏组合

```sql
CREATE MACRO percentile(col, p := 0.5)
  AS quantile_cont(col, p);

SELECT percentile(salary)            FROM emp;  -- 中位数
SELECT percentile(salary, p := 0.95) FROM emp;  -- 95 分位
```

## 关键发现

### 1. 函数重载已成主流，操作符重载仍是 PG 专利

* 45 个引擎中约 24 个支持函数名重载（53%）；
* 仅 8 个支持 `CREATE OPERATOR`，其中 6 个直接继承 PostgreSQL；
* Oracle、DB2、Informix 是非 PG 阵营中坚持完整可扩展性体系的代表。

### 2. 云数据仓库的"反扩展"倾向

Snowflake、BigQuery、Redshift、Databricks 都不支持用户定义操作符。原因有三：

* 多租户隔离要求严格的资源边界；
* 操作符与查询优化器深度耦合，扩展会破坏代价模型；
* 厂商希望通过内置函数族而非用户扩展来推动生态。

但函数重载在 2022-2023 集中补齐，说明云仓认为这是"基本舒适度"功能。

### 3. PostgreSQL 多态系统是泛型函数的事实标准

`anyelement` 系列实现了简洁的"参数化多态"，比 SQL 标准更早、更彻底。`anycompatible` (13+) 进一步引入了"统一类型推导"，处理 `coalesce(int, bigint)` 这类多源参数。其他引擎要么用动态类型 (`VARIANT`/`ANY`) 模拟，要么放弃。

### 4. 默认参数 ≠ 命名参数

很多开发者混淆这两个特性：

* 默认参数解决的是"省略尾部参数"问题；
* 命名参数解决的是"我只想指定第 5 个参数"问题；
* 二者结合才能写出 Pythonic 风格的 API。
* PostgreSQL、Oracle、DB2、Snowflake (2023+)、Spark 3.5+ 是同时拥有两者的"完整方案"代表。

### 5. 操作符类是被低估的索引扩展利器

PostgreSQL 之所以能孵化 PostGIS、pgvector、pg_trgm、ZomboDB 这些"现象级"扩展，根本原因是 OPERATOR CLASS/FAMILY 让用户类型与 B-tree、GiST、GIN 等索引方法平等对接。任何想要构建可扩展数据库的引擎，都应认真研究这套接口的设计。Oracle 通过 ODCI 实现了类似目标，但门槛更高、API 更原始。

### 6. CockroachDB / YugabyteDB / Greenplum 的 PG 兼容深度差异

* **YugabyteDB** 直接复用 PG 解析器，函数重载、CREATE OPERATOR、OPERATOR CLASS 全继承；
* **Greenplum** 在 PG 8.x/9.x 基础上分叉，多态、opclass 大体兼容；
* **CockroachDB** 独立实现，重载支持有限，操作符不可扩展。

这种差异提示：**"PostgreSQL 兼容"在重载与扩展层面有质的不同**，迁移评估时不可只看 SQL 语法层。

### 7. ANSI SQL 标准与现实严重脱节

SQL:1999 已经定义了用户定义例程和重载，但二十多年后许多主流引擎 (MySQL、SQLite、ClickHouse、StarRocks、Doris、CrateDB、Firebolt) 仍然没有实现。这是 SQL 标准在 OLAP 和云原生领域影响力衰退的缩影。

### 8. 命名参数正在悄悄成为新基线

Spark 3.5 和 Snowflake 2023 几乎同时为 UDF 加入命名参数，背后是数据工程师对"可读 SQL"的强烈需求。可以预见，未来 2-3 年内大多数活跃维护的 SQL 引擎都会跟进这一特性。

### 9. 操作符重载的"无声革命"：向量数据库

pgvector 通过自定义 `<->`、`<#>`、`<=>` 三个操作符 + 三个 opclass，把一个传统 RDBMS 变成了向量检索引擎。这是 PostgreSQL 可扩展性近年来最重要的成功案例，也证明了"看似古老的"`CREATE OPERATOR` 在 AI 时代焕发了第二春。任何认为操作符重载是"小众炫技"的看法都应被重新审视。

### 10. 写 SQL UDF 时的可移植性建议

* 不要依赖函数重载——大多数引擎不支持；
* 默认参数和命名参数尽可能使用，但要为不支持的引擎准备包装层；
* 自定义操作符仅在 PostgreSQL/Oracle/DB2 生态内可移植；
* 如果你的扩展希望"跨引擎"，最稳妥的路径是用前缀命名 (`myext_add`, `myext_distance`) 和位置参数，而非操作符与命名参数。

---

> 本文写作时间：2026-04-13。各引擎的具体版本号会随时间变化，建议在迁移评估前以官方文档为准。
