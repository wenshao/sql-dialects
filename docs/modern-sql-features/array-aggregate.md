# 数组聚合函数 (Array Aggregate Functions)

将多行的值收集进同一个集合容器——`ARRAY_AGG` 是 SQL:2003 标准中诞生的一类聚合函数，与 `STRING_AGG`/`GROUP_CONCAT`/`LISTAGG` 这些"返回字符串"的拼接型聚合并列存在。两者解决的是同一类需求（聚合多行成一个组合值），但有着本质的差异：`STRING_AGG` 返回的是带分隔符的标量字符串，而 `ARRAY_AGG` 返回的是一等公民的数组类型，可以继续被切片、遍历、UNNEST 展开为关系。这一点决定了：在没有原生数组类型的引擎里（MySQL、SQL Server、SQLite），不可能有真正意义上的 `ARRAY_AGG`，最多只能用 JSON 数组或字符串拼接来"模拟"。

本文系统对比 50+ 主流 SQL 引擎在数组聚合上的支持差异，覆盖标准 `ARRAY_AGG`、Hive/Spark 的 `collect_list`/`collect_set`、ClickHouse 的 `groupArray`、MySQL 的 `JSON_ARRAYAGG`，以及 ORDER BY、FILTER WHERE、DISTINCT 等关键修饰符。

## 与字符串聚合的对比定位

数组聚合与字符串聚合是同一族函数的两种形态，对比如下：

```sql
-- 输入:
-- dept_id | name
-- 1       | Alice
-- 1       | Bob
-- 1       | Charlie
-- 2       | Dave

-- 字符串聚合 (返回标量 VARCHAR/TEXT)
SELECT dept_id, STRING_AGG(name, ', ') AS names FROM employees GROUP BY dept_id;
-- dept_id | names
-- 1       | "Alice, Bob, Charlie"     ← 字符串
-- 2       | "Dave"                    ← 字符串

-- 数组聚合 (返回 ARRAY<VARCHAR>)
SELECT dept_id, ARRAY_AGG(name) AS names FROM employees GROUP BY dept_id;
-- dept_id | names
-- 1       | {"Alice", "Bob", "Charlie"}   ← 真正的数组
-- 2       | {"Dave"}                       ← 真正的数组
```

差异与重叠：

| 维度 | STRING_AGG / LISTAGG | ARRAY_AGG / collect_list |
|------|---------------------|------------------------|
| 返回类型 | 标量字符串（VARCHAR、TEXT） | 真正的数组（ARRAY<T>） |
| 元素类型 | 必须是字符串（其他类型隐式 CAST） | 任意类型，包括嵌套数组、STRUCT |
| 后续操作 | 只能再字符串处理（SUBSTRING、SPLIT） | UNNEST、下标、切片、`element_at`、`array_length` |
| 标准化 | SQL:2016 引入 LISTAGG | SQL:2003 引入 ARRAY_AGG |
| 类型保真 | 丢失（数字、日期都成字符串） | 保持原类型 |
| 与 JOIN/查询融合 | 难（需 SPLIT 还原） | 用 UNNEST 直接展开为行 |
| 不依赖什么 | 仅需字符串拼接能力 | 需要原生 ARRAY 类型支持 |

设计上有重叠：当元素全是字符串、调用方只需要拼接展示时，两者效果接近，PostgreSQL/DuckDB 也允许 `ARRAY_TO_STRING(ARRAY_AGG(...), ', ')` 把数组聚合再降级为字符串。但反向不成立：`STRING_AGG` 的结果是不可逆的标量字符串，无法廉价还原为数组，元素中如果含分隔符还会出错。

## 标准化时间线

```
1999  SQL:1999 引入 ARRAY 类型 (固定大小数组)
2003  SQL:2003 引入 ARRAY_AGG 标准聚合函数 (Section 10.9)
       同年还引入 MULTISET 类型与 COLLECT 聚合
2009  PostgreSQL 8.4 实现 ARRAY_AGG (业界第一个完整实现)
2013  Hive 0.13 引入 collect_list / collect_set
2014  Trino (Presto) 引入 array_agg
2015  MySQL 5.7 引入 JSON_ARRAYAGG (JSON 数组,非原生 ARRAY)
2016  SQL:2016 标准化 LISTAGG (字符串聚合)
2017  SQL Server 2017 引入 STRING_AGG (仍无 ARRAY_AGG)
2018  ClickHouse groupArray 系列稳定
2019  BigQuery ARRAY_AGG 加入 ORDER BY / LIMIT 修饰符
2020  Snowflake / Redshift 增强 ARRAY_AGG
```

SQL:2003 标准的 `ARRAY_AGG` 定义如下（ISO/IEC 9075-2:2003, Section 10.9）：

```sql
<array aggregate function> ::=
    ARRAY_AGG <left paren> <value expression>
        [ ORDER BY <sort specification list> ]
    <right paren>
```

标准定义的关键语义：

1. 返回值是数组类型，元素类型由参数表达式决定
2. ORDER BY 子句指定数组内元素的顺序，未指定时顺序未定义
3. NULL 元素保留（与 SUM/AVG 不同），即 `ARRAY_AGG(NULL_value)` 会产生 NULL 元素
4. 空集上返回 NULL（不是空数组），这与 PostgreSQL/Snowflake/BigQuery 实际行为一致
5. SQL:2003 标准未定义 `DISTINCT` 修饰符；DISTINCT 由各厂商扩展

## 支持矩阵 (50+ 引擎)

### ARRAY_AGG / 数组聚合基础支持

| 引擎 | 函数名 | 引入版本 | 返回类型 | 备注 |
|------|--------|---------|----------|------|
| PostgreSQL | `array_agg` | 8.4 (2009) | `anyarray` | 业界第一个完整实现 |
| MySQL | `JSON_ARRAYAGG` | 5.7.22 (2018) | `JSON` | 无原生 ARRAY，返回 JSON 数组 |
| MariaDB | `JSON_ARRAYAGG` | 10.5+ | `JSON` (LONGTEXT) | 同 MySQL |
| SQLite | -- | -- | -- | 无原生 ARRAY，无内置实现 |
| Oracle | `COLLECT` | 10gR2+ | `nested table` | 标准 SQL:2003 MULTISET 风格 |
| SQL Server | -- | -- | -- | **从未实现**，因为没有 ARRAY 类型 |
| DB2 | `ARRAY_AGG` | 9.7+ | `ARRAY` | 标准实现，需 SQL PL 上下文 |
| Snowflake | `ARRAY_AGG` | GA (早期) | `ARRAY` | 元素为 VARIANT |
| BigQuery | `ARRAY_AGG` | GA | `ARRAY<T>` | 必须显式 IGNORE NULLS 才忽略 NULL |
| Redshift | `LISTAGG` (但有 `ARRAY()`) | 2018+ | `SUPER` | 通过 SUPER 间接支持 |
| Redshift Serverless | `ARRAY_AGG` | 2022+ | `SUPER ARRAY` | RA3 集群上原生支持 |
| DuckDB | `array_agg` / `list` / `list_agg` | 0.3+ | `LIST<T>` | 多别名兼容 |
| ClickHouse | `groupArray` / `groupArrayArray` | 早期 | `Array(T)` | 非标准命名 |
| Trino | `array_agg` | 0.85+ | `ARRAY<T>` | 标准命名 |
| Presto | `array_agg` | 0.85+ | `ARRAY<T>` | 同 Trino |
| Spark SQL | `collect_list` / `collect_set` / `array_agg` | 1.6+ / 3.0+ | `ARRAY<T>` | array_agg 别名在 3.0 加入 |
| Hive | `collect_list` / `collect_set` | 0.13 (2014) | `ARRAY<T>` | 早于 Spark SQL |
| Databricks | `collect_list` / `collect_set` / `array_agg` | GA | `ARRAY<T>` | 继承 Spark SQL |
| Flink SQL | `ARRAY_AGG` | 1.18+ | `ARRAY<T>` | 较晚加入，1.17 之前无 |
| Doris | `array_agg` / `collect_list` | 1.2+ | `ARRAY<T>` | 双别名 |
| StarRocks | `array_agg` | 2.5+ | `ARRAY<T>` | 后期支持 ORDER BY |
| CockroachDB | `array_agg` | GA | `ARRAY<T>` | PG 兼容 |
| TiDB | `JSON_ARRAYAGG` | 5.0+ | `JSON` | 继承 MySQL 行为 |
| OceanBase | `JSON_ARRAYAGG` | MySQL 模式 | `JSON` | Oracle 模式有 `COLLECT` |
| YugabyteDB | `array_agg` | GA | `ARRAY` | 继承 PostgreSQL |
| Greenplum | `array_agg` | 4.0+ | `ARRAY` | 继承 PostgreSQL |
| Vertica | `LISTAGG` (无 ARRAY_AGG) | -- | -- | 仅字符串聚合 |
| Teradata | `ARRAY_AGG` | 16.0+ | `ARRAY` | 较晚加入，需 ARRAY 类型 |
| SAP HANA | `ARRAY_AGG` | 2.0 SP3+ | `ARRAY` | 标准实现 |
| Amazon Athena | `array_agg` | GA | `ARRAY<T>` | 继承 Trino/Presto |
| Azure Synapse | -- | -- | -- | 不支持，与 SQL Server 一致 |
| Google Spanner | `ARRAY_AGG` | GA | `ARRAY<T>` | GoogleSQL 方言 |
| SingleStore | `JSON_AGG` | GA | `JSON` | 与 MySQL 类似 |
| Materialize | `array_agg` / `list_agg` | GA | `LIST<T>` | PostgreSQL 兼容 |
| RisingWave | `array_agg` | GA | `ARRAY<T>` | PG 兼容 |
| CrateDB | `array_agg` | 4.5+ | `ARRAY<T>` | PG 兼容 |
| Firebolt | `ARRAY_AGG` | GA | `ARRAY<T>` | 标准命名 |
| TimescaleDB | `array_agg` | 继承 PG | `ARRAY` | PG 扩展，完全继承 |
| Yellowbrick | `array_agg` | GA | `ARRAY<T>` | PG 兼容 |
| MonetDB | -- | -- | -- | 不支持 |
| QuestDB | -- | -- | -- | 不支持，仅 string_agg |
| Exasol | -- | -- | -- | 不支持 ARRAY_AGG，无原生 ARRAY |
| Informix | `LIST` (集合聚合) | GA | `LIST/SET/MULTISET` | SQL:2003 风格 |
| Firebird | `LIST` (字符串聚合) | -- | -- | 仅字符串聚合 |
| H2 | `array_agg` | 1.4+ | `ARRAY` | PG 兼容 |
| HSQLDB | `array_agg` | 2.5+ | `ARRAY` | 标准实现 |
| Derby | -- | -- | -- | 不支持 |
| Impala | `group_concat` | -- | `STRING` | 仅字符串聚合 |
| DatabendDB | `array_agg` | GA | `ARRAY<T>` | 标准命名 |
| Pinot | -- | -- | -- | 不支持，可用 `ARRAYAGG`(不同语义) |
| Druid | -- | -- | -- | 不支持原生 ARRAY 聚合 |
| Cassandra (CQL) | -- | -- | -- | 不支持聚合到集合 |
| MongoDB (MQL) | `$push` | GA | `Array` | 文档模型，用 aggregation pipeline |

> 统计：约 35 个引擎支持某种形式的"原生 ARRAY 聚合"（返回真正数组类型），另有约 5 个引擎（MySQL/MariaDB/TiDB/SingleStore/OceanBase MySQL 模式）通过 JSON 数组实现近似能力。SQL Server / SQLite / Vertica / SQL Server 系列不支持。

### ORDER BY 修饰符（控制数组内元素顺序）

SQL:2003 标准要求 `ARRAY_AGG` 接受 `ORDER BY` 子句来控制数组内元素的顺序，但各引擎实现的语法位置和强制程度差异巨大：

| 引擎 | 是否支持 | 语法风格 | 备注 |
|------|---------|---------|------|
| PostgreSQL | 支持 | `ARRAY_AGG(col ORDER BY sort_col)` | 函数内 ORDER BY，标准语法 |
| BigQuery | 支持 | `ARRAY_AGG(col ORDER BY sort_col [LIMIT N])` | 还支持 LIMIT |
| Snowflake | 支持 | `ARRAY_AGG(col) WITHIN GROUP (ORDER BY sort_col)` | WITHIN GROUP 风格 |
| DuckDB | 支持 | `ARRAY_AGG(col ORDER BY sort_col)` | PG 风格 |
| Trino / Presto | 支持 | `ARRAY_AGG(col ORDER BY sort_col)` | PG 风格 |
| Spark SQL | 部分 | `array_sort(collect_list(col))` | collect_list 不接受 ORDER BY，需后置 array_sort |
| Hive | 不支持 | -- | collect_list 顺序未定义 |
| ClickHouse | 部分 | `arraySort(groupArray(col))` | 与 Spark 类似 |
| DB2 | 支持 | `ARRAY_AGG(col ORDER BY sort_col)` | PG 风格 |
| Oracle | 支持 | `COLLECT(col ORDER BY sort_col)` | 11.2+ |
| Teradata | 支持 | `ARRAY_AGG(col) WITHIN GROUP (ORDER BY sort_col)` | WITHIN GROUP 风格 |
| SAP HANA | 支持 | `ARRAY_AGG(col ORDER BY sort_col)` | PG 风格 |
| MySQL | 支持 | `JSON_ARRAYAGG(col ORDER BY sort_col)` | 8.0.40+ 才支持 |
| Doris / StarRocks | 支持 | `array_agg(col ORDER BY sort_col)` | 较晚版本 |
| Redshift (SUPER) | 不支持 | -- | -- |
| H2 | 支持 | `array_agg(col ORDER BY sort_col)` | PG 风格 |
| HSQLDB | 支持 | `array_agg(col ORDER BY sort_col)` | PG 风格 |
| CockroachDB | 支持 | `array_agg(col ORDER BY sort_col)` | PG 兼容 |

> 关键分歧：PostgreSQL 风格（`ARRAY_AGG(col ORDER BY ...)`）与 DB2/Oracle/Teradata 的 `WITHIN GROUP` 风格在历史上是平行演进的——PG 风格更像普通函数参数，WITHIN GROUP 风格强调"有序集合聚合"语义。后者在 SQL:2003 中被定义为 `<ordered set function>`。Snowflake 和 Teradata 选择了 WITHIN GROUP，PostgreSQL/BigQuery/DuckDB/Trino 选择了 PG 风格。

### FILTER WHERE 修饰符（聚合前过滤）

| 引擎 | FILTER 支持 | 语法 |
|------|------------|------|
| PostgreSQL | 支持 | `ARRAY_AGG(name) FILTER (WHERE active)` |
| DuckDB | 支持 | `array_agg(name) FILTER (WHERE active)` |
| Trino | 支持 | `array_agg(name) FILTER (WHERE active)` |
| Spark SQL | 支持 (3.0+) | `collect_list(name) FILTER (WHERE active)` |
| BigQuery | 不支持 FILTER | 用 IF/ARRAY_AGG: `ARRAY_AGG(IF(active, name, NULL) IGNORE NULLS)` |
| Snowflake | 不支持 FILTER | 用 CASE WHEN |
| ClickHouse | 不支持 FILTER | 用 -If 后缀: `groupArrayIf(name, active)` |
| MySQL | 不支持 FILTER | 用 CASE WHEN |
| Oracle | 不支持 FILTER | 用 CASE WHEN |
| DB2 | 支持 | `ARRAY_AGG(name) FILTER (WHERE active)` |
| SAP HANA | 不支持 | 用 CASE WHEN |
| H2 | 支持 | PG 风格 |
| HSQLDB | 支持 | PG 风格 |
| Hive | 不支持 | 用 CASE WHEN |
| Redshift | 不支持 | 用 CASE WHEN |

### DISTINCT 修饰符

| 引擎 | DISTINCT 支持 | 备注 |
|------|--------------|------|
| PostgreSQL | 支持 | `ARRAY_AGG(DISTINCT col)` |
| DuckDB | 支持 | -- |
| Trino | 支持 | -- |
| BigQuery | 支持 | `ARRAY_AGG(DISTINCT col)` |
| Snowflake | 支持 | `ARRAY_AGG(DISTINCT col)` |
| MySQL | 支持 | `JSON_ARRAYAGG(DISTINCT col)` |
| Spark SQL (collect_list) | 不支持 | 用 `collect_set` 代替 |
| Spark SQL (array_agg) | 支持 (3.4+) | -- |
| Hive collect_list | 不支持 | 用 `collect_set` 代替 |
| ClickHouse | 用 `groupUniqArray` | `groupArray` 不支持 DISTINCT |
| Oracle | 支持 | `COLLECT(DISTINCT col)` |
| DB2 | 支持 | -- |
| SAP HANA | 支持 | -- |
| Doris / StarRocks | 支持 | -- |
| Redshift | -- | -- |
| H2 | 支持 | -- |

### 是否需要原生 ARRAY 类型

数组聚合的支持深度直接受限于引擎是否有原生数组类型：

| 引擎 | 原生 ARRAY 类型 | ARRAY_AGG 实现 | 后续展开能力 |
|------|----------------|--------------|------------|
| PostgreSQL | 是 | array_agg | UNNEST |
| BigQuery | 是 | ARRAY_AGG | UNNEST |
| Snowflake | 是 (VARIANT) | ARRAY_AGG | FLATTEN |
| Trino / Presto | 是 | array_agg | UNNEST |
| Spark / Hive | 是 | collect_list | LATERAL VIEW EXPLODE |
| DuckDB | 是 (LIST) | list / array_agg | UNNEST |
| ClickHouse | 是 | groupArray | ARRAY JOIN |
| Doris / StarRocks | 是 | array_agg | UNNEST |
| MySQL | 否 (JSON 替代) | JSON_ARRAYAGG | JSON_TABLE |
| MariaDB | 否 (JSON 替代) | JSON_ARRAYAGG | JSON_TABLE |
| TiDB | 否 (JSON 替代) | JSON_ARRAYAGG | JSON_TABLE |
| SQL Server | 否 | -- | -- |
| SQLite | 否 | -- | -- |
| Oracle | 是 (VARRAY/TABLE) | COLLECT | TABLE() |

## 各引擎语法详解

### PostgreSQL（最早最完整的标准实现）

PostgreSQL 8.4（2009 年发布）是业界第一个完整实现 SQL:2003 `ARRAY_AGG` 的开源数据库。它的设计成为后续多数引擎模仿的范本——PG 风格的 `ARRAY_AGG(col ORDER BY ...)` 影响了 BigQuery、DuckDB、Trino 等。

```sql
-- 基本用法：聚合为数组
SELECT dept_id, ARRAY_AGG(name) AS names
FROM employees GROUP BY dept_id;
-- dept_id | names
-- 1       | {Alice,Bob,Charlie}
-- 2       | {Dave}

-- ORDER BY: 控制数组内元素顺序
SELECT dept_id, ARRAY_AGG(name ORDER BY name) AS sorted_names
FROM employees GROUP BY dept_id;

-- 多列排序
SELECT dept_id, ARRAY_AGG(name ORDER BY hire_date DESC, name ASC) AS names
FROM employees GROUP BY dept_id;

-- DISTINCT
SELECT dept_id, ARRAY_AGG(DISTINCT skill) AS unique_skills
FROM employee_skills GROUP BY dept_id;

-- DISTINCT 与 ORDER BY 的限制
-- 注意：DISTINCT 与 ORDER BY 同时使用时，ORDER BY 表达式必须出现在 SELECT 列表中
SELECT dept_id, ARRAY_AGG(DISTINCT name ORDER BY name) AS unique_sorted_names
FROM employees GROUP BY dept_id;

-- FILTER WHERE: 聚合前过滤（PG 9.4+）
SELECT dept_id,
       ARRAY_AGG(name) FILTER (WHERE salary > 50000) AS high_earners
FROM employees GROUP BY dept_id;

-- 嵌套：ARRAY_AGG 可以嵌套形成二维数组
SELECT region,
       ARRAY_AGG(dept_arr) AS region_depts
FROM (
    SELECT region, dept_id, ARRAY_AGG(name) AS dept_arr
    FROM employees
    GROUP BY region, dept_id
) t
GROUP BY region;

-- 返回的数组是 PostgreSQL 一等公民，可以继续操作
SELECT dept_id, ARRAY_AGG(name) AS names,
       array_length(ARRAY_AGG(name), 1) AS member_count,
       (ARRAY_AGG(name ORDER BY name))[1] AS first_name,
       (ARRAY_AGG(name ORDER BY hire_date DESC))[1:3] AS top_3_recent
FROM employees GROUP BY dept_id;

-- UNNEST 把数组展开回行
SELECT dept_id, name
FROM (
    SELECT dept_id, ARRAY_AGG(name) AS names FROM employees GROUP BY dept_id
) t, UNNEST(t.names) AS name;

-- 与 ARRAY_TO_STRING 组合 = STRING_AGG
SELECT dept_id, ARRAY_TO_STRING(ARRAY_AGG(name ORDER BY name), ', ') AS names_csv
FROM employees GROUP BY dept_id;

-- NULL 处理：标准要求保留 NULL 元素，PG 也是如此
SELECT ARRAY_AGG(col) FROM (VALUES (1), (NULL), (2)) t(col);
-- {1,NULL,2}    ← NULL 被保留

-- 空集返回 NULL（不是空数组）
SELECT ARRAY_AGG(col) FROM employees WHERE 1 = 0;
-- NULL

-- 安全写法：保证返回空数组
SELECT COALESCE(ARRAY_AGG(col), ARRAY[]::text[]) FROM employees WHERE 1 = 0;
```

### BigQuery（最晚成熟但功能最完整）

BigQuery 的 `ARRAY_AGG` 是少数支持 LIMIT 的实现，并且通过 `IGNORE NULLS` 显式控制 NULL 行为：

```sql
-- 基本用法
SELECT dept_id, ARRAY_AGG(name) AS names
FROM employees GROUP BY dept_id;

-- ORDER BY + LIMIT (BigQuery 独有)
SELECT dept_id,
       ARRAY_AGG(name ORDER BY hire_date DESC LIMIT 5) AS top_5_recent
FROM employees GROUP BY dept_id;

-- IGNORE NULLS / RESPECT NULLS（BigQuery 独有显式控制）
SELECT ARRAY_AGG(name IGNORE NULLS) FROM employees;
SELECT ARRAY_AGG(name RESPECT NULLS) FROM employees;  -- 默认行为

-- BigQuery 注意：默认行为是 RESPECT NULLS（保留 NULL）
-- 但 ARRAY 元素本身不能是 NULL（BigQuery ARRAY 类型限制）
-- 因此如果输入有 NULL，必须用 IGNORE NULLS，否则报错：
-- "An ARRAY cannot contain a NULL element"

-- DISTINCT
SELECT ARRAY_AGG(DISTINCT skill) FROM employee_skills;

-- 通过 STRUCT 聚合多列
SELECT dept_id,
       ARRAY_AGG(STRUCT(name, salary, hire_date) ORDER BY hire_date DESC LIMIT 5)
       AS recent_hires
FROM employees GROUP BY dept_id;

-- ARRAY_CONCAT_AGG: 合并多个数组（不是聚合标量）
SELECT user_id, ARRAY_CONCAT_AGG(events) AS all_events
FROM user_event_arrays GROUP BY user_id;

-- UNNEST 展开
SELECT t.dept_id, name
FROM dept_summary t, UNNEST(t.names) AS name;
```

BigQuery 的设计特点：

```
1. ARRAY 元素不能是 NULL（语言级限制）
2. IGNORE NULLS / RESPECT NULLS 是必需的显式选择
3. ORDER BY 内嵌 LIMIT，方便取 top-N
4. ARRAY_CONCAT_AGG 是独有函数，把多个数组连接为一个
5. 与 STRUCT 联合极佳：ARRAY<STRUCT<...>> 是嵌套表的核心
```

### ClickHouse（非标准命名，但功能最丰富）

ClickHouse 的 `groupArray` 系列函数采用了完全不同的命名风格（`groupArray` 而非 `array_agg`），但提供了最丰富的变体：

```sql
-- 基本聚合
SELECT dept_id, groupArray(name) AS names
FROM employees GROUP BY dept_id;

-- groupArray(N): 限制最多收集 N 个元素
SELECT dept_id, groupArray(5)(name) AS first_5_names
FROM employees GROUP BY dept_id;

-- groupUniqArray: 自动去重
SELECT dept_id, groupUniqArray(skill) AS unique_skills
FROM employee_skills GROUP BY dept_id;

-- groupArrayArray: 展开嵌套数组并合并
SELECT user_id, groupArrayArray(tags) AS all_tags
FROM user_tags GROUP BY user_id;
-- 等价于 PG 的 ARRAY_CONCAT_AGG

-- groupArraySorted: 自动排序的聚合
SELECT dept_id, groupArraySorted(10)(salary) AS top_10_salaries
FROM employees GROUP BY dept_id;

-- 排序：通过 arraySort 后置
SELECT dept_id, arraySort(groupArray(name)) AS sorted_names
FROM employees GROUP BY dept_id;

-- 复杂排序：基于其他键
SELECT dept_id,
       arrayMap(x -> x.2,
           arraySort(x -> x.1, groupArray((hire_date, name))))
       AS names_by_hire_date
FROM employees GROUP BY dept_id;

-- FILTER：通过 -If 后缀
SELECT dept_id, groupArrayIf(name, salary > 50000) AS high_earners
FROM employees GROUP BY dept_id;

-- groupArrayMovingAvg / groupArrayMovingSum: 移动窗口聚合
SELECT user_id,
       groupArrayMovingAvg(7)(daily_amount) AS rolling_7d_avg
FROM daily_metrics GROUP BY user_id;

-- 最重要的差异：groupArray 默认不保证元素顺序
-- 即使输入有序，结果数组可能乱序
-- 必须显式 arraySort 或 ORDER BY
```

ClickHouse 的 `groupArray` 系列变体是其他引擎少见的：

| 函数 | 等价标准语义 |
|------|------------|
| `groupArray` | `ARRAY_AGG` |
| `groupArray(N)` | `ARRAY_AGG(... LIMIT N)` |
| `groupUniqArray` | `ARRAY_AGG(DISTINCT)` |
| `groupArrayArray` | `ARRAY_CONCAT_AGG` |
| `groupArraySorted(N)` | `ARRAY_AGG(... ORDER BY x DESC LIMIT N)` |
| `groupArrayInsertAt(value, pos)` | 按位置填充数组（独有） |
| `groupArrayMovingAvg/Sum` | 移动窗口聚合（独有） |

### Spark SQL / Hive collect_list / collect_set

Hive 0.13（2014 年）首次引入 `collect_list` 和 `collect_set`，这一对函数后被 Spark SQL 完全继承，并形成大数据领域最广泛使用的数组聚合接口：

```sql
-- collect_list: 聚合为数组，保留重复值
SELECT dept_id, collect_list(name) AS all_names
FROM employees GROUP BY dept_id;
-- dept_id | all_names
-- 1       | ["Alice", "Bob", "Alice", "Charlie"]    ← 保留重复

-- collect_set: 聚合为数组，自动去重
SELECT dept_id, collect_set(name) AS unique_names
FROM employees GROUP BY dept_id;
-- dept_id | unique_names
-- 1       | ["Alice", "Bob", "Charlie"]    ← 自动去重

-- 重要差异：collect_list / collect_set 不支持 ORDER BY 子句
-- 必须先排序再聚合（不可靠）或后置 sort_array
SELECT dept_id, sort_array(collect_list(name)) AS sorted_names
FROM employees GROUP BY dept_id;

-- 复杂排序：先在子查询排序
SELECT dept_id, collect_list(name) AS names
FROM (SELECT * FROM employees ORDER BY hire_date DESC) t
GROUP BY dept_id;
-- 注意：上述顺序在分布式环境中不保证（除非加 DISTRIBUTE BY）

-- Spark SQL 3.4+ 才加入 array_agg 别名（兼容标准）
SELECT dept_id, array_agg(name) AS names FROM employees GROUP BY dept_id;
-- 等价于 collect_list

-- FILTER（Spark 3.0+）
SELECT dept_id,
       collect_list(name) FILTER (WHERE active) AS active_names
FROM employees GROUP BY dept_id;

-- 与 explode 配合（反向操作）
SELECT dept_id, name
FROM dept_summary
LATERAL VIEW explode(all_names) t AS name;

-- collect_set 的去重基于精确比较，对 STRUCT 类型也有效
SELECT collect_set(named_struct('name', name, 'salary', salary))
FROM employees;
```

`collect_list` 与 `collect_set` 的对比：

| 维度 | collect_list | collect_set |
|------|-------------|-------------|
| 是否去重 | 否（保留重复） | 是（自动去重） |
| 元素顺序 | 输入顺序（不保证） | 不保证 |
| 性能 | 快（仅追加） | 慢（需要哈希集合维护） |
| 内存 | 与输入行数成正比 | 与去重后元素数成正比 |
| 等价 SQL 标准 | `ARRAY_AGG` | `ARRAY_AGG(DISTINCT)` |
| NULL 处理 | 跳过 NULL（与标准不同） | 跳过 NULL |
| 何时用 | 需要保留所有原始数据 | 只关心唯一值集合 |

注意：Hive/Spark 的 `collect_list`/`collect_set` 都跳过 NULL 输入，这与 SQL:2003 标准要求"保留 NULL"不一致。这是历史设计选择，不是 bug。

### MySQL JSON_ARRAYAGG（无原生 ARRAY 的妥协方案）

MySQL 5.7.22（2018 年）引入 `JSON_ARRAYAGG`，但因为 MySQL 没有原生 ARRAY 类型，返回值是 JSON 数组（实际存储为 LONGTEXT）：

```sql
-- 基本用法
SELECT dept_id, JSON_ARRAYAGG(name) AS names
FROM employees GROUP BY dept_id;
-- dept_id | names
-- 1       | ["Alice", "Bob", "Charlie"]
-- 注意：返回的是 JSON 字符串，不是真正的数组

-- 后续操作必须用 JSON_* 函数
SELECT dept_id,
       JSON_LENGTH(JSON_ARRAYAGG(name)) AS member_count,
       JSON_EXTRACT(JSON_ARRAYAGG(name), '$[0]') AS first_name
FROM employees GROUP BY dept_id;

-- ORDER BY (MySQL 8.0.40+)
SELECT dept_id, JSON_ARRAYAGG(name ORDER BY hire_date DESC)
FROM employees GROUP BY dept_id;

-- DISTINCT (8.0+)
SELECT JSON_ARRAYAGG(DISTINCT skill) FROM employee_skills;

-- 与 JSON_OBJECTAGG 配对（聚合为 JSON 对象）
SELECT JSON_OBJECTAGG(emp_id, name) FROM employees;
-- {"1":"Alice","2":"Bob",...}

-- 关键限制：受 max_allowed_packet 限制（默认 64MB）
-- 超出会报错：ER_NET_PACKET_TOO_LARGE

-- 关键陷阱：返回的 JSON 字符串无法直接 UNNEST
-- 需要 JSON_TABLE 解析（MySQL 8.0+）
SELECT dept_id, t.name
FROM (
    SELECT dept_id, JSON_ARRAYAGG(name) AS names
    FROM employees GROUP BY dept_id
) summary,
JSON_TABLE(summary.names, '$[*]' COLUMNS (name VARCHAR(50) PATH '$')) t;
```

MySQL 用户的核心痛点：

```
1. 类型保真丢失：所有元素经 JSON 序列化，DATETIME → 字符串、DECIMAL → 数字
2. 性能差：JSON 序列化/反序列化开销显著
3. 不可索引：JSON 数组结果通常不可作为索引列
4. 无 FILTER：必须用 CASE WHEN 模拟
5. 元素操作笨重：JSON_EXTRACT 路径表达式不如下标直接
6. 与多数 ORM 不兼容：返回的 JSON 字符串需手工反序列化
```

### SQL Server（永远没有 ARRAY_AGG）

SQL Server 至今（2022 版本）仍未实现 ARRAY_AGG，这与其设计哲学一致：T-SQL 没有原生数组类型。要聚合多行：

```sql
-- 选项 1：STRING_AGG（仅支持字符串聚合，不是真正数组）
SELECT dept_id, STRING_AGG(name, ', ') WITHIN GROUP (ORDER BY name) AS names
FROM employees GROUP BY dept_id;

-- 选项 2：FOR XML PATH（旧版常用 hack，效率低）
SELECT dept_id,
    STUFF((
        SELECT ', ' + name FROM employees e2 WHERE e2.dept_id = e1.dept_id
        ORDER BY name FOR XML PATH('')
    ), 1, 2, '') AS names
FROM employees e1 GROUP BY dept_id;

-- 选项 3：FOR JSON PATH（2017+，返回 JSON 字符串）
SELECT dept_id,
    (SELECT name FROM employees e2 WHERE e2.dept_id = e1.dept_id
     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS names_json
FROM employees e1 GROUP BY dept_id;
-- 返回 JSON 字符串 [{"name":"Alice"},{"name":"Bob"}]

-- 选项 4：表值参数 / 临时表（最接近原生数组）
DECLARE @names NameList;  -- 假设已定义类型
INSERT @names SELECT name FROM employees WHERE dept_id = 1;

-- 选项 5：仅在应用层组装数组
```

为什么 SQL Server 拒绝实现 ARRAY_AGG：

```
1. T-SQL 类型系统设计：以表为唯一集合容器，反对"行内多值"
2. XML / JSON 已被认为足以处理嵌套数据（自 2005/2017）
3. 微软对兼容性极保守，引入新类型涉及索引、统计、查询计划的重大改造
4. 用户反馈集中在 STRING_AGG（已 2017 实现），ARRAY_AGG 优先级靠后
5. Azure Synapse 与 Fabric 也继承了这一设计
```

### Snowflake ARRAY_AGG（VARIANT 元素，WITHIN GROUP 排序）

```sql
-- 基本用法
SELECT dept_id, ARRAY_AGG(name) AS names
FROM employees GROUP BY dept_id;
-- 返回 ARRAY 类型，元素是 VARIANT

-- WITHIN GROUP 风格的 ORDER BY
SELECT dept_id, ARRAY_AGG(name) WITHIN GROUP (ORDER BY hire_date DESC) AS names
FROM employees GROUP BY dept_id;

-- DISTINCT
SELECT ARRAY_AGG(DISTINCT skill) FROM employee_skills;

-- 嵌套：与 OBJECT_CONSTRUCT 组合产生 ARRAY<OBJECT>
SELECT dept_id,
       ARRAY_AGG(OBJECT_CONSTRUCT('name', name, 'salary', salary))
       WITHIN GROUP (ORDER BY hire_date DESC)
       AS detail_array
FROM employees GROUP BY dept_id;

-- 后续操作：FLATTEN 展开
SELECT dept_id, value:name::VARCHAR AS name
FROM dept_summary, LATERAL FLATTEN(input => detail_array);

-- ARRAY_AGG 与窗口结合
SELECT name, dept_id,
       ARRAY_AGG(name) WITHIN GROUP (ORDER BY name)
           OVER (PARTITION BY dept_id) AS dept_names
FROM employees;

-- ARRAY_AGG_DISTINCT 是不存在的；用 DISTINCT 修饰符
SELECT dept_id, ARRAY_AGG(DISTINCT skill) FROM employee_skills GROUP BY dept_id;
```

Snowflake 的特殊点：

```
1. ARRAY 元素都是 VARIANT 类型，不强制类型一致
2. WITHIN GROUP (ORDER BY) 风格，与标准 LISTAGG 一致
3. 不支持 FILTER 子句
4. ARRAY_AGG 结果可以通过 VARIANT 强转：col::ARRAY
5. 整体性能受 VARIANT 影响，不如严格类型系统优化
```

### DuckDB list / array_agg（最丰富的兼容性别名）

DuckDB 是兼容性最好的引擎之一，为数组聚合提供了多个别名：

```sql
-- 三个等价别名
SELECT dept_id, list(name) FROM employees GROUP BY dept_id;
SELECT dept_id, array_agg(name) FROM employees GROUP BY dept_id;
SELECT dept_id, list_agg(name) FROM employees GROUP BY dept_id;
-- 三者结果完全一致

-- ORDER BY (PG 风格)
SELECT dept_id, array_agg(name ORDER BY hire_date DESC) FROM employees GROUP BY dept_id;

-- DISTINCT
SELECT array_agg(DISTINCT skill) FROM employee_skills;

-- FILTER (PG 风格)
SELECT dept_id, array_agg(name) FILTER (WHERE active) FROM employees GROUP BY dept_id;

-- 注意：DuckDB 的 LIST<T> 类型实际就是 ARRAY<T>
-- 操作时下标从 1 开始（PG 风格）
SELECT (array_agg(name ORDER BY name))[1] AS first_name FROM employees;

-- DuckDB 独有：list_concat / list_aggregate / list_transform 等丰富的列表 lambda
SELECT list_transform(array_agg(salary), x -> x * 1.1) AS adjusted_salaries
FROM employees;

-- 与 unnest 配合
SELECT name FROM (SELECT array_agg(name) AS names FROM employees), unnest(names) AS name;

-- 还兼容 collect_list / collect_set （3.0+）
SELECT collect_list(name) FROM employees;   -- 等价 array_agg
SELECT collect_set(name) FROM employees;    -- 等价 array_agg(DISTINCT)
```

### Trino / Presto array_agg

```sql
-- 基本用法
SELECT dept_id, array_agg(name) FROM employees GROUP BY dept_id;

-- ORDER BY (PG 风格)
SELECT dept_id, array_agg(name ORDER BY hire_date DESC) FROM employees GROUP BY dept_id;

-- DISTINCT
SELECT array_agg(DISTINCT skill) FROM employee_skills;

-- FILTER
SELECT dept_id, array_agg(name) FILTER (WHERE active) FROM employees GROUP BY dept_id;

-- multimap_agg: 聚合 (key, value) 为 map<key, array<value>>
SELECT multimap_agg(dept_id, name) FROM employees;
-- {1: [Alice, Bob], 2: [Charlie]}

-- 与 UNNEST 配合
SELECT name FROM (SELECT array_agg(name) AS names FROM employees) CROSS JOIN UNNEST(names) AS t(name);

-- Trino 独有的内建函数与 array_agg 协同：
-- array_join: 等价于 array_to_string
-- array_distinct: 数组级别去重
SELECT array_join(array_distinct(array_agg(skill)), ', ') FROM employee_skills;
-- 与 STRING_AGG(DISTINCT skill) 等价
```

### Oracle COLLECT（非标准但更早）

Oracle 的 `COLLECT` 早于 SQL:2003 的 `ARRAY_AGG`，使用 SQL:1999 MULTISET 语义：

```sql
-- 必须先定义集合类型（Oracle 风格）
CREATE OR REPLACE TYPE name_list AS TABLE OF VARCHAR2(100);

-- 使用 COLLECT
SELECT dept_id, CAST(COLLECT(name ORDER BY name) AS name_list) AS names
FROM employees GROUP BY dept_id;

-- 不需要类型转换的简化用法（Oracle 21c+）
SELECT dept_id, COLLECT(name) FROM employees GROUP BY dept_id;

-- DISTINCT
SELECT dept_id, CAST(COLLECT(DISTINCT skill) AS skill_list) FROM employee_skills GROUP BY dept_id;

-- 与 TABLE() 操作符展开
SELECT t.column_value
FROM TABLE(SELECT COLLECT(name) FROM employees WHERE dept_id = 1) t;

-- 注意：Oracle 也有 ARRAY_AGG 的扩展（19c+），但仍以 COLLECT 为主流
```

### DB2 ARRAY_AGG

```sql
-- 基本用法（DB2 9.7+）
SELECT dept_id, ARRAY_AGG(name) AS names FROM employees GROUP BY dept_id;

-- ORDER BY
SELECT dept_id, ARRAY_AGG(name ORDER BY hire_date DESC) FROM employees GROUP BY dept_id;

-- DISTINCT
SELECT ARRAY_AGG(DISTINCT skill) FROM employee_skills;

-- FILTER
SELECT dept_id, ARRAY_AGG(name) FILTER (WHERE active) FROM employees GROUP BY dept_id;

-- 重要限制：DB2 的 ARRAY_AGG 主要用于 SQL PL（存储过程）上下文
-- 普通 SELECT 中需要 ARRAY 类型的目标
DECLARE name_list ANCHOR DATA TYPE TO ARRAY OF VARCHAR(100);
SET name_list = (SELECT ARRAY_AGG(name) FROM employees WHERE dept_id = 1);
```

### Teradata ARRAY_AGG（晚到的 WITHIN GROUP）

```sql
-- Teradata 16.0+
SELECT dept_id, ARRAY_AGG(name) WITHIN GROUP (ORDER BY hire_date DESC) AS names
FROM employees GROUP BY dept_id;

-- Teradata 还提供 ARRAY 类型的字面量与索引访问
-- 例如：ARRAY_AGG 结果可以直接通过 [1]、[1:5] 访问

-- 限制：Teradata ARRAY 是固定大小（最大长度需要在表定义中声明）
-- 因此 ARRAY_AGG 受总元素数限制
```

### CockroachDB / YugabyteDB / Greenplum / TimescaleDB

这些 PostgreSQL 兼容引擎完全继承 PG 的 `array_agg` 行为：

```sql
-- 全部支持标准 PG 风格
SELECT dept_id, array_agg(name ORDER BY name) AS sorted_names
FROM employees GROUP BY dept_id;

-- DISTINCT、FILTER 全部支持
SELECT array_agg(DISTINCT skill) FILTER (WHERE active) FROM employee_skills;

-- 分布式实现差异：
-- CockroachDB/YugabyteDB: 分布式 shuffle 后局部聚合
-- Greenplum: MPP 架构，每个 segment 局部聚合后合并
-- TimescaleDB: 仅扩展 PG，继承全部行为
```

### Doris / StarRocks

```sql
-- Doris 1.2+ / StarRocks 2.5+
SELECT dept_id, array_agg(name) FROM employees GROUP BY dept_id;

-- ORDER BY (晚期版本)
SELECT dept_id, array_agg(name ORDER BY hire_date DESC) FROM employees GROUP BY dept_id;

-- collect_list 别名（Doris 兼容）
SELECT dept_id, collect_list(name) FROM employees GROUP BY dept_id;

-- collect_set
SELECT dept_id, collect_set(skill) FROM employee_skills GROUP BY dept_id;

-- DISTINCT
SELECT array_agg(DISTINCT skill) FROM employee_skills;

-- 不支持 FILTER WHERE，需用 CASE WHEN
```

### Flink SQL ARRAY_AGG（流处理特殊点）

```sql
-- Flink 1.18+ 加入 ARRAY_AGG
SELECT dept_id, ARRAY_AGG(name) AS names FROM employees GROUP BY dept_id;

-- 流式语义的特殊性：
-- 1. 在 GROUP BY 上用 ARRAY_AGG 等同于"无界聚合"，状态会持续增长
-- 2. 必须配合窗口聚合（TUMBLE、HOP、SESSION）使用
SELECT
    TUMBLE_START(rowtime, INTERVAL '5' MINUTE) AS window_start,
    user_id,
    ARRAY_AGG(event_type) AS events
FROM user_events
GROUP BY TUMBLE(rowtime, INTERVAL '5' MINUTE), user_id;
-- 每 5 分钟窗口聚合，避免无界状态

-- 1.17 之前需要 UDAF 或转换为 STRING_AGG
```

## ORDER BY within ARRAY_AGG: 两种风格

### PG 风格：函数内 ORDER BY

```sql
-- PostgreSQL / DuckDB / BigQuery / Trino / DB2 / SAP HANA
ARRAY_AGG(col ORDER BY sort_expr [ASC|DESC])
```

```sql
SELECT ARRAY_AGG(name ORDER BY hire_date DESC) FROM employees;
SELECT ARRAY_AGG(name ORDER BY salary DESC, name ASC) FROM employees;
```

### WITHIN GROUP 风格

```sql
-- Snowflake / Teradata / Oracle (LISTAGG 是同一风格)
ARRAY_AGG(col) WITHIN GROUP (ORDER BY sort_expr [ASC|DESC])
```

```sql
SELECT ARRAY_AGG(name) WITHIN GROUP (ORDER BY hire_date DESC) FROM employees;
```

两种风格的对比：

| 维度 | PG 风格 | WITHIN GROUP 风格 |
|------|---------|------------------|
| 起源 | PostgreSQL 8.4 (2009) | SQL:2003 有序集合聚合 |
| 适用面 | array_agg, string_agg, json_agg 等 | LISTAGG、percentile_cont 等专用聚合 |
| 与 OVER 配合 | 可以 | 可以 |
| 与 FILTER 配合 | 可以 | 部分引擎可以 |
| DISTINCT 兼容 | 可以 | 多数引擎不可同时使用 |
| 阅读性 | 简洁 | 显式区分聚合参数与排序键 |

可移植写法：尽可能使用 PG 风格（兼容引擎更多），WITHIN GROUP 风格仅在 Snowflake/Teradata/Oracle 上必要。

### 跨引擎可移植代码片段

```sql
-- 写法 1：PG 风格（PG/BigQuery/DuckDB/Trino/DB2/SAP HANA/H2/HSQLDB/Doris/StarRocks）
SELECT dept_id, ARRAY_AGG(name ORDER BY name) FROM employees GROUP BY dept_id;

-- 写法 2：WITHIN GROUP（Snowflake/Teradata）
SELECT dept_id, ARRAY_AGG(name) WITHIN GROUP (ORDER BY name) FROM employees GROUP BY dept_id;

-- 写法 3：Spark/Hive 后置 sort_array
SELECT dept_id, sort_array(collect_list(name)) FROM employees GROUP BY dept_id;

-- 写法 4：ClickHouse 后置 arraySort
SELECT dept_id, arraySort(groupArray(name)) FROM employees GROUP BY dept_id;

-- 写法 5：MySQL 8.0.40+
SELECT dept_id, JSON_ARRAYAGG(name ORDER BY name) FROM employees GROUP BY dept_id;
```

## MySQL JSON_ARRAYAGG: 没有原生数组的妥协

MySQL 走的路径与其他主流引擎不同：因为没有原生 ARRAY 类型，MySQL 选择用 JSON 数组承载聚合结果。

```sql
-- 等价于其他引擎的 ARRAY_AGG
SELECT dept_id, JSON_ARRAYAGG(name) AS names_json FROM employees GROUP BY dept_id;

-- 返回 JSON 数组（实际是 LONGTEXT 字符串）
-- ["Alice", "Bob", "Charlie"]
```

JSON_ARRAYAGG vs 真正的 ARRAY_AGG：

```
功能等价性：
+ JSON_ARRAYAGG 提供"多行 → 单值"的聚合能力
+ 支持 ORDER BY (8.0.40+) 与 DISTINCT (8.0+)
+ 可以用 JSON_TABLE 反向展开

性能与体验差距：
- 序列化/反序列化开销（每次 JSON 编解码）
- 类型保真丢失（DECIMAL → JSON 数字、DATE → 字符串）
- 无 FILTER 支持，必须用 CASE WHEN
- 无下标语法，必须用 JSON_EXTRACT('$[0]')
- 不可索引（JSON 数组列做索引需 generated column）
- 受 max_allowed_packet 限制（默认 64MB），超出报错
- 与 ORM 的集成笨重（需手工反序列化）
```

迁移影响：从 PG/Snowflake 迁移到 MySQL（或反之）时，所有 ARRAY_AGG 代码都需要重写：

```sql
-- PostgreSQL
SELECT dept_id, ARRAY_AGG(name ORDER BY name) FROM employees GROUP BY dept_id;
-- 后续: SELECT names[1] FROM ...

-- MySQL 等价
SELECT dept_id, JSON_ARRAYAGG(name ORDER BY name) FROM employees GROUP BY dept_id;
-- 后续: SELECT JSON_EXTRACT(names, '$[0]') FROM ...
-- 或   SELECT names ->> '$[0]' FROM ...
```

JSON_ARRAYAGG 的另一个用法是配合 JSON_OBJECTAGG 构造嵌套 JSON 文档：

```sql
-- 构造每个部门的员工详情数组
SELECT dept_id,
       JSON_ARRAYAGG(JSON_OBJECT('name', name, 'salary', salary))
FROM employees GROUP BY dept_id;
-- {"dept_id": 1, "employees": [{"name": "Alice", "salary": 60000}, ...]}
```

## collect_list vs collect_set：Hive/Spark 双子函数

Hive 0.13（2014 年）首次引入 `collect_list` 和 `collect_set`，后被 Spark SQL 全盘继承。这一对函数是大数据领域最常用的数组聚合接口，也最容易因细微语义差被误用。

### 语义对比

```sql
-- 输入：
-- dept_id | name | role
-- 1       | Alice | engineer
-- 1       | Bob | manager
-- 1       | Alice | engineer       ← 重复行
-- 2       | Charlie | engineer

-- collect_list: 保留所有值（包括重复）
SELECT dept_id, collect_list(name) FROM employees GROUP BY dept_id;
-- 1 | ["Alice", "Bob", "Alice"]    ← 重复保留
-- 2 | ["Charlie"]

-- collect_set: 自动去重
SELECT dept_id, collect_set(name) FROM employees GROUP BY dept_id;
-- 1 | ["Alice", "Bob"]              ← 去重
-- 2 | ["Charlie"]
```

### 性能与内存差异

```
collect_list 性能特性：
+ 仅追加操作，时间复杂度 O(N)
+ 内存占用 = 每个值的内存 × 数量
+ 适合：日志拼接、事件序列、保留全部历史

collect_set 性能特性：
+ 维护哈希集合，时间复杂度 O(N) 平均（哈希冲突 O(N²) 最坏）
+ 内存占用 = 唯一值数量 × 单值内存
+ 适合：标签集合、唯一用户列表、去重统计
+ 警告：高基数列上慢且耗内存（如 user_id）
```

### 与 ORDER BY 的局限

`collect_list` / `collect_set` 都不接受 ORDER BY 子句：

```sql
-- 错误（语法不允许）
SELECT collect_list(name ORDER BY hire_date) FROM employees;
-- AnalysisException

-- 解决方案 1: 后置 sort_array（仅可按元素自身排序）
SELECT sort_array(collect_list(name)) FROM employees;
-- 仅按 name 字典序排序

-- 解决方案 2: 子查询先排序（分布式不保证顺序）
SELECT collect_list(name)
FROM (SELECT * FROM employees ORDER BY hire_date) t
GROUP BY dept_id;
-- 分布式 shuffle 后顺序可能丢失，除非加 DISTRIBUTE BY

-- 解决方案 3: collect_list of struct，后置 array_sort
SELECT array_sort(
    collect_list(struct(hire_date, name)),
    (left, right) -> CASE WHEN left.hire_date > right.hire_date THEN -1 ELSE 1 END
) FROM employees;
-- 收集 (hire_date, name) 元组，按 hire_date 排序

-- 解决方案 4: Spark 3.0+ 用 array_agg + ORDER BY
SELECT array_agg(name ORDER BY hire_date) FROM employees;
```

### NULL 处理差异

```sql
-- Hive/Spark 的 collect_list / collect_set 跳过 NULL
-- 这与 SQL:2003 标准（保留 NULL）不一致
SELECT collect_list(col) FROM (VALUES (1), (NULL), (2)) t(col);
-- [1, 2]    ← NULL 被跳过

-- PostgreSQL 的 array_agg 保留 NULL（标准）
SELECT array_agg(col) FROM (VALUES (1), (NULL), (2)) t(col);
-- {1, NULL, 2}    ← NULL 保留
```

### Hive/Spark 与原生数组聚合的对接

随着标准化的推进，Spark SQL 3.0+ 加入了 `array_agg` 别名，3.4+ 进一步支持 ORDER BY 修饰符：

```sql
-- Spark 3.0+ 支持
SELECT array_agg(name) FROM employees;       -- 等价 collect_list

-- Spark 3.4+ 支持 ORDER BY
SELECT array_agg(name ORDER BY hire_date DESC) FROM employees;

-- 但 collect_list / collect_set 仍是 Spark/Hive 主流命名
```

## NULL 处理：标准与实际的鸿沟

不同引擎对 NULL 元素的处理存在显著差异：

| 引擎 | 标准期望 | 实际行为 | 备注 |
|------|---------|---------|------|
| PostgreSQL | 保留 NULL | 保留 NULL | 符合 SQL:2003 |
| BigQuery | 保留 NULL（默认） | 必须 IGNORE NULLS | ARRAY 元素不能 NULL |
| Snowflake | 保留 NULL | 保留 NULL | NULL 元素是 VARIANT 的 NULL |
| DuckDB | 保留 NULL | 保留 NULL | 符合 SQL:2003 |
| Trino | 保留 NULL | 保留 NULL | 符合 SQL:2003 |
| Spark SQL collect_list | 跳过 NULL | 跳过 NULL | 与标准不一致 |
| Hive collect_list | 跳过 NULL | 跳过 NULL | 与标准不一致 |
| ClickHouse groupArray | 保留 NULL | 保留 NULL | 取决于列类型是否 Nullable |
| MySQL JSON_ARRAYAGG | 保留 NULL（标准） | 保留 NULL | NULL 序列化为 JSON null |
| Oracle COLLECT | 保留 NULL | 保留 NULL | -- |

```sql
-- 测试：包含 NULL 的列
WITH data AS (SELECT * FROM (VALUES (1), (NULL), (2), (NULL), (3)) t(col))

-- PostgreSQL: {1,NULL,2,NULL,3} ← 5 个元素
-- BigQuery: 报错 "ARRAY cannot contain NULL element"，需 IGNORE NULLS
-- Spark collect_list: [1, 2, 3] ← 3 个元素，NULL 跳过
-- Snowflake: [1, null, 2, null, 3] ← 5 个元素
-- ClickHouse Nullable(Int): [1, NULL, 2, NULL, 3]
-- MySQL JSON_ARRAYAGG: [1, null, 2, null, 3]
```

跨引擎一致写法：在不依赖 NULL 元素时，主动过滤：

```sql
-- 通用安全写法
SELECT array_agg(col) FROM data WHERE col IS NOT NULL;
```

## 空集与空数组的差异

各引擎对空输入的返回值不一致：

| 引擎 | 空集返回 | 备注 |
|------|---------|------|
| PostgreSQL | `NULL` | 标准行为 |
| BigQuery | `NULL` | 标准行为 |
| Snowflake | `NULL` 或 `[]` | 取决于上下文 |
| DuckDB | `NULL` | 标准行为 |
| Trino | `NULL` | 标准行为 |
| Spark SQL | `[]`（空数组） | 与标准不一致 |
| Hive | `[]`（空数组） | 与标准不一致 |
| ClickHouse | `[]`（空数组） | 与标准不一致 |
| MySQL | `NULL` | -- |

```sql
-- 空集行为差异
SELECT ARRAY_AGG(col) FROM employees WHERE 1 = 0;
-- PostgreSQL/BigQuery/Snowflake: NULL
-- Spark/Hive/ClickHouse: []
```

跨引擎统一写法：

```sql
-- 在所有引擎上保证返回空数组
SELECT COALESCE(ARRAY_AGG(col), ARRAY[]::INT[]) FROM ...;
```

## 性能考量

### 内存占用

数组聚合在大组上可能消耗大量内存：

```
内存估算：
  ARRAY_AGG 结果大小 ≈ Σ(每个元素的字节数) + 数组元数据

  对一个 100 万行的 GROUP，每个元素 100 字节：
    ARRAY_AGG 结果 ≈ 100MB（单个聚合结果）
    若有 1000 个 GROUP → 100GB 总内存

  实际引擎应在内存超过阈值时：
  - 落盘（PostgreSQL work_mem 控制）
  - 报错（防止 OOM）
  - 截断（违反语义，多数引擎不采用）
```

### DISTINCT 的代价

```
ARRAY_AGG(DISTINCT col)：
  - 需要维护一个集合（哈希或排序）
  - 内存占用 ~ 唯一值数量 × 单值大小
  - 时间复杂度 O(N) 平均、O(N²) 最坏（哈希冲突）

collect_set 性能：
  - 哈希集合维护，与 ARRAY_AGG(DISTINCT) 相同
  - 高基数列（如 user_id）上极慢
```

### ORDER BY 的代价

```
ARRAY_AGG(col ORDER BY sort_key)：
  - 每个 GROUP 内排序，O(N log N) 时间
  - 分布式：先局部聚合，shuffle 后全局排序

  优化策略：
  - 如果 sort_key 已是分区/排序键，可避免重新排序
  - 如果数据已按 GROUP BY 列预排序（cluster by），可流式聚合
```

## 与窗口函数的组合

```sql
-- ARRAY_AGG 作为窗口函数使用
SELECT name, dept_id, hire_date,
       ARRAY_AGG(name) OVER (PARTITION BY dept_id ORDER BY hire_date) AS hires_so_far
FROM employees;
-- 每行得到截至当前的所有同部门员工列表（累积窗口）

-- PostgreSQL / BigQuery / DuckDB / Trino 都支持
-- Snowflake 用 WITHIN GROUP 风格：
SELECT name, dept_id, hire_date,
       ARRAY_AGG(name) WITHIN GROUP (ORDER BY hire_date)
           OVER (PARTITION BY dept_id) AS hires_so_far
FROM employees;
```

注意：窗口模式下 ORDER BY 既出现在窗口定义里又出现在聚合里，多数引擎按窗口的 ORDER BY 决定数组顺序。

## 真实场景：构建 JSON / OLAP 物化视图

数组聚合最大的应用之一是把规范化数据"反规范化"为 JSON 文档或 OLAP 物化视图：

```sql
-- 场景：构建用户的事件历史 JSON
SELECT
    user_id,
    JSON_OBJECT(
        'user_id', user_id,
        'recent_events', JSON_ARRAYAGG(
            JSON_OBJECT('type', event_type, 'time', event_time)
            ORDER BY event_time DESC
            LIMIT 10
        )
    ) AS user_doc
FROM user_events
GROUP BY user_id;
-- BigQuery / Snowflake / PostgreSQL 都有类似能力

-- 场景：构建宽表（每用户的所有标签数组）
SELECT user_id, ARRAY_AGG(DISTINCT tag) AS tags
FROM user_tags GROUP BY user_id;
-- 物化视图后，查询时不再需要 JOIN

-- 场景：每商品最近 30 天的销售数组
SELECT product_id, ARRAY_AGG(daily_sales ORDER BY day DESC LIMIT 30) AS sales_30d
FROM daily_product_sales GROUP BY product_id;
```

## 与 STRING_AGG 的相互转换

```sql
-- STRING_AGG → ARRAY_AGG
-- PostgreSQL: STRING_TO_ARRAY 反向
SELECT STRING_TO_ARRAY(STRING_AGG(name, ','), ',') FROM employees;
-- 等价 ARRAY_AGG(name)，但有数据丢失风险（元素含分隔符）

-- ARRAY_AGG → STRING_AGG
-- PostgreSQL/DuckDB
SELECT ARRAY_TO_STRING(ARRAY_AGG(name ORDER BY name), ', ') FROM employees;

-- BigQuery
SELECT ARRAY_TO_STRING(ARRAY_AGG(name ORDER BY name), ', ') FROM employees;

-- Trino / Presto
SELECT ARRAY_JOIN(ARRAY_AGG(name ORDER BY name), ', ') FROM employees;

-- Spark SQL
SELECT CONCAT_WS(', ', SORT_ARRAY(COLLECT_LIST(name))) FROM employees;

-- ClickHouse
SELECT arrayStringConcat(arraySort(groupArray(name)), ', ') FROM employees;
```

## 嵌套数组：ARRAY<ARRAY<T>> 与 ARRAY_CONCAT_AGG

```sql
-- 二维数组聚合
-- PostgreSQL：ARRAY_AGG 嵌套
SELECT region, ARRAY_AGG(dept_arr)
FROM (SELECT region, dept_id, ARRAY_AGG(name) AS dept_arr FROM employees GROUP BY region, dept_id) t
GROUP BY region;
-- 结果是 ARRAY<ARRAY<TEXT>>

-- BigQuery：ARRAY_CONCAT_AGG 把多个数组合并为一个（去掉嵌套）
SELECT region, ARRAY_CONCAT_AGG(events) FROM event_arrays GROUP BY region;

-- ClickHouse：groupArrayArray 等价
SELECT region, groupArrayArray(events) FROM event_arrays GROUP BY region;

-- Trino：array_agg + flatten
SELECT region, flatten(array_agg(events)) FROM event_arrays GROUP BY region;
```

## 实际迁移：跨引擎兼容写法

### 场景 1：从 MySQL 迁移到 PostgreSQL

```sql
-- 原 MySQL
SELECT dept_id, JSON_ARRAYAGG(name ORDER BY name) FROM employees GROUP BY dept_id;

-- PostgreSQL 等价（更优）
SELECT dept_id, ARRAY_AGG(name ORDER BY name) FROM employees GROUP BY dept_id;

-- 如需保留 JSON 输出
SELECT dept_id, JSON_AGG(name ORDER BY name) FROM employees GROUP BY dept_id;
-- json_agg 返回 json，jsonb_agg 返回 jsonb（推荐后者）
```

### 场景 2：从 PostgreSQL 迁移到 SQL Server

```sql
-- 原 PostgreSQL
SELECT dept_id, ARRAY_AGG(name ORDER BY name) FROM employees GROUP BY dept_id;

-- SQL Server 没有 ARRAY_AGG，改用 STRING_AGG
SELECT dept_id, STRING_AGG(name, ',') WITHIN GROUP (ORDER BY name) AS names_csv
FROM employees GROUP BY dept_id;

-- 或者用 FOR JSON
SELECT dept_id,
    (SELECT name FROM employees e2 WHERE e2.dept_id = e1.dept_id ORDER BY name
     FOR JSON AUTO) AS names_json
FROM employees e1 GROUP BY dept_id;
```

### 场景 3：从 Hive 迁移到 BigQuery

```sql
-- 原 Hive
SELECT dept_id, sort_array(collect_list(name)) FROM employees GROUP BY dept_id;

-- BigQuery
SELECT dept_id, ARRAY_AGG(name ORDER BY name) FROM employees GROUP BY dept_id;
```

### 场景 4：从 ClickHouse 迁移到 Trino

```sql
-- 原 ClickHouse
SELECT dept_id, arraySort(groupArray(name)) FROM employees GROUP BY dept_id;

-- Trino
SELECT dept_id, array_agg(name ORDER BY name) FROM employees GROUP BY dept_id;
```

## 对引擎开发者的实现建议

### 1. ARRAY_AGG 累加器设计

```
ArrayAggAccumulator<T> {
    buffer: Vec<T>              // 动态增长的元素列表
    sort_keys: Vec<SortKey>     // 如果有 ORDER BY，存储排序键
    distinct_set: HashSet<T>    // 如果有 DISTINCT，维护去重集合
    null_count: usize           // NULL 元素计数（用于 IGNORE/RESPECT NULLS）
    total_bytes: usize          // 内存占用跟踪

    fn update(value: Option<T>):
        if value.is_none():
            if respect_nulls:
                buffer.push(NULL)
            else:
                null_count += 1
            return
        let v = value.unwrap()
        if has_distinct:
            if distinct_set.insert(v):
                buffer.push(v)
        else:
            buffer.push(v)
        total_bytes += sizeof(v)
        check_memory_limit()  // 防 OOM

    fn merge(other: ArrayAggAccumulator):
        // 分布式合并
        // 关键：必须保持 ORDER BY 的全局有序性
        if has_order_by:
            // 合并时保留 (value, sort_key) 对
            // 局部已排序时可用归并合并
        else:
            // 简单 extend
        if has_distinct:
            for v in other.buffer:
                if distinct_set.insert(v):
                    buffer.push(v)

    fn finalize() -> Array<T>:
        if has_order_by:
            buffer.sort_by(sort_keys)
        return Array::from(buffer)
}
```

### 2. ORDER BY 的分布式实现

带 ORDER BY 的数组聚合在分布式环境中是难点：

```
方案 A：先全局排序，再聚合（准确，性能差）
  Phase 1: 局部排序 (sort_key, group_key, value)
  Phase 2: Shuffle by group_key
  Phase 3: 全局排序 + 聚合
  代价：所有数据需 shuffle，排序键也参与

方案 B：局部聚合保留 (value, sort_key) 对，合并时排序
  Phase 1: 局部聚合 → ArrayAggAccumulator (含 sort_key 列)
  Phase 2: Shuffle 后合并 accumulator
  Phase 3: 在 finalize 时按 sort_key 排序
  代价：内存占用 = 数据量 + 排序键大小

方案 C：分区聚合 + 后处理排序（PostgreSQL 实际策略）
  Phase 1: 局部聚合（无序）
  Phase 2: Shuffle 后合并
  Phase 3: 最终输出时整体排序
  代价：最终阶段单点瓶颈

选择建议：
- 排序键是分区键 / 已排序：方案 A，零额外代价
- 数据量小：方案 C，简单
- 数据量大且无预排序：方案 B
```

### 3. NULL 处理策略

```
设计选择：
- 标准合规（PG/Snowflake/Trino）：保留 NULL
- 大数据兼容（Spark/Hive）：跳过 NULL
- BigQuery 模式：要求显式 IGNORE NULLS / RESPECT NULLS

引擎实现建议：
1. 提供配置开关支持两种模式
2. 默认遵循 SQL:2003 标准（保留 NULL）
3. 提供 IGNORE NULLS / RESPECT NULLS 显式语法（BigQuery 模式）
4. 跨引擎兼容时优先使用过滤而非依赖默认行为
```

### 4. 内存保护与溢出处理

```
关键问题：单个 GROUP 上的 ARRAY_AGG 可能消耗大量内存

防护策略：
1. 每个 accumulator 跟踪当前内存占用
2. 超过 work_mem / 算子级内存预算时：
   - PostgreSQL: 报错 "out of memory"
   - 现代引擎: 落盘 (spill to disk) 后继续
   - 极端情况: 截断并标记（违反语义，慎用）
3. 全局聚合内存上限（防止多个大 GROUP 同时消耗）

落盘实现：
- 部分聚合状态序列化到磁盘
- 维护"内存中"和"磁盘上"两部分缓冲区
- finalize 时合并所有部分

DISTINCT 优化：
- 哈希集合的内存估算 = #unique × (key_size + 8)
- 高基数时切换为 sort-distinct（外部排序去重）
```

### 5. 与 ARRAY 类型系统的接口

```
依赖关系：
  ARRAY_AGG → 需要 ARRAY 类型
  ARRAY 类型 → 需要类型推断、序列化、子操作

类型推断：
  ARRAY_AGG(col) 的类型 = ARRAY<col 的类型>
  对于 ORDER BY 排序键不影响返回类型

边缘类型：
  ARRAY_AGG(NULL) → ARRAY<UNKNOWN>，需后续上下文确定
  ARRAY_AGG(struct_col) → ARRAY<STRUCT<...>>
  ARRAY_AGG(array_col) → ARRAY<ARRAY<...>>

序列化：
  - 行存：变长二进制 / 文本表示
  - 列存：长度数组 + 元素列（Dremel 模型）
  - JSON 引擎：JSON 数组字符串
```

### 6. 兼容性策略：多别名支持

DuckDB 是最佳实践，同时支持：
- `array_agg`（标准）
- `list`（DuckDB 原生）
- `list_agg`（变体）
- `collect_list` / `collect_set`（Hive/Spark 兼容）

```
建议引擎实现：
1. 内部使用一个 ARRAY_AGG 算子
2. 解析层把所有别名映射到同一函数
3. 不同别名的语义差异（如 collect_set 隐含 DISTINCT）通过修饰符传递
4. 文档中明确标注每个别名的"权威版本"
```

### 7. 与 UNNEST/EXPLODE 的对偶性

```
ARRAY_AGG 是 UNNEST 的逆运算：
  ARRAY_AGG(t.col) GROUP BY t.id
  = UNNEST(列出来) 再 ARRAY_AGG

引擎应保证两者的对偶性：
  1. ARRAY_AGG(UNNEST(arr)) 应能恢复原数组（除非有 DISTINCT/ORDER BY）
  2. UNNEST(ARRAY_AGG(col)) 应等价于原列（如果保持顺序）

优化器应识别这种模式：
  ARRAY_AGG → UNNEST 链可消除
  例：(SELECT ARRAY_AGG(x) FROM ...) → UNNEST → SELECT x FROM ...
```

### 8. 测试要点

```
功能测试：
- 基本聚合：单值、多值、空集
- ORDER BY：升序、降序、多列、表达式
- DISTINCT：与 ORDER BY 组合
- FILTER：与 DISTINCT、ORDER BY 组合
- NULL：保留 vs 跳过
- 嵌套：ARRAY_AGG of ARRAY_AGG

边界测试：
- 单元素 GROUP
- 全 NULL GROUP
- 极大 GROUP（100 万行）
- 极宽元素（每个 1MB）
- 极多 GROUP（百万级 GROUP）

正确性测试：
- 与 STRING_AGG 的对偶性（数组转字符串）
- 与 UNNEST 的对偶性（数组转回行）
- 与 COUNT 的一致性（数组长度 = 行数 - NULL 数）

性能测试：
- 局部聚合 vs 全局聚合
- 内存占用增长曲线
- DISTINCT 的高基数性能
- ORDER BY 的有序输入优化
```

## 总结对比矩阵

### 核心能力总览

| 能力 | PG | BigQuery | Snowflake | Trino | Spark | Hive | ClickHouse | DuckDB | DB2 | MySQL | SQL Server |
|------|---|----------|-----------|-------|-------|------|-----------|--------|-----|-------|------------|
| ARRAY_AGG 函数名 | array_agg | ARRAY_AGG | ARRAY_AGG | array_agg | collect_list / array_agg | collect_list | groupArray | array_agg / list | ARRAY_AGG | JSON_ARRAYAGG | -- |
| 原生 ARRAY 类型 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 否 (JSON) | 否 |
| ORDER BY 内嵌 | 是 | 是 | WITHIN GROUP | 是 | 3.4+ | -- | arraySort | 是 | 是 | 8.0.40+ | -- |
| LIMIT 内嵌 | -- | 是 | -- | -- | -- | -- | groupArray(N) | -- | -- | -- | -- |
| DISTINCT | 是 | 是 | 是 | 是 | 3.4+ | collect_set | groupUniqArray | 是 | 是 | 是 | -- |
| FILTER WHERE | 是 | -- | -- | 是 | 是 | -- | -If 后缀 | 是 | 是 | -- | -- |
| 跳过 NULL 默认 | 否 | 必须 | 否 | 否 | 是 | 是 | 否 | 否 | 否 | 否 | -- |
| 空集返回 | NULL | NULL | NULL | NULL | [] | [] | [] | NULL | NULL | NULL | -- |
| 引入年份 | 2009 | GA | GA | 2014 | 2014 (collect_list) | 2014 | 早期 | GA | 9.7 | 2018 | -- |

### 选型建议

| 场景 | 推荐引擎 | 原因 |
|------|---------|------|
| 严格标准合规 | PostgreSQL | SQL:2003 标准实现最完整、文档最详细 |
| 多别名兼容 | DuckDB | 同时支持 array_agg/list/collect_list/collect_set |
| 大数据栈 | Spark + array_agg (3.4+) | 兼顾 collect_list 历史代码与标准语义 |
| Top-N 聚合 | BigQuery | ARRAY_AGG(... ORDER BY x LIMIT N) 内嵌简洁 |
| OLAP 分析 | ClickHouse groupArray + 变体 | 性能与功能丰富度最强 |
| 严格 NULL 控制 | BigQuery (IGNORE NULLS / RESPECT NULLS) | 显式语法不易出错 |
| 跨引擎可移植代码 | DuckDB / PostgreSQL 风格 | PG 风格被多数引擎兼容 |
| MySQL 兼容栈 | MySQL JSON_ARRAYAGG | 唯一可用方案，注意性能与类型保真 |
| SQL Server 用户 | STRING_AGG / FOR JSON | ARRAY_AGG 永久不会到来 |

## 关键发现

1. **数组聚合的支持深度直接由"原生 ARRAY 类型"决定**：拥有原生 ARRAY 的引擎（约 35 个）都提供 ARRAY_AGG；无原生 ARRAY 的 MySQL/MariaDB/TiDB/SingleStore 通过 JSON_ARRAYAGG 模拟，性能与体验都更差；SQL Server / SQLite / Vertica 干脆不提供数组聚合，仅有字符串聚合。

2. **PostgreSQL 8.4 (2009) 是数组聚合的"业界鼻祖"**：在 SQL:2003 标准发布六年后，PG 8.4 首先实现了完整的 array_agg。其设计（PG 风格 ORDER BY、保留 NULL、空集返回 NULL）成为后续 BigQuery / DuckDB / Trino 等的范本。

3. **SQL Server 永远不会有 ARRAY_AGG**：T-SQL 类型系统拒绝行内集合，微软选择用 STRING_AGG（2017）和 FOR JSON（2017）覆盖大部分需求。Azure Synapse 与 Microsoft Fabric 也继承此设计。

4. **MySQL 的 JSON_ARRAYAGG 是次优方案**：返回 JSON 字符串而非真正数组，类型保真丢失、性能开销大、与 ORM 集成笨重。但作为"无 ARRAY 类型"的数据库的唯一出路，它至少实现了功能等价。

5. **collect_list 与 collect_set 是大数据领域的事实标准**：Hive 0.13（2014）首创、被 Spark SQL 完全继承。两者最大区别是 set 自动去重、list 保留重复。但 NULL 跳过行为与 SQL:2003 标准（保留 NULL）不一致，这是 Hive 设计当年的历史选择。

6. **ORDER BY 的两种风格分裂**：PG 风格（`ARRAY_AGG(col ORDER BY x)`）与 WITHIN GROUP 风格（`ARRAY_AGG(col) WITHIN GROUP (ORDER BY x)`）平行演进。PG 风格被多数引擎采纳（PG/BigQuery/DuckDB/Trino/DB2/HANA/H2/HSQLDB），WITHIN GROUP 风格仅 Snowflake/Teradata/Oracle 保留——这是 SQL:2003 有序集合聚合传统的延续。

7. **空集返回的差异是迁移陷阱**：PostgreSQL/BigQuery/Snowflake/Trino/DuckDB/MySQL 返回 NULL；Spark/Hive/ClickHouse 返回空数组 `[]`。从 PG 迁移到 Spark 时，原本对 NULL 的判断会失效。

8. **DuckDB 是兼容性最好的引擎**：同时支持 `array_agg`、`list`、`list_agg`、`collect_list`、`collect_set` 五个别名，覆盖标准、PG 风格、Hive/Spark 风格的所有调用习惯。

9. **ClickHouse 的 groupArray 系列功能最丰富**：`groupArray(N)` 限制元素数、`groupUniqArray` 去重、`groupArrayArray` 合并嵌套、`groupArraySorted` 自动排序、`groupArrayMovingAvg/Sum` 移动窗口——这些变体在其他引擎都需要组合多个函数实现。

10. **FILTER WHERE 子句的采纳率仍然偏低**：仅 PG/DuckDB/Trino/Spark 3.0+/DB2/H2/HSQLDB 等 8 个引擎支持。BigQuery/Snowflake/MySQL 必须用 CASE WHEN 模拟，ClickHouse 用 -If 后缀，这进一步加剧了跨引擎代码迁移成本。

11. **ARRAY_AGG 与 STRING_AGG 是同根的两面**：在支持原生数组的引擎上，`STRING_AGG(col, sep)` 等价于 `ARRAY_TO_STRING(ARRAY_AGG(col), sep)`。但反向不成立——字符串结果的 SPLIT 还原存在数据安全风险（元素含分隔符）。这就是为什么所有现代引擎都倾向于把 ARRAY_AGG 作为更基础的能力。

12. **流处理引擎的 ARRAY_AGG 是无界状态隐患**：Flink SQL 1.18+ 才加入 ARRAY_AGG，但在 GROUP BY 上使用会产生持续增长的状态。生产中必须配合 TUMBLE/HOP/SESSION 窗口，否则状态最终会耗尽内存。

## 参考资料

- SQL:2003 标准: ISO/IEC 9075-2:2003, Section 10.9 (aggregate function - ARRAY_AGG)
- PostgreSQL: [array_agg](https://www.postgresql.org/docs/current/functions-aggregate.html)
- BigQuery: [ARRAY_AGG](https://cloud.google.com/bigquery/docs/reference/standard-sql/aggregate_functions#array_agg)
- Snowflake: [ARRAY_AGG](https://docs.snowflake.com/en/sql-reference/functions/array_agg)
- DuckDB: [array_agg / list](https://duckdb.org/docs/sql/aggregates)
- Trino: [array_agg](https://trino.io/docs/current/functions/aggregate.html#array_agg)
- ClickHouse: [groupArray](https://clickhouse.com/docs/en/sql-reference/aggregate-functions/reference/grouparray)
- Spark SQL: [collect_list / collect_set](https://spark.apache.org/docs/latest/api/sql/index.html#collect_list)
- Hive: [collect_list / collect_set](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF)
- MySQL: [JSON_ARRAYAGG](https://dev.mysql.com/doc/refman/8.0/en/aggregate-functions.html#function_json-arrayagg)
- DB2: [ARRAY_AGG](https://www.ibm.com/docs/en/db2/11.5?topic=functions-array-agg)
- Oracle: [COLLECT](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/COLLECT.html)
- SQL Server: [STRING_AGG](https://learn.microsoft.com/en-us/sql/t-sql/functions/string-agg-transact-sql) (无 ARRAY_AGG)
- Flink SQL: [ARRAY_AGG](https://nightlies.apache.org/flink/flink-docs-release-1.18/docs/dev/table/functions/systemfunctions/)
- Doris: [array_agg](https://doris.apache.org/docs/sql-manual/sql-functions/aggregate-functions/array-agg)
- StarRocks: [array_agg](https://docs.starrocks.io/docs/sql-reference/sql-functions/aggregate-functions/array_agg/)
