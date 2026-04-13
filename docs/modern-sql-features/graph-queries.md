# 图查询 (Graph Queries in SQL)

图（Graph）是现实世界中最普遍的数据模型之一——社交网络、知识图谱、供应链、欺诈检测、推荐系统——都天然具备节点（Node）和边（Edge）的结构。传统关系模型需要通过 JOIN 和递归 CTE 来"模拟"图遍历，而 SQL:2023 引入的 SQL/PGQ（Property Graph Queries）标准则试图将图查询原生嵌入 SQL 体系。本文面向 SQL 引擎开发者，全面对比 45+ 种 SQL 方言在图查询能力上的现状：从 SQL/PGQ 标准到专有 MATCH 语法，从 Oracle CONNECT BY 到 SQL Server 图表，从 Apache AGE 扩展到递归 CTE 图遍历方案。

---

## 1. 标准与规范

### 1.1 SQL/PGQ (SQL:2023)

SQL:2023（ISO/IEC 9075-16:2023）正式引入 SQL/PGQ（Property Graph Queries），这是 SQL 标准首次将图查询作为一等公民纳入。核心概念：

- **GRAPH_TABLE 表达式**: 在 FROM 子句中使用，将图模式匹配的结果转为关系表
- **CREATE PROPERTY GRAPH**: 声明性地将关系表映射为属性图
- **MATCH 子句**: 使用 ASCII-art 风格的路径模式描述图遍历
- **路径模式**: `(a)-[e]->(b)` 表示从节点 a 经边 e 到节点 b

```sql
-- SQL/PGQ 标准语法（SQL:2023）
-- 第一步：定义属性图
CREATE PROPERTY GRAPH my_graph
    VERTEX TABLES (
        persons KEY (person_id)
            LABEL Person PROPERTIES (person_id, name, age),
        cities  KEY (city_id)
            LABEL City  PROPERTIES (city_id, city_name)
    )
    EDGE TABLES (
        knows
            SOURCE KEY (person1_id) REFERENCES persons (person_id)
            DESTINATION KEY (person2_id) REFERENCES persons (person_id)
            LABEL Knows PROPERTIES (since),
        lives_in
            SOURCE KEY (person_id) REFERENCES persons (person_id)
            DESTINATION KEY (city_id) REFERENCES cities (city_id)
            LABEL LivesIn
    );

-- 第二步：在 FROM 中使用 GRAPH_TABLE 进行图模式匹配
SELECT *
FROM GRAPH_TABLE (my_graph
    MATCH (p1:Person)-[:Knows]->(p2:Person)-[:LivesIn]->(c:City)
    WHERE p1.name = 'Alice'
    COLUMNS (p2.name AS friend_name, c.city_name AS city)
);
```

### 1.2 ISO GQL (Graph Query Language)

ISO GQL（ISO/IEC 39075:2024）是独立于 SQL 的图查询语言标准，与 SQL/PGQ 共享相同的路径模式语法。二者的关系：

```
SQL/PGQ:  SQL 的扩展，在 SELECT...FROM 中嵌入图模式匹配
ISO GQL:  独立的图查询语言，面向原生图数据库（Neo4j、TigerGraph 等）

共同点:   路径模式语法一致 —— (a)-[e]->(b)
区别:     SQL/PGQ 将图结果转为关系表（COLUMNS 子句）
          GQL 直接操作图结构（返回路径、子图等）
```

### 1.3 与递归 CTE 的关系

在 SQL/PGQ 出现之前，递归 CTE（SQL:1999）是 SQL 标准中唯一的图遍历机制。参见 [cte-recursive-query.md](cte-recursive-query.md) 的完整分析。

```
递归 CTE:
  - SQL:1999 标准，广泛支持
  - 通用的迭代计算，可用于图遍历但非专为图设计
  - 需要用户手动处理循环检测、路径追踪
  - 性能：每轮迭代执行一次 JOIN，深度 N 的遍历需要 N 轮

SQL/PGQ:
  - SQL:2023 标准，极少引擎支持
  - 专为图模式匹配设计
  - 内置路径模式、可变长路径、最短路径
  - 引擎可使用专用图索引和遍历算法优化
```

---

## 2. 图查询支持总览

### 2.1 SQL/PGQ 与原生图语法支持矩阵

| 引擎 | SQL/PGQ (GRAPH_TABLE) | CREATE PROPERTY GRAPH | 专有 MATCH 语法 | 原生图表模型 | 版本/备注 |
|------|----------------------|----------------------|----------------|------------|----------|
| PostgreSQL | ❌ | ❌ | ❌ (需 AGE 扩展) | ❌ | 通过 Apache AGE 扩展支持 Cypher |
| MySQL | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| MariaDB | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| SQLite | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Oracle | ✅ | ✅ | ✅ | ❌ | 23ai+ (2024): SQL/PGQ 完整支持 |
| SQL Server | ❌ | ❌ | ✅ | ✅ (NODE/EDGE) | 2017+: 专有图表语法 |
| DB2 | ❌ | ❌ | ❌ | ❌ | 无原生图查询 |
| Snowflake | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| BigQuery | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Redshift | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| DuckDB | ❌ | ❌ | ❌ | ❌ | 无原生图查询；有实验性 PGQ 讨论 |
| ClickHouse | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Trino | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Presto | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Spark SQL | ❌ | ❌ | ❌ | ❌ | GraphX 是独立 API，非 SQL |
| Hive | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Flink SQL | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Databricks | ❌ | ❌ | ❌ | ❌ | GraphFrames 是独立 API，非 SQL |
| Teradata | ❌ | ❌ | ❌ | ❌ | 无原生图查询 |
| Greenplum | ❌ | ❌ | ❌ (需 AGE 扩展) | ❌ | 可通过 AGE 扩展 |
| CockroachDB | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| TiDB | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| OceanBase | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| YugabyteDB | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| SingleStore | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Vertica | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Impala | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| StarRocks | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Doris | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| MonetDB | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| CrateDB | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| TimescaleDB | ❌ | ❌ | ❌ (需 AGE 扩展) | ❌ | 继承 PostgreSQL，可加 AGE |
| QuestDB | ❌ | ❌ | ❌ | ❌ | 时序数据库，无图能力 |
| Exasol | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| SAP HANA | ❌ | ❌ | ❌ | ✅ (Graph Workspace) | 专有图工作空间语法 |
| Informix | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Firebird | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| H2 | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| HSQLDB | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Derby | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Amazon Athena | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Azure Synapse | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Google Spanner | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Materialize | ❌ | ❌ | ❌ | ❌ | 流数据库，无图能力 |
| RisingWave | ❌ | ❌ | ❌ | ❌ | 流数据库，无图能力 |
| InfluxDB | ❌ | ❌ | ❌ | ❌ | 时序数据库，无图能力 |
| DatabendDB | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Yellowbrick | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |
| Firebolt | ❌ | ❌ | ❌ | ❌ | 无图查询能力 |

**关键发现**: 截至 2025 年，只有 Oracle 23ai 实现了 SQL/PGQ 标准。SQL Server 有独立的图表模型（2017+）但不遵循 SQL/PGQ。SAP HANA 有 Graph Workspace 但也是专有方案。绝大多数 SQL 引擎没有原生图查询能力，需要依赖递归 CTE 或外部扩展。

---

### 2.2 递归 CTE 图遍历支持矩阵

递归 CTE 是大多数 SQL 引擎中进行图遍历的唯一标准手段。详细的递归 CTE 支持情况参见 [cte-recursive-query.md](cte-recursive-query.md)，此处仅列出与图遍历直接相关的能力。

| 引擎 | 递归 CTE | CYCLE 检测 | SEARCH 排序 | 路径追踪 | 默认限制 | 图遍历可行性 |
|------|---------|-----------|------------|---------|---------|------------|
| PostgreSQL | ✅ | ✅ (14+) | ✅ (14+) | 手动 | 无限制 | 优秀 |
| MySQL | ✅ | ❌ | ❌ | 手动 | 1000（`cte_max_recursion_depth`） | 良好 |
| MariaDB | ✅ | ❌ | ❌ | 手动 | 1000（`max_recursive_iterations`） | 良好 |
| SQLite | ✅ | ❌ | ❌ | 手动 | 1000 | 良好 |
| Oracle | ✅ | ✅ | ✅ | 内置 | 无限制 | 优秀（也有 CONNECT BY） |
| SQL Server | ✅ | ❌ | ❌ | 手动 | 100（`OPTION (MAXRECURSION N)`，0 表示无限制） | 有限（深度限制） |
| DB2 | ✅ | ✅ | ✅ | 手动 | 无限制 | 优秀 |
| Snowflake | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| BigQuery | ✅ | ❌ | ❌ | 手动 | 500 | 良好 |
| Redshift | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| DuckDB | ✅ | ✅ (0.8+) | ✅ (0.8+) | 手动 | 无限制 | 优秀 |
| ClickHouse | ⚠️ (24.3+) | ❌ | ❌ | 手动 | -- | 有限（实验性） |
| Trino | ✅ | ❌ | ❌ | 手动 | 10 | 有限（深度限制） |
| Presto | ⚠️ | ❌ | ❌ | 手动 | -- | 有限 |
| Spark SQL | ❌ | -- | -- | -- | -- | 不可行 |
| Hive | ❌ | -- | -- | -- | -- | 不可行 |
| Flink SQL | ❌ | -- | -- | -- | -- | 不可行 |
| Databricks | ⚠️ | ❌ | ❌ | -- | -- | 有限 |
| Teradata | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| Greenplum | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| CockroachDB | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| TiDB | ✅ | ❌ | ❌ | 手动 | 1000 | 良好 |
| OceanBase | ✅ | ❌ | ❌ | 手动 | 1000 | 良好 |
| YugabyteDB | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| SingleStore | ❌ | -- | -- | -- | -- | 不可行 |
| Vertica | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| Impala | ❌ | -- | -- | -- | -- | 不可行 |
| StarRocks | ❌ | -- | -- | -- | -- | 不可行 |
| Doris | ❌ | -- | -- | -- | -- | 不可行 |
| MonetDB | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| CrateDB | ❌ | -- | -- | -- | -- | 不可行 |
| TimescaleDB | ✅ | ✅ (14+) | ✅ (14+) | 手动 | 无限制 | 优秀（继承 PG） |
| QuestDB | ❌ | -- | -- | -- | -- | 不可行 |
| Exasol | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| SAP HANA | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| Informix | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| Firebird | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| H2 | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| HSQLDB | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| Derby | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| Amazon Athena | ✅ | ❌ | ❌ | 手动 | 10 | 有限（继承 Trino） |
| Azure Synapse | ✅ | ❌ | ❌ | 手动 | 100 | 有限（继承 SQL Server） |
| Google Spanner | ❌ | -- | -- | -- | -- | 不可行 |
| Materialize | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好（但增量维护） |
| RisingWave | ❌ | -- | -- | -- | -- | 不可行 |
| InfluxDB | ❌ | -- | -- | -- | -- | 不可行 |
| DatabendDB | ❌ | -- | -- | -- | -- | 不可行 |
| Yellowbrick | ✅ | ❌ | ❌ | 手动 | 无限制 | 良好 |
| Firebolt | ❌ | -- | -- | -- | -- | 不可行 |

---

### 2.3 CONNECT BY (Oracle 层级查询) 支持矩阵

Oracle CONNECT BY 是最早的 SQL 层级/图遍历方案（1979 年），后被部分引擎采纳。

| 引擎 | CONNECT BY | START WITH | LEVEL 伪列 | SYS_CONNECT_BY_PATH | CONNECT_BY_ROOT | CONNECT_BY_ISLEAF | PRIOR | NOCYCLE | 版本 |
|------|-----------|------------|-----------|---------------------|----------------|-------------------|-------|---------|------|
| Oracle | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 2+ (1979) |
| DB2 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | 9.7+ |
| Databricks | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | Runtime 11.2+ |
| Snowflake | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | GA |
| OceanBase | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Oracle 模式 |
| SAP HANA | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | 1.0+ |
| Informix | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | 12.10+ |
| H2 | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | 1.4+ |
| HSQLDB | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | 2.4+ |
| PostgreSQL | ❌ | -- | -- | -- | -- | -- | -- | -- | 使用递归 CTE |
| MySQL | ❌ | -- | -- | -- | -- | -- | -- | -- | 使用递归 CTE |
| SQL Server | ❌ | -- | -- | -- | -- | -- | -- | -- | 使用递归 CTE |
| MariaDB | ❌ | -- | -- | -- | -- | -- | -- | -- | 使用递归 CTE |
| SQLite | ❌ | -- | -- | -- | -- | -- | -- | -- | 使用递归 CTE |
| BigQuery | ❌ | -- | -- | -- | -- | -- | -- | -- | 使用递归 CTE |
| DuckDB | ❌ | -- | -- | -- | -- | -- | -- | -- | 使用递归 CTE |

**关键发现**: CONNECT BY 主要流行于 Oracle 及其兼容引擎（DB2、OceanBase Oracle 模式）。Snowflake 和 Databricks 的支持主要为了方便 Oracle 迁移。新引擎不应实现 CONNECT BY，而应优先支持递归 CTE（SQL 标准）。

---

### 2.4 最短路径查询支持矩阵

最短路径是图查询中最核心的算法需求之一。

| 引擎 | 内置最短路径 | 方法 | 语法 | 版本/备注 |
|------|------------|------|------|----------|
| Oracle | ✅ | SQL/PGQ SHORTEST | `MATCH SHORTEST (a)-[*]->(b)` | 23ai+ |
| SQL Server | ⚠️ | SHORTEST_PATH 函数 | `MATCH ... SHORTEST_PATH(...)` | 2019+ |
| SAP HANA | ✅ | Graph Workspace | `SHORTEST_PATH(...)` | 2.0 SPS03+ |
| PostgreSQL + AGE | ✅ | Cypher via AGE | `shortestPath()` | AGE 1.0+ |
| Neo4j (Cypher) | ✅ | 内置函数 | `shortestPath((a)-[*]-(b))` | 原生 |
| PostgreSQL | ❌ | 递归 CTE 模拟 | 手动实现 BFS | -- |
| MySQL | ❌ | 递归 CTE 模拟 | 手动实现 BFS | 8.0+ |
| BigQuery | ❌ | 递归 CTE 模拟 | 手动实现 BFS | -- |
| Snowflake | ❌ | 递归 CTE 模拟 | 手动实现 BFS | -- |
| DuckDB | ❌ | 递归 CTE 模拟 | 手动实现 BFS | -- |
| 其他引擎 | ❌ | 递归 CTE 或应用层 | -- | -- |

---

### 2.5 Cypher 集成与图扩展支持矩阵

Neo4j 的 Cypher 查询语言通过 Apache AGE 等扩展进入了 SQL 生态。

| 引擎 | 扩展/方式 | Cypher 支持 | 部署方式 | 版本/备注 |
|------|----------|------------|---------|----------|
| PostgreSQL | Apache AGE | ✅ | 扩展 (CREATE EXTENSION) | AGE 1.0+；PostgreSQL 11-16 |
| Greenplum | Apache AGE | ✅ | 扩展 | 社区移植 |
| TimescaleDB | Apache AGE | ✅ | 扩展 | 继承 PostgreSQL |
| YugabyteDB | Apache AGE | ⚠️ | 实验性 | 社区讨论中 |
| DuckDB | -- | ❌ | -- | 无 Cypher 扩展 |
| MySQL | -- | ❌ | -- | 无 Cypher 扩展 |
| SQL Server | -- | ❌ | -- | 使用自有 MATCH 语法 |
| Oracle | -- | ❌ | -- | 使用 SQL/PGQ |
| SAP HANA | -- | ❌ | -- | 使用 Graph Workspace |

---

## 3. 各引擎详细语法

### 3.1 Oracle 23ai: SQL/PGQ 完整实现

Oracle 23ai（2024）是第一个实现 SQL/PGQ 标准的主流商业数据库。

#### 创建属性图

```sql
-- Oracle 23ai: CREATE PROPERTY GRAPH
CREATE PROPERTY GRAPH financial_graph
    VERTEX TABLES (
        accounts KEY (account_id)
            LABEL Account
            PROPERTIES (account_id, holder_name, balance),
        branches KEY (branch_id)
            LABEL Branch
            PROPERTIES (branch_id, branch_name, city)
    )
    EDGE TABLES (
        transfers
            SOURCE KEY (src_account) REFERENCES accounts (account_id)
            DESTINATION KEY (dst_account) REFERENCES accounts (account_id)
            LABEL Transfer
            PROPERTIES (transfer_id, amount, transfer_date),
        account_branch
            SOURCE KEY (account_id) REFERENCES accounts (account_id)
            DESTINATION KEY (branch_id) REFERENCES branches (branch_id)
            LABEL BelongsTo
    );
```

#### GRAPH_TABLE 查询

```sql
-- 查找所有直接转账路径
SELECT *
FROM GRAPH_TABLE (financial_graph
    MATCH (src:Account)-[t:Transfer]->(dst:Account)
    WHERE t.amount > 10000
    COLUMNS (
        src.holder_name AS sender,
        dst.holder_name AS receiver,
        t.amount,
        t.transfer_date
    )
) AS transfers
ORDER BY transfers.amount DESC;

-- 可变长路径: 查找 1-3 跳的转账链路
SELECT *
FROM GRAPH_TABLE (financial_graph
    MATCH (src:Account)-[t:Transfer]->{1,3}(dst:Account)
    WHERE src.holder_name = 'Alice'
    COLUMNS (
        dst.holder_name AS reachable_account,
        LISTAGG(t.amount, '->') AS transfer_chain
    )
);

-- 最短路径
SELECT *
FROM GRAPH_TABLE (financial_graph
    MATCH SHORTEST (src:Account)-[t:Transfer]->{1,5}(dst:Account)
    WHERE src.holder_name = 'Alice' AND dst.holder_name = 'Bob'
    COLUMNS (
        COUNT(t.transfer_id) AS hop_count,
        SUM(t.amount) AS total_amount
    )
);
```

#### Oracle CONNECT BY（传统层级查询）

```sql
-- CONNECT BY: Oracle 最早的层级查询语法（1979 年至今）
SELECT
    employee_id,
    name,
    manager_id,
    LEVEL AS depth,
    SYS_CONNECT_BY_PATH(name, '/') AS path,
    CONNECT_BY_ISLEAF AS is_leaf,
    CONNECT_BY_ROOT name AS root_name
FROM employees
START WITH manager_id IS NULL
CONNECT BY NOCYCLE PRIOR employee_id = manager_id
ORDER SIBLINGS BY name;

-- LEVEL: 当前节点在树中的深度（根为 1）
-- SYS_CONNECT_BY_PATH: 从根到当前节点的路径
-- CONNECT_BY_ROOT: 获取根节点列值
-- CONNECT_BY_ISLEAF: 叶子节点标志（1=叶子，0=非叶子）
-- NOCYCLE: 检测到循环时停止该分支，避免无限递归
-- ORDER SIBLINGS BY: 同层节点的排序
```

### 3.2 SQL Server: 图表 (Graph Tables)

SQL Server 2017 引入了专有的图数据库功能，使用 `AS NODE` 和 `AS EDGE` 定义图表。

#### 创建图表

```sql
-- SQL Server 2017+: 创建节点表和边表
CREATE TABLE Person (
    ID INT PRIMARY KEY,
    Name NVARCHAR(100),
    Age INT
) AS NODE;
-- AS NODE 会自动添加 $node_id 列（内部标识符）

CREATE TABLE City (
    CityID INT PRIMARY KEY,
    CityName NVARCHAR(100)
) AS NODE;

CREATE TABLE Knows (
    Since DATE,
    Strength INT
) AS EDGE;
-- AS EDGE 会自动添加 $from_id, $to_id, $edge_id 列

CREATE TABLE LivesIn AS EDGE;

-- 插入数据
INSERT INTO Person (ID, Name, Age) VALUES (1, 'Alice', 30), (2, 'Bob', 25);
INSERT INTO City (CityID, CityName) VALUES (1, 'Beijing');

-- 边的插入: 需要通过 $node_id 引用节点
INSERT INTO Knows ($from_id, $to_id, Since, Strength)
    SELECT p1.$node_id, p2.$node_id, '2020-01-01', 5
    FROM Person p1, Person p2
    WHERE p1.Name = 'Alice' AND p2.Name = 'Bob';

INSERT INTO LivesIn ($from_id, $to_id)
    SELECT p.$node_id, c.$node_id
    FROM Person p, City c
    WHERE p.Name = 'Alice' AND c.CityName = 'Beijing';
```

#### MATCH 查询

```sql
-- SQL Server MATCH 语法（非 SQL/PGQ 标准）
-- 基本模式匹配
SELECT
    p1.Name AS person,
    p2.Name AS friend,
    k.Since
FROM
    Person p1, Knows k, Person p2
WHERE MATCH(p1-(k)->p2);

-- 多跳查询: 朋友的朋友
SELECT
    p1.Name AS person,
    p3.Name AS friend_of_friend
FROM
    Person p1, Knows k1, Person p2,
    Knows k2, Person p3
WHERE MATCH(p1-(k1)->p2-(k2)->p3)
  AND p1.Name <> p3.Name;

-- SQL Server 2019+: SHORTEST_PATH
-- 查找从 Alice 出发可达的所有人及最短路径长度
SELECT
    p1.Name AS source,
    LAST_VALUE(p2.Name) WITHIN GROUP (GRAPH PATH) AS destination,
    COUNT(p2.Name) WITHIN GROUP (GRAPH PATH) AS hops
FROM
    Person p1, Knows FOR PATH k, Person FOR PATH p2
WHERE MATCH(SHORTEST_PATH(p1(-(k)->p2)+))
  AND p1.Name = 'Alice';
```

**SQL Server MATCH 与 SQL/PGQ 的区别**:

```
SQL Server MATCH:
  WHERE MATCH(a-(e)->b)          -- 箭头方向: -(e)->
  表必须在 FROM 中列出            -- 不能内联在 MATCH 中
  SHORTEST_PATH 用 FOR PATH 标记 -- 专有语法

SQL/PGQ MATCH:
  MATCH (a:Label)-[e:Label]->(b:Label)  -- 括号包裹，标签内联
  在 GRAPH_TABLE(...) 中使用              -- 独立的表表达式
  SHORTEST 是模式修饰符                   -- 标准语法
```

### 3.3 SAP HANA: Graph Workspace

SAP HANA 从 SPS03 起提供 Graph Workspace 作为图查询方案。

```sql
-- SAP HANA: 创建 Graph Workspace
CREATE GRAPH WORKSPACE my_graph
    EDGE TABLE edges
        SOURCE COLUMN source_id
        TARGET COLUMN target_id
        KEY COLUMN edge_id
    VERTEX TABLE vertices
        KEY COLUMN vertex_id;

-- 使用 Graph 计算视图进行图算法查询
-- SAP HANA 的图查询主要通过 GRAPH 脚本语言（GraphScript）执行
-- 而非直接在 SQL 中编写路径模式
CREATE PROCEDURE shortest_path_proc(
    IN start_id BIGINT,
    IN end_id BIGINT,
    OUT result TABLE(vertex_id BIGINT, edge_id BIGINT)
)
LANGUAGE GRAPH
READS SQL DATA
AS
BEGIN
    GRAPH g = Graph("SCHEMA", "MY_GRAPH");
    VERTEX v_start = Vertex(:g, :start_id);
    VERTEX v_end = Vertex(:g, :end_id);
    WeightedPath<BIGINT> p = SHORTEST_PATH(:g, :v_start, :v_end);
    result = SELECT :v.vertex_id, :e.edge_id FOREACH v IN Vertices(:p) WITH e IN Edges(:p);
END;

-- 调用
CALL shortest_path_proc(1, 100, ?);
```

**注意**: SAP HANA 的图查询使用 GraphScript（过程式语言）而非 SQL 内联语法。与 SQL/PGQ 的声明式方式有本质区别。

### 3.4 PostgreSQL + Apache AGE: Cypher in SQL

Apache AGE（A Graph Extension）是一个 PostgreSQL 扩展，允许在 SQL 查询中嵌入 Cypher 图查询语言。

```sql
-- 安装 AGE 扩展
CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- 创建图
SELECT create_graph('social_network');

-- 在 SQL 中嵌入 Cypher 创建节点和边
SELECT * FROM cypher('social_network', $$
    CREATE (alice:Person {name: 'Alice', age: 30})
    CREATE (bob:Person {name: 'Bob', age: 25})
    CREATE (alice)-[:KNOWS {since: 2020}]->(bob)
    RETURN alice, bob
$$) AS (a agtype, b agtype);

-- 图查询: 使用 Cypher 语法
SELECT * FROM cypher('social_network', $$
    MATCH (p1:Person)-[:KNOWS]->(p2:Person)
    WHERE p1.name = 'Alice'
    RETURN p2.name AS friend, p2.age AS age
$$) AS (friend agtype, age agtype);

-- 可变长路径
SELECT * FROM cypher('social_network', $$
    MATCH path = (p1:Person)-[:KNOWS*1..3]->(p2:Person)
    WHERE p1.name = 'Alice'
    RETURN p2.name AS reachable, length(path) AS hops
$$) AS (reachable agtype, hops agtype);

-- 最短路径
SELECT * FROM cypher('social_network', $$
    MATCH path = shortestPath((p1:Person)-[:KNOWS*]-(p2:Person))
    WHERE p1.name = 'Alice' AND p2.name = 'Charlie'
    RETURN path
$$) AS (path agtype);

-- AGE 的 Cypher 查询可以与 SQL 混合使用
SELECT employees.dept, graph_result.friend_count
FROM employees
JOIN (
    SELECT * FROM cypher('social_network', $$
        MATCH (p:Person)-[:KNOWS]->(friend:Person)
        RETURN p.name AS name, count(friend) AS friend_count
    $$) AS (name agtype, friend_count agtype)
) graph_result ON employees.name = graph_result.name::text;
```

### 3.5 递归 CTE 实现图遍历（通用方案）

对于不支持原生图查询的引擎，递归 CTE 是实现图遍历的标准方法。

#### 数据模型

```sql
-- 图的关系模型表示
CREATE TABLE vertices (
    vertex_id INT PRIMARY KEY,
    label VARCHAR(50),
    properties JSON  -- 或使用独立列
);

CREATE TABLE edges (
    edge_id INT PRIMARY KEY,
    source_id INT REFERENCES vertices(vertex_id),
    target_id INT REFERENCES vertices(vertex_id),
    label VARCHAR(50),
    weight DECIMAL(10,2)
);
```

#### 可达性查询（DFS/BFS）

```sql
-- PostgreSQL / Oracle / SQL Server / DB2 / DuckDB 等支持 `||` 字符串拼接的引擎
-- 从节点 1 出发可达的所有节点（带路径追踪和循环检测）
-- 注：MySQL 8.0+ 默认 sql_mode 下 `||` 表示逻辑 OR，需使用 `CONCAT(...)` 与 `CAST(... AS CHAR(N))`，
--     或先 `SET sql_mode='PIPES_AS_CONCAT'`
WITH RECURSIVE reachable AS (
    -- 锚成员: 起始节点（路径两端补上 `->` 分隔符，便于边界匹配）
    SELECT
        v.vertex_id,
        v.label,
        '->' || CAST(v.vertex_id AS VARCHAR(1000)) || '->' AS path,
        0 AS depth
    FROM vertices v
    WHERE v.vertex_id = 1

    UNION ALL

    -- 递归成员: 沿边遍历
    SELECT
        v.vertex_id,
        v.label,
        r.path || CAST(v.vertex_id AS VARCHAR(1000)) || '->',
        r.depth + 1
    FROM reachable r
    JOIN edges e ON r.vertex_id = e.source_id
    JOIN vertices v ON e.target_id = v.vertex_id
    -- 使用 `->id->` 作为边界匹配，避免节点 1 误匹配路径中的 11、21 等
    WHERE r.path NOT LIKE '%->' || CAST(v.vertex_id AS VARCHAR(10)) || '->%'
      AND r.depth < 10  -- 深度限制（安全阀）
)
SELECT * FROM reachable;
```

#### BFS 最短路径模拟

```sql
-- 使用递归 CTE 模拟 BFS 最短路径
-- 注意: 部分引擎的递归 CTE 仅支持 UNION ALL（如 Snowflake、TiDB；MySQL 8.0.19 之前亦是如此），
-- PostgreSQL / Oracle / SQL Server / DB2 / MySQL 8.0.19+ 等支持 UNION 去重。
-- 为兼容不同引擎，本示例统一采用 UNION ALL，并通过路径检查手动去重已访问节点，
-- 再在外层用 MIN(distance) 取最短距离
WITH RECURSIVE bfs AS (
    SELECT
        vertex_id,
        0 AS distance,
        CAST(vertex_id AS VARCHAR(1000)) AS path
    FROM vertices
    WHERE vertex_id = 1  -- 起点

    UNION ALL

    SELECT
        v.vertex_id,
        b.distance + 1,
        b.path || '->' || CAST(v.vertex_id AS VARCHAR(1000))
    FROM bfs b
    JOIN edges e ON b.vertex_id = e.source_id
    JOIN vertices v ON e.target_id = v.vertex_id
    WHERE b.distance < 10
      AND b.path NOT LIKE '%' || CAST(v.vertex_id AS VARCHAR(10)) || '%'  -- 手动去重
)
SELECT vertex_id, MIN(distance) AS shortest_distance
FROM bfs
GROUP BY vertex_id;
-- 注意: 严格来说这不是真正的 BFS，因为 CTE 的迭代顺序不保证广度优先
-- 但路径去重 + MIN(distance) 可以得到正确的最短距离
```

#### PostgreSQL 14+ 循环检测语法

```sql
-- PostgreSQL 14+: CYCLE 子句（SQL 标准）
WITH RECURSIVE traversal AS (
    SELECT vertex_id, label, ARRAY[vertex_id] AS path, 0 AS depth
    FROM vertices WHERE vertex_id = 1
    UNION ALL
    SELECT v.vertex_id, v.label, t.path || v.vertex_id, t.depth + 1
    FROM traversal t
    JOIN edges e ON t.vertex_id = e.source_id
    JOIN vertices v ON e.target_id = v.vertex_id
    WHERE t.depth < 20
)
CYCLE vertex_id SET is_cycle USING cycle_path
SELECT * FROM traversal WHERE NOT is_cycle;
-- CYCLE 子句自动检测 vertex_id 列的重复访问
-- is_cycle: 布尔标志，指示当前行是否形成循环
-- cycle_path: 记录导致循环的路径
```

#### Oracle CONNECT BY 图遍历

```sql
-- Oracle: CONNECT BY 用于层级查询（本质是树遍历）
-- 查找员工 100 的所有下属（树结构）
SELECT
    employee_id,
    name,
    LEVEL AS depth,
    SYS_CONNECT_BY_PATH(name, ' > ') AS hierarchy_path,
    CONNECT_BY_ISLEAF AS is_leaf
FROM employees
START WITH employee_id = 100
CONNECT BY PRIOR employee_id = manager_id
ORDER SIBLINGS BY name;

-- CONNECT BY 的局限:
-- 1. 仅支持单表（或视图）层级关系
-- 2. 不支持通用的多表图遍历
-- 3. 循环检测仅靠 NOCYCLE 关键字（标记但不处理）
-- 4. 无法指定可变长路径范围（如 1..3 跳）
```

### 3.6 DuckDB: 递归 CTE + 扩展模式

DuckDB 虽然没有原生图查询语法，但其递归 CTE 实现较为完整，包括 SEARCH 和 CYCLE 子句。

```sql
-- DuckDB: 递归 CTE 图遍历（支持 CYCLE 检测）
WITH RECURSIVE graph_walk AS (
    SELECT
        source_id AS current_node,
        target_id AS next_node,
        [source_id, target_id] AS path,
        1 AS hops
    FROM edges
    WHERE source_id = 1

    UNION ALL

    SELECT
        gw.next_node,
        e.target_id,
        list_append(gw.path, e.target_id),
        gw.hops + 1
    FROM graph_walk gw
    JOIN edges e ON gw.next_node = e.source_id
    WHERE NOT list_contains(gw.path, e.target_id)  -- DuckDB 列表函数检测循环
      AND gw.hops < 10
)
SELECT * FROM graph_walk;

-- DuckDB 0.8+: SEARCH 和 CYCLE 子句
WITH RECURSIVE reachable AS (
    SELECT vertex_id, label FROM vertices WHERE vertex_id = 1
    UNION ALL
    SELECT v.vertex_id, v.label
    FROM reachable r
    JOIN edges e ON r.vertex_id = e.source_id
    JOIN vertices v ON e.target_id = v.vertex_id
)
SEARCH BREADTH FIRST BY vertex_id SET ordercol
CYCLE vertex_id SET is_cycle USING cycle_path
SELECT * FROM reachable WHERE NOT is_cycle ORDER BY ordercol;
```

### 3.7 Spark SQL / Databricks: GraphFrames（非 SQL）

Spark SQL 本身不支持图查询语法，但 Spark 生态提供了 GraphFrames 库。

```python
# GraphFrames（Python API，非 SQL）
from graphframes import GraphFrame

# 从 DataFrame 创建图
vertices = spark.createDataFrame([
    ("1", "Alice", 30),
    ("2", "Bob", 25),
], ["id", "name", "age"])

edges = spark.createDataFrame([
    ("1", "2", "knows"),
    ("2", "3", "knows"),
], ["src", "dst", "relationship"])

g = GraphFrame(vertices, edges)

# 图算法
shortest_paths = g.shortestPaths(landmarks=["3"])
shortest_paths.show()

# BFS
bfs_result = g.bfs(fromExpr="name = 'Alice'", toExpr="name = 'Charlie'", maxPathLength=3)
bfs_result.show()

# 注意: 这是 Spark API，不是 SQL 语法
# Databricks SQL 本身不支持图查询
```

```sql
-- Databricks SQL: CONNECT BY（有限的层级查询）
SELECT
    employee_id,
    name,
    LEVEL
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id;
-- 仅支持基本语法，不支持 SYS_CONNECT_BY_PATH 等高级功能
```

### 3.8 SQL Server MATCH 完整示例

```sql
-- 欺诈检测场景: 查找可疑的环形转账链
-- SQL Server 2019+
CREATE TABLE Account (
    AccountID INT PRIMARY KEY,
    HolderName NVARCHAR(100),
    Balance DECIMAL(18,2)
) AS NODE;

CREATE TABLE Transfer (
    Amount DECIMAL(18,2),
    TransferDate DATE
) AS EDGE;

-- 查找三角转账 (A->B->C->A)
SELECT
    a1.HolderName AS account_1,
    a2.HolderName AS account_2,
    a3.HolderName AS account_3,
    t1.Amount AS transfer_1_amount,
    t2.Amount AS transfer_2_amount,
    t3.Amount AS transfer_3_amount
FROM
    Account a1, Transfer t1, Account a2,
    Transfer t2, Account a3, Transfer t3, Account a4
WHERE MATCH(a1-(t1)->a2-(t2)->a3-(t3)->a4)
  AND a1.AccountID = a4.AccountID  -- 形成环
  AND t1.Amount > 50000
  AND t2.Amount > 50000
  AND t3.Amount > 50000;

-- SQL Server 2019+: 任意长度路径遍历
SELECT
    a1.HolderName AS source,
    STRING_AGG(a2.HolderName, '->') WITHIN GROUP (GRAPH PATH) AS path,
    LAST_VALUE(a2.HolderName) WITHIN GROUP (GRAPH PATH) AS destination,
    SUM(t.Amount) WITHIN GROUP (GRAPH PATH) AS total_amount
FROM
    Account a1,
    Transfer FOR PATH t,
    Account FOR PATH a2
WHERE MATCH(SHORTEST_PATH(a1(-(t)->a2)+))
  AND a1.HolderName = 'Alice';
```

---

## 4. 路径枚举与循环检测

### 4.1 路径追踪方案对比

在图遍历中跟踪完整路径是常见需求。不同引擎的实现方式差异显著。

| 方案 | 适用引擎 | 语法 | 优点 | 缺点 |
|------|---------|------|------|------|
| 字符串拼接路径 | 几乎所有引擎 | `path \|\| '->' \|\| node_id` | 通用性最好 | 字符串匹配检测循环不精确 |
| 数组路径 | PostgreSQL, DuckDB | `path \|\| ARRAY[node_id]` | 精确的循环检测 | 部分引擎不支持数组 |
| JSON 数组 | MySQL, 支持 JSON 的引擎 | `JSON_ARRAY_APPEND(path, '$', node_id)` | 结构化 | JSON 操作开销 |
| CYCLE 子句 | PostgreSQL 14+, DuckDB 0.8+, DB2, Oracle | `CYCLE col SET flag USING path` | SQL 标准，自动检测 | 极少引擎支持 |
| SYS_CONNECT_BY_PATH | Oracle, DB2 | `SYS_CONNECT_BY_PATH(col, sep)` | 内置函数 | 仅 CONNECT BY 可用 |
| FOR PATH + GRAPH PATH | SQL Server | `FOR PATH ... WITHIN GROUP (GRAPH PATH)` | 与图表集成 | SQL Server 专有 |

### 4.2 各引擎路径追踪示例

```sql
-- PostgreSQL: 数组路径（推荐）
WITH RECURSIVE traverse AS (
    SELECT vertex_id, ARRAY[vertex_id] AS path
    FROM vertices WHERE vertex_id = 1
    UNION ALL
    SELECT e.target_id, t.path || e.target_id
    FROM traverse t
    JOIN edges e ON t.vertex_id = e.source_id
    WHERE e.target_id <> ALL(t.path)  -- 精确的数组成员检查
)
SELECT * FROM traverse;

-- MySQL 8.0+: 字符串拼接路径
WITH RECURSIVE traverse AS (
    SELECT vertex_id, CAST(vertex_id AS CHAR(1000)) AS path, 0 AS depth
    FROM vertices WHERE vertex_id = 1
    UNION ALL
    SELECT e.target_id, CONCAT(t.path, ',', e.target_id), t.depth + 1
    FROM traverse t
    JOIN edges e ON t.vertex_id = e.source_id
    WHERE FIND_IN_SET(e.target_id, t.path) = 0  -- CSV 风格循环检测
      AND t.depth < 100
)
SELECT * FROM traverse;

-- SQL Server: 字符串路径（受限于 MAXRECURSION 100）
WITH traverse AS (
    SELECT vertex_id, CAST(vertex_id AS VARCHAR(MAX)) AS path, 0 AS depth
    FROM vertices WHERE vertex_id = 1
    UNION ALL
    SELECT e.target_id, t.path + '->' + CAST(e.target_id AS VARCHAR(10)), t.depth + 1
    FROM traverse t
    JOIN edges e ON t.vertex_id = e.source_id
    WHERE CHARINDEX(CAST(e.target_id AS VARCHAR(10)), t.path) = 0
      AND t.depth < 50
)
SELECT * FROM traverse
OPTION (MAXRECURSION 100);

-- Oracle: CONNECT BY 路径
SELECT
    employee_id,
    SYS_CONNECT_BY_PATH(employee_id, '/') AS path,
    LEVEL AS depth
FROM employees
START WITH employee_id = 1
CONNECT BY NOCYCLE PRIOR employee_id = manager_id;
```

### 4.3 循环检测方案总结

| 引擎 | 循环检测方案 | 自动/手动 | 安全性 |
|------|------------|----------|--------|
| PostgreSQL 14+ | CYCLE 子句 | 自动 | 高 |
| DuckDB 0.8+ | CYCLE 子句 | 自动 | 高 |
| Oracle | CYCLE 子句 / NOCYCLE | 自动 | 高 |
| DB2 | CYCLE 子句 | 自动 | 高 |
| PostgreSQL (旧) | `node <> ALL(path_array)` | 手动 | 高 |
| MySQL | `FIND_IN_SET()` / 字符串匹配 | 手动 | 中（字符串匹配可能误判） |
| SQL Server | `CHARINDEX()` / 字符串匹配 | 手动 | 中 |
| SQLite | 字符串匹配 | 手动 | 中 |
| Snowflake | 字符串或数组匹配 | 手动 | 高（支持 ARRAY_CONTAINS） |
| BigQuery | 字符串匹配 | 手动 | 中 |

---

## 5. 递归 CTE vs 原生图查询

### 5.1 能力对比

```
递归 CTE（通用方案）:
  ✓ SQL 标准（SQL:1999），大多数引擎支持
  ✓ 可在不修改引擎的前提下使用
  ✓ 适合简单的树遍历和浅层图遍历
  ✗ 每轮迭代执行完整 JOIN，大图上性能差
  ✗ 用户需手动实现循环检测、路径追踪
  ✗ 不支持图特有算法（最短路径、PageRank、社区检测）
  ✗ 可变长路径需要固定上界（如 depth < 10）

原生图查询（SQL/PGQ / SQL Server MATCH / SAP HANA）:
  ✓ 声明式路径模式，语法简洁
  ✓ 引擎可使用专用索引和遍历算法
  ✓ 内置最短路径、可变长路径
  ✓ 循环检测由引擎自动处理
  ✗ 极少引擎支持（截至 2025 年仅 Oracle 23ai 实现 SQL/PGQ）
  ✗ 各引擎语法不兼容
  ✗ 需要专用表结构（NODE/EDGE）

外部图扩展（Apache AGE / GraphFrames）:
  ✓ 成熟的图查询语言（Cypher）
  ✓ 支持丰富的图算法
  ✓ 可与 SQL 混合使用
  ✗ 需要额外安装和维护
  ✗ 与宿主数据库的集成深度有限
  ✗ 可能存在数据一致性问题
```

### 5.2 性能特征

```
图的规模与遍历深度对性能的影响:

递归 CTE:
  - 遍历深度 d, 平均出度 k → 每轮 JOIN 处理 k^d 行
  - 深度 10, 出度 10 → 第 10 轮 JOIN 处理 10^10 = 100 亿行
  - 适合: 深度 < 5, 出度 < 10 的场景（组织结构、BOM）
  - 不适合: 社交网络、知识图谱等大规模稠密图

原生图遍历:
  - 使用邻接表索引，每步 O(k) 而非 O(N)
  - 可提前剪枝（发现目标即停止）
  - 最短路径用 BFS/Dijkstra，复杂度 O(V + E)
  - 适合: 任意规模的图遍历

推荐策略:
  深度 ≤ 3, 图规模 < 100K 边    → 递归 CTE 足够
  深度 > 5, 图规模 > 1M 边       → 考虑原生图引擎或扩展
  需要图算法（最短路径/PageRank） → 必须使用原生图方案
```

### 5.3 迁移策略

```sql
-- 场景: 从递归 CTE 迁移到 Oracle SQL/PGQ

-- 原始: 递归 CTE 版本（所有支持递归的引擎）
WITH RECURSIVE friends_of_friends AS (
    SELECT person_id, friend_id, 1 AS depth,
           CAST(person_id AS VARCHAR(1000)) || '->' || CAST(friend_id AS VARCHAR(10)) AS path
    FROM friendships WHERE person_id = 1
    UNION ALL
    SELECT f.person_id, fs.friend_id, f.depth + 1,
           f.path || '->' || CAST(fs.friend_id AS VARCHAR(10))
    FROM friends_of_friends f
    JOIN friendships fs ON f.friend_id = fs.person_id
    WHERE f.depth < 3
      AND f.path NOT LIKE '%' || CAST(fs.friend_id AS VARCHAR(10)) || '%'
)
SELECT DISTINCT friend_id, MIN(depth) AS shortest_depth
FROM friends_of_friends
GROUP BY friend_id;

-- 目标: SQL/PGQ 版本（Oracle 23ai）
SELECT *
FROM GRAPH_TABLE (social_graph
    MATCH (p:Person)-[:Knows]->{1,3}(f:Person)
    WHERE p.person_id = 1
    COLUMNS (f.person_id AS friend_id, path_length() AS depth)
);
-- 声明式、简洁、引擎自动优化路径遍历和循环检测
```

---

## 6. 特殊场景与高级模式

### 6.1 带权最短路径（Dijkstra 模拟）

```sql
-- 使用递归 CTE 模拟 Dijkstra 最短路径
-- 注意: 这不是真正的 Dijkstra，因为递归 CTE 不支持优先队列
-- 但对于小规模图，结果等价
-- PostgreSQL / DuckDB / MySQL 8.0+
WITH RECURSIVE dijkstra AS (
    SELECT
        target_id AS vertex_id,
        weight AS total_weight,
        ARRAY[source_id, target_id] AS path
    FROM edges
    WHERE source_id = 1  -- 起点

    UNION ALL

    SELECT
        e.target_id,
        d.total_weight + e.weight,
        d.path || e.target_id
    FROM dijkstra d
    JOIN edges e ON d.vertex_id = e.source_id
    WHERE e.target_id <> ALL(d.path)  -- PostgreSQL 数组检查
      AND d.total_weight + e.weight < 1000  -- 剪枝
)
SELECT vertex_id, MIN(total_weight) AS shortest_weight
FROM dijkstra
GROUP BY vertex_id
ORDER BY shortest_weight;
```

### 6.2 子图匹配模式

```sql
-- Oracle 23ai SQL/PGQ: 复杂子图模式匹配
-- 查找三角关系（A 认识 B，B 认识 C，C 认识 A）
SELECT *
FROM GRAPH_TABLE (social_graph
    MATCH (a:Person)-[:Knows]->(b:Person)-[:Knows]->(c:Person)-[:Knows]->(a)
    WHERE a.person_id < b.person_id AND b.person_id < c.person_id  -- 去重
    COLUMNS (a.name AS person_a, b.name AS person_b, c.name AS person_c)
);

-- 等价的递归 CTE 版本（任意支持递归的引擎）
-- 注意: 三角匹配不需要递归，普通 JOIN 即可
SELECT
    p1.name AS person_a,
    p2.name AS person_b,
    p3.name AS person_c
FROM friendships f1
JOIN friendships f2 ON f1.friend_id = f2.person_id
JOIN friendships f3 ON f2.friend_id = f3.person_id AND f3.friend_id = f1.person_id
JOIN persons p1 ON f1.person_id = p1.person_id
JOIN persons p2 ON f2.person_id = p2.person_id
JOIN persons p3 ON f3.person_id = p3.person_id
WHERE p1.person_id < p2.person_id AND p2.person_id < p3.person_id;
-- 固定长度的图模式可以直接用 JOIN，不需要递归
```

### 6.3 分层聚合（树结构汇总）

```sql
-- 常见场景: 组织结构中向上汇总预算
-- PostgreSQL / MySQL 8.0+ / 支持递归 CTE 的引擎
WITH RECURSIVE org_tree AS (
    -- 叶子节点: 直接取预算
    SELECT dept_id, parent_dept_id, budget, dept_name
    FROM departments
    WHERE dept_id NOT IN (SELECT DISTINCT parent_dept_id FROM departments WHERE parent_dept_id IS NOT NULL)

    UNION ALL

    -- 向上汇总
    SELECT d.dept_id, d.parent_dept_id, d.budget + child_sum.total, d.dept_name
    FROM departments d
    JOIN (
        SELECT parent_dept_id, SUM(budget) AS total
        FROM org_tree
        GROUP BY parent_dept_id
    ) child_sum ON d.dept_id = child_sum.parent_dept_id
)
SELECT * FROM org_tree;
-- 注意: 上述写法在大多数引擎中不可行，因为递归成员不允许 GROUP BY
-- 实际方案: 先递归展开树，再在外部查询中聚合
```

```sql
-- 实际可行的方案: 先遍历再聚合
WITH RECURSIVE org_tree AS (
    SELECT dept_id, dept_name, budget, dept_id AS root_dept
    FROM departments
    WHERE parent_dept_id IS NULL

    UNION ALL

    SELECT d.dept_id, d.dept_name, d.budget, o.root_dept
    FROM departments d
    JOIN org_tree o ON d.parent_dept_id = o.dept_id
)
SELECT root_dept, SUM(budget) AS total_budget
FROM org_tree
GROUP BY root_dept;
```

---

## 7. 关键发现

### 7.1 图查询支持的现状

```
2025 年 SQL 引擎图查询能力分层:

Tier 1 — 原生图查询 (专用语法/标准):
  Oracle 23ai     SQL/PGQ (SQL:2023 标准)
  SQL Server      NODE/EDGE 图表 + MATCH + SHORTEST_PATH
  SAP HANA        Graph Workspace + GraphScript

Tier 2 — 图扩展 (通过扩展支持 Cypher):
  PostgreSQL      Apache AGE (Cypher)
  Greenplum       Apache AGE (Cypher)
  TimescaleDB     Apache AGE (继承 PostgreSQL)

Tier 3 — 递归 CTE 图遍历 (完整支持):
  PostgreSQL      CYCLE + SEARCH 子句 (14+)
  DuckDB          CYCLE + SEARCH 子句 (0.8+)
  DB2             CYCLE + SEARCH 子句
  Oracle          也有 CONNECT BY
  MySQL, MariaDB, SQLite, Snowflake, BigQuery, Redshift,
  TiDB, OceanBase, CockroachDB, YugabyteDB, Teradata,
  Greenplum, Exasol, SAP HANA, Informix, Firebird,
  H2, HSQLDB, Derby, MonetDB, Yellowbrick, Materialize,
  Vertica

Tier 4 — 仅 CONNECT BY (无递归 CTE):
  (无: 所有支持 CONNECT BY 的引擎都同时支持递归 CTE)

Tier 5 — 无图遍历能力:
  Hive, Spark SQL, Flink SQL, StarRocks, Doris,
  SingleStore, Impala, CrateDB, QuestDB, InfluxDB,
  Google Spanner, RisingWave, DatabendDB, Firebolt
  → 这些引擎需要在应用层处理图遍历，或将图结构预扁平化
```

### 7.2 对引擎开发者的建议

```
1. 最低目标: 实现递归 CTE (WITH RECURSIVE)
   - 这是 SQL:1999 标准，也是图遍历的最基本能力
   - 参见 cte-recursive-query.md 的实现建议

2. 进阶目标: 实现 CYCLE / SEARCH 子句
   - SQL:1999 标准定义，PostgreSQL 14 / DuckDB 0.8 已实现
   - 可大幅简化用户的图遍历查询

3. 高级目标: 考虑 SQL/PGQ 支持
   - SQL:2023 标准，Oracle 23ai 率先实现
   - 标准仍在早期阶段，可先观望 2-3 年
   - 如果已有图查询需求，Apache AGE 是 PostgreSQL 生态的实用选择

4. 不推荐: 实现 CONNECT BY
   - 除非需要兼容 Oracle 迁移
   - 递归 CTE 功能更通用，是标准方案
```

### 7.3 SQL/PGQ 的未来

```
SQL/PGQ 标准化进程:
  2019   ISO 启动 SQL/PGQ 和 GQL 标准化工作
  2023   SQL:2023 发布，SQL/PGQ 正式纳入 (ISO/IEC 9075-16)
  2024   Oracle 23ai 实现 SQL/PGQ
  2024   ISO GQL (ISO/IEC 39075) 发布
  2025   等待更多引擎跟进...

预期采用节奏:
  2024-2025   Oracle 23ai (已实现)
  2025-2027   PostgreSQL、DuckDB、DB2 可能跟进
  2027+       主流引擎逐步采纳

对比历史:
  递归 CTE (SQL:1999):  Oracle (2009) → MySQL (2018)   间隔 ~10 年
  窗口函数 (SQL:2003):  Oracle (2003) → MySQL (2018)   间隔 ~15 年
  SQL/PGQ (SQL:2023):  Oracle (2024) → ???             观察中

结论: SQL/PGQ 的广泛采用预计需要 5-10 年。在此期间，
递归 CTE 仍是最实用的跨引擎图遍历方案。
```

---

## 参考资料

- SQL:2023 标准: ISO/IEC 9075-16:2023 (SQL/PGQ - Property Graph Queries)
- ISO GQL: ISO/IEC 39075:2024 (Graph Query Language)
- SQL:1999 标准: ISO/IEC 9075-2:1999, Section 7.13 (Recursive Query)
- [Oracle 23ai: SQL Property Graphs](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/graph-queries.html)
- [Oracle: CONNECT BY](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Hierarchical-Queries.html)
- [SQL Server: Graph Processing](https://learn.microsoft.com/en-us/sql/relational-databases/graphs/sql-graph-overview)
- [SQL Server: MATCH](https://learn.microsoft.com/en-us/sql/t-sql/queries/match-sql-graph)
- [SQL Server: SHORTEST_PATH](https://learn.microsoft.com/en-us/sql/relational-databases/graphs/sql-graph-shortest-path)
- [SAP HANA: Graph Engine](https://help.sap.com/docs/hana-cloud-database/sap-hana-cloud-sap-hana-database-graph-reference/sap-hana-graph-reference)
- [Apache AGE](https://age.apache.org/)
- [PostgreSQL: WITH Queries](https://www.postgresql.org/docs/current/queries-with.html)
- [DuckDB: Recursive CTEs](https://duckdb.org/docs/sql/query_syntax/with.html)
- [Neo4j Cypher](https://neo4j.com/docs/cypher-manual/current/)
- [Spark GraphFrames](https://graphframes.github.io/graphframes/)
