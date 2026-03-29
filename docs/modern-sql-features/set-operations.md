# SET 操作 (UNION / INTERSECT / EXCEPT)

集合操作——将多个 SELECT 的结果集按集合代数合并、求交、求差。SQL 标准定义了三种操作符，但各引擎在语法细节、NULL 处理、性能特性上差异显著。

## 基本语义

| 操作 | 集合含义 | 默认行为 |
|------|---------|---------|
| `UNION` | 并集 | 去重（隐含 DISTINCT） |
| `UNION ALL` | 并集 | 保留重复 |
| `INTERSECT` | 交集 | 去重（隐含 DISTINCT） |
| `INTERSECT ALL` | 交集 | 保留重复（按最小出现次数） |
| `EXCEPT` / `MINUS` | 差集 | 去重（隐含 DISTINCT） |
| `EXCEPT ALL` / `MINUS ALL` | 差集 | 保留重复（按出现次数之差） |

关键语义：UNION / INTERSECT / EXCEPT 不带 ALL 时，输出结果中**不含重复行**。这意味着引擎需要执行去重操作（排序或哈希），成本远高于 ALL 变体。

```sql
-- UNION: 去重合并
SELECT city FROM customers
UNION
SELECT city FROM suppliers;
-- 结果中每个 city 只出现一次

-- UNION ALL: 保留全部行
SELECT city FROM customers
UNION ALL
SELECT city FROM suppliers;
-- 结果中同一 city 可能出现多次
```

## UNION / UNION ALL 支持矩阵

所有主流引擎均支持 UNION 和 UNION ALL，这是 SQL 最古老的集合操作。

| 引擎 | UNION | UNION ALL | 默认行为 | 版本 |
|------|-------|-----------|---------|------|
| PostgreSQL | 支持 | 支持 | UNION = 去重 | 全版本 |
| MySQL | 支持 | 支持 | UNION = 去重 | 全版本 |
| MariaDB | 支持 | 支持 | UNION = 去重 | 全版本 |
| Oracle | 支持 | 支持 | UNION = 去重 | 全版本 |
| SQL Server | 支持 | 支持 | UNION = 去重 | 全版本 |
| SQLite | 支持 | 支持 | UNION = 去重 | 全版本 |
| Db2 | 支持 | 支持 | UNION = 去重 | 全版本 |
| DuckDB | 支持 | 支持 | UNION = 去重 | 0.1+ |
| ClickHouse | 支持 | 支持 | **裸 UNION 默认不合法**（需设置 `union_default_mode`） | 20.3+ |
| BigQuery | 支持 | 支持 | UNION 必须显式写 ALL 或 DISTINCT | 全版本 |
| Snowflake | 支持 | 支持 | UNION = 去重 | 全版本 |
| Trino | 支持 | 支持 | UNION = 去重 | 全版本 |
| Presto | 支持 | 支持 | UNION = 去重 | 全版本 |
| Spark SQL | 支持 | 支持 | UNION = 去重 | 2.0+ |
| Hive | 支持 | 支持 | **仅 UNION ALL**（早期）；UNION DISTINCT 自 1.2.0+ | 0.x+ |
| Flink SQL | 支持 | 支持 | UNION = 去重 | 1.0+ |
| Redshift | 支持 | 支持 | UNION = 去重 | 全版本 |
| Teradata | 支持 | 支持 | UNION = 去重 | 全版本 |
| Greenplum | 支持 | 支持 | UNION = 去重 | 全版本 |
| CockroachDB | 支持 | 支持 | UNION = 去重 | 全版本 |
| TiDB | 支持 | 支持 | UNION = 去重 | 全版本 |
| OceanBase | 支持 | 支持 | UNION = 去重 | 全版本 |
| Doris | 支持 | 支持 | UNION = 去重 | 0.13+ |
| StarRocks | 支持 | 支持 | UNION = 去重 | 全版本 |
| Vertica | 支持 | 支持 | UNION = 去重 | 全版本 |
| Exasol | 支持 | 支持 | UNION = 去重 | 全版本 |
| SingleStore (MemSQL) | 支持 | 支持 | UNION = 去重 | 全版本 |
| YugabyteDB | 支持 | 支持 | UNION = 去重 | 全版本 |
| Databricks SQL | 支持 | 支持 | UNION = 去重 | 全版本 |
| Google Spanner | 支持 | 支持 | UNION = 去重 | 全版本 |
| SAP HANA | 支持 | 支持 | UNION = 去重 | 全版本 |
| Informix | 支持 | 支持 | UNION = 去重 | 全版本 |
| Firebird | 支持 | 支持 | UNION = 去重 | 全版本 |
| H2 | 支持 | 支持 | UNION = 去重 | 全版本 |
| HSQLDB | 支持 | 支持 | UNION = 去重 | 全版本 |
| Derby | 支持 | 支持 | UNION = 去重 | 全版本 |

注意事项：
- **ClickHouse**: 裸 `UNION`（不带 ALL/DISTINCT）默认不合法（`union_default_mode` 默认为空字符串）。需显式写 `UNION ALL` 或 `UNION DISTINCT`，或通过设置 `union_default_mode` 为 `'ALL'` 或 `'DISTINCT'` 来允许裸 `UNION`。
- **BigQuery**: 裸 `UNION` 不合法，必须显式写 `UNION ALL` 或 `UNION DISTINCT`——这是最严格的设计，杜绝歧义。
- **Hive**: 早期版本（< 1.2.0）只支持 `UNION ALL`，不支持去重的 `UNION`。

## INTERSECT / EXCEPT 支持矩阵

| 引擎 | INTERSECT | EXCEPT | MINUS | INTERSECT ALL | EXCEPT ALL | 版本 |
|------|-----------|--------|-------|---------------|------------|------|
| PostgreSQL | 支持 | 支持 | 不支持 | 支持 | 支持 | 8.4+ (ALL) |
| MySQL | 支持 | 支持 | 不支持 | 支持 | 支持 | **8.0.31+** |
| MariaDB | 支持 | 支持 | 不支持 | 支持 | 支持 | 10.3+ / 10.5+ (ALL) |
| Oracle | 支持 | **21c+** | **MINUS** | 支持 | 不支持 | MINUS 全版本; EXCEPT 21c+ |
| SQL Server | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 2005+ |
| SQLite | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 3.x+ |
| Db2 | 支持 | 支持 | 不支持 | 支持 | 支持 | 9.x+ |
| DuckDB | 支持 | 支持 | 不支持 | 支持 | 支持 | 0.3+ |
| ClickHouse | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 21.x+ |
| BigQuery | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 全版本 |
| Snowflake | 支持 | 支持 | **MINUS** | 不支持 | 不支持 | 全版本 |
| Trino | 支持 | 支持 | 不支持 | 支持 | 支持 | 全版本 |
| Presto | 支持 | 支持 | 不支持 | 支持 | 支持 | 全版本 |
| Spark SQL | 支持 | 支持 | **MINUS** | 支持 | 支持 | 2.0+ / 3.0+ (ALL) |
| Hive | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 2.1.0+ |
| Flink SQL | 支持 | 支持 | 支持(别名) | 支持 | 支持 | 1.12+ |
| Redshift | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 全版本 |
| Teradata | 支持 | 支持 | **MINUS** | 支持 | 支持 | 全版本 |
| Greenplum | 支持 | 支持 | 不支持 | 支持 | 支持 | 全版本（同 PostgreSQL） |
| CockroachDB | 支持 | 支持 | 不支持 | 支持 | 支持 | 全版本 |
| TiDB | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 6.x+ |
| OceanBase | 支持 | 支持 | **MINUS** | 不支持 | 不支持 | MySQL/Oracle 模式均支持 |
| Doris | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 1.2+ |
| StarRocks | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 2.5+ |
| Vertica | 支持 | 支持 | **MINUS** | 支持 | 支持 | 全版本 |
| Exasol | 支持 | 支持 | **MINUS** | 不支持 | 不支持 | 全版本 |
| SAP HANA | 支持 | 支持 | **MINUS** | 不支持 | 不支持 | 全版本 |
| Firebird | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 2.0+ |
| H2 | 支持 | 支持 | **MINUS** | 不支持 | 不支持 | 全版本 |
| HSQLDB | 支持 | 支持 | 不支持 | 支持 | 支持 | 全版本 |
| Derby | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 全版本 |
| Informix | 支持 | 支持 | **MINUS** | 支持 | 支持 | 全版本 |
| Google Spanner | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 全版本 |
| Databricks SQL | 支持 | 支持 | **MINUS** | 支持 | 支持 | 全版本（同 Spark） |

## MINUS vs EXCEPT 命名

SQL 标准使用 `EXCEPT`。Oracle 长期使用 `MINUS` 作为差集操作符，这一命名影响了多个数据库。

| 引擎 | EXCEPT | MINUS | 两者均可 | 备注 |
|------|--------|-------|---------|------|
| SQL 标准 | 标准 | — | — | ISO/IEC 9075 |
| PostgreSQL | 支持 | — | — | 仅 EXCEPT |
| MySQL | 支持 | — | — | 仅 EXCEPT（8.0.31+） |
| Oracle | 21c+ | **传统** | 21c+ 两者均可 | MINUS 从 V2 起可用 |
| Snowflake | 支持 | 支持 | 两者均可 | MINUS 是 EXCEPT 的别名 |
| Spark SQL | 支持 | 支持 | 两者均可 | MINUS 是 EXCEPT 的别名 |
| Teradata | 支持 | 支持 | 两者均可 | |
| Vertica | 支持 | 支持 | 两者均可 | |
| SAP HANA | 支持 | 支持 | 两者均可 | |
| H2 | 支持 | 支持 | 两者均可 | |
| SQL Server | 支持 | — | — | 仅 EXCEPT |
| BigQuery | 支持 | — | — | 仅 EXCEPT |
| DuckDB | 支持 | — | — | 仅 EXCEPT |

对引擎开发者的建议：解析器同时接受 `EXCEPT` 和 `MINUS` 作为关键字，在 AST 中统一映射到同一个节点类型。对兼容 Oracle 的引擎（如 OceanBase）尤为重要。

## 列对齐规则

所有集合操作都要求参与的各 SELECT 列表满足以下条件：

### 列数必须一致

```sql
-- 错误: 列数不匹配
SELECT id, name FROM t1
UNION
SELECT id FROM t2;
-- 所有引擎均报错
```

### 类型协调（Type Coercion）

各引擎在列类型不一致时的处理策略：

| 引擎 | 策略 | 示例 |
|------|------|------|
| PostgreSQL | 寻找公共超类型；失败则报错 | INT ∪ TEXT → TEXT |
| MySQL | 宽松隐式转换 | INT ∪ VARCHAR → VARCHAR |
| Oracle | 仅允许兼容类型 | NUMBER ∪ VARCHAR2 → 报错 |
| SQL Server | 类型优先级规则 | INT ∪ VARCHAR → 隐式转 INT（值不兼容时运行时报错） |
| SQLite | 动态类型，无强制约束 | 任意类型均可合并 |
| DuckDB | 寻找公共超类型 | INT ∪ VARCHAR → VARCHAR |
| BigQuery | 严格类型匹配 | INT64 ∪ STRING → 报错 |
| Snowflake | 宽松转换 | NUMBER ∪ VARCHAR → VARCHAR |
| ClickHouse | 寻找公共超类型 | Int32 ∪ String → String |
| Spark SQL | 寻找最宽类型 | INT ∪ STRING → STRING |

```sql
-- PostgreSQL: INT 和 NUMERIC 自动提升为 NUMERIC
SELECT 1 AS val UNION SELECT 2.5;    -- 结果列类型: NUMERIC

-- Oracle: NUMBER 和 VARCHAR2 不兼容，需显式转换
SELECT 1 AS val FROM DUAL UNION SELECT CAST('2' AS NUMBER) FROM DUAL;

-- SQLite: 不关心类型，直接合并
SELECT 1 UNION SELECT 'hello';       -- 合法，但结果语义可疑
```

### 列名规则

集合操作结果集的列名取自**第一个 SELECT**，这是所有引擎的通用行为。

```sql
SELECT employee_id AS id, full_name AS name FROM employees
UNION ALL
SELECT supplier_id, company_name FROM suppliers;
-- 结果列名: id, name（来自第一个 SELECT）
```

## ORDER BY 作用域

ORDER BY 在复合查询中的作用域是一个常见困惑点：**ORDER BY 作用于整个复合查询的最终结果，而非最后一个 SELECT**。

```sql
-- ORDER BY 排序的是 UNION 之后的完整结果集
SELECT name, 'customer' AS source FROM customers
UNION ALL
SELECT name, 'supplier' AS source FROM suppliers
ORDER BY name;
-- name 排序应用于合并后的全部行
```

### 子查询中的 ORDER BY

大多数引擎不允许在复合查询的单个分支中直接使用 ORDER BY，除非用括号包裹为子查询：

| 引擎 | 分支中裸 ORDER BY | 括号子查询中 ORDER BY | 备注 |
|------|------------------|---------------------|------|
| PostgreSQL | 不允许 | 允许 | 裸 ORDER BY 属于整个 UNION |
| MySQL | 允许但**被忽略** | 允许 | 分支中的 ORDER BY 无效（除非配合 LIMIT） |
| MariaDB | 允许但被忽略 | 允许 | 同 MySQL |
| Oracle | 不允许 | 允许 | |
| SQL Server | 不允许（除非有 TOP） | 允许 | `SELECT TOP 100 PERCENT ... ORDER BY` 可绕过但不推荐 |
| SQLite | 不允许 | 允许 | |
| DuckDB | 不允许 | 允许 | |
| BigQuery | 不允许 | 允许 | |
| Snowflake | 不允许 | 允许 | |
| ClickHouse | 不允许 | 允许 | |

```sql
-- MySQL 特殊行为: 分支中的 ORDER BY 被悄悄忽略
SELECT name FROM customers ORDER BY name      -- 这个 ORDER BY 会被忽略!
UNION ALL
SELECT name FROM suppliers ORDER BY name;     -- 这个 ORDER BY 生效（作用于整体）

-- 如需在分支中排序并截取，需配合 LIMIT
(SELECT name FROM customers ORDER BY name LIMIT 10)
UNION ALL
(SELECT name FROM suppliers ORDER BY name LIMIT 10)
ORDER BY name;
```

## 括号化复合查询

括号可以控制集合操作的结合顺序和优先级：

```sql
-- 无括号: INTERSECT 优先级高于 UNION（SQL 标准）
SELECT id FROM a
UNION
SELECT id FROM b
INTERSECT
SELECT id FROM c;
-- 等价于: a UNION (b INTERSECT c)

-- 括号改变优先级
(SELECT id FROM a UNION SELECT id FROM b)
INTERSECT
SELECT id FROM c;
-- 含义: (a UNION b) INTERSECT c
```

### 操作符优先级

SQL 标准规定 `INTERSECT` 的优先级高于 `UNION` 和 `EXCEPT`，但并非所有引擎都遵守：

| 引擎 | INTERSECT 高于 UNION/EXCEPT | 备注 |
|------|---------------------------|------|
| PostgreSQL | 是 | 遵循标准 |
| MySQL | **是**（8.0.31+） | 8.0.31 起支持 INTERSECT，遵循标准优先级 |
| Oracle | **否**——从左到右 | 所有 SET 操作同优先级，按出现顺序执行 |
| SQL Server | 是 | 遵循标准 |
| SQLite | **否**——从左到右 | 同优先级 |
| DuckDB | 是 | 遵循标准 |
| BigQuery | **否**——要求括号 | 混合不同 SET 操作符时必须用括号明确优先级，否则报错 |
| Snowflake | **否**——从左到右 | 同优先级 |
| Trino | 是 | 遵循标准 |
| Spark SQL | 是 | 遵循标准 |
| ClickHouse | **否**——从左到右 | 同优先级 |
| Db2 | 是 | 遵循标准 |
| Teradata | 是 | 遵循标准 |
| Redshift | 是 | 遵循标准 |

建议：无论引擎是否遵循标准优先级，混合使用多种 SET 操作时**始终用括号明确意图**，避免跨引擎行为差异。

### 括号化子查询的支持

| 引擎 | 括号化 SELECT | 备注 |
|------|-------------|------|
| PostgreSQL | 支持 | `(SELECT ...) UNION (SELECT ...)` |
| MySQL | 支持 | 8.0+ 完整支持括号化 |
| Oracle | 支持 | `(SELECT ... FROM DUAL) UNION (SELECT ... FROM DUAL)` |
| SQL Server | 不支持 | 不能在 UNION 的分支外加括号；需用子查询 |
| SQLite | 支持 | |
| DuckDB | 支持 | |
| BigQuery | 支持 | |
| Snowflake | 支持 | |

## LIMIT / FETCH 在复合查询上

对整个复合查询结果应用行数限制：

```sql
-- 标准 SQL (FETCH)
SELECT name FROM customers
UNION ALL
SELECT name FROM suppliers
ORDER BY name
FETCH FIRST 20 ROWS ONLY;

-- MySQL / PostgreSQL / DuckDB 等 (LIMIT)
SELECT name FROM customers
UNION ALL
SELECT name FROM suppliers
ORDER BY name
LIMIT 20;

-- SQL Server (TOP 不可直接用于 UNION，需子查询)
SELECT TOP 20 *
FROM (
    SELECT name FROM customers
    UNION ALL
    SELECT name FROM suppliers
) AS combined
ORDER BY name;
```

### 分支级别的 LIMIT

```sql
-- 每个分支独立限制行数（需括号）
(SELECT name FROM customers ORDER BY name LIMIT 5)
UNION ALL
(SELECT name FROM suppliers ORDER BY name LIMIT 5);

-- Oracle 分支限制（FETCH 语法）
(SELECT name FROM customers ORDER BY name FETCH FIRST 5 ROWS ONLY)
UNION ALL
(SELECT name FROM suppliers ORDER BY name FETCH FIRST 5 ROWS ONLY);
```

## NULL 处理

集合操作中的去重逻辑将 **NULL 视为相等**，即两个 NULL 被认为是同一个值（IS NOT DISTINCT FROM 语义）。这与 WHERE 中的 `=` 比较不同。

```sql
-- NULL = NULL 在 WHERE 中为 UNKNOWN (false)
SELECT * FROM t WHERE x = NULL;   -- 永远返回 0 行

-- 但在 UNION 去重中，NULL 被视为相等
SELECT NULL AS val
UNION
SELECT NULL;
-- 结果: 仅一行 NULL（两个 NULL 被认为重复并去重）
```

| 引擎 | UNION 去重中 NULL=NULL | INTERSECT 中 NULL=NULL | EXCEPT 中 NULL=NULL |
|------|----------------------|----------------------|---------------------|
| PostgreSQL | 是 | 是 | 是 |
| MySQL | 是 | 是 | 是 |
| Oracle | 是 | 是 | 是（MINUS） |
| SQL Server | 是 | 是 | 是 |
| SQLite | 是 | 是 | 是 |
| DuckDB | 是 | 是 | 是 |
| BigQuery | 是 | 是 | 是 |
| Snowflake | 是 | 是 | 是 |
| ClickHouse | 是 | 是 | 是 |
| Spark SQL | 是 | 是 | 是 |

这一行为在所有主流引擎中一致，符合 SQL 标准（SQL:1992 Section 8.12）。NULL 在集合操作中的等价语义可以理解为：去重和集合比较使用 `IS NOT DISTINCT FROM` 而非 `=`。

### 多列 NULL 比较

```sql
-- (NULL, 1) 和 (NULL, 1) 在 UNION 去重中视为相同行
SELECT NULL, 1 UNION SELECT NULL, 1;
-- 结果: 一行 (NULL, 1)

-- (NULL, 1) 和 (NULL, 2) 视为不同行
SELECT NULL, 1 UNION SELECT NULL, 2;
-- 结果: 两行
```

## 性能: UNION vs UNION ALL

`UNION` 需要去重，`UNION ALL` 不需要——这个区别对性能影响极大。

### 去重的代价

```
UNION ALL:  Append(Scan(A), Scan(B))                     -- O(n+m)
UNION:      Distinct(Append(Scan(A), Scan(B)))            -- O((n+m) log(n+m)) 或 O(n+m) hash
INTERSECT:  HashIntersect(Scan(A), Scan(B))               -- O(n+m) hash
EXCEPT:     HashExcept(Scan(A), Scan(B))                  -- O(n+m) hash
```

| 操作 | 时间复杂度 | 内存消耗 | 适用场景 |
|------|-----------|---------|---------|
| UNION ALL | O(n+m) | 无额外 | 已知无重复或允许重复 |
| UNION | O((n+m) log(n+m)) 排序去重 | 排序缓冲区 | 需要去重的小数据集 |
| UNION | O(n+m) 哈希去重 | 哈希表 | 需要去重的大数据集 |
| INTERSECT | O(n+m) | 哈希表 | 求交集 |
| EXCEPT | O(n+m) | 哈希表 | 求差集 |

### 最佳实践

```sql
-- 反模式: 不必要的去重
SELECT user_id FROM active_users
UNION                              -- 花费大量资源去重
SELECT user_id FROM premium_users;

-- 优化方案 1: 如果允许重复，用 UNION ALL
SELECT user_id FROM active_users
UNION ALL
SELECT user_id FROM premium_users;

-- 优化方案 2: 如果需要去重但数据源已知不重叠
-- 先用 UNION ALL，外层 DISTINCT
SELECT DISTINCT user_id FROM (
    SELECT user_id FROM active_users
    UNION ALL
    SELECT user_id FROM premium_users
) t;
-- 看似多余，但在某些优化器中（如分布式系统）可能有更好的执行计划

-- 优化方案 3: 改写为等价的 OR 条件
SELECT user_id FROM users
WHERE is_active = true OR is_premium = true;
```

### 物化与流式执行

| 引擎类型 | UNION ALL 执行模式 | UNION 执行模式 |
|---------|------------------|---------------|
| 传统 OLTP（PostgreSQL, MySQL） | 流式追加 | 排序去重或哈希去重 |
| 列存 OLAP（ClickHouse, DuckDB） | 流式追加 | 哈希去重 |
| MPP（Redshift, BigQuery） | 各节点并行追加 | 分布式哈希去重 |
| 流处理（Flink SQL） | 流式合并 | 需要状态维护（较重） |

## 递归 CTE 与集合操作的交互

递归 CTE 的定义中使用 `UNION ALL` 或 `UNION` 连接锚定成员（anchor）和递归成员（recursive）：

```sql
-- 标准递归 CTE（UNION ALL: 保留重复，可能无限递归）
WITH RECURSIVE tree AS (
    SELECT id, parent_id, name, 0 AS depth
    FROM categories
    WHERE parent_id IS NULL                  -- 锚定成员

    UNION ALL                                 -- 连接操作符

    SELECT c.id, c.parent_id, c.name, t.depth + 1
    FROM categories c
    JOIN tree t ON c.parent_id = t.id         -- 递归成员
)
SELECT * FROM tree;

-- 使用 UNION（去重: 自动终止循环，但可能丢失合法重复）
WITH RECURSIVE graph AS (
    SELECT start_node AS node FROM edges WHERE start_node = 1

    UNION                                     -- 去重: 已访问节点不再递归

    SELECT e.end_node
    FROM edges e
    JOIN graph g ON e.start_node = g.node
)
SELECT * FROM graph;
```

### 各引擎对递归 CTE 中集合操作的支持

| 引擎 | UNION ALL | UNION (去重) | 其他集合操作 | 循环检测 |
|------|-----------|-------------|-------------|---------|
| PostgreSQL | 支持 | 支持 | 不支持 | `CYCLE` 子句（14+） |
| MySQL | 支持 | 支持 | 不支持 | `cte_max_recursion_depth` |
| SQL Server | 支持 | 不支持 | 不支持 | `OPTION (MAXRECURSION n)` |
| Oracle | 支持 | 支持 | 不支持 | `CYCLE` 子句 |
| SQLite | 支持 | 支持 | 不支持 | 深度限制 |
| DuckDB | 支持 | 支持 | 不支持 | 深度限制 |
| BigQuery | 支持 | 支持 | 不支持 | 深度限制 |
| Snowflake | 支持 | 不支持 | 不支持 | 深度限制 |
| Trino | 支持 | 不支持 | 不支持 | 深度限制 |
| Spark SQL | 支持（3.4+） | — | — | `spark.sql.cte.maxIterations`（3.4+） |
| ClickHouse | 不支持递归 CTE | — | — | — |

注意：SQL Server 在递归 CTE 中**不允许使用 UNION**（仅 UNION ALL），因此需要在递归成员中手动过滤已访问节点来避免无限循环。

## INTERSECT ALL / EXCEPT ALL 语义详解

ALL 变体使用多重集（multiset）语义而非集合语义。

### INTERSECT ALL

返回行的出现次数等于两侧中的**最小值**：

```sql
-- 左侧: {A, A, A, B, B, C}
-- 右侧: {A, A, B, B, B, D}
-- INTERSECT ALL: {A, A, B, B}  -- A: min(3,2)=2, B: min(2,3)=2
-- INTERSECT:     {A, B}         -- 仅保留存在性
```

### EXCEPT ALL

返回行的出现次数等于左侧次数**减去**右侧次数（不小于 0）：

```sql
-- 左侧: {A, A, A, B, B, C}
-- 右侧: {A, B, B, B}
-- EXCEPT ALL: {A, A, C}  -- A: 3-1=2, B: 2-3=0, C: 1-0=1
-- EXCEPT:     {C}          -- 仅保留左侧独有的值
```

### 实现方式

```sql
-- 引擎可以用哈希表 + 计数器实现 INTERSECT ALL:
-- 1. 扫描左侧，建立 {行 → 计数} 哈希表
-- 2. 扫描右侧，对每行查找哈希表，取 min(左计数, 右计数)

-- 对于不支持 INTERSECT ALL 的引擎，可用窗口函数模拟:
SELECT val FROM (
    SELECT val, ROW_NUMBER() OVER (PARTITION BY val ORDER BY val) AS rn
    FROM left_table
) l
INTERSECT
SELECT val FROM (
    SELECT val, ROW_NUMBER() OVER (PARTITION BY val ORDER BY val) AS rn
    FROM right_table
) r;
```

## 各引擎特殊语法

### ClickHouse: UNION 默认行为可配置

```sql
-- 默认 union_default_mode = ''（空字符串），裸 UNION 是语法错误！
SELECT 1 UNION SELECT 1;         -- 语法错误（默认设置下）

-- 可配置为允许裸 UNION
SET union_default_mode = 'ALL';
SELECT 1 UNION SELECT 1;         -- 返回两行（等价于 UNION ALL）

SET union_default_mode = 'DISTINCT';
SELECT 1 UNION SELECT 1;         -- 返回一行（等价于 UNION DISTINCT）

-- 推荐: 始终显式写明 ALL 或 DISTINCT，不依赖 union_default_mode 设置
SELECT 1 UNION ALL SELECT 1;
SELECT 1 UNION DISTINCT SELECT 1;
```

### BigQuery: 强制显式

```sql
-- 不合法:
SELECT 1 UNION SELECT 2;           -- 语法错误!

-- 必须显式:
SELECT 1 UNION ALL SELECT 2;       -- 合法
SELECT 1 UNION DISTINCT SELECT 2;  -- 合法
```

### Oracle: MINUS 的历史

```sql
-- Oracle 传统写法（V2 起支持）
SELECT id FROM a MINUS SELECT id FROM b;

-- Oracle 21c 起也支持标准 EXCEPT
SELECT id FROM a EXCEPT SELECT id FROM b;

-- 两者等价，MINUS 是 Oracle 方言
```

### Spark SQL / Databricks: MINUS 作为别名

```sql
-- Spark SQL 同时支持 EXCEPT 和 MINUS
SELECT id FROM a EXCEPT SELECT id FROM b;
SELECT id FROM a MINUS SELECT id FROM b;    -- 等价

-- 也支持 ALL 变体
SELECT id FROM a EXCEPT ALL SELECT id FROM b;
SELECT id FROM a MINUS ALL SELECT id FROM b;
```

### SQL Server: TOP 与 UNION 的交互

```sql
-- TOP 不能直接用在 UNION 结果上
-- 需要子查询包装
SELECT TOP 10 * FROM (
    SELECT name FROM customers
    UNION ALL
    SELECT name FROM suppliers
) AS combined
ORDER BY name;

-- 分支中使用 TOP 需配合 ORDER BY
SELECT TOP 5 name FROM customers ORDER BY name
UNION ALL
SELECT TOP 5 name FROM suppliers ORDER BY name;
-- 注意: 外层没有 ORDER BY，最终顺序不确定
```

### MySQL: UNION 与括号的微妙行为

```sql
-- MySQL 中括号化的 SELECT 可以有自己的 ORDER BY + LIMIT
(SELECT name FROM customers ORDER BY name LIMIT 10)
UNION ALL
(SELECT name FROM suppliers ORDER BY name LIMIT 10)
ORDER BY name
LIMIT 15;

-- 但不加 LIMIT 时，分支中的 ORDER BY 会被优化器忽略
(SELECT name FROM customers ORDER BY name)  -- ORDER BY 被忽略
UNION ALL
(SELECT name FROM suppliers);
```

## 多路集合操作

三个或更多 SELECT 的链式集合操作：

```sql
-- 三路 UNION ALL
SELECT id FROM a
UNION ALL
SELECT id FROM b
UNION ALL
SELECT id FROM c;

-- 混合操作（注意优先级！）
SELECT id FROM a
UNION
SELECT id FROM b
INTERSECT
SELECT id FROM c;
-- 标准解释: a UNION (b INTERSECT c)
-- Oracle/SQLite/Snowflake: (a UNION b) INTERSECT c  ← 从左到右
-- BigQuery: 混合不同操作符时报错，必须用括号

-- 推荐写法: 始终用括号
(SELECT id FROM a)
UNION
(SELECT id FROM b INTERSECT SELECT id FROM c);
```

## 对引擎开发者的实现建议

### 1. 解析器设计

集合操作在语法中的位置：

```
query_expression:
    query_term ((UNION | EXCEPT | MINUS) [ALL | DISTINCT] query_term)*

query_term:
    query_primary (INTERSECT [ALL | DISTINCT] query_primary)*

query_primary:
    simple_select
  | '(' query_expression ')'
  | VALUES row_list
```

INTERSECT 作为 `query_term` 的操作符绑定更紧，自然实现了标准优先级。如果引擎选择从左到右的优先级（Oracle 模式），则将所有 SET 操作放在同一层。

### 2. 类型推导

复合查询的输出列类型需要对齐：

```
for i in 0..num_columns:
    result_type[i] = common_supertype(
        select1.column[i].type,
        select2.column[i].type,
        ...
    )
```

需要处理的边界情况：
- NULL 字面量的类型推导（通常作为目标列类型处理）
- 字符集/排序规则的合并（COERCIBILITY 规则）
- DECIMAL 精度/标度的合并（取最大精度和标度）

### 3. 执行计划节点

```
SetOperationNode:
    operation: UNION | INTERSECT | EXCEPT
    all: bool
    children: [PlanNode, PlanNode, ...]
    output_types: [Type, ...]
```

执行策略选择：

| 操作 | 推荐策略 |
|------|---------|
| UNION ALL | Append——最简单，零额外开销 |
| UNION | Hash Aggregate 或 Sort + Dedup |
| INTERSECT | Hash Semi Join 或 Sort Merge |
| INTERSECT ALL | Hash Join + 计数器 |
| EXCEPT | Hash Anti Join 或 Sort Merge |
| EXCEPT ALL | Hash Join + 计数器递减 |

### 4. 优化器规则

关键优化规则：

```
-- 规则 1: UNION ALL 下推（谓词下推到各分支）
SELECT * FROM (
    SELECT id, name FROM a UNION ALL SELECT id, name FROM b
) WHERE id > 100
→ SELECT id, name FROM a WHERE id > 100
  UNION ALL
  SELECT id, name FROM b WHERE id > 100

-- 规则 2: UNION → UNION ALL（如果列上有 UNIQUE 约束保证无重复）
-- 如果 a.id 和 b.id 分别有唯一约束且值域不重叠
SELECT id FROM a UNION SELECT id FROM b
→ SELECT id FROM a UNION ALL SELECT id FROM b

-- 规则 3: 去重提升（将分支中的 DISTINCT 消除）
SELECT DISTINCT id FROM a
UNION
SELECT DISTINCT id FROM b
→ SELECT id FROM a UNION SELECT id FROM b
-- UNION 本身已去重，分支中的 DISTINCT 多余

-- 规则 4: 常量折叠
SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
→ VALUES (1), (2), (3)
```

### 5. 分布式执行考量

在分布式引擎中：

```
UNION ALL:
  - 各分片并行执行各分支
  - Coordinator 简单合并结果流

UNION:
  - 各分片执行各分支
  - 需要全局去重: 按 hash 重分布到去重节点
  - 或两阶段: 先本地预去重，再全局去重

INTERSECT / EXCEPT:
  - 两侧按相同 key 做 hash 分布
  - 各分片本地计算交集/差集
  - 合并分片结果
```

### 6. NULL 比较器

集合操作的去重/比较逻辑需要使用 `IS NOT DISTINCT FROM` 语义。实现时需要一个独立的比较器，区别于常规 `=` 运算符：

```python
def set_operation_equals(row1, row2):
    """集合操作中的行比较: NULL 视为相等"""
    for col1, col2 in zip(row1, row2):
        if col1 is None and col2 is None:
            continue  # NULL = NULL → true
        if col1 is None or col2 is None:
            return False
        if col1 != col2:
            return False
    return True
```

### 7. 流式引擎的特殊考量

流处理引擎（Flink SQL）中的集合操作：

- **UNION ALL**: 简单合并两个流，无状态
- **UNION**: 需要维护已见行的状态（可能无限增长），实践中需要配合 TTL 或水位线
- **INTERSECT / EXCEPT**: 需要维护两侧的状态，在流语义下复杂度高
- 建议：流模式下优先使用 UNION ALL，避免有状态的集合操作

### 8. 内存管理与 work_mem 配置

集合操作中的去重（UNION、INTERSECT、EXCEPT）依赖 Hash Table 或 Sort，其内存消耗直接影响性能和稳定性：

```
去重的内存消耗模型:
  Hash 去重: 内存 = 行数 × (行大小 + hash 桶开销)
  Sort 去重: 内存 = 数据量 (排序缓冲区)

PostgreSQL 参考:
  - work_mem 参数控制每个排序/哈希操作的可用内存
  - 默认 4MB，复杂集合操作可能需要调高
  - 超过 work_mem 后自动切换到磁盘临时文件 (外部排序/Hash)

引擎实现建议:
  1. 为 SetOperation 节点分配独立的内存配额
  2. 配额可参考 PostgreSQL 的 work_mem 模型: 每个算子独立计量
  3. 内存超限时的行为:
     - 优先: 溢出到磁盘 (external sort / partitioned hash)
     - 次选: 报错并提示用户增大内存配额
     - 禁止: 静默 OOM 或无限制占用内存
  4. 监控: 暴露每个 SetOperation 节点的内存使用量和溢出次数
```

### 9. Hash 去重的碰撞风险与磁盘溢出

Hash 去重在高并发、大数据量场景下需要关注碰撞率和溢出机制：

```
Hash 碰撞风险:
  - 当 hash 桶数不足或 hash 函数质量差时，大量行映射到同一桶
  - 同桶内退化为线性比较，极端情况下 O(N²)
  - 高并发写入 hash 表时，锁竞争加剧碰撞链的遍历延迟

碰撞缓解策略:
  1. 使用高质量 hash 函数 (如 xxHash, MurmurHash3)
  2. 动态扩容: 负载因子超过阈值 (如 0.75) 时 rehash
  3. 两级 hash: 先用粗粒度 hash 分区，再在分区内精确去重

磁盘溢出 (Disk Spill) 机制:
  当内存中的 hash 表超过配额时，必须有可靠的溢出路径:
  1. Grace Hash 分区: 按 hash 值将数据分为 P 个分区，
     每次只加载一个分区到内存中去重
  2. Hybrid Hash: 尽量将第一个分区保留在内存中处理，
     其余分区写入磁盘后逐个加载
  3. 递归分区: 如果单个分区仍超过内存，对该分区使用
     不同 hash 函数再次分区

  注意: 溢出路径必须在并发场景下线程安全，
        临时文件需要在查询结束后清理
```

### 10. MULTISET 类型与标准集合操作的区分

SQL 标准（SQL:2003+）定义了 MULTISET 类型，它是一种保留重复元素的集合类型，与常规集合操作（UNION/INTERSECT/EXCEPT）语义不同但容易混淆：

```
标准集合操作 vs MULTISET 操作:

  UNION vs MULTISET UNION:
    {1,1,2} UNION {1,3}       = {1,2,3}       -- 去重
    {1,1,2} MULTISET UNION {1,3} = {1,1,2,1,3}  -- 保留所有

  INTERSECT vs MULTISET INTERSECT:
    {1,1,2} INTERSECT {1,1,3}       = {1}         -- 去重
    {1,1,2} MULTISET INTERSECT {1,1,3} = {1,1}     -- 取最小出现次数

  EXCEPT vs MULTISET EXCEPT:
    {1,1,2} EXCEPT {1}       = {2}           -- 去重后差集
    {1,1,2} MULTISET EXCEPT {1} = {1,2}       -- 减去一个实例

SQL 标准中的 MULTISET 支持:
  - SQL:2003 引入 MULTISET 类型和 MULTISET UNION/INTERSECT/EXCEPT
  - Oracle 从 10g 开始支持 MULTISET 操作（基于嵌套表类型）
  - 大多数引擎未实现 MULTISET 类型

引擎实现注意:
  - UNION ALL / INTERSECT ALL / EXCEPT ALL 在语义上等价于
    MULTISET UNION / INTERSECT / EXCEPT，但操作对象是查询结果而非集合类型
  - 如果引擎计划支持 MULTISET 类型，需要在类型系统中区分
    集合类型 (SET) 和多重集合类型 (MULTISET)
  - 解析器需区分 SELECT ... UNION ALL ... (集合操作)
    和 col MULTISET UNION col2 (MULTISET 表达式)
```

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992 Section 7.10 `<query expression>`
- SQL:2016 标准: ISO/IEC 9075-2:2016 Section 7.13 `<query expression>`
- PostgreSQL: [UNION / INTERSECT / EXCEPT](https://www.postgresql.org/docs/current/sql-select.html#SQL-UNION)
- MySQL: [UNION Clause](https://dev.mysql.com/doc/refman/8.0/en/union.html)
- Oracle: [The UNION, INTERSECT, MINUS Operators](https://docs.oracle.com/en/database/oracle/oracle-database/21/sqlrf/The-UNION-ALL-INTERSECT-MINUS-Operators.html)
- SQL Server: [Set Operators](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/set-operators-except-and-intersect-transact-sql)
- ClickHouse: [UNION](https://clickhouse.com/docs/en/sql-reference/statements/select/union)
- BigQuery: [Set Operations](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#set_operators)
- DuckDB: [Set Operations](https://duckdb.org/docs/sql/query_syntax/setops)
- Spark SQL: [Set Operators](https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-setops.html)
