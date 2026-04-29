# 递归复合类型 (Recursive Composite Types)

"我有一棵 JSON 树，想用一个类型同时描述节点和它的子节点列表，能不能让一个 `CREATE TYPE` 直接引用自己？"——这是几乎每位从应用语言（Java、TypeScript、Rust）切换到 SQL 的工程师都会问过的问题。在大多数面向对象语言里，递归类型（`class Node { next: Node }` 或 `struct Tree { children: Vec<Tree> }`) 是描述链表、二叉树、嵌套 JSON 的家常便饭；而在 SQL 世界里，"一个类型直接包含它自己" 这件事被 SQL:1999 标准明确禁止——结构化用户定义类型的字段类型不允许形成有向环。然而工程现实总是更复杂的：Oracle 自 8i 以来允许通过 `REF` 类型实现对象身份的循环引用；BigQuery / Spark 的嵌套 STRUCT 可以无限叠加（虽有深度限制）；Snowflake 的 VARIANT 与 PostgreSQL 的 JSONB 在动态类型层面任意嵌套；ClickHouse 的 Tuple 与 Nested 自由组合；DuckDB 的 STRUCT/LIST 互嵌套——绕过 "直接递归" 禁令的方式各自精彩。

本文系统梳理 45+ 数据库在 "递归复合类型" 上的支持现状：从 SQL 标准结构化类型的禁令、到 Oracle 对象引用、再到分析型引擎的嵌套 STRUCT、再到 JSON 这一通用 "万能递归类型"，我们将看到 SQL 如何在 "强类型严谨性" 与 "嵌套数据现实需求" 之间反复权衡。

姊妹文章：
- [行类型与复合类型 (Row and Composite Types)](./row-composite-types.md) 关注 ROW 与命名复合类型的基础语义。
- [数组与复合类型 (Array and Collection Types)](./array-collection-types.md) 关注 ARRAY/MAP/STRUCT 集合层面的细节。
- [层次数据类型 (Hierarchical Data Types)](./hierarchyid-ltree-types.md) 关注路径编码与层次索引。

## 什么是递归复合类型

递归复合类型，简称 "self-referencing structured type"，指的是一个复合类型在它自己的字段定义里直接或间接引用了 "自己"。最经典的几个形态：

```text
单链表节点：     Node {value, next: Node}
二叉树节点：     Tree {value, left: Tree, right: Tree}
N 叉树节点：     Tree {value, children: ARRAY<Tree>}
JSON 节点：      JsonValue = Object | Array | Scalar，其中 Object/Array 含 JsonValue
互递归：         A {b: B}, B {a: A}
```

在 ANSI SQL 里，这些定义看起来是这样的：

```sql
-- 直接递归 (SQL:1999 禁止)
CREATE TYPE node_t AS (
    value INTEGER,
    next  node_t          -- 错误：不能引用自己
);

-- 通过 ARRAY 间接递归 (PG 也禁止)
CREATE TYPE tree_t AS (
    value    INTEGER,
    children tree_t[]      -- 错误：仍然是循环依赖
);

-- 互递归 (绝大多数引擎禁止)
CREATE TYPE a_t AS (...);
CREATE TYPE b_t AS (... a_t);    -- 引用 a_t
ALTER  TYPE a_t ADD ATTRIBUTE b b_t;  -- 错误：形成环
```

绕过禁令的几种现实手段：

1. **指针 / 对象引用**：Oracle 的 `REF`、PG 的 OID 引用——把循环依赖转化为 "对象身份链"。
2. **嵌套 STRUCT 有限深度**：BigQuery、Spark 的嵌套结构在 schema 层就要展开，所以深度有限但可以预先列举。
3. **JSON / VARIANT**：值自带 schema，递归不在 DDL 里出现，运行时任意嵌套。
4. **数组下标 / 自连接**：把递归关系建在数据层（adjacency list），而不是类型层。

理解了这四类绕道方案，就能看清 45+ 引擎为什么各有各的样貌。

## SQL 标准定义

### SQL:1999 结构化类型禁止递归

SQL:1999 第二部分（Foundation, ISO/IEC 9075-2）在 Section 4.8 "User-defined types" 里定义了结构化类型：

```sql
<user-defined type definition> ::=
    CREATE TYPE <user-defined type name>
        [ <subtype clause> ]
        [ AS <representation> ]
        [ <instantiable clause> ]
        [ <finality clause> ]
        ...

<representation> ::= <attribute definition>...

<attribute definition> ::=
    <attribute name> <data type> ...
```

标准的关键约束（在 General Rules 里）：

> **A structured type shall not directly or indirectly contain an attribute whose declared type is the type being defined or is a structured type that directly or indirectly contains an attribute of the type being defined.**

简言之：**结构化类型的字段不允许形成有向环。** 标准给出的理由有两层：

1. **存储模型**：行存数据库无法预知一个递归值的最终大小，必须引入间接性（指针）才能存储。
2. **类型系统终止性**：递归类型的相等比较、序列化、深拷贝等操作必须显式定义终止条件；标准为了避免引入这些复杂性，干脆禁止。

### SQL:2003 引入 REF 类型解禁部分场景

SQL:2003（基于 SQL:1999 之上的修订）引入了 `REF(structured-type)` 这一引用类型：

```sql
CREATE TYPE node_t AS (
    value INTEGER,
    next  REF(node_t) SCOPE next_table   -- 合法：REF 是引用，非递归内嵌
) NOT FINAL;

CREATE TABLE next_table OF node_t (REF IS oid SYSTEM GENERATED);
```

`REF` 在标准中是 "对象引用类型"，类似面向对象语言的指针——它存储的是另一个对象的标识符，不是对象本身的值。这就把 "递归" 从 "结构内嵌" 转化为 "标识链接"，在存储模型上可以闭环：

- `node_t` 是固定大小的（`value INTEGER + REF`，REF 通常是 16 字节 OID）。
- 链表 `1 -> 2 -> 3` 是三个独立行，靠 OID 互相指。
- 类型系统也终止——`REF(node_t)` 是一个 "引用 node_t 的类型"，本身不是 node_t。

这是 Oracle 早在 8i（1999）就实现的模型，也成为 IBM DB2、Informix 等少数走 OO 路线引擎的基础。

### SQL:2003 ARRAY OF self 仍然禁止

SQL:2003 引入了 `ARRAY` 作为集合类型，但标准对结构化类型的递归限制依然适用：

```sql
CREATE TYPE tree_t AS (
    value    INTEGER,
    children tree_t ARRAY    -- 仍然违反 SQL:1999 General Rules
);
```

理论上 `ARRAY` 是变长容器，可以避免 "无限嵌套"，但标准坚持把 "存在性" 和 "大小" 分开看：哪怕容器是空的，类型定义形成的环也是不允许的。这是为什么 PostgreSQL 至今 `CREATE TYPE foo AS (next foo[])` 也会报错。

### SQL:2016 与现代标准对 JSON 的处理

SQL:2016 引入了 `JSON` 作为数据类型（JSON path、JSON_TABLE 等），但 JSON 在标准里是 **运行时类型**——JSON 值的内部结构不在 DDL 层暴露给类型系统。这恰恰让 JSON 成为 "事实上的递归类型"：

```sql
-- JSON 值可以是任意嵌套
SELECT JSON_OBJECT(
    'name'     : 'root',
    'children' : JSON_ARRAY(
        JSON_OBJECT('name' : 'leaf1', 'children' : JSON_ARRAY()),
        JSON_OBJECT('name' : 'leaf2', 'children' : JSON_ARRAY())
    )
);
```

JSON 的存在让 SQL 标准 "正式禁止 + 实用允许" 的双层态度变得清晰：强类型走 REF 路线，弱类型走 JSON 路线。

## 支持矩阵（45+ 引擎）

### 自引用 UDT (CREATE TYPE 直接递归)

| 引擎 | 直接自引用 | ARRAY of self | REF/指针 | 互递归 | 说明 |
|------|------------|---------------|----------|--------|------|
| PostgreSQL | -- | -- | -- (无 REF) | -- | `CREATE TYPE foo AS (next foo)` 报错 |
| Oracle | -- (直接) | -- (直接) | 是 (REF) | 是 (REF) | 8i+ 通过 REF 实现对象引用 |
| DB2 | -- | -- | 是 (REF) | 是 | Structured Type + REF |
| SQL Server | -- (T-SQL) | -- | 是 (CLR UDT) | 是 (CLR) | CLR 类型可任意递归 |
| MySQL | -- | -- | -- | -- | 无 CREATE TYPE |
| MariaDB | -- | -- | -- | -- | 无 CREATE TYPE |
| SQLite | -- | -- | -- | -- | 无 CREATE TYPE |
| Snowflake | -- | -- | -- | -- | 无命名 UDT；用 VARIANT |
| BigQuery | -- (有限深度嵌套) | -- (有限) | -- | -- | STRUCT 嵌套深度上限 15 |
| Redshift | -- | -- | -- | -- | 无命名 UDT；用 SUPER |
| DuckDB | -- (直接) | -- (直接) | -- | -- | STRUCT/LIST 可深嵌套 |
| ClickHouse | -- | -- | -- | -- | Tuple/Nested 可深嵌套 |
| Trino | -- | -- | -- | -- | ROW 可深嵌套 |
| Presto | -- | -- | -- | -- | 同 Trino |
| Spark SQL | -- | -- | -- | -- | StructType 可任意嵌套 |
| Hive | -- | -- | -- | -- | STRUCT 可深嵌套 |
| Flink SQL | -- | -- | -- | -- | ROW 可深嵌套 |
| Databricks | -- | -- | -- | -- | StructType 可任意嵌套 |
| Teradata | -- | -- | 是 (REFERENCE) | 部分 | UDT 支持引用 |
| Greenplum | -- | -- | -- | -- | 同 PG |
| CockroachDB | -- | -- | -- | -- | 无 CREATE TYPE composite |
| TiDB | -- | -- | -- | -- | 无 CREATE TYPE |
| OceanBase | -- (MySQL 模式) | -- | 是 (Oracle 模式 REF) | 是 (Oracle 模式) | 双模式 |
| YugabyteDB | -- | -- | -- | -- | 同 PG |
| SingleStore | -- | -- | -- | -- | 无命名 UDT |
| Vertica | -- | -- | -- | -- | ROW 可嵌套 |
| Impala | -- | -- | -- | -- | STRUCT 可嵌套 |
| StarRocks | -- | -- | -- | -- | STRUCT 可嵌套 |
| Doris | -- | -- | -- | -- | STRUCT 可嵌套 |
| MonetDB | -- | -- | -- | -- | 无递归类型 |
| CrateDB | -- | -- | -- | -- | OBJECT 可嵌套 |
| TimescaleDB | -- | -- | -- | -- | 同 PG |
| QuestDB | -- | -- | -- | -- | 无嵌套类型 |
| Exasol | -- | -- | -- | -- | 无嵌套类型 |
| SAP HANA | -- | -- | -- | -- | 无 CREATE TYPE composite |
| Informix | -- (直接) | -- | 是 (Named ROW REF) | 部分 | OO 路线 |
| Firebird | -- | -- | -- | -- | 无嵌套类型 |
| H2 | -- | -- | -- | -- | 无 CREATE TYPE composite |
| HSQLDB | -- | -- | -- | -- | 无 CREATE TYPE composite |
| Derby | -- | -- | -- | -- | 无 CREATE TYPE composite |
| Amazon Athena | -- | -- | -- | -- | ROW 可嵌套 |
| Azure Synapse | -- | -- | -- | -- | 无 CREATE TYPE composite |
| Google Spanner | -- (有限深度) | -- (有限) | -- | -- | STRUCT 仅限查询表达 |
| Materialize | -- | -- | -- | -- | 同 PG |
| RisingWave | -- | -- | -- | -- | STRUCT 可嵌套 |
| InfluxDB (SQL) | -- | -- | -- | -- | 无嵌套类型 |
| Databend | -- | -- | -- | -- | Tuple 可嵌套 |
| Yellowbrick | -- | -- | -- | -- | 同 PG |
| Firebolt | -- | -- | -- | -- | 无嵌套类型 |

> 关键发现：**45+ 引擎里没有一个支持 "结构化 UDT 直接递归"**——这是 SQL:1999 General Rules 在工程上的一致体现。Oracle / DB2 / Informix / Teradata / SQL Server CLR 通过 REF（或 .NET 引用）这种 "间接递归" 路径绕过禁令；其余所有引擎要么禁止递归 UDT、要么干脆没有命名复合类型 DDL。

### JSON / VARIANT 嵌套深度

| 引擎 | JSON 类型 | 最大嵌套深度 | 备注 |
|------|-----------|--------------|------|
| PostgreSQL | JSONB | ~10000 | 受 PostgreSQL 内存与栈限制影响 |
| MySQL | JSON | 100 | 服务器变量 `--max-statement-nested` 限制相关；JSON 文档默认深度 100 |
| MariaDB | JSON (LONGTEXT 别名) | 100 | 与 MySQL 接近 |
| SQL Server | NVARCHAR + JSON 函数 | 32 (`OPENJSON` 嵌套) | 无原生 JSON 类型直到 2022 |
| Oracle | JSON / VARCHAR2 | 100+ | 21c+ 原生 JSON |
| SQLite | TEXT + JSON1 扩展 | 1000 (默认) | `SQLITE_LIMIT_DEPTH` 可调 |
| Snowflake | VARIANT | ~16 MB 大小限制 | 没有显式深度限制 |
| BigQuery | JSON / STRING | 500 | JSON 字段嵌套深度上限约 500 |
| Redshift | SUPER | 数据有限 | 单文档大小 1 MB 上限 |
| DuckDB | JSON 扩展 / VARCHAR | 大约无限 | 受内存限制 |
| ClickHouse | JSON / String | 实验性 JSON 类型 | 24.x 引入新一代 JSON |
| Trino | JSON | 无显式上限 | -- |
| Spark SQL | STRING + from_json | 200+ | from_json 解析有递归栈限制 |
| Flink SQL | STRING | -- | 用 ROW + JSON_VALUE |
| Vertica | VARCHAR / 半结构化 | -- | FLEX 表 |
| Teradata | JSON | -- | 18+ |
| DB2 | JSON | -- | -- |
| MongoDB | BSON | 100 | 文档嵌套深度限制 |
| CrateDB | OBJECT | 实际无限 | 嵌套对象 |
| Cassandra | UDT 嵌套 | 受 SSTable 影响 | 内嵌 UDT 列 |

> 注：JSON / VARIANT 深度限制大多是 "防御性的"——超过实际需求很多。但如果设计依赖任意深度递归（例如代码 AST 树），需要明确各引擎的具体上限。

### 嵌套 STRUCT/ROW (有限深度递归近似)

| 引擎 | STRUCT 可嵌套 | 嵌套深度上限 | 数组嵌套 STRUCT |
|------|---------------|--------------|-----------------|
| PostgreSQL | 是 (复合类型) | 由 schema 限定 | 是 (composite[]) |
| Oracle | 是 (OBJECT) | -- | VARRAY/NESTED TABLE |
| DB2 | 是 (Structured) | -- | ARRAY |
| BigQuery | 是 (STRUCT) | **15 层** | ARRAY<STRUCT> 任意 |
| Snowflake | 是 (OBJECT/VARIANT) | 16 MB | ARRAY<OBJECT> |
| DuckDB | 是 (STRUCT) | 实践无限 | LIST<STRUCT> |
| ClickHouse | 是 (Tuple/Nested) | 实践无限 | Array(Tuple) |
| Trino | 是 (ROW) | -- | ARRAY<ROW> |
| Spark SQL | 是 (StructType) | -- | ARRAY<StructType> |
| Hive | 是 (STRUCT) | -- | ARRAY<STRUCT> |
| Flink SQL | 是 (ROW) | -- | ARRAY<ROW> |
| Databricks | 是 (StructType) | -- | ARRAY<StructType> |
| Vertica | 是 (ROW) | -- | ARRAY<ROW> |
| Impala | 是 (STRUCT) | -- | ARRAY<STRUCT> (Parquet) |
| StarRocks | 是 (STRUCT) | -- | ARRAY<STRUCT> |
| Doris | 是 (STRUCT) | -- | ARRAY<STRUCT> |
| Athena | 是 (ROW) | -- | ARRAY<ROW> |
| Spanner | 是 (STRUCT) | 仅查询 | ARRAY<STRUCT> |
| RisingWave | 是 (STRUCT) | -- | ARRAY<STRUCT> |
| Databend | 是 (Tuple) | -- | Array(Tuple) |

> **关键引擎深度上限**：BigQuery 在官方文档中明确列出 STRUCT 嵌套深度上限为 15（[BigQuery STRUCT 类型](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#struct_type)）；Snowflake VARIANT 单值大小上限 16 MB。Spark/DuckDB/ClickHouse 没有显式 schema 嵌套深度限制，但解析/序列化栈深度仍是隐性约束。

### 基于 ID 自引用 (递归外键)

| 引擎 | 表自引用外键 | WITH RECURSIVE | 递归 SQL 函数 | 备注 |
|------|--------------|----------------|---------------|------|
| PostgreSQL | 是 | 是 | 是 | 全功能 |
| MySQL | 是 | 8.0+ | -- (无 SQL 函数递归) | -- |
| MariaDB | 是 | 10.2+ | -- | -- |
| SQLite | 是 | 是 | -- | -- |
| Oracle | 是 | 11gR2+ | 是 (PL/SQL) | 也支持 CONNECT BY |
| SQL Server | 是 | 是 | 是 (T-SQL) | -- |
| DB2 | 是 | 是 | 是 | -- |
| Snowflake | 是 | 是 | -- (UDF 不能递归) | -- |
| BigQuery | -- (无 FK 强制) | 是 | -- (UDF 不能递归) | -- |
| Redshift | -- (无 FK 强制) | 是 | -- | -- |
| DuckDB | 是 | 是 | -- | -- |
| ClickHouse | -- (无 FK) | 是 (24.x+) | -- | -- |
| Trino | -- (取决于连接器) | 是 | -- | -- |
| Spark SQL | -- | 是 (3.0+) | -- | -- |

## 各引擎详解

### PostgreSQL：明确禁止直接递归

PostgreSQL 在复合类型领域是最完整的实现之一，但同样严格遵守 SQL:1999 的递归禁令：

```sql
-- 直接递归：报错
CREATE TYPE node_t AS (
    value INTEGER,
    next  node_t          -- ERROR: type "node_t" does not yet exist
);

-- 错误：
-- ERROR:  type "node_t" does not yet exist
-- 实际上 PG 在解析 CREATE TYPE 时会按字段顺序解析，引用未定义的类型会失败

-- 即使先创建空类型再 ALTER，也无法添加自引用：
CREATE TYPE node_t AS ();    -- ERROR: composite type must have at least one attribute
-- PG 的复合类型必须至少有一个字段才能创建
```

PostgreSQL 也禁止通过 ARRAY 间接递归：

```sql
CREATE TYPE tree_t AS (
    value    INTEGER,
    children tree_t[]    -- ERROR: type "tree_t" does not yet exist
);
```

PG 的 `RECORD` 类型可以包含任意字段（动态 schema），但它是一个**运行时**类型，不能 `CREATE TYPE` 为递归。

### PG 的指针模式：用 OID 模拟引用

虽然没有原生 REF，PG 可以用 OID 自引用模拟链表/树：

```sql
CREATE TABLE node (
    id    SERIAL PRIMARY KEY,
    value INTEGER,
    next  INTEGER REFERENCES node(id)
);

INSERT INTO node (value, next) VALUES (1, NULL);  -- tail
INSERT INTO node (value, next) VALUES (2, 1);     -- mid
INSERT INTO node (value, next) VALUES (3, 2);     -- head

-- 递归查询整条链
WITH RECURSIVE chain AS (
    SELECT id, value, next
    FROM node WHERE id = 3   -- start at head
    UNION ALL
    SELECT n.id, n.value, n.next
    FROM node n JOIN chain c ON n.id = c.next
)
SELECT value FROM chain;     -- 3, 2, 1
```

这就是 SQL 标准里 "类型层禁递归，数据层允许" 的妥协方案。

### PG 的 JSONB 路线

把递归数据存在 JSONB 列里，类型层完全不参与：

```sql
CREATE TABLE tree_doc (
    id   SERIAL PRIMARY KEY,
    data JSONB
);

INSERT INTO tree_doc (data) VALUES (
    '{"name": "root",
      "children": [
          {"name": "a", "children": [
              {"name": "a1", "children": []}
          ]},
          {"name": "b", "children": []}
      ]}'
);

-- 递归地展开 JSON 树
WITH RECURSIVE walk AS (
    SELECT data AS node, 0 AS depth
    FROM tree_doc WHERE id = 1
    UNION ALL
    SELECT child, depth + 1
    FROM walk, jsonb_array_elements(node->'children') AS child
)
SELECT depth, node->>'name' FROM walk;
```

JSONB 是 PG 的 "万能递归类型"——schema-on-read 的代价是编译期没有类型检查，但灵活性无可比拟。

### Oracle：REF 与对象身份

Oracle 是 SQL 阵营里 **唯一从 8i (1999) 起就把 REF 类型做为一等公民** 的引擎。`REF(object-type)` 让自引用合法：

```sql
-- 对象类型可以 forward-declare
CREATE OR REPLACE TYPE node_t;        -- 占位
/

CREATE OR REPLACE TYPE node_t AS OBJECT (
    value INTEGER,
    next  REF node_t                  -- 引用自己：合法
);
/

-- 必须有 "object table" 才能产生 REF
CREATE TABLE node_table OF node_t (
    value NOT NULL,
    PRIMARY KEY (value)
);

-- 创建链表 1 -> 2 -> 3
DECLARE
    n3 REF node_t;
    n2 REF node_t;
BEGIN
    INSERT INTO node_table VALUES (node_t(3, NULL));
    SELECT REF(n) INTO n3 FROM node_table n WHERE value = 3;

    INSERT INTO node_table VALUES (node_t(2, n3));
    SELECT REF(n) INTO n2 FROM node_table n WHERE value = 2;

    INSERT INTO node_table VALUES (node_t(1, n2));
END;
/

-- 解引用 (DEREF)
SELECT n.value, DEREF(n.next).value AS next_value
FROM node_table n;
```

`REF` 的实现细节：

- 每个 object table 行有一个 16 字节 OID（自动生成或基于主键）。
- `REF(node_t)` 列存储 OID + 类型信息，本身固定大小。
- `DEREF(ref_value)` 在查询时跟随 OID 找到对应行。
- `IS DANGLING` 检测引用的对象是否已被删除。

互递归同样支持：

```sql
CREATE OR REPLACE TYPE department_t;
/
CREATE OR REPLACE TYPE employee_t AS OBJECT (
    id      INTEGER,
    name    VARCHAR2(50),
    dept    REF department_t
);
/
CREATE OR REPLACE TYPE department_t AS OBJECT (
    id      INTEGER,
    name    VARCHAR2(50),
    manager REF employee_t
);
/
ALTER TYPE employee_t COMPILE;
```

### Oracle 的 NESTED TABLE 与 VARRAY

Oracle 还有 `NESTED TABLE` 与 `VARRAY` 两种集合类型——但二者都不允许直接递归：

```sql
-- 直接尝试：报错
CREATE TYPE tree_t AS OBJECT (
    value INTEGER,
    children tree_t_tab    -- 需要先定义 tree_t_tab
);
/
CREATE TYPE tree_t_tab AS TABLE OF tree_t;
/
-- ORA-22907: invalid CAST to a type that is not a nested table or VARRAY

-- 必须用 REF
CREATE TYPE tree_t;
/
CREATE TYPE tree_ref_tab AS TABLE OF REF tree_t;
/
CREATE OR REPLACE TYPE tree_t AS OBJECT (
    value INTEGER,
    children tree_ref_tab
);
/
```

这是 Oracle "REF 路线最完整" 的体现：递归只能通过对象引用，不能通过值嵌套。

### SQL Server：CLR UDT 的递归特例

T-SQL 没有 `CREATE TYPE ... AS (...)` 风格的命名复合类型，但 SQL Server 提供 **CLR User-Defined Types**——用 .NET 类型扩展 SQL：

```csharp
// .NET 端
[Serializable]
[SqlUserDefinedType(Format.UserDefined, IsByteOrdered = true,
                    MaxByteSize = 8000)]
public class TreeNode : INullable, IBinarySerialize
{
    public int Value;
    public TreeNode[] Children;     // C# 端递归引用
    // ...
}
```

```sql
-- T-SQL 端
CREATE ASSEMBLY TreeNodeAssembly FROM 'C:\TreeNode.dll'
WITH PERMISSION_SET = SAFE;

CREATE TYPE dbo.TreeNode
EXTERNAL NAME TreeNodeAssembly.[TreeNode];

CREATE TABLE dbo.Trees (
    id INT PRIMARY KEY,
    root dbo.TreeNode
);
```

CLR UDT 的递归是 .NET 类型系统的能力，并非 T-SQL 的：序列化时整棵树压成二进制（最大 8000 字节，或 GB 级 LOB）。这种 "把递归外包给宿主语言" 的模式与 Oracle REF 截然不同——后者是数据库引擎原生支持，前者是宿主语言绕开 SQL 限制。

SQL Server 的 `hierarchyid` 类型也是 CLR 实现，专门为层次数据设计（参见 `hierarchyid-ltree-types.md`）。

### DB2：Structured Type 的 REF

DB2 沿袭 SQL:2003 标准，提供 `REF` 类型：

```sql
CREATE TYPE Person AS (
    name VARCHAR(50),
    age  INTEGER
) REF USING INTEGER
  MODE DB2SQL
  NOT FINAL;

CREATE TYPE Employee UNDER Person AS (
    salary DECIMAL(10,2),
    boss   REF(Employee) SCOPE Employee_table
) MODE DB2SQL
  NOT FINAL;

CREATE TABLE Employee_table OF Employee
  (REF IS oid SYSTEM GENERATED);
```

DB2 的结构化类型支持继承（`UNDER`），与 Oracle 同一血脉。但 DB2 在 OLAP 与云上的存在感远不如 Oracle。

### BigQuery：嵌套 STRUCT 不递归但可深嵌套

BigQuery 的 `STRUCT<...>` 是 GoogleSQL 的核心嵌套类型，但它**不允许递归引用自己**（schema 在编译期就要展开）：

```sql
-- BigQuery：不能递归
CREATE TABLE dataset.tree (
    node STRUCT<value INT64, children ARRAY<STRUCT<...>>>  -- 必须显式展开
);

-- 实际可写到深度 15
CREATE TABLE dataset.tree (
    node STRUCT<
        value INT64,
        children ARRAY<STRUCT<
            value INT64,
            children ARRAY<STRUCT<
                value INT64,
                children ARRAY<STRUCT<value INT64>>    -- 显式嵌套
            >>
        >>
    >
);
```

BigQuery 官方文档（[STRUCT 类型](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#struct_type)）明确给出：

> Maximum nested depth: 15

也就是说，最多 15 层 STRUCT 嵌套——足够大多数业务场景，但不是真正的 "递归"。当业务真的需要任意深度树时，BigQuery 推荐两种方案：

1. **JSON 列**：`CREATE TABLE t (data JSON)` —— 存任意嵌套数据，运行时解析。
2. **adjacency list + WITH RECURSIVE**：把树拆成关系表 + 父 ID 列。

```sql
-- 方案 1：JSON
CREATE TABLE dataset.tree_json (
    id INT64,
    data JSON
);

INSERT INTO dataset.tree_json VALUES (1, JSON '''
{"name": "root", "children": [
    {"name": "a", "children": [{"name": "a1"}]},
    {"name": "b"}
]}
''');

SELECT JSON_VALUE(data, '$.children[0].children[0].name')
FROM dataset.tree_json;
```

```sql
-- 方案 2：递归 CTE
WITH RECURSIVE tree AS (
    SELECT id, parent_id, name, 0 AS depth
    FROM dataset.tree_table WHERE parent_id IS NULL
    UNION ALL
    SELECT t.id, t.parent_id, t.name, p.depth + 1
    FROM dataset.tree_table t JOIN tree p ON t.parent_id = p.id
)
SELECT * FROM tree;
```

### ClickHouse：Tuple/Nested 嵌套

ClickHouse 的 `Tuple` 与 `Nested` 都是有限深度的嵌套——不能直接自引用：

```sql
-- 嵌套 Tuple
CREATE TABLE events (
    id UInt64,
    ctx Tuple(
        user Tuple(
            id   UInt64,
            name String,
            addr Tuple(
                city String,
                country String
            )
        ),
        device String
    )
) ENGINE = MergeTree ORDER BY id;

SELECT ctx.user.addr.city FROM events;
```

ClickHouse 不允许 `Tuple(self_t)`：每层 Tuple 必须显式定义。但通过 `JSON` 类型（24.x 引入了一代新的 JSON 列存编码）可以达到 "事实递归"：

```sql
-- 24.x 起 JSON 是一等列存类型
CREATE TABLE docs (
    id UInt64,
    payload JSON
) ENGINE = MergeTree ORDER BY id;

INSERT INTO docs VALUES (1, '{"a":{"b":{"c":42}}}');
SELECT payload.a.b.c FROM docs;
```

### DuckDB：STRUCT/LIST 互嵌套

DuckDB 的 STRUCT 与 LIST 可以自由嵌套，但 schema 仍然是有限深度的：

```sql
-- 多层嵌套
CREATE TABLE tree (
    root STRUCT(
        value INTEGER,
        children LIST(STRUCT(
            value INTEGER,
            children LIST(STRUCT(value INTEGER))    -- 显式三层
        ))
    )
);
```

DuckDB 也不支持 `STRUCT(s self)`。但因为 DuckDB 把 JSON 作为二等公民支持，类似 PG 的 JSONB 模式同样可用：

```sql
-- 安装 JSON 扩展
INSTALL json;
LOAD json;

CREATE TABLE docs (
    id   INTEGER,
    body JSON
);

INSERT INTO docs VALUES (1, '{"a": {"b": {"c": 42}}}');
SELECT body->'a'->'b'->'c' FROM docs;
```

### Spark SQL / Databricks：StructType 任意深嵌套

Spark 的 `StructType` 本身是 Java/Scala 类型系统的递归类型，所以理论上可以任意嵌套——但 SQL 层 DDL 写起来痛苦：

```sql
CREATE TABLE tree (
    root STRUCT<
        value: INT,
        children: ARRAY<STRUCT<
            value: INT,
            children: ARRAY<STRUCT<value: INT>>
        >>
    >
);
```

Spark 不支持 SQL 层的递归 STRUCT 定义；但 DataFrame API 可以构造任意深度的 schema：

```scala
import org.apache.spark.sql.types._

// Scala 端构造递归 schema 的常见做法
def treeSchema(depth: Int): StructType = {
    if (depth == 0) StructType(Seq(StructField("value", IntegerType)))
    else StructType(Seq(
        StructField("value", IntegerType),
        StructField("children", ArrayType(treeSchema(depth - 1)))
    ))
}

val schema = treeSchema(10)   // 10 层
```

实践中处理 "任意深度树" 的 Spark 做法是 from_json + 解析 String：

```sql
SELECT from_json(payload, 'STRUCT<a:STRUCT<b:STRUCT<c:INT>>>')
FROM docs;
```

每次解析时显式给出 schema——这其实是 BigQuery 的同一个权衡：编译期 schema 已知。

### Snowflake：VARIANT 任意嵌套

Snowflake 没有命名复合类型 DDL，全靠 `VARIANT` 与 `OBJECT`：

```sql
CREATE TABLE docs (
    id INT,
    data VARIANT
);

INSERT INTO docs SELECT 1, PARSE_JSON('
{"name": "root", "children": [
    {"name": "a", "children": [
        {"name": "a1", "children": []}
    ]}
]}
');

-- 任意深度访问
SELECT data:children[0]:children[0]:name::STRING
FROM docs;

-- 限制：单 VARIANT 值最大 16 MB
```

VARIANT 在 Snowflake 内部是 Parquet 风格的列式半结构化存储——第一次插入时自动推断 schema，但运行时仍然允许 schema 漂移。这是 "schema-on-read" 的极致演绎，递归不在 DDL 里出现。

### Trino / Presto：ROW 嵌套

Trino 的 ROW 类型可以任意深度嵌套，但同样不支持自引用：

```sql
CREATE TABLE tree (
    node ROW(
        value INT,
        children ARRAY<ROW(
            value INT,
            children ARRAY<ROW(value INT)>
        )>
    )
);
```

Trino 通常用 JSON 类型处理任意深度：

```sql
SELECT json_extract_scalar(payload, '$.a.b.c.d.e')
FROM docs;
```

### Flink SQL：ROW 嵌套与流处理

Flink 的 ROW 类型与 Trino 类似，常配合 Avro/Protobuf 反序列化器：

```sql
CREATE TABLE events (
    payload ROW<
        user_id BIGINT,
        actions ROW<
            type   STRING,
            params ROW<key STRING, value STRING>
        >
    >
) WITH ('format' = 'avro', ...);
```

任意深度的递归 schema 不被支持，但 Avro union 类型 + JSON 字段是常见绕道方案。

### Informix：Named ROW Type 与 REF

Informix（IBM 的另一个产品）也是 OO 路线，支持 `REF`：

```sql
CREATE ROW TYPE person_t (
    name VARCHAR(50),
    age  INTEGER
);

CREATE ROW TYPE employee_t (
    person  person_t,
    boss    REF(employee_t)         -- 自引用
);
```

Informix 在企业级 OLTP 时代有不少应用，但市场份额已大幅萎缩。

### Teradata：UDT REFERENCE

Teradata 的结构化 UDT 通过 `REFERENCE` 关键字支持自引用：

```sql
CREATE TYPE node_t AS (
    value INTEGER,
    next  REFERENCE TO node_t
) INSTANTIABLE NOT FINAL;
```

实际部署中，自引用 UDT 在 Teradata 也较少见——客户更常用 adjacency list + WITH RECURSIVE。

### MySQL / MariaDB / SQLite / TiDB：完全不支持

MySQL 阵营从未提供 `CREATE TYPE` 风格的命名复合类型 DDL：

```sql
-- MySQL：报语法错误
CREATE TYPE node_t AS (value INT, next node_t);
```

这一阵营唯一的 "递归数据" 路径是：

1. **JSON 列**：MySQL 5.7+ 与 MariaDB 10.2+ 都支持 JSON。
2. **adjacency list 表 + WITH RECURSIVE**：MySQL 8.0+ 支持。
3. **应用层 ORM**：Hibernate / SQLAlchemy 把对象图序列化成 JSON 或多张表。

### CockroachDB / YugabyteDB：PG 兼容但无复合类型

PG 协议兼容的 CockroachDB 与 YugabyteDB 部分支持 PG 的 ROW 比较，但 CRDB 至今没有 `CREATE TYPE composite`。YugabyteDB 继承了 PG 的复合类型，但同样禁止递归。

## 解决 "需要递归" 的工程方案

### 方案 1：指针 / OID / REF

适用引擎：Oracle (REF), DB2 (REF), Informix (REF), Teradata (REFERENCE)。

```sql
-- Oracle
CREATE OR REPLACE TYPE node_t AS OBJECT (
    value INTEGER,
    next  REF node_t
);
```

优势：
- 类型层闭环——`node_t` 是固定大小的。
- 数据库原生支持，遍历可被优化器知道。
- 对象身份可比较（`o1.next = o2`）。

劣势：
- 行存数据库才能存 OID；列存引擎几乎没有 REF。
- DEREF 是随机 I/O，深递归代价高。
- 跨数据库迁移困难。

### 方案 2：adjacency list + 自引用外键

适用引擎：几乎所有支持外键的引擎。

```sql
CREATE TABLE node (
    id    INT PRIMARY KEY,
    value INT,
    next  INT REFERENCES node(id)
);

-- 遍历用 WITH RECURSIVE
WITH RECURSIVE chain AS (
    SELECT id, value, next FROM node WHERE id = $start
    UNION ALL
    SELECT n.id, n.value, n.next
    FROM node n JOIN chain c ON n.id = c.next
)
SELECT * FROM chain;
```

优势：
- 标准 SQL，无引擎特定语法。
- 可以加索引（`next` 列）。
- 增删节点不影响其他节点的物理存储。

劣势：
- 类型层无递归——形式上是 "ID 引用"。
- WITH RECURSIVE 在大树上性能不优。
- 不能在一行里直接看到子树（必须查询）。

### 方案 3：JSON / VARIANT 列

适用引擎：几乎所有现代引擎。

```sql
CREATE TABLE tree_doc (
    id   INT PRIMARY KEY,
    data JSONB                -- PG / MySQL / SQLite / DuckDB / ...
);
```

优势：
- 类型层完全不出现递归。
- 单行存整棵树，读取一次完成。
- 任意深度（受单值大小限制）。

劣势：
- 编译期无类型检查。
- JSON 解析有运行时开销。
- 难以索引深层字段（JSONB 支持 GIN，但跨字段查询仍然慢）。

### 方案 4：物化路径 (Materialized Path)

适用场景：树结构、不需要任意 graph。

```sql
CREATE TABLE tree (
    id    INT PRIMARY KEY,
    path  VARCHAR(500)        -- 例如 '/1/2/3'
);

-- 查询所有后代
SELECT * FROM tree WHERE path LIKE '/1/%';
```

PG 的 `ltree` 扩展、SQL Server 的 `hierarchyid` 都是这种思路的进阶版（参见 `hierarchyid-ltree-types.md`）。

### 方案 5：数组下标的 "扁平化树"

```sql
CREATE TABLE tree (
    id        INT,
    parent_id INT,
    children  INT[]           -- 子节点 ID 数组
);
```

PG/Vertica/CockroachDB 等支持 ARRAY 的引擎可用。优势是单行包含子节点列表，但仍然是 ID 引用而非真正的嵌套类型。

## JSON：通用的 "万能递归类型"

JSON 在事实上承担了 SQL 标准里 "递归类型" 这一角色。它的特殊性：

1. **运行时类型**：JSON 值的内部结构不在 DDL 暴露，类型系统天然支持任意嵌套。
2. **跨引擎统一**：几乎所有现代 SQL 引擎都支持 JSON。
3. **不参与代价模型**：优化器看 JSON 列是黑盒，索引必须显式建（GIN / 函数索引 / 倒排索引）。

各引擎的 JSON 递归处理对比：

| 引擎 | JSON 类型 | 路径访问 | 函数式更新 | 索引方案 |
|------|-----------|----------|-----------|---------|
| PostgreSQL | JSONB | `data->'a'->'b'` | `jsonb_set` | GIN |
| MySQL | JSON | `data->'$.a.b'` | `JSON_SET` | 函数索引 |
| MariaDB | JSON | `JSON_VALUE(...)` | `JSON_SET` | 函数索引 |
| SQL Server | NVARCHAR + 函数 | `JSON_VALUE` | `JSON_MODIFY` | 计算列 + 索引 |
| Oracle | JSON | `data.a.b` (dot) | `JSON_TRANSFORM` | JSON Search Index |
| SQLite | TEXT + JSON1 | `json_extract` | `json_set` | 表达式索引 |
| Snowflake | VARIANT | `data:a:b` | -- | 无索引 |
| BigQuery | JSON | `JSON_VALUE` | -- | 不支持索引 |
| Redshift | SUPER | `data.a.b` | -- | -- |
| DuckDB | JSON | `data->'a'->'b'` | -- | -- |
| ClickHouse | JSON | `data.a.b` | -- | -- |
| Trino | JSON | `json_extract_scalar` | -- | -- |
| Spark SQL | STRING + from_json | `from_json` | -- | -- |
| Vertica | VARCHAR + 函数 | `MAPLOOKUP` | -- | FLEX |

### 递归 JSON 查询的标准化

SQL:2016 引入了 JSON 路径表达式标准（`JSON_VALUE`, `JSON_QUERY`, `JSON_TABLE`, `IS JSON`），但**递归路径**至今没有标准化。各引擎的 "递归子查询 JSON" 写法五花八门：

```sql
-- PostgreSQL: 用 jsonb_path_query
SELECT jsonb_path_query(data, '$.** ? (@.name == "target")')
FROM tree_doc;

-- Oracle: JSON_TABLE 配合 NESTED PATH
SELECT *
FROM tree_doc t,
     JSON_TABLE(t.data, '$' COLUMNS (
         name VARCHAR2(50) PATH '$.name',
         NESTED PATH '$.children[*]' COLUMNS (
             child_name VARCHAR2(50) PATH '$.name'
         )
     ));

-- BigQuery: 递归 SQL 函数 + UNNEST
WITH RECURSIVE walk AS (
    SELECT data AS node, 0 AS depth FROM tree_doc
    UNION ALL
    SELECT JSON_QUERY_ARRAY(node, '$.children'), depth + 1
    FROM walk
    WHERE JSON_QUERY_ARRAY(node, '$.children') IS NOT NULL
)
SELECT * FROM walk;
```

这种 "JSON + 递归 CTE" 的组合是 45+ 引擎里最广泛可用的 "递归数据查询" 方案。

## BigQuery / Spark 嵌套 STRUCT 的设计哲学

BigQuery（基于 Google Dremel 论文）和 Spark（基于 Parquet 的 Dremel 复刻）走的是完全不同的路：

### Dremel / Capacitor 模型

Google Dremel 的核心洞察：**列存可以直接表达嵌套结构**，无需关系展开。一个嵌套字段 `addr.city` 在 Capacitor 文件里是独立的一列，带 definition level（标记哪一层是 NULL）和 repetition level（标记数组边界）。

```text
扁平: id | name | city | zip
       1 | Alice | SF   | 94016

嵌套: id | name  | addr.city | addr.zip
       1 | Alice | SF        | 94016
```

物理上等价，但嵌套表达的语义更接近业务对象：

```sql
SELECT addr.city, COUNT(*)
FROM users
GROUP BY addr.city;        -- 无 JOIN，直接访问嵌套列
```

### 嵌套深度的工程权衡

为什么 BigQuery 限制 STRUCT 深度 15 层？三个理由：

1. **schema 序列化大小**：每层 STRUCT 增加 schema 元数据，深嵌套的 schema 文本可能膨胀。
2. **优化器**：列剪裁、谓词下推都要在 schema 树上递归走——栈深度有限。
3. **学术经验**：Dremel 论文里给出的工业测试集，嵌套深度极少超过 7-8 层。15 层是 "工程上够用 + 不至于压垮系统" 的折中。

Spark 没有显式深度上限，但 Catalyst 优化器在分析嵌套类型时同样面临栈深度问题。实际部署里，超过 20 层的嵌套 schema 已经罕见。

### ARRAY<STRUCT> 模式

最常见的 "嵌套表" 模式：

```sql
-- BigQuery
CREATE TABLE orders (
    order_id INT64,
    items ARRAY<STRUCT<
        sku   STRING,
        qty   INT64,
        price NUMERIC
    >>
);

-- 查询：UNNEST 展开
SELECT o.order_id, item.sku, item.qty
FROM orders o, UNNEST(items) item;
```

Spark / Hive / Trino / DuckDB / ClickHouse 等都有等价语法，统称 "嵌套关系模型" 或 "Dremel 模型"。这是分析型 SQL 引擎的标志特征。

## 关键发现

1. **SQL 标准统一禁止结构化 UDT 直接递归**：SQL:1999 的 General Rules 明确规定结构化类型不允许形成有向环。45+ 引擎里没有一个支持 `CREATE TYPE foo AS (next foo)`——这是 30 年来最一致的工程妥协。

2. **REF 类型是 SQL 标准的官方解药**：SQL:2003 引入 `REF(structured-type)`，把 "结构内嵌" 转化为 "标识链接"。Oracle 8i (1999)、DB2、Informix、Teradata 沿用此模型；这是面向对象数据库时代的遗产。

3. **PostgreSQL 没有 REF**：PG 是复合类型最完整的开源引擎，但偏偏没实现 REF——其哲学是 "用关系（外键）表达对象身份"。这让 PG 在递归类型上严格禁止，开发者必须走 adjacency list 或 JSONB。

4. **BigQuery STRUCT 深度上限 15**：BigQuery 官方文档明确给出嵌套 STRUCT 上限。这不是真递归，而是 "有限深度的预定义嵌套"——在 schema 已知的业务场景里足够，但需要任意深度时必须改用 JSON。

5. **JSON 是事实上的通用递归类型**：几乎所有现代 SQL 引擎都支持 JSON / JSONB / VARIANT / OBJECT，运行时任意嵌套。SQL:2016 的 JSON 路径标准统一了访问语法，但**递归路径查询**仍然没有跨引擎标准。

6. **SQL Server 的 CLR UDT 是另类解药**：把递归外包给 .NET 类型系统——和 Oracle REF 的引擎原生路线完全相反，但也提供了 SQL Server 在企业级递归数据上的最强工具（hierarchyid 就是其代表作）。

7. **MySQL 阵营全员缺席**：MySQL/MariaDB/SQLite/TiDB 既无 `CREATE TYPE`，也无 REF，更无嵌套 STRUCT。它们的 "递归数据" 全靠 JSON 列 + WITH RECURSIVE——这与它们对 OLTP 简单性的执着一脉相承。

8. **分析引擎统一选择 "有限深度嵌套 + JSON 兜底"**：BigQuery / Spark / DuckDB / ClickHouse / Trino / Snowflake 等没有命名 UDT，但 STRUCT/ROW/Tuple 可深嵌套；当业务超过这一深度时，统一退化到 JSON。这是 "类型严谨性 vs 嵌套灵活性" 的工程平衡。

9. **Oracle 是 REF 路线的事实标准**：Oracle 8i (1999) 至今 25 年的 REF 实现是 SQL 标准 "对象引用" 的唯一大规模生产部署。OceanBase 的 Oracle 兼容模式是这一血脉的延续。

10. **互递归比直接递归更被忽视**：SQL 标准里互递归与直接递归同等被禁；只有 Oracle / DB2 / Informix 通过 REF + forward declaration 显式支持。BigQuery / Spark 等连互递归 schema 都无法表达。

11. **WITH RECURSIVE 是事实上的 "数据层递归"**：当类型层无法表达递归时，递归 CTE 是唯一标准化的递归查询语法（SQL:1999）。adjacency list + WITH RECURSIVE 是 45+ 引擎里最通用的递归方案——但它不是 "类型递归"，而是 "查询递归"。

12. **递归 SQL 函数几乎不被支持**：PG / Oracle / SQL Server / DB2 等可以在 PL/SQL / T-SQL 里写递归函数；但纯 SQL UDF 在大多数引擎里都不允许递归调用（Snowflake、BigQuery 的 UDF 明确禁止）。这进一步把递归推向 WITH RECURSIVE 这一 "声明式递归"。

13. **嵌套 STRUCT 重塑了分析引擎的 schema 设计**：`ARRAY<STRUCT<...>>` 取代 1:N 表 + JOIN 是 Dremel/BigQuery/Spark 的核心抽象。这从根本上改变了 OLAP 的 schema 设计哲学——但代价是嵌套深度上限与运行时灵活性之间的永恒权衡。

14. **"递归类型" 是 SQL 标准与现代数据现实的最大裂缝之一**：JSON 的事实标准化、Dremel 模型的工业普及、应用层 ORM 对对象图的需求，都让 SQL:1999 的 "禁止递归" 显得过时。但标准化机构的保守与各引擎的兼容性顾虑，让这一裂缝在可见的未来仍将存在。

15. **45+ 引擎可以划成五大阵营**：
    - **REF 派**（Oracle/DB2/Informix/Teradata/SQL Server CLR）：标准对象引用，类型层闭环。
    - **PG 派**（PostgreSQL/Greenplum/CockroachDB/YugabyteDB/TimescaleDB/Materialize/Yellowbrick）：禁递归 + JSONB 兜底。
    - **嵌套分析派**（BigQuery/Spark/DuckDB/ClickHouse/Trino/Snowflake/Hive/Impala/StarRocks/Doris/Athena/Databricks/Flink/Vertica/RisingWave/Spanner）：有限深度嵌套 + JSON 兜底。
    - **MySQL 派**（MySQL/MariaDB/SQLite/TiDB/SingleStore）：完全无 CREATE TYPE，全靠 JSON 列。
    - **缺位派**（H2/Firebird/Derby/Exasol/QuestDB/Firebolt/InfluxDB 等）：连 JSON 嵌套都不完善，递归数据基本无解。

16. **"类型递归" 与 "数据递归" 是两个独立维度**：SQL 标准与 45+ 引擎的实践都在告诉我们——类型层不允许递归，是为了存储模型与类型系统的简洁；数据层允许递归，是为了表达业务现实。两者通过 JSON、REF、adjacency list 等机制连接。理解这一分层是 SQL 引擎开发者的核心素养。

递归类型不像 ROW 类型那样被广泛讨论，也不像层次数据类型那样有标志性产品（hierarchyid / ltree）。但它恰恰是关系模型与对象模型、SQL 标准与现实数据、强类型与灵活 schema 之间最隐蔽却最根本的张力点——读懂它，就能更好地理解为什么现代 SQL 同时拥有 `CREATE TYPE`、`STRUCT`、`JSON`、`REF`、`WITH RECURSIVE` 这五类看似冗余但各有所长的能力。

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-2:1999, Section 4.8 (User-defined types) 与 Section 11.39 (`<user-defined type definition>`)
- SQL:2003 标准: ISO/IEC 9075-2:2003, REF Type 与 Object Reference 章节
- Oracle: [Object-Relational Features](https://docs.oracle.com/en/database/oracle/oracle-database/19/adobj/index.html)
- Oracle: [REF Type](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Object-REF-Operators.html)
- IBM DB2: [Structured Types](https://www.ibm.com/docs/en/db2/11.5?topic=types-structured)
- BigQuery: [STRUCT Type and Nesting Limits](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#struct_type)
- BigQuery: [Working with Nested and Repeated Data](https://cloud.google.com/bigquery/docs/nested-repeated)
- Snowflake: [Semi-Structured Data: VARIANT](https://docs.snowflake.com/en/sql-reference/data-types-semistructured)
- ClickHouse: [Tuple Type](https://clickhouse.com/docs/en/sql-reference/data-types/tuple) / [Nested](https://clickhouse.com/docs/en/sql-reference/data-types/nested-data-structures/nested)
- DuckDB: [STRUCT and LIST Types](https://duckdb.org/docs/sql/data_types/struct)
- Spark SQL: [StructType](https://spark.apache.org/docs/latest/api/scala/org/apache/spark/sql/types/StructType.html)
- Trino: [ROW Type](https://trino.io/docs/current/language/types.html#row)
- Microsoft: [CLR User-Defined Types](https://learn.microsoft.com/en-us/sql/relational-databases/clr-integration-database-objects-user-defined-types/clr-user-defined-types)
- Melnik et al., "Dremel: Interactive Analysis of Web-Scale Datasets" (VLDB 2010)
- Date, C. J., "An Introduction to Database Systems" 8th ed. - Chapter on User-Defined Types
- Stonebraker, M., "Object-Relational DBMSs: The Next Great Wave" (1996)
