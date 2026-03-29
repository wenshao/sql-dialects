# 数组与复合类型

ARRAY、MAP、STRUCT 及集合类型——从关系模型的"第一范式"到嵌套类型的全面拥抱。

## 支持矩阵总览

| 引擎 | ARRAY | MAP | STRUCT/ROW | VARIANT/ANY | 嵌套类型 | 版本 |
|------|-------|-----|-----------|-------------|---------|------|
| PostgreSQL | ✅ 原生 | ❌ (hstore 扩展) | ✅ ROW / 复合类型 | ❌ | ✅ | 8.0+ |
| MySQL | ❌ | ❌ | ❌ | ❌ | ❌ | — |
| MariaDB | ❌ | ❌ | ❌ | ❌ | ❌ | — |
| SQL Server | ❌ | ❌ | ❌ | sql_variant | ❌ | — |
| Oracle | ✅ VARRAY / TABLE | ❌ | ✅ OBJECT TYPE | ❌ | ✅ | 8i+ |
| SQLite | ❌ | ❌ | ❌ | 动态类型 | ❌ | — |
| BigQuery | ✅ ARRAY | ❌ | ✅ STRUCT | ❌ | ✅ | GA |
| Snowflake | ✅ ARRAY | ✅ OBJECT | ✅ OBJECT | ✅ VARIANT | ✅ | GA |
| Redshift | ✅ SUPER | ✅ SUPER | ✅ SUPER | ✅ SUPER | ✅ | 2021+ |
| DuckDB | ✅ LIST | ✅ MAP | ✅ STRUCT | ✅ UNION | ✅ | GA |
| ClickHouse | ✅ Array | ✅ Map | ✅ Tuple / Nested | ❌ | ✅ | GA |
| Trino | ✅ ARRAY | ✅ MAP | ✅ ROW | ❌ | ✅ | GA |
| Spark SQL | ✅ ARRAY | ✅ MAP | ✅ STRUCT | ❌ | ✅ | 1.0+ |
| Hive | ✅ ARRAY | ✅ MAP | ✅ STRUCT | ❌ | ✅ | 0.14+ |
| Databricks | ✅ ARRAY | ✅ MAP | ✅ STRUCT | ❌ | ✅ | GA |
| Flink SQL | ✅ ARRAY | ✅ MAP | ✅ ROW | ❌ | ✅ | GA |
| Presto | ✅ ARRAY | ✅ MAP | ✅ ROW | ❌ | ✅ | GA |
| Doris | ✅ ARRAY | ✅ MAP | ✅ STRUCT | ✅ VARIANT | ✅ | 2.0+ |
| StarRocks | ✅ ARRAY | ✅ MAP | ✅ STRUCT | ❌ | ✅ | 2.5+ |
| CockroachDB | ✅ ARRAY | ❌ | ❌ | ❌ | ❌ | GA |
| TiDB | ❌ | ❌ | ❌ | ❌ | ❌ | — |
| OceanBase | ❌ (MySQL 模式) | ❌ | ❌ | ❌ | ❌ | — |
| YugabyteDB | ✅ ARRAY | ❌ (hstore) | ✅ ROW | ❌ | ✅ | GA |
| Greenplum | ✅ ARRAY | ❌ (hstore) | ✅ ROW | ❌ | ✅ | GA |
| SingleStore (MemSQL) | ❌ | ❌ | ❌ | ✅ JSON | ❌ | — |
| Vertica | ✅ ARRAY | ✅ MAP | ✅ ROW | ✅ FLEX | ✅ | 9.0+ |
| Teradata | ✅ ARRAY | ❌ | ✅ PERIOD / UDT | ❌ | 有限 | 16.0+ |
| DB2 | ✅ ARRAY | ❌ | ✅ ROW | ❌ | 有限 | 9.5+ |
| Informix | ✅ LIST / SET | ✅ (ROW) | ✅ ROW | ❌ | ✅ | GA |
| MonetDB | ❌ | ❌ | ❌ | ❌ | ❌ | — |
| QuestDB | ❌ | ❌ | ❌ | ❌ | ❌ | — |
| TimescaleDB | ✅ ARRAY | ❌ (hstore) | ✅ ROW | ❌ | ✅ | GA |
| CrateDB | ✅ ARRAY | ✅ OBJECT | ✅ OBJECT | ❌ | ✅ | GA |
| Pinot | ✅ MV 列 | ❌ | ❌ | ✅ JSON | ❌ | GA |
| Druid | ✅ MVD | ❌ | ❌ | ❌ | ❌ | GA |
| Elasticsearch SQL | ✅ 隐式 | ✅ nested | ✅ object | ❌ | ✅ | GA |
| MongoDB (MQL) | ✅ Array | ✅ Document | ✅ Document | ✅ 动态 | ✅ | GA |
| Cassandra (CQL) | ✅ LIST / SET | ✅ MAP | ✅ UDT | ❌ | 有限 | 2.1+ |
| ScyllaDB | ✅ LIST / SET | ✅ MAP | ✅ UDT | ❌ | 有限 | GA |
| InfluxDB (Flux) | ❌ | ❌ | ❌ | ❌ | ❌ | — |
| DynamoDB (PartiQL) | ✅ List | ✅ Map | ❌ | ❌ | ✅ | GA |
| Spanner | ✅ ARRAY | ❌ | ✅ STRUCT | ❌ | ✅ | GA |
| Athena | ✅ ARRAY | ✅ MAP | ✅ STRUCT | ❌ | ✅ | GA |
| Firebolt | ✅ ARRAY | ❌ | ❌ | ❌ | ❌ | GA |
| Materialize | ✅ LIST | ✅ MAP | ✅ ROW / record | ❌ | ✅ | GA |
| RisingWave | ✅ ARRAY | ❌ | ✅ STRUCT | ❌ | ✅ | GA |

## 设计动机与历史演进

### 为什么关系模型需要数组类型

关系模型的第一范式（1NF）要求每个属性值都是原子的。但现实数据中，一对多关系的建模往往需要额外的关联表：

```
传统关系模型（严格 1NF）:
  users: {id, name}
  user_tags: {user_id, tag}     ← 额外的关联表

  SELECT u.name, GROUP_CONCAT(t.tag)
  FROM users u JOIN user_tags t ON u.id = t.user_id
  GROUP BY u.name;

嵌套类型模型（放松 1NF）:
  users: {id, name, tags ARRAY<STRING>}

  SELECT name, tags FROM users;
```

嵌套类型在以下场景中有明确优势：

```
1. 减少 JOIN: 嵌套数据消除了多表关联的开销
2. 数据局部性: 相关数据物理上存储在一起
3. Schema 表达力: 直接表达现实世界的层次结构
4. 半结构化数据: JSON / Avro / Protobuf 天然是嵌套的
5. 分析查询: 列式存储引擎原生支持嵌套列（Dremel 模型）
```

### 演进时间线

```
1996  PostgreSQL 原生数组类型（最早的 SQL 数组实现之一）
1997  Oracle 8 引入 VARRAY 和嵌套表（TABLE 类型）
1999  SQL:1999 标准引入 ARRAY 和 ROW 类型
2003  SQL:2003 标准增加 MULTISET 类型
2009  Hive 引入 ARRAY / MAP / STRUCT（面向大数据）
2011  BigQuery 采用 ARRAY + STRUCT（Dremel 模型）
2012  Cassandra 引入 LIST / SET / MAP 集合类型
2014  Trino (Presto) 支持 ARRAY / MAP / ROW
2018  ClickHouse Map 类型 GA
2019  Snowflake VARIANT / ARRAY / OBJECT 成熟
2020  DuckDB LIST / STRUCT / MAP / UNION（最完整的类型系统之一）
2022  Doris 2.0 引入 ARRAY / MAP / STRUCT / VARIANT
2023  StarRocks 支持 ARRAY / MAP / STRUCT
```

## ARRAY 类型详解

### 类型声明语法

| 引擎 | 声明语法 | 元素类型约束 |
|------|---------|-------------|
| PostgreSQL | `INT[]`, `TEXT[][]`, `INTEGER ARRAY` | 同类型，支持多维 |
| BigQuery | `ARRAY<INT64>` | 同类型，不允许 `ARRAY<ARRAY>` |
| Snowflake | `ARRAY` | 无类型约束（任意 VARIANT） |
| DuckDB | `INTEGER[]`, `LIST(INTEGER)` | 同类型 |
| ClickHouse | `Array(UInt32)` | 同类型 |
| Trino | `ARRAY(INTEGER)` | 同类型 |
| Spark SQL | `ARRAY<INT>` | 同类型 |
| Hive | `ARRAY<STRING>` | 同类型 |
| Oracle | `VARRAY(100) OF NUMBER` | 同类型，固定最大长度 |
| DB2 | `INTEGER ARRAY[100]` | 同类型，固定最大长度 |
| Cassandra | `LIST<TEXT>`, `SET<INT>` | 同类型 |
| CockroachDB | `INT[]` | 同类型 |
| Spanner | `ARRAY<INT64>` | 同类型 |
| Vertica | `ARRAY[VARCHAR(50)]` | 同类型 |
| Flink SQL | `ARRAY<INT>` | 同类型 |

### 字面量构造语法

数组字面量的语法差异是跨引擎移植时最直接的痛点之一。

```sql
-- PostgreSQL: ARRAY 关键字 + 方括号
SELECT ARRAY[1, 2, 3];                    -- {1,2,3}
SELECT ARRAY['a', 'b', 'c'];             -- {a,b,c}
SELECT '{1,2,3}'::int[];                  -- 字符串字面量转换
SELECT ARRAY[[1,2],[3,4]];               -- 二维数组

-- BigQuery: 方括号（简洁）
SELECT [1, 2, 3];                         -- ARRAY<INT64>
SELECT ARRAY<STRING>['a', 'b', 'c'];     -- 带类型声明

-- Snowflake: ARRAY_CONSTRUCT 函数
SELECT ARRAY_CONSTRUCT(1, 2, 3);          -- [1, 2, 3]
SELECT [1, 2, 3];                         -- 简写语法（较新版本）

-- DuckDB: 方括号或 list_value 函数
SELECT [1, 2, 3];                         -- [1, 2, 3]
SELECT list_value(1, 2, 3);              -- 等价

-- ClickHouse: 方括号
SELECT [1, 2, 3];                         -- Array(UInt8)
SELECT array(1, 2, 3);                   -- 等价

-- Trino: ARRAY 关键字 + 方括号
SELECT ARRAY[1, 2, 3];

-- Spark SQL / Hive: array() 函数
SELECT array(1, 2, 3);

-- Databricks: array() 函数或方括号
SELECT array(1, 2, 3);

-- Flink SQL: ARRAY 关键字 + 方括号
SELECT ARRAY[1, 2, 3];

-- Oracle: 需要先定义类型
CREATE TYPE int_array AS VARRAY(100) OF NUMBER;
SELECT int_array(1, 2, 3) FROM DUAL;

-- CockroachDB: 同 PostgreSQL
SELECT ARRAY[1, 2, 3];

-- Spanner: 方括号或 ARRAY 关键字
SELECT [1, 2, 3];
SELECT ARRAY<INT64>[1, 2, 3];

-- Cassandra: 方括号（LIST）或大括号（SET）
INSERT INTO t (id, tags) VALUES (1, ['a', 'b', 'c']);
INSERT INTO t (id, labels) VALUES (1, {'a', 'b', 'c'});

-- Redshift: ARRAY() 函数或 JSON 解析
SELECT ARRAY(1, 2, 3);
SELECT JSON_PARSE('[1,2,3]');

-- Vertica: ARRAY 关键字 + 方括号
SELECT ARRAY[1, 2, 3];

-- StarRocks / Doris: 方括号
SELECT [1, 2, 3];
```

### 字面量语法对比矩阵

| 语法形式 | 支持引擎 |
|---------|---------|
| `ARRAY[1,2,3]` | PostgreSQL, Trino, Flink SQL, CockroachDB, YugabyteDB, Greenplum, Vertica, Materialize |
| `[1,2,3]` | BigQuery, DuckDB, ClickHouse, Snowflake (新版), Spanner, StarRocks, Doris |
| `array(1,2,3)` | Spark SQL, Hive, Databricks, ClickHouse |
| `ARRAY_CONSTRUCT(1,2,3)` | Snowflake |
| `ARRAY(1,2,3)` | Redshift |
| 需要预定义类型 | Oracle, DB2, Teradata |

### 元素访问与索引

数组索引的起始位置（0-based vs 1-based）是一个需要特别注意的差异。

| 引擎 | 语法 | 索引起始 | 负索引 | 越界行为 |
|------|------|---------|--------|---------|
| PostgreSQL | `arr[1]` | **1** | ❌ 返回 NULL | 返回 NULL |
| BigQuery | `arr[OFFSET(0)]` / `arr[ORDINAL(1)]` | 0 或 1 | ❌ | OFFSET 报错，SAFE_OFFSET 返回 NULL |
| Snowflake | `arr[0]` | **0** | ❌ | 返回 NULL |
| DuckDB | `arr[1]` | **1** | ✅ `arr[-1]` | 返回 NULL |
| ClickHouse | `arr[1]` | **1** | ✅ `arr[-1]` | 返回默认值 |
| Trino | `arr[1]` | **1** | ❌ | 报错 |
| Spark SQL | `arr[0]` | **0** | ❌ | 返回 NULL |
| Hive | `arr[0]` | **0** | ❌ | 返回 NULL |
| Redshift | `arr[0]` | **0** | ❌ | 返回 NULL |
| CockroachDB | `arr[1]` | **1** | ❌ | 返回 NULL |
| Spanner | `arr[OFFSET(0)]` / `arr[ORDINAL(1)]` | 0 或 1 | ❌ | 报错 |
| Cassandra | `list[0]` | **0** | ❌ | — |
| Doris | `arr[1]` | **1** (0 返回 NULL) | ❌ | 返回 NULL |
| StarRocks | `arr[1]` | **1** | ❌ | 返回 NULL |
| Vertica | `arr[0]` | **0** | ❌ | 返回 NULL |

```sql
-- PostgreSQL: 1-based
SELECT (ARRAY['a','b','c'])[1];     -- 'a'
SELECT (ARRAY['a','b','c'])[2:3];   -- {'b','c'} (切片)

-- BigQuery: 显式指定偏移方式（最安全的设计）
SELECT (['a','b','c'])[OFFSET(0)];      -- 'a' (0-based)
SELECT (['a','b','c'])[ORDINAL(1)];     -- 'a' (1-based)
SELECT (['a','b','c'])[SAFE_OFFSET(99)]; -- NULL (安全版本)

-- Snowflake: 0-based
SELECT ARRAY_CONSTRUCT('a','b','c')[0];  -- 'a'

-- DuckDB: 1-based，支持负索引
SELECT (['a','b','c'])[1];    -- 'a'
SELECT (['a','b','c'])[-1];   -- 'c' (最后一个)
SELECT (['a','b','c'])[2:3];  -- ['b','c'] (切片)

-- ClickHouse: 1-based，支持负索引
SELECT ['a','b','c'][1];      -- 'a'
SELECT ['a','b','c'][-1];     -- 'c'

-- Spark SQL: 0-based
SELECT array('a','b','c')[0]; -- 'a'

-- Trino: 1-based，越界报错
SELECT ARRAY['a','b','c'][1]; -- 'a'
SELECT ARRAY['a','b','c'][99]; -- 报错！（不是 NULL）
```

> **引擎开发者注意**: BigQuery 的 OFFSET/ORDINAL 设计是最明确的方案，消除了 0-based 与 1-based 的歧义。Trino 的越界报错虽然更安全但可能影响查询的健壮性。建议引擎至少提供 SAFE_ 系列函数作为替代。

### 数组切片

```sql
-- PostgreSQL: 方括号切片（1-based，包含两端）
SELECT (ARRAY[10,20,30,40,50])[2:4];   -- {20,30,40}

-- DuckDB: 方括号切片（1-based）
SELECT ([10,20,30,40,50])[2:4];        -- [20, 30, 40]

-- Snowflake: ARRAY_SLICE 函数（0-based，不包含右端）
SELECT ARRAY_SLICE(ARRAY_CONSTRUCT(10,20,30,40,50), 1, 3); -- [20, 30]

-- ClickHouse: arraySlice 函数（1-based，第三参数是长度）
SELECT arraySlice([10,20,30,40,50], 2, 3); -- [20, 30, 40]

-- Spark SQL: slice 函数（1-based，第三参数是长度）
SELECT slice(array(10,20,30,40,50), 2, 3); -- [20, 30, 40]

-- Trino: slice 函数（1-based，第三参数是长度）
SELECT slice(ARRAY[10,20,30,40,50], 2, 3); -- [20, 30, 40]

-- BigQuery: 无原生切片语法，需用子查询
SELECT ARRAY(SELECT x FROM UNNEST([10,20,30,40,50]) x WITH OFFSET o WHERE o BETWEEN 1 AND 3);
```

## MAP / DICT 类型

MAP 类型表示键值对集合，在分析引擎中越来越常见。

### MAP 支持矩阵

| 引擎 | 类型名称 | 键类型约束 | 值类型约束 | 构造语法 |
|------|---------|-----------|-----------|---------|
| DuckDB | MAP | 任意可比较类型 | 任意类型 | `MAP {'a': 1}` |
| ClickHouse | Map(K, V) | String, Integer, Date 等 | 任意类型 | `map('a', 1)` |
| Trino | MAP(K, V) | 任意可比较类型 | 任意类型 | `MAP(ARRAY['a'], ARRAY[1])` |
| Spark SQL | MAP<K, V> | 任意类型 | 任意类型 | `map('a', 1)` |
| Hive | MAP<K, V> | 基本类型 | 任意类型 | `map('a', 1)` |
| Snowflake | OBJECT | STRING | VARIANT | `OBJECT_CONSTRUCT('a', 1)` |
| Cassandra | MAP<K, V> | 基本类型 | 基本类型 | `{'a': 1}` |
| Vertica | MAP | — | — | 有限支持 |
| Flink SQL | MAP<K, V> | 任意可比较类型 | 任意类型 | `MAP['a', 1]` |
| Doris | MAP<K, V> | 基本类型 | 任意类型 | `map('a', 1)` |
| StarRocks | MAP<K, V> | 基本类型 | 任意类型 | `map('a', 1)` |

传统关系型数据库（PostgreSQL、MySQL、SQL Server、Oracle）不原生支持 MAP 类型。PostgreSQL 通过 hstore 扩展和 JSONB 提供类似功能。

### MAP 构造与访问

```sql
-- DuckDB: 花括号语法（最直观）
SELECT MAP {'name': 'alice', 'role': 'admin'};
SELECT MAP {'name': 'alice'}['name'];          -- 'alice'
-- 也支持 map_from_entries
SELECT map_from_entries([('a', 1), ('b', 2)]);

-- ClickHouse: map() 函数
SELECT map('name', 'alice', 'role', 'admin');
SELECT map('name', 'alice')['name'];           -- 'alice'

-- Trino: MAP() 从两个数组构造
SELECT MAP(ARRAY['name', 'role'], ARRAY['alice', 'admin']);
SELECT MAP(ARRAY['name'], ARRAY['alice'])['name']; -- 'alice'

-- Spark SQL / Databricks: map() 函数
SELECT map('name', 'alice', 'role', 'admin');
SELECT map('name', 'alice')['name'];           -- 'alice'
-- str_to_map 用于解析字符串
SELECT str_to_map('name:alice,role:admin', ',', ':');

-- Snowflake: OBJECT_CONSTRUCT
SELECT OBJECT_CONSTRUCT('name', 'alice', 'role', 'admin');
SELECT OBJECT_CONSTRUCT('name', 'alice'):name::STRING; -- 'alice'

-- Flink SQL: MAP 关键字 + 方括号
SELECT MAP['name', 'alice', 'role', 'admin'];

-- Cassandra: 花括号
INSERT INTO t (id, props) VALUES (1, {'name': 'alice', 'role': 'admin'});
SELECT props['name'] FROM t;

-- Redshift: OBJECT() 或 JSON_PARSE
SELECT OBJECT('name', 'alice');
```

## STRUCT / ROW / RECORD 类型

STRUCT（结构体）类型表示一组命名字段的复合值，类似于编程语言中的 struct 或 record。

### STRUCT 支持矩阵

| 引擎 | 类型名称 | 声明方式 | 匿名支持 | 嵌套支持 |
|------|---------|---------|---------|---------|
| PostgreSQL | ROW / 复合类型 | `CREATE TYPE` 或匿名 ROW | ✅ | ✅ |
| BigQuery | STRUCT | 内联声明 | ✅ | ✅ |
| DuckDB | STRUCT | 内联声明 | ✅ | ✅ |
| ClickHouse | Tuple / Nested | 内联声明 | ✅ | ✅ |
| Trino | ROW | 内联声明 | ✅ | ✅ |
| Spark SQL | STRUCT | 内联声明 | ❌ | ✅ |
| Hive | STRUCT | 内联声明 | ❌ | ✅ |
| Snowflake | OBJECT | 动态 | ✅ | ✅ |
| Oracle | OBJECT TYPE | `CREATE TYPE` | ❌ | ✅ |
| Flink SQL | ROW | 内联声明 | ✅ | ✅ |
| Spanner | STRUCT | 内联声明 | ✅ | ✅ |
| Vertica | ROW | 内联声明 | ✅ | ✅ |
| Doris | STRUCT | 内联声明 | ❌ | ✅ |
| StarRocks | STRUCT | 内联声明 | ❌ | ✅ |
| Cassandra | UDT | `CREATE TYPE` | ❌ | 有限 |
| DB2 | ROW | `CREATE TYPE` | ❌ | ✅ |

### STRUCT 构造与字段访问

```sql
-- PostgreSQL: ROW 构造器或命名复合类型
SELECT ROW(1, 'alice', 42.5);                  -- 匿名 ROW
-- 命名类型
CREATE TYPE person AS (name TEXT, age INT);
SELECT ROW('alice', 30)::person;
SELECT (ROW('alice', 30)::person).name;        -- 'alice'

-- BigQuery: STRUCT 关键字
SELECT STRUCT(1 AS id, 'alice' AS name, 30 AS age);
SELECT STRUCT<id INT64, name STRING, age INT64>(1, 'alice', 30);
-- 字段访问用点号
SELECT user.name FROM (SELECT STRUCT('alice' AS name) AS user);

-- DuckDB: 花括号语法（最直观）
SELECT {'id': 1, 'name': 'alice', 'age': 30};
SELECT ROW(1, 'alice', 30);
-- 字段访问
SELECT struct.name FROM (SELECT {'name': 'alice'} AS struct);

-- ClickHouse: tuple() 函数
SELECT tuple(1, 'alice', 30);                  -- Tuple(UInt8, String, UInt8)
-- 命名 Tuple
SELECT tuple(1 AS id, 'alice' AS name);        -- Tuple(id UInt8, name String)
-- 字段访问
SELECT t.1, t.2 FROM (SELECT tuple(1, 'alice') AS t);  -- 按位置
SELECT t.name FROM (SELECT tuple('alice' AS name) AS t); -- 按名称

-- Trino: ROW() 或匿名 ROW
SELECT ROW(1, 'alice', 30);
SELECT CAST(ROW(1, 'alice') AS ROW(id INTEGER, name VARCHAR));
-- 字段访问
SELECT r.name FROM (SELECT CAST(ROW('alice') AS ROW(name VARCHAR)) AS r);

-- Spark SQL: struct() 函数或 named_struct()
SELECT struct(1 AS id, 'alice' AS name);
SELECT named_struct('id', 1, 'name', 'alice');
-- 字段访问
SELECT user.name FROM (SELECT struct('alice' AS name) AS user);

-- Snowflake: OBJECT_CONSTRUCT（类 MAP 的动态结构）
SELECT OBJECT_CONSTRUCT('id', 1, 'name', 'alice');
-- 字段访问（冒号语法）
SELECT obj:name::STRING FROM (SELECT OBJECT_CONSTRUCT('name', 'alice') AS obj);

-- Flink SQL: ROW() 构造
SELECT ROW(1, 'alice', 30);

-- Oracle: 必须先 CREATE TYPE
CREATE TYPE person_t AS OBJECT (name VARCHAR2(100), age NUMBER);
SELECT person_t('alice', 30) FROM DUAL;
SELECT TREAT(VALUE(p) AS person_t).name FROM person_table p;
```

### STRUCT 构造语法对比矩阵

| 语法形式 | 支持引擎 |
|---------|---------|
| `ROW(val, ...)` | PostgreSQL, Trino, Flink SQL, DuckDB, Vertica, DB2 |
| `STRUCT(val AS name, ...)` | BigQuery, Spark SQL |
| `struct(val AS name, ...)` | Spark SQL, Databricks |
| `named_struct('name', val, ...)` | Spark SQL, Hive |
| `{'key': val, ...}` | DuckDB |
| `tuple(val, ...)` | ClickHouse |
| `OBJECT_CONSTRUCT('key', val, ...)` | Snowflake |
| `type_name(val, ...)` | Oracle (需 CREATE TYPE) |

## VARIANT / ANY 动态类型

部分引擎提供"万能类型"，可以存储任意数据：

| 引擎 | 类型名称 | 包含类型 | 存储格式 | 使用场景 |
|------|---------|---------|---------|---------|
| Snowflake | VARIANT | 标量、数组、对象 | 自有二进制 | 半结构化数据统一入口 |
| DuckDB | UNION | 有限个类型的联合 | 内联 tag + value | 类型安全的 variant |
| Redshift | SUPER | 标量、数组、对象 | PartiQL 友好 | 半结构化数据 |
| SQL Server | sql_variant | SQL 基础类型 | 带类型标签 | 存储异构数据 |
| Doris | VARIANT | 任意类型 | 自动列化 | 半结构化查询 |

```sql
-- Snowflake VARIANT: 万能容器
CREATE TABLE flexible_data (id INT, data VARIANT);
INSERT INTO flexible_data SELECT 1, PARSE_JSON('{"name": "alice", "scores": [90, 85]}');
INSERT INTO flexible_data SELECT 2, TO_VARIANT(42);          -- 标量
INSERT INTO flexible_data SELECT 3, TO_VARIANT(ARRAY_CONSTRUCT(1, 2, 3)); -- 数组

-- 类型检测
SELECT TYPEOF(data) FROM flexible_data;  -- OBJECT, INTEGER, ARRAY
SELECT data:name::STRING FROM flexible_data WHERE TYPEOF(data) = 'OBJECT';

-- DuckDB UNION: 类型安全的 variant（更接近代数数据类型）
CREATE TABLE events (
    id INT,
    payload UNION(text_val VARCHAR, num_val INT, list_val INT[])
);
INSERT INTO events VALUES (1, 'hello'::UNION(text_val VARCHAR, num_val INT, list_val INT[]));
-- 类型检测
SELECT union_tag(payload) FROM events;   -- 'text_val'
SELECT payload.text_val FROM events WHERE union_tag(payload) = 'text_val';

-- SQL Server sql_variant: 经典的异构存储
CREATE TABLE settings (
    key_name VARCHAR(100),
    value sql_variant
);
INSERT INTO settings VALUES ('timeout', CAST(30 AS INT));
INSERT INTO settings VALUES ('name', CAST('app1' AS VARCHAR(50)));
SELECT SQL_VARIANT_PROPERTY(value, 'BaseType') FROM settings;

-- Redshift SUPER: PartiQL 查询
CREATE TABLE events (id INT, data SUPER);
INSERT INTO events VALUES (1, JSON_PARSE('{"type": "click", "coords": [10, 20]}'));
SELECT data.type, data.coords[0] FROM events;
```

## 核心数组函数对比

### ARRAY_AGG（聚合为数组）

将多行值聚合为一个数组，是最常用的数组函数。

| 引擎 | 语法 | 排序 | 去重 | NULL 处理 |
|------|------|------|------|----------|
| PostgreSQL | `ARRAY_AGG(x ORDER BY y)` | ✅ | ✅ DISTINCT | 包含 NULL |
| BigQuery | `ARRAY_AGG(x ORDER BY y)` | ✅ | ✅ DISTINCT | 默认忽略 NULL |
| Snowflake | `ARRAY_AGG(x) WITHIN GROUP (ORDER BY y)` | ✅ | ✅ DISTINCT | 包含 NULL |
| DuckDB | `ARRAY_AGG(x ORDER BY y)` / `LIST()` | ✅ | ✅ DISTINCT | 包含 NULL |
| ClickHouse | `groupArray(x)` | ✅ `groupArraySorted` | ❌ 用 groupUniqArray | 忽略 NULL |
| Trino | `ARRAY_AGG(x ORDER BY y)` | ✅ | ❌ | 包含 NULL |
| Spark SQL | `COLLECT_LIST(x)` / `COLLECT_SET(x)` | ❌ (不保证顺序) | SET 去重 | 忽略 NULL |
| Flink SQL | `ARRAY_AGG(x)` | ❌ | ❌ | — |
| Redshift | `ARRAY_AGG(x ORDER BY y)` | ✅ | ❌ | — |

```sql
-- PostgreSQL: 最完整的 ARRAY_AGG
SELECT department,
       ARRAY_AGG(name ORDER BY salary DESC) AS top_earners,
       ARRAY_AGG(DISTINCT department) AS unique_depts
FROM employees GROUP BY department;

-- BigQuery
SELECT department, ARRAY_AGG(name ORDER BY salary DESC) AS top_earners
FROM employees GROUP BY department;

-- Snowflake: WITHIN GROUP 语法
SELECT department,
       ARRAY_AGG(name) WITHIN GROUP (ORDER BY salary DESC) AS top_earners
FROM employees GROUP BY department;

-- ClickHouse: 独特的函数名
SELECT department,
       groupArray(name) AS all_names,
       groupUniqArray(name) AS unique_names,
       groupArraySorted(5)(name) AS top5_names  -- 带参数的聚合函数
FROM employees GROUP BY department;

-- Spark SQL: COLLECT_LIST / COLLECT_SET
SELECT department,
       COLLECT_LIST(name) AS all_names,       -- 保留重复
       COLLECT_SET(name) AS unique_names      -- 去重
FROM employees GROUP BY department;
```

### ARRAY_LENGTH / CARDINALITY

| 引擎 | 函数 | 备注 |
|------|------|------|
| PostgreSQL | `ARRAY_LENGTH(arr, dim)` / `CARDINALITY(arr)` | dim 指定维度 |
| BigQuery | `ARRAY_LENGTH(arr)` | — |
| Snowflake | `ARRAY_SIZE(arr)` | — |
| DuckDB | `LEN(arr)` / `ARRAY_LENGTH(arr)` | — |
| ClickHouse | `length(arr)` | 与字符串共用 |
| Trino | `CARDINALITY(arr)` | SQL 标准 |
| Spark SQL | `SIZE(arr)` / `CARDINALITY(arr)` | — |
| Flink SQL | `CARDINALITY(arr)` | SQL 标准 |
| Redshift | `GET_ARRAY_LENGTH(arr)` | — |
| CockroachDB | `ARRAY_LENGTH(arr, dim)` | 同 PostgreSQL |
| Doris | `ARRAY_SIZE(arr)` / `SIZE(arr)` | — |
| StarRocks | `ARRAY_LENGTH(arr)` | — |

### ARRAY_CONTAINS / 元素查找

| 引擎 | 函数 | 反向查找 |
|------|------|---------|
| PostgreSQL | `val = ANY(arr)` | `arr @> ARRAY[val]` |
| BigQuery | `val IN UNNEST(arr)` | — |
| Snowflake | `ARRAY_CONTAINS(val, arr)` | — |
| DuckDB | `ARRAY_CONTAINS(arr, val)` / `LIST_HAS()` | `ARRAY_POSITION` |
| ClickHouse | `has(arr, val)` | `indexOf(arr, val)` |
| Trino | `CONTAINS(arr, val)` | — |
| Spark SQL | `ARRAY_CONTAINS(arr, val)` | `ARRAY_POSITION` |
| Flink SQL | `val IN (SELECT * FROM UNNEST(arr))` | — |
| Doris | `ARRAY_CONTAINS(arr, val)` | `ARRAY_POSITION` |
| StarRocks | `ARRAY_CONTAINS(arr, val)` | `ARRAY_POSITION` |

```sql
-- PostgreSQL: ANY/ALL 运算符（最灵活）
SELECT * FROM users WHERE 'admin' = ANY(roles);     -- 数组中包含 'admin'
SELECT * FROM users WHERE 100 < ALL(scores);        -- 所有分数大于 100
SELECT * FROM users WHERE roles && ARRAY['admin', 'root']; -- 数组重叠

-- BigQuery: IN UNNEST
SELECT * FROM users WHERE 'admin' IN UNNEST(roles);

-- Snowflake: ARRAY_CONTAINS（注意参数顺序）
SELECT * FROM users WHERE ARRAY_CONTAINS('admin'::VARIANT, roles);

-- DuckDB: 多种方式
SELECT * FROM users WHERE list_has(roles, 'admin');
SELECT * FROM users WHERE 'admin' = ANY(roles);     -- 也支持 ANY

-- ClickHouse: has / hasAll / hasAny
SELECT * FROM users WHERE has(roles, 'admin');
SELECT * FROM users WHERE hasAll(roles, ['admin', 'root']);   -- 全部包含
SELECT * FROM users WHERE hasAny(roles, ['admin', 'root']);   -- 任一包含

-- Spark SQL
SELECT * FROM users WHERE array_contains(roles, 'admin');

-- Trino
SELECT * FROM users WHERE contains(roles, 'admin');
```

### UNNEST / EXPLODE / FLATTEN

将数组展开为多行是数组操作中最关键的能力。各引擎语法差异极大。

| 引擎 | 语法 | 保留空数组 | 带序号 |
|------|------|-----------|--------|
| PostgreSQL | `UNNEST(arr)` | LEFT JOIN | `WITH ORDINALITY` |
| BigQuery | `UNNEST(arr)` | LEFT JOIN | `WITH OFFSET` (0-based) |
| Snowflake | `LATERAL FLATTEN(input => arr)` | `OUTER => TRUE` | `f.index` (0-based) |
| DuckDB | `UNNEST(arr)` | LEFT JOIN | `generate_subscripts` |
| ClickHouse | `arrayJoin(arr)` | ❌ | `arrayEnumerate` |
| Trino | `UNNEST(arr)` | LEFT JOIN | `WITH ORDINALITY` |
| Spark SQL | `EXPLODE(arr)` / `POSEXPLODE(arr)` | `EXPLODE_OUTER` | `POSEXPLODE` (0-based) |
| Hive | `LATERAL VIEW EXPLODE(arr)` | `OUTER` | `POSEXPLODE` |
| Flink SQL | `CROSS JOIN UNNEST(arr)` | LEFT JOIN | `WITH ORDINALITY` |
| Redshift | PartiQL 语法 | — | — |
| Doris | `EXPLODE(arr)` | `EXPLODE_OUTER` | `POSEXPLODE` |
| StarRocks | `UNNEST(arr)` | — | — |

```sql
-- PostgreSQL
SELECT u.id, t.val, t.ord
FROM users u
CROSS JOIN UNNEST(u.tags) WITH ORDINALITY AS t(val, ord);

-- BigQuery
SELECT u.id, tag, off
FROM users u, UNNEST(u.tags) AS tag WITH OFFSET off;

-- Snowflake: LATERAL FLATTEN（独特语法）
SELECT u.id, f.value::STRING AS tag, f.index AS pos
FROM users u,
LATERAL FLATTEN(input => u.tags) f;
-- FLATTEN 返回丰富的元数据: seq, key, path, index, value, this

-- DuckDB
SELECT u.id, UNNEST(u.tags) AS tag FROM users u;

-- ClickHouse: arrayJoin 作为特殊函数
SELECT id, arrayJoin(tags) AS tag FROM users;
-- 带序号
SELECT id, tag, num
FROM users
ARRAY JOIN tags AS tag, arrayEnumerate(tags) AS num;

-- Spark SQL / Hive
SELECT u.id, t.tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;
-- 带位置
SELECT u.id, t.pos, t.tag
FROM users u
LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;
-- 保留空数组行
SELECT u.id, t.tag
FROM users u
LATERAL VIEW OUTER EXPLODE(u.tags) t AS tag;

-- Flink SQL
SELECT u.id, tag
FROM users u
CROSS JOIN UNNEST(u.tags) AS T(tag);
```

## WHERE 中的数组操作: ANY / ALL / SOME

SQL 标准定义了 ANY、ALL、SOME 用于数组/子查询的比较：

```sql
-- SQL 标准语法（PostgreSQL 实现最完整）
SELECT * FROM products WHERE price > ANY(ARRAY[10, 20, 30]);  -- 价格大于任一值
SELECT * FROM products WHERE price > ALL(ARRAY[10, 20, 30]);  -- 价格大于所有值
SELECT * FROM products WHERE price > SOME(ARRAY[10, 20, 30]); -- SOME = ANY 的别名

-- PostgreSQL: 数组运算符
SELECT * FROM t WHERE arr @> ARRAY[1, 2];     -- arr 包含 {1, 2}
SELECT * FROM t WHERE arr <@ ARRAY[1, 2, 3];  -- arr 被 {1,2,3} 包含
SELECT * FROM t WHERE arr && ARRAY[1, 2];     -- arr 与 {1,2} 有交集
```

各引擎 ANY/ALL 支持情况：

| 引擎 | ANY(array) | ALL(array) | ANY(subquery) | ALL(subquery) |
|------|-----------|-----------|--------------|--------------|
| PostgreSQL | ✅ | ✅ | ✅ | ✅ |
| BigQuery | ❌ (用 IN UNNEST) | ❌ | ✅ | ✅ |
| Snowflake | ❌ | ❌ | ✅ | ✅ |
| DuckDB | ✅ | ✅ | ✅ | ✅ |
| ClickHouse | ❌ (用 has) | ❌ (用 arrayAll) | ✅ | ✅ |
| Trino | ✅ | ✅ | ✅ | ✅ |
| Spark SQL | ❌ | ❌ | ✅ | ✅ |
| MySQL | ❌ (无数组) | ❌ | ✅ | ✅ |
| SQL Server | ❌ (无数组) | ❌ | ✅ | ✅ |

## 嵌套类型: ARRAY<STRUCT<...>>

嵌套类型是现代分析引擎的核心能力，用于表达层次化数据。

```sql
-- BigQuery: 最典型的嵌套类型使用
CREATE TABLE orders (
    order_id INT64,
    customer STRUCT<name STRING, email STRING>,
    items ARRAY<STRUCT<
        product STRING,
        quantity INT64,
        price FLOAT64
    >>,
    tags ARRAY<STRING>
);

-- 查询嵌套字段
SELECT order_id, customer.name,
       item.product, item.quantity, item.price
FROM orders, UNNEST(items) AS item
WHERE item.price > 100;

-- DuckDB: 同样支持深度嵌套
CREATE TABLE orders (
    order_id INT,
    customer STRUCT(name VARCHAR, email VARCHAR),
    items STRUCT(product VARCHAR, quantity INT, price DOUBLE)[]
);

SELECT order_id, customer.name,
       UNNEST(items) AS item
FROM orders;

-- ClickHouse: Nested 类型（自动展开为并行数组）
CREATE TABLE orders (
    order_id UInt64,
    items Nested(
        product String,
        quantity UInt32,
        price Float64
    )
) ENGINE = MergeTree() ORDER BY order_id;
-- 实际存储为: items.product Array(String), items.quantity Array(UInt32), ...

-- Trino: ROW + ARRAY
CREATE TABLE orders (
    order_id INTEGER,
    items ARRAY(ROW(product VARCHAR, quantity INTEGER, price DOUBLE))
);

-- Spark SQL: STRUCT 嵌套 ARRAY
CREATE TABLE orders (
    order_id INT,
    items ARRAY<STRUCT<product: STRING, quantity: INT, price: DOUBLE>>
);

SELECT order_id, item.product, item.price
FROM orders LATERAL VIEW EXPLODE(items) t AS item;

-- Snowflake: VARIANT 实现任意嵌套
CREATE TABLE orders (
    order_id NUMBER,
    data VARIANT    -- 存储任意嵌套的 JSON
);

SELECT order_id,
       f.value:product::STRING AS product,
       f.value:price::NUMBER AS price
FROM orders,
LATERAL FLATTEN(input => data:items) f;
```

### 嵌套类型限制

| 引擎 | 最大嵌套深度 | ARRAY<ARRAY> | ARRAY<MAP> | MAP<K, STRUCT> |
|------|------------|-------------|-----------|---------------|
| PostgreSQL | 无限制 | ✅ (多维数组) | ❌ | ❌ |
| BigQuery | 15 层 | ❌ | ❌ | ❌ |
| DuckDB | 无限制 | ✅ | ✅ | ✅ |
| ClickHouse | 无限制 | ✅ | ✅ | ✅ |
| Trino | 无限制 | ✅ | ✅ | ✅ |
| Spark SQL | 无限制 | ✅ | ✅ | ✅ |
| Snowflake | 无限制 (VARIANT) | ✅ | ✅ | ✅ |

> **BigQuery 限制**: BigQuery 不允许 `ARRAY<ARRAY<...>>`，需要用 `ARRAY<STRUCT<inner ARRAY<...>>>` 绕过。这是因为 Dremel 编码中数组的 repetition level 不能直接嵌套。

## 类型构造与转换

### 从其他类型构造数组

```sql
-- 字符串分割为数组
-- PostgreSQL
SELECT STRING_TO_ARRAY('a,b,c', ',');          -- {a,b,c}
-- BigQuery
SELECT SPLIT('a,b,c', ',');                    -- ['a', 'b', 'c']
-- Snowflake
SELECT SPLIT('a,b,c', ',');                    -- ["a", "b", "c"]
-- DuckDB
SELECT STRING_SPLIT('a,b,c', ',');             -- [a, b, c]
-- ClickHouse
SELECT splitByChar(',', 'a,b,c');              -- ['a', 'b', 'c']
-- Spark SQL
SELECT split('a,b,c', ',');                    -- ['a', 'b', 'c']
-- Trino
SELECT split('a,b,c', ',');                    -- [a, b, c]

-- 范围生成数组
-- PostgreSQL
SELECT ARRAY(SELECT generate_series(1, 10));   -- {1,2,...,10}
-- DuckDB
SELECT range(1, 11);                           -- [1, 2, ..., 10]
SELECT generate_series(1, 10);                 -- 返回表
-- ClickHouse
SELECT range(1, 11);                           -- [1, 2, ..., 10]
-- Trino
SELECT SEQUENCE(1, 10);                        -- [1, 2, ..., 10]
-- Spark SQL
SELECT SEQUENCE(1, 10);                        -- [1, 2, ..., 10]
-- BigQuery
SELECT GENERATE_ARRAY(1, 10);                  -- [1, 2, ..., 10]
-- Snowflake (无直接语法，需用 TABLE(GENERATOR))
SELECT ARRAY_AGG(SEQ4()) FROM TABLE(GENERATOR(ROWCOUNT => 10));

-- JSON 转数组
-- PostgreSQL
SELECT ARRAY(SELECT jsonb_array_elements_text('["a","b","c"]'::jsonb));
-- Snowflake
SELECT PARSE_JSON('["a","b","c"]')::ARRAY;
-- DuckDB
SELECT json_extract('[1,2,3]', '$[*]');
```

### 数组转其他类型

```sql
-- 数组转字符串
-- PostgreSQL
SELECT ARRAY_TO_STRING(ARRAY['a','b','c'], ',');   -- 'a,b,c'
-- BigQuery
SELECT ARRAY_TO_STRING(['a','b','c'], ',');         -- 'a,b,c'
-- Snowflake
SELECT ARRAY_TO_STRING(ARRAY_CONSTRUCT('a','b','c'), ','); -- 'a,b,c'
-- DuckDB
SELECT ARRAY_TO_STRING(['a','b','c'], ',');         -- 'a,b,c'
-- ClickHouse
SELECT arrayStringConcat(['a','b','c'], ',');       -- 'a,b,c'
-- Spark SQL
SELECT ARRAY_JOIN(array('a','b','c'), ',');         -- 'a,b,c'
-- Trino
SELECT ARRAY_JOIN(ARRAY['a','b','c'], ',');         -- 'a,b,c'
```

## Lambda 表达式与数组高阶函数

部分引擎支持对数组元素进行函数式变换：

| 引擎 | TRANSFORM/MAP | FILTER | REDUCE/AGGREGATE | Lambda 语法 |
|------|-------------|--------|-----------------|------------|
| PostgreSQL | ❌ | ❌ | ❌ | ❌ |
| BigQuery | ❌ | ❌ | ❌ | ❌ |
| Snowflake | ✅ TRANSFORM | ✅ FILTER | ✅ REDUCE | `x -> expr` |
| DuckDB | ✅ LIST_TRANSFORM | ✅ LIST_FILTER | ✅ LIST_REDUCE | `x -> expr` |
| ClickHouse | ✅ arrayMap | ✅ arrayFilter | ✅ arrayReduce | `x -> expr` |
| Trino | ✅ TRANSFORM | ✅ FILTER | ✅ REDUCE | `x -> expr` |
| Spark SQL | ✅ TRANSFORM | ✅ FILTER | ✅ AGGREGATE | `x -> expr` |
| Databricks | ✅ TRANSFORM | ✅ FILTER | ✅ REDUCE | `x -> expr` |
| Flink SQL | ❌ | ❌ | ❌ | ❌ |
| Doris | ✅ ARRAY_MAP | ✅ ARRAY_FILTER | ❌ | `x -> expr` |

```sql
-- DuckDB: lambda 表达式
SELECT list_transform([1,2,3,4,5], x -> x * 2);         -- [2, 4, 6, 8, 10]
SELECT list_filter([1,2,3,4,5], x -> x > 3);             -- [4, 5]
SELECT list_reduce([1,2,3,4,5], (a, b) -> a + b);        -- 15

-- ClickHouse: arrayMap / arrayFilter
SELECT arrayMap(x -> x * 2, [1,2,3,4,5]);                -- [2, 4, 6, 8, 10]
SELECT arrayFilter(x -> x > 3, [1,2,3,4,5]);             -- [4, 5]
SELECT arrayReduce('sum', [1,2,3,4,5]);                   -- 15

-- Trino: TRANSFORM / FILTER
SELECT TRANSFORM(ARRAY[1,2,3,4,5], x -> x * 2);         -- [2, 4, 6, 8, 10]
SELECT FILTER(ARRAY[1,2,3,4,5], x -> x > 3);             -- [4, 5]
SELECT REDUCE(ARRAY[1,2,3,4,5], 0, (s, x) -> s + x, s -> s); -- 15

-- Spark SQL: TRANSFORM / FILTER / AGGREGATE
SELECT TRANSFORM(array(1,2,3,4,5), x -> x * 2);          -- [2, 4, 6, 8, 10]
SELECT FILTER(array(1,2,3,4,5), x -> x > 3);              -- [4, 5]
SELECT AGGREGATE(array(1,2,3,4,5), 0, (acc, x) -> acc + x); -- 15

-- Snowflake: TRANSFORM / FILTER (2023+)
SELECT TRANSFORM([1,2,3,4,5], x INT -> x * 2);            -- [2, 4, 6, 8, 10]
SELECT FILTER([1,2,3,4,5], x INT -> x > 3);               -- [4, 5]
```

## 数组集合操作

```sql
-- 数组排序
-- DuckDB
SELECT list_sort([3,1,2]);                          -- [1, 2, 3]
SELECT list_sort([3,1,2], 'DESC');                  -- [3, 2, 1]
-- ClickHouse
SELECT arraySort([3,1,2]);                          -- [1, 2, 3]
SELECT arrayReverseSort([3,1,2]);                   -- [3, 2, 1]
-- Spark SQL
SELECT sort_array(array(3,1,2));                    -- [1, 2, 3]
SELECT sort_array(array(3,1,2), false);             -- [3, 2, 1]
-- Trino
SELECT ARRAY_SORT(ARRAY[3,1,2]);                    -- [1, 2, 3]
-- BigQuery
SELECT ARRAY(SELECT x FROM UNNEST([3,1,2]) x ORDER BY x); -- [1, 2, 3]
-- PostgreSQL
SELECT ARRAY(SELECT UNNEST(ARRAY[3,1,2]) ORDER BY 1);     -- {1,2,3}

-- 数组去重
-- DuckDB
SELECT list_distinct([1,2,2,3,3]);                  -- [1, 2, 3]
-- ClickHouse
SELECT arrayDistinct([1,2,2,3,3]);                  -- [1, 2, 3]
-- Spark SQL
SELECT array_distinct(array(1,2,2,3,3));            -- [1, 2, 3]
-- Trino
SELECT ARRAY_DISTINCT(ARRAY[1,2,2,3,3]);            -- [1, 2, 3]
-- BigQuery (无内置函数，需子查询)
SELECT ARRAY(SELECT DISTINCT x FROM UNNEST([1,2,2,3,3]) x);
-- PostgreSQL
SELECT ARRAY(SELECT DISTINCT UNNEST(ARRAY[1,2,2,3,3]) ORDER BY 1);

-- 数组交集 / 并集 / 差集
-- DuckDB
SELECT list_intersect([1,2,3], [2,3,4]);            -- [2, 3]
SELECT list_union([1,2,3], [2,3,4]);                -- 不存在，需 list_distinct(list_concat(...))
-- ClickHouse
SELECT arrayIntersect([1,2,3], [2,3,4]);            -- [2, 3]
-- Spark SQL
SELECT array_intersect(array(1,2,3), array(2,3,4)); -- [2, 3]
SELECT array_union(array(1,2,3), array(2,3,4));     -- [1, 2, 3, 4]
SELECT array_except(array(1,2,3), array(2,3,4));    -- [1]
-- Trino
SELECT ARRAY_INTERSECT(ARRAY[1,2,3], ARRAY[2,3,4]); -- [2, 3]
SELECT ARRAY_UNION(ARRAY[1,2,3], ARRAY[2,3,4]);     -- [1, 2, 3, 4]
SELECT ARRAY_EXCEPT(ARRAY[1,2,3], ARRAY[2,3,4]);    -- [1]
```

## 数组拼接与修改

```sql
-- 数组拼接
-- PostgreSQL
SELECT ARRAY[1,2] || ARRAY[3,4];                    -- {1,2,3,4}
SELECT ARRAY[1,2] || 3;                             -- {1,2,3}
-- DuckDB
SELECT [1,2] || [3,4];                              -- [1, 2, 3, 4]
SELECT list_concat([1,2], [3,4]);                   -- 等价
-- ClickHouse
SELECT arrayConcat([1,2], [3,4]);                   -- [1, 2, 3, 4]
-- Trino
SELECT ARRAY[1,2] || ARRAY[3,4];                    -- [1, 2, 3, 4]
SELECT CONCAT(ARRAY[1,2], ARRAY[3,4]);              -- 等价
-- Spark SQL
SELECT concat(array(1,2), array(3,4));              -- [1, 2, 3, 4]
SELECT array_cat(array(1,2), array(3,4));           -- 别名
-- BigQuery
SELECT ARRAY_CONCAT([1,2], [3,4]);                  -- [1, 2, 3, 4]
-- Snowflake
SELECT ARRAY_CAT(ARRAY_CONSTRUCT(1,2), ARRAY_CONSTRUCT(3,4)); -- [1,2,3,4]

-- 添加/删除元素
-- PostgreSQL
SELECT ARRAY_APPEND(ARRAY[1,2], 3);                 -- {1,2,3}
SELECT ARRAY_PREPEND(0, ARRAY[1,2]);                 -- {0,1,2}
SELECT ARRAY_REMOVE(ARRAY[1,2,3,2], 2);             -- {1,3} (删除所有 2)
-- DuckDB
SELECT list_append([1,2], 3);                       -- [1, 2, 3]
SELECT list_prepend(0, [1,2]);                       -- [0, 1, 2]
-- ClickHouse
SELECT arrayPushBack([1,2], 3);                     -- [1, 2, 3]
SELECT arrayPushFront([1,2], 0);                    -- [0, 1, 2]
SELECT arrayFilter(x -> x != 2, [1,2,3,2]);        -- [1, 3]
-- Snowflake
SELECT ARRAY_APPEND(ARRAY_CONSTRUCT(1,2), 3);       -- [1, 2, 3]
SELECT ARRAY_PREPEND(ARRAY_CONSTRUCT(1,2), 0);      -- [0, 1, 2]
```

## 存储格式的影响

数组和复合类型的存储方式直接影响查询性能，是引擎开发者需要深入考虑的问题。

### 行式存储引擎（PostgreSQL、MySQL、Oracle）

```
PostgreSQL 数组存储:
  ┌─────────────────────────────────────────────┐
  │ ndim │ flags │ elemtype │ dim1 │ lb1 │ data │
  │  4B  │  4B   │   4B     │  4B  │ 4B  │ ... │
  └─────────────────────────────────────────────┘
  - 元素连续存储在 tuple 内
  - 整个数组作为单个 datum 读取
  - 随机访问 O(n)（变长元素需要遍历）
  - 更新某个元素需要重写整个数组
  - TOAST 压缩对大数组有效
```

### 列式存储引擎（BigQuery、ClickHouse、DuckDB）

```
Dremel / Parquet 编码（BigQuery, Spark, DuckDB）:
  repetition_level + definition_level 编码嵌套结构

  数据: [{a:1, b:[10,20]}, {a:2, b:[30]}]

  列 a:  [1, 2]           rep=[0, 0]  def=[1, 1]
  列 b:  [10, 20, 30]     rep=[0, 1, 0] def=[2, 2, 2]

  优势:
  - 只读取需要的列（列裁剪）
  - 向量化处理
  - 压缩率高（同类型数据连续存储）

ClickHouse 数组存储:
  Array(T) 存储为两个列:
  - offsets: [2, 3]        (每行数组的结束位置)
  - data: [10, 20, 30]    (所有元素连续存储)

  优势:
  - 随机访问 O(1)
  - 向量化扫描
  - 压缩效率高
```

### 半结构化存储（Snowflake、Redshift）

```
Snowflake VARIANT 存储:
  - 摄入时自动推断类型并列化存储
  - 高频字段提取为独立的微分区列
  - 低频字段保留为序列化格式
  - 查询时自动选择最优路径

Redshift SUPER 存储:
  - 类似 JSON 的二进制格式
  - 支持 PartiQL 查询
  - 自动 schema 推断用于优化
```

### 存储模型对比

| 特性 | 行式 (PostgreSQL) | 列式 (ClickHouse) | Dremel (BigQuery) | 半结构化 (Snowflake) |
|------|-----------------|------------------|-------------------|---------------------|
| 随机元素访问 | O(n) | O(1) | O(1) | O(1)~O(n) |
| 全数组扫描 | 快（连续） | 快（连续） | 快 | 中等 |
| 更新单个元素 | 重写整个数组 | 重写整列段 | 不支持 UPDATE | 重写微分区 |
| 列裁剪 | ❌ | ✅ | ✅ | ✅ |
| 压缩率 | 中 | 高 | 高 | 高 |
| Schema 灵活性 | 类型固定 | 类型固定 | 类型固定 | 完全灵活 |

## 对引擎开发者的实现建议

### 1. 类型系统设计

```
决策点 A: 类型化数组 vs 无类型数组

  类型化数组 (PostgreSQL, BigQuery, Trino):
  ├── ARRAY<INT> 只能存 INT
  ├── 编译期类型检查，更安全
  ├── 存储和计算可以优化
  └── 建议: OLAP 引擎推荐

  无类型数组 (Snowflake ARRAY, MongoDB):
  ├── 数组中可以混合类型
  ├── 更灵活，适合 ETL
  ├── 需要运行时类型检查
  └── 建议: 需要处理 JSON 的引擎推荐

决策点 B: 是否支持多维数组

  支持 (PostgreSQL):
  ├── INT[][] 是合法类型
  ├── 实现复杂度高
  └── 实际使用频率低

  不支持 (BigQuery):
  ├── ARRAY<ARRAY<INT>> 不合法
  ├── 用 ARRAY<STRUCT<inner ARRAY<INT>>> 绕过
  └── 建议: 新引擎可以不支持，用 STRUCT 包装替代
```

### 2. 索引起始位置

```
1-based (PostgreSQL, Trino, ClickHouse, DuckDB):
├── 与 SQL 标准一致
├── 与 ORDINAL/ROW_NUMBER 概念一致
└── 推荐新引擎采用

0-based (Snowflake, Spark, Hive, Redshift):
├── 与编程语言一致
├── 与 JSON 数组索引一致
└── 大数据引擎的主流选择

BigQuery 方案（最佳实践）:
├── arr[OFFSET(0)]  -- 0-based, 显式
├── arr[ORDINAL(1)] -- 1-based, 显式
├── arr[SAFE_OFFSET(0)] -- 0-based, 越界返回 NULL
└── 消除了所有歧义
```

### 3. UNNEST 实现

```
实现方式 1: 集合返回函数 (PostgreSQL)
├── UNNEST 是一个 SRF (Set-Returning Function)
├── 在 FROM 子句中展开
├── 需要处理 SRF 在 SELECT 列表中的特殊行为
└── 实现: 在执行器层面生成多行输出

实现方式 2: LATERAL JOIN (SQL 标准)
├── CROSS JOIN UNNEST(arr) AS t(val)
├── 语义上是每行产生一个虚拟表，然后 JOIN
├── LEFT JOIN UNNEST 可保留空数组行
└── 实现: 在 JOIN 执行器中处理

实现方式 3: 特殊函数 (ClickHouse arrayJoin)
├── arrayJoin 是一个特殊的函数，改变行数
├── 不是标准的 FROM 子句语法
├── 实现简单，但语义不规范
└── 注意: 多个 arrayJoin 的行为可能不直观

建议: 支持 SQL 标准的 CROSS JOIN UNNEST 语法，
     同时实现 WITH ORDINALITY 返回元素位置，
     LEFT JOIN 模式保留空数组行。
```

### 4. 存储层实现

```
行式引擎:
├── 数组序列化为连续字节块
├── 元素计数 + 偏移量数组 + 数据区
├── 变长元素需要偏移量表
├── 考虑 TOAST/压缩大数组
└── 注意: NULL 位图需要为每个元素维护

列式引擎:
├── 分离 offsets 列和 data 列
├── offsets 列: 每行存储数组在 data 列中的起止位置
├── data 列: 所有数组元素连续存储
├── 嵌套数组递归使用相同模式
├── 与 Apache Arrow 格式对齐可简化实现
└── 注意: 压缩时 offsets 和 data 可分别选择编码

Dremel 编码 (适合深度嵌套):
├── repetition_level: 表示重复的层级
├── definition_level: 表示 NULL 的层级
├── 优势: 任意深度嵌套统一处理
├── 劣势: 编码/解码复杂度高
└── 推荐: 需要兼容 Parquet 的引擎
```

### 5. 查询优化

```
优化 1: 数组函数下推
  SELECT * FROM t WHERE ARRAY_CONTAINS(arr, 42)
  → 可以下推到存储层，避免读取整个数组

优化 2: UNNEST + 聚合消除
  SELECT ARRAY_AGG(x) FROM (SELECT UNNEST(arr) AS x FROM t)
  → 优化为直接返回 arr（如果没有 WHERE/ORDER BY）

优化 3: 嵌套列裁剪
  SELECT customer.name FROM orders
  → 列式存储中只读取 customer.name 子列

优化 4: 数组常量折叠
  WHERE arr[1] > 10 AND ARRAY_LENGTH(arr) > 5
  → 对静态可计算的数组表达式在编译期求值

优化 5: UNNEST 位置优化
  CROSS JOIN UNNEST(arr) 应尽早计算
  → 在 JOIN reorder 中考虑 UNNEST 的扩展因子
```

### 6. MAP 类型实现考量

```
选项 A: 独立的 MAP 类型 (ClickHouse, Trino)
├── MAP<K, V> 作为一等类型
├── 键有序或无序（影响查找性能）
├── 存储: 两个并行数组 (keys + values)
└── 适合: 需要高效键查找的场景

选项 B: ARRAY<STRUCT<key, value>> 的语法糖 (部分实现)
├── 底层复用 ARRAY + STRUCT 的存储
├── MAP 只是一个语义别名
├── 简化实现，但键查找效率低
└── 适合: 初始实现阶段

选项 C: 动态 OBJECT 类型 (Snowflake)
├── 键总是 STRING，值是 VARIANT
├── 本质是 JSON Object 的原生表示
├── 灵活但类型安全性低
└── 适合: 半结构化数据引擎
```

## 跨引擎移植指南

在不同引擎间移植数组操作时，以下是最常遇到的差异：

| 操作 | PostgreSQL | BigQuery | Snowflake | ClickHouse | Spark SQL |
|------|-----------|---------|-----------|-----------|-----------|
| 创建数组 | `ARRAY[1,2]` | `[1,2]` | `ARRAY_CONSTRUCT(1,2)` | `[1,2]` | `array(1,2)` |
| 取元素 | `arr[1]` (1-based) | `arr[OFFSET(0)]` | `arr[0]` | `arr[1]` (1-based) | `arr[0]` (0-based) |
| 长度 | `CARDINALITY(arr)` | `ARRAY_LENGTH(arr)` | `ARRAY_SIZE(arr)` | `length(arr)` | `SIZE(arr)` |
| 包含 | `val = ANY(arr)` | `val IN UNNEST(arr)` | `ARRAY_CONTAINS(v, arr)` | `has(arr, v)` | `array_contains(arr, v)` |
| 展开 | `UNNEST(arr)` | `UNNEST(arr)` | `FLATTEN(arr)` | `arrayJoin(arr)` | `EXPLODE(arr)` |
| 聚合 | `ARRAY_AGG(x)` | `ARRAY_AGG(x)` | `ARRAY_AGG(x)` | `groupArray(x)` | `COLLECT_LIST(x)` |
| 拼接 | `arr1 \|\| arr2` | `ARRAY_CONCAT(a,b)` | `ARRAY_CAT(a,b)` | `arrayConcat(a,b)` | `concat(a,b)` |
| 排序 | 子查询 | 子查询 | — | `arraySort(arr)` | `sort_array(arr)` |

## 参考资料

- SQL:1999 标准: ARRAY 和 ROW 类型定义
- PostgreSQL: [Array Types](https://www.postgresql.org/docs/current/arrays.html), [Composite Types](https://www.postgresql.org/docs/current/rowtypes.html)
- BigQuery: [ARRAY](https://cloud.google.com/bigquery/docs/reference/standard-sql/arrays), [STRUCT](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#struct_type)
- Snowflake: [Semi-structured Data Types](https://docs.snowflake.com/en/sql-reference/data-types-semistructured)
- DuckDB: [Nested Types](https://duckdb.org/docs/sql/data_types/list), [STRUCT](https://duckdb.org/docs/sql/data_types/struct)
- ClickHouse: [Array](https://clickhouse.com/docs/en/sql-reference/data-types/array), [Map](https://clickhouse.com/docs/en/sql-reference/data-types/map), [Tuple](https://clickhouse.com/docs/en/sql-reference/data-types/tuple)
- Trino: [Array](https://trino.io/docs/current/functions/array.html), [Map](https://trino.io/docs/current/functions/map.html), [Row](https://trino.io/docs/current/language/types.html#row)
- Spark SQL: [Complex Types](https://spark.apache.org/docs/latest/sql-ref-datatypes.html)
- Hive: [Complex Types](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types#LanguageManualTypes-ComplexTypes)
- Oracle: [Collections](https://docs.oracle.com/en/database/oracle/oracle-database/21/lnpls/plsql-collections-and-records.html)
- Cassandra: [Collection Types](https://cassandra.apache.org/doc/latest/cassandra/cql/types.html#collections)
- Dremel 论文: [Dremel: Interactive Analysis of Web-Scale Datasets](https://research.google/pubs/pub36632/)
