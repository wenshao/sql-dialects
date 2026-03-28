# Spark SQL: PIVOT / UNPIVOT (行列转换)

> 参考资料:
> - [1] Spark SQL - PIVOT
>   https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-pivot.html
> - [2] Spark SQL - UNPIVOT
>   https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-unpivot.html


## 1. PIVOT: 行转列（Spark 2.4+）


基本 PIVOT

```sql
SELECT * FROM (
    SELECT product, quarter, amount FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
);

```

多聚合 PIVOT

```sql
SELECT * FROM (
    SELECT product, quarter, amount FROM sales
)
PIVOT (
    SUM(amount) AS total,
    AVG(amount) AS average
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);

```

 设计分析:
   PIVOT 的 IN 值列表必须是字面量（不能是子查询）。
   这是 Spark/大多数 SQL 引擎的共同限制: SQL 是声明式语言，
   输出列必须在解析时确定——子查询的结果在运行时才知道。
   动态 PIVOT 需要在应用层构建 SQL 字符串。

 对比:
   MySQL:      不支持 PIVOT 语法（只能用 CASE WHEN 模拟）
   PostgreSQL: 不支持 PIVOT 语法（通过 crosstab 函数或 CASE WHEN）
   Oracle:     11g+ 支持 PIVOT（与 Spark 语法类似）
   SQL Server: 2005+ 支持 PIVOT（与 Spark 语法类似）
   BigQuery:   不支持 PIVOT 语法（用 CASE WHEN 或 PIVOT 函数）
   Flink SQL:  不支持 PIVOT

## 2. CASE WHEN 替代 PIVOT（全版本通用）


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

## 3. UNPIVOT: 列转行（Spark 3.4+）


```sql
SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

```

INCLUDE NULLS（保留 NULL 值的行）

```sql
SELECT * FROM quarterly_sales
UNPIVOT INCLUDE NULLS (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

```

## 4. stack() 函数: UNPIVOT 替代（全版本通用）


```sql
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW stack(4,
    'Q1', Q1,
    'Q2', Q2,
    'Q3', Q3,
    'Q4', Q4
) AS quarter, amount;

```

 stack(n, k1, v1, k2, v2, ..., kn, vn) 生成 n 行，每行包含一对 key-value
 这是 Hive 遗留函数，Spark 3.4 之前是 UNPIVOT 的唯一替代

## 5. UNION ALL 替代 UNPIVOT


```sql
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;

```

 缺点: 扫描源表 N 次（N = 列数），数据量翻倍
 stack() 只扫描一次，性能更优

## 6. 版本演进

Spark 2.4: PIVOT 原生语法
Spark 3.4: UNPIVOT 原生语法（INCLUDE NULLS 支持）
全版本:    CASE WHEN (PIVOT 替代), stack() (UNPIVOT 替代)

限制:
PIVOT 的 IN 值列表必须是字面量（不能是子查询——动态 PIVOT 需应用层构建）
UNPIVOT 仅 Spark 3.4+（之前使用 stack() 函数）
PIVOT 支持多聚合函数
stack() 函数是 Hive 遗留，语义不如 UNPIVOT 直观

