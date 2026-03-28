# 集合返回函数 (SRF)

返回多行的函数——从序列生成到数组展开，各引擎从标准方案到独有语法的差异。

## 支持矩阵

| 引擎 | 序列生成 | 数组/JSON 展开 | SRF 位置 | 版本 |
|------|---------|---------------|---------|------|
| PostgreSQL | `generate_series` | `unnest`, `jsonb_array_elements` | FROM + SELECT | 8.0+ |
| DuckDB | `generate_series`, `range` | `unnest` | FROM + SELECT | 0.3.0+ |
| BigQuery | `GENERATE_DATE_ARRAY` 等 | `UNNEST` | FROM | GA |
| Snowflake | `GENERATOR` + `SEQ` | `LATERAL FLATTEN` | FROM | GA |
| Oracle | `CONNECT BY LEVEL` | `JSON_TABLE` (12c+) | FROM (表函数) | 8i+ |
| SQL Server | 无直接 SRF | `OPENJSON`, `STRING_SPLIT` | FROM | 2016+ |
| MySQL | 无 SRF | `JSON_TABLE` (8.0+) | FROM | 8.0+ |
| ClickHouse | `numbers`, `range` | `arrayJoin` | FROM + SELECT | 早期 |
| Trino | `UNNEST`, `sequence` | `UNNEST` | FROM | 早期 |
| Spark SQL | `explode`, `posexplode` | `explode` | SELECT (LATERAL VIEW) | 1.0+ |
| Flink SQL | `UNNEST` | `UNNEST` | FROM (CROSS JOIN) | 1.0+ |

## 基本概念

集合返回函数（Set-Returning Function, SRF）是返回多行结果的函数。普通函数对每行输入返回一个标量值；SRF 对每行输入可以返回零到多行。

```
普通函数:  一行输入 → 一个值输出
聚合函数:  多行输入 → 一个值输出
SRF:       一行输入 → 多行输出
```

SRF 的典型用途：
1. **生成序列**：数字序列、日期序列
2. **展开集合**：数组、JSON 数组、字符串分割
3. **表函数**：读取外部数据源的函数

## 序列生成

### PostgreSQL: generate_series

PostgreSQL 的 `generate_series` 是最灵活的序列生成器：

```sql
-- 整数序列
SELECT generate_series(1, 5);
-- 1, 2, 3, 4, 5

-- 带步长
SELECT generate_series(0, 100, 10);
-- 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100

-- 日期序列
SELECT generate_series(
    '2024-01-01'::date,
    '2024-01-07'::date,
    '1 day'::interval
);
-- 2024-01-01, 2024-01-02, ..., 2024-01-07

-- 时间戳序列（每小时）
SELECT generate_series(
    '2024-01-01 00:00'::timestamp,
    '2024-01-01 23:00'::timestamp,
    '1 hour'::interval
);

-- 在 FROM 子句中使用（推荐）
SELECT d::date AS report_date
FROM generate_series('2024-01-01'::date, '2024-12-31'::date, '1 day') AS d;

-- 在 SELECT 中使用（PostgreSQL 特有，其他引擎不支持）
SELECT id, generate_series(1, quantity) AS item_no
FROM orders;
-- 每行展开为 quantity 行
```

### DuckDB: generate_series / range

```sql
-- generate_series: 闭区间; range: 半开区间（类似 Python）
SELECT * FROM generate_series(1, 5);         -- 1,2,3,4,5
SELECT * FROM range(1, 5);                   -- 1,2,3,4
SELECT * FROM generate_series(DATE '2024-01-01', DATE '2024-01-07', INTERVAL 1 DAY);
```

### BigQuery: GENERATE_xxx_ARRAY + UNNEST

```sql
-- 序列生成分两步: 生成数组 + UNNEST 展开
SELECT date FROM UNNEST(GENERATE_DATE_ARRAY('2024-01-01', '2024-01-07')) AS date;
SELECT n FROM UNNEST(GENERATE_ARRAY(1, 100)) AS n;
```

### Oracle: CONNECT BY LEVEL

```sql
-- 用层次查询的副作用生成序列（无直接 SRF）
SELECT LEVEL AS n FROM DUAL CONNECT BY LEVEL <= 100;
SELECT DATE '2024-01-01' + LEVEL - 1 AS d FROM DUAL CONNECT BY LEVEL <= 365;
```

### MySQL / SQL Server（递归 CTE）

```sql
-- 无 SRF，用递归 CTE 代替
WITH RECURSIVE seq (n) AS (
    SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 100
) SELECT n FROM seq;
-- SQL Server 需加 OPTION (MAXRECURSION 0) 取消 100 层限制
```

### ClickHouse: numbers / Snowflake: GENERATOR

```sql
-- ClickHouse: numbers() 表函数
SELECT number FROM numbers(10);                            -- 0..9
SELECT toDate('2024-01-01') + number AS d FROM numbers(365);

-- Snowflake: GENERATOR + SEQ4
SELECT SEQ4() AS n FROM TABLE(GENERATOR(ROWCOUNT => 100));
```

## 数组/JSON 展开

### PostgreSQL: unnest / jsonb_array_elements

```sql
-- unnest: 展开数组（最常用）
SELECT id, unnest(tags) AS tag FROM articles;

-- jsonb 数组展开
SELECT jsonb_array_elements('[1, 2, 3]'::jsonb);

-- jsonb 对象展开为键值对
SELECT * FROM jsonb_each('{"a": 1, "b": 2}'::jsonb);

-- 字符串分割展开
SELECT regexp_split_to_table('one,two,three', ',');
SELECT string_to_table('one,two,three', ',');  -- PostgreSQL 14+
```

### BigQuery: UNNEST

```sql
-- 展开数组（逗号 JOIN 隐含 LATERAL 语义）
SELECT id, tag FROM articles, UNNEST(tags) AS tag;

-- 展开 STRUCT 数组（带下标）
SELECT id, item.name, offset
FROM orders, UNNEST(items) AS item WITH OFFSET;
```

### Spark SQL: explode / posexplode

```sql
-- LATERAL VIEW + explode
SELECT id, tag FROM articles LATERAL VIEW explode(tags) t AS tag;

-- posexplode: 展开并带位置
SELECT id, pos, tag FROM articles LATERAL VIEW posexplode(tags) t AS pos, tag;

-- explode_outer: NULL 或空数组时保留原行
SELECT id, tag FROM articles LATERAL VIEW OUTER explode(tags) t AS tag;
```

### ClickHouse: arrayJoin

```sql
-- arrayJoin: 可以在 SELECT 子句中使用（不需要 FROM）
SELECT arrayJoin([1, 2, 3]) AS n;

-- 展开表中的数组列
SELECT id, arrayJoin(tags) AS tag FROM articles;
```

## 对引擎开发者的实现建议

1. SRF 在执行计划中的位置

SRF 在执行计划中的处理有两种模式：

**模式 A: FROM 子句中的 SRF (标准方式)**

```sql
SELECT * FROM generate_series(1, 10) AS t(n);
```

执行计划:

```
Project
└── TableFunctionScan (generate_series, args=[1, 10])
```

SRF 作为一个特殊的表扫描节点，与普通 TableScan 并列。这是最干净的语义。

**模式 B: SELECT 子句中的 SRF (PostgreSQL 特有)**

```sql
SELECT id, generate_series(1, quantity) FROM orders;
```

执行计划:

```
ProjectWithSRF
├── output: [id, generate_series_result]
├── srf: generate_series(1, orders.quantity)
└── TableScan(orders)
```

这种模式需要在投影算子中处理行展开——对输入的每一行，SRF 可能产生多行输出。

**推荐**: 优先支持 FROM 子句中的 SRF（标准方式）。SELECT 中的 SRF 语义复杂（多个 SRF 在 SELECT 中如何交互？PostgreSQL 在不同版本中改变过行为）。

2. 与 LATERAL 的交互

SRF 最常见的使用模式是与外部表做 LATERAL JOIN。逗号连接的 SRF 如果引用了前面表的列，应自动推断为 LATERAL 语义：

```sql
SELECT t.id, s.n
FROM my_table t, generate_series(1, t.count) AS s(n);
-- 等效于: FROM my_table t CROSS JOIN LATERAL generate_series(1, t.count) AS s(n)
```

3. 空结果与高效实现

SRF 返回零行时：CROSS JOIN 语义下外部行被过滤掉；LEFT JOIN LATERAL 下外部行保留、SRF 列为 NULL。

高效实现要点：
- **generate_series**: 迭代器模式，每次 `next()` 返回当前值并加步长，内存 O(1)
- **unnest**: 直接遍历数组元素，大数组考虑流式输出
- **JSON 数组展开**: 使用流式 JSON 解析器（SAX style），避免先解析整个 JSON

## 实际场景

```sql
-- 场景 1: 填充缺失日期（报表必备）
-- 确保每天都有数据行，无数据的天填 0
SELECT d.report_date, COALESCE(s.total, 0) AS total
FROM generate_series('2024-01-01'::date, '2024-01-31'::date, '1 day') AS d(report_date)
LEFT JOIN daily_sales s ON s.sale_date = d.report_date;

-- 场景 2: 将标签数组展开为行（用于统计）
SELECT tag, COUNT(*) AS article_count
FROM articles, unnest(tags) AS tag
GROUP BY tag
ORDER BY article_count DESC;

-- 场景 3: 生成时间桶（用于时间序列分析）
SELECT ts AS bucket_start,
       ts + INTERVAL '1 hour' AS bucket_end
FROM generate_series(
    '2024-01-01'::timestamp,
    '2024-01-31 23:00'::timestamp,
    '1 hour'::interval
) AS ts;
```

## 参考资料

- PostgreSQL: [Set Returning Functions](https://www.postgresql.org/docs/current/functions-srf.html)
- BigQuery: [GENERATE_DATE_ARRAY](https://cloud.google.com/bigquery/docs/reference/standard-sql/array_functions#generate_date_array)
- DuckDB: [generate_series](https://duckdb.org/docs/sql/functions/nested#generate_series)
- ClickHouse: [arrayJoin](https://clickhouse.com/docs/en/sql-reference/functions/array-join)
- Spark SQL: [explode](https://spark.apache.org/docs/latest/api/sql/#explode)
