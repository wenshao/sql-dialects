# Hive: PIVOT / UNPIVOT (行列转换)

> 参考资料:
> - [1] Apache Hive Language Manual - LATERAL VIEW
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+LateralView
> - [2] Apache Hive Language Manual - SELECT
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select


## 1. Hive 没有原生 PIVOT / UNPIVOT 语法

 行转列(PIVOT): 使用 CASE WHEN + GROUP BY
 列转行(UNPIVOT): 使用 LATERAL VIEW + stack() 或 UNION ALL

 对比:
   Oracle:     PIVOT/UNPIVOT (11g+)
   SQL Server: PIVOT/UNPIVOT (2005+)
   Spark SQL:  不支持原生 PIVOT（DataFrame API 支持）
   BigQuery:   不支持原生 PIVOT

## 2. PIVOT: CASE WHEN + GROUP BY

```sql
SELECT
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales
GROUP BY product;

```

IF 函数版本（更简洁）

```sql
SELECT
    product,
    SUM(IF(quarter = 'Q1', amount, 0)) AS Q1,
    SUM(IF(quarter = 'Q2', amount, 0)) AS Q2,
    SUM(IF(quarter = 'Q3', amount, 0)) AS Q3,
    SUM(IF(quarter = 'Q4', amount, 0)) AS Q4
FROM sales
GROUP BY product;

```

数组聚合版本

```sql
SELECT product,
    COLLECT_LIST(CASE WHEN quarter = 'Q1' THEN amount END) AS Q1_values
FROM sales
GROUP BY product;

```

 动态 PIVOT: 需要在客户端拼接 SQL（Hive 无法在 SQL 层面动态生成列）

## 3. UNPIVOT: LATERAL VIEW + stack() (推荐)

stack(n, key1, val1, key2, val2, ...) 将列转为行

```sql
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW stack(4,
    'Q1', Q1,
    'Q2', Q2,
    'Q3', Q3,
    'Q4', Q4
) t AS quarter, amount;

```

过滤 NULL 值

```sql
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW stack(4,
    'Q1', Q1, 'Q2', Q2, 'Q3', Q3, 'Q4', Q4
) t AS quarter, amount
WHERE amount IS NOT NULL;

```

 设计分析: stack() 的优势
 stack() 是 UDTF（表生成函数），一次扫描生成多行
 对比 UNION ALL（需要扫描源表 N 次），stack() 只扫描一次
 大数据量下性能差异显著

## 4. UNPIVOT: LATERAL VIEW + explode(map())

```sql
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW EXPLODE(
    map('Q1', Q1, 'Q2', Q2, 'Q3', Q3, 'Q4', Q4)
) t AS quarter, amount;

```

 这种方式将列名和列值构造为 MAP，然后 explode 展开
 缺点: MAP 的所有值必须是相同类型

## 5. UNPIVOT: UNION ALL (通用但低效)

```sql
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;

```

 UNION ALL 的问题: 源表被扫描 4 次
 stack() 只扫描 1 次 → 大表场景下首选 stack()

## 6. 跨引擎对比: PIVOT/UNPIVOT

 引擎          PIVOT 语法        UNPIVOT 语法         替代方案
 Oracle        PIVOT(11g+)       UNPIVOT(11g+)        CASE WHEN / UNION ALL
 SQL Server    PIVOT(2005+)      UNPIVOT(2005+)       CASE WHEN / CROSS APPLY
 MySQL         不支持            不支持               CASE WHEN / UNION ALL
 PostgreSQL    不支持            不支持               CASE WHEN / UNNEST
 Hive          不支持            不支持               CASE WHEN / stack()
 Spark SQL     DataFrame pivot() 不支持               CASE WHEN / stack()
 BigQuery      PIVOT(预览)       UNPIVOT(预览)        CASE WHEN / UNNEST

## 7. 已知限制

1. 无原生 PIVOT/UNPIVOT 语法

2. 动态 PIVOT（列数不固定）需要在客户端生成 SQL

3. stack() 的列数必须在 SQL 中硬编码

4. 多个 LATERAL VIEW 是笛卡尔积（注意性能）


## 8. 对引擎开发者的启示

1. stack() UDTF 是 UNPIVOT 的高效实现:

    单次扫描 + 行扩展，比 UNION ALL 的多次扫描高效得多
2. PIVOT/UNPIVOT 语法糖值得支持:

    CASE WHEN 写法冗长且容易出错，原生语法大幅提升可读性
3. 动态 PIVOT 是所有引擎的难题:

列数在编译时必须确定，动态列需要两阶段（先查值再拼 SQL）

