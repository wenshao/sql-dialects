# PostgreSQL: PIVOT/UNPIVOT

> 参考资料:
> - [PostgreSQL Documentation - tablefunc (crosstab)](https://www.postgresql.org/docs/current/tablefunc.html)
> - [PostgreSQL Documentation - FILTER Clause](https://www.postgresql.org/docs/current/sql-expressions.html#SYNTAX-AGGREGATES)

## PIVOT: CASE WHEN + GROUP BY（传统方式）

```sql
SELECT product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS "Q1",
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS "Q2",
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS "Q3",
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS "Q4"
FROM sales GROUP BY product;
```

## PIVOT: FILTER 子句 (9.4+, PostgreSQL 优势)

```sql
SELECT product,
    SUM(amount) FILTER (WHERE quarter = 'Q1') AS "Q1",
    SUM(amount) FILTER (WHERE quarter = 'Q2') AS "Q2",
    SUM(amount) FILTER (WHERE quarter = 'Q3') AS "Q3",
    SUM(amount) FILTER (WHERE quarter = 'Q4') AS "Q4"
FROM sales GROUP BY product;
```

FILTER 比 CASE WHEN 更简洁，且语义更清晰。
COUNT + FILTER（经典场景: 多维度计数）
```sql
SELECT department,
    COUNT(*) FILTER (WHERE status = 'active') AS active_count,
    COUNT(*) FILTER (WHERE status = 'inactive') AS inactive_count,
    AVG(salary) FILTER (WHERE status = 'active') AS active_avg_salary
FROM employees GROUP BY department;
```

设计分析:
  FILTER 是 SQL:2003 标准，但 MySQL/Oracle/SQL Server 均不支持。
  PostgreSQL 是唯一原生支持 FILTER 的主流 RDBMS。
  对引擎开发者: FILTER 实现简单（在 agg transition 前加 if 判断），
  但用户体验提升巨大——强烈建议新引擎支持。

## PIVOT: crosstab（tablefunc 扩展）

```sql
CREATE EXTENSION IF NOT EXISTS tablefunc;
```

基本 crosstab
```sql
SELECT * FROM crosstab(
    'SELECT product, quarter, SUM(amount)
     FROM sales GROUP BY product, quarter ORDER BY product, quarter'
) AS ct(product TEXT, "Q1" NUMERIC, "Q2" NUMERIC, "Q3" NUMERIC, "Q4" NUMERIC);
```

两参数 crosstab（处理缺失值）
```sql
SELECT * FROM crosstab(
    'SELECT product, quarter, SUM(amount)
     FROM sales GROUP BY product, quarter ORDER BY product, quarter',
    'SELECT DISTINCT quarter FROM sales ORDER BY quarter'
) AS ct(product TEXT, "Q1" NUMERIC, "Q2" NUMERIC, "Q3" NUMERIC, "Q4" NUMERIC);
```

crosstab 的限制: 返回类型必须在 AS 子句中硬编码，不能动态列。

## UNPIVOT: LATERAL + VALUES (9.3+, 最佳方式)

```sql
SELECT s.product, v.quarter, v.amount
FROM quarterly_sales s
CROSS JOIN LATERAL (
    VALUES ('Q1', s."Q1"), ('Q2', s."Q2"), ('Q3', s."Q3"), ('Q4', s."Q4")
) AS v(quarter, amount)
WHERE v.amount IS NOT NULL;
```

设计分析: LATERAL + VALUES 的优势
  (a) 不需要扩展（纯 SQL）
  (b) 可以过滤 NULL（WHERE v.amount IS NOT NULL）
  (c) 可以同时 UNPIVOT 多组列
  对比:
    SQL Server: UNPIVOT 关键字（原生语法）
    Oracle:     UNPIVOT 关键字（11g+）
    MySQL:      无 UNPIVOT（只能 UNION ALL）

UNPIVOT: UNION ALL（传统方式，所有数据库通用）
```sql
SELECT product, 'Q1' AS quarter, "Q1" AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2', "Q2" FROM quarterly_sales
UNION ALL
SELECT product, 'Q3', "Q3" FROM quarterly_sales
UNION ALL
SELECT product, 'Q4', "Q4" FROM quarterly_sales;
```

UNPIVOT: unnest + array (PostgreSQL 特有)
```sql
SELECT product,
    UNNEST(ARRAY['Q1','Q2','Q3','Q4']) AS quarter,
    UNNEST(ARRAY["Q1","Q2","Q3","Q4"]) AS amount
FROM quarterly_sales;
```

## 动态 PIVOT（PL/pgSQL 动态 SQL）

PostgreSQL 无原生动态 PIVOT 语法（列名必须编译时确定）
```sql
DO $$
DECLARE
    sql_text TEXT;
    col_list TEXT;
BEGIN
    SELECT STRING_AGG(
        FORMAT('SUM(amount) FILTER (WHERE quarter = %L) AS %I', quarter, quarter),
        ', '
    ) INTO col_list
    FROM (SELECT DISTINCT quarter FROM sales ORDER BY quarter) q;
    sql_text := FORMAT('SELECT product, %s FROM sales GROUP BY product', col_list);
    RAISE NOTICE '%', sql_text;
END $$;
```

## 横向对比: PIVOT/UNPIVOT 语法

### 原生 PIVOT 语法

  SQL Server: SELECT ... FROM t PIVOT (AGG FOR col IN ([v1],[v2])) p
  Oracle:     SELECT ... FROM t PIVOT (AGG FOR col IN (v1,v2))（11g+）
  PostgreSQL: 无原生 PIVOT（用 FILTER/CASE WHEN/crosstab）
  MySQL:      无原生 PIVOT（用 CASE WHEN）

### FILTER 子句（PIVOT 最简洁方式）

  PostgreSQL: 独有（SQL 标准但其他数据库不实现）

### LATERAL + VALUES（UNPIVOT 最优雅方式）

  PostgreSQL: 9.3+
  SQL Server: CROSS APPLY + VALUES（等价）

## 对引擎开发者的启示

(1) PIVOT/UNPIVOT 原生语法的价值有争议:
    SQL Server 的 PIVOT 语法虽然原生，但不如 FILTER 灵活。
    PostgreSQL 用 FILTER + CASE WHEN 覆盖了所有 PIVOT 场景，
    且更符合 SQL 的声明式风格。

(2) 动态 PIVOT（运行时确定列数和列名）在所有数据库中都很困难:
    SQL 的列名必须在编译时确定（静态类型系统的限制）。
    解决方案: 返回 JSON 而非关系表（列数不固定的场景更适合 JSON）。

## 版本演进

PostgreSQL 8.3:  crosstab (tablefunc 扩展)
PostgreSQL 9.3:  LATERAL JOIN（使 VALUES UNPIVOT 成为可能）
PostgreSQL 9.4:  FILTER 子句（PIVOT 最佳实践）
