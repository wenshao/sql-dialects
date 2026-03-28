# Oracle: PIVOT/UNPIVOT

> 参考资料:
> - [Oracle SQL Language Reference - PIVOT and UNPIVOT](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html)

## PIVOT 基本语法（11g+）

```sql
SELECT * FROM (
    SELECT product, quarter, amount FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);
```

多聚合函数
```sql
SELECT * FROM (
    SELECT product, quarter, amount FROM sales
)
PIVOT (
    SUM(amount) AS total, COUNT(amount) AS cnt
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);
```

结果列名: Q1_TOTAL, Q1_CNT, Q2_TOTAL, Q2_CNT, ...

设计分析: PIVOT 的自动 GROUP BY
  PIVOT 子查询中"未被 PIVOT 或 FOR 引用的列"自动成为 GROUP BY 列。
  这是 Oracle 独特的隐式行为:
  SELECT product, quarter, amount → product 自动成为 GROUP BY 列

  这意味着多余的列会导致意外的分组行为:
  SELECT product, quarter, amount, created_at → product + created_at 都成为分组列!
  解决: 在子查询中只 SELECT 需要的列。

## DECODE 替代法（全版本，Oracle 独有函数）

```sql
SELECT
    product,
    SUM(DECODE(quarter, 'Q1', amount, 0)) AS Q1,
    SUM(DECODE(quarter, 'Q2', amount, 0)) AS Q2,
    SUM(DECODE(quarter, 'Q3', amount, 0)) AS Q3,
    SUM(DECODE(quarter, 'Q4', amount, 0)) AS Q4
FROM sales GROUP BY product;
```

DECODE 是 Oracle 特有的简单 CASE 语法糖:
DECODE(col, val1, result1, val2, result2, default)
等价于 CASE col WHEN val1 THEN result1 WHEN val2 THEN result2 ELSE default END

CASE WHEN 方法（SQL 标准，所有版本通用）
```sql
SELECT
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales GROUP BY product;
```

## UNPIVOT（11g+）

基本 UNPIVOT
```sql
SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);
```

INCLUDE NULLS（默认排除 NULL 行）
```sql
SELECT * FROM quarterly_sales
UNPIVOT INCLUDE NULLS (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);
```

自定义列值标签
```sql
SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1 AS 'First Quarter', Q2 AS 'Second Quarter',
                           Q3 AS 'Third Quarter', Q4 AS 'Fourth Quarter')
);
```

多列 UNPIVOT
```sql
SELECT * FROM employee_contacts
UNPIVOT (
    (contact_value, contact_type) FOR contact_kind IN (
        (home_phone, home_type) AS 'Home',
        (work_phone, work_type) AS 'Work'
    )
);
```

## UNION ALL 替代法（全版本通用）

```sql
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2', Q2 FROM quarterly_sales
UNION ALL
SELECT product, 'Q3', Q3 FROM quarterly_sales
UNION ALL
SELECT product, 'Q4', Q4 FROM quarterly_sales;
```

## 动态 PIVOT: PIVOT XML（11g+，Oracle 独有）

IN 子句中使用子查询（只有 XML 输出支持）
```sql
SELECT * FROM (
    SELECT product, quarter, amount FROM sales
)
PIVOT XML (
    SUM(amount)
    FOR quarter IN (SELECT DISTINCT quarter FROM sales)
);
```

设计分析:
  PIVOT XML 解决了"静态列名"的限制: 普通 PIVOT 要求 IN 中列出所有值。
  XML 输出允许用子查询动态获取值，但结果是 XML 格式而非关系表。

横向对比:
  Oracle:     PIVOT（静态列）+ PIVOT XML（动态列，XML 输出）
  PostgreSQL: crosstab()（tablefunc 扩展，需要指定列）
  MySQL:      无原生 PIVOT（只能用 CASE WHEN）
  SQL Server: PIVOT（静态列，类似 Oracle）
  BigQuery:   动态 SQL + EXECUTE IMMEDIATE

对引擎开发者的启示:
  PIVOT 的核心挑战是"编译时确定列数" vs "运行时动态列"。
  关系模型要求固定列数，所以动态 PIVOT 本质上需要动态 SQL 或非关系输出。

## '' = NULL 对 PIVOT/UNPIVOT 的影响

UNPIVOT 默认排除 NULL 值（EXCLUDE NULLS）
由于 '' = NULL，空字符串值也会被排除!
使用 INCLUDE NULLS 可以保留 NULL 和空字符串

PIVOT 中 DECODE(quarter, 'Q1', amount, 0):
如果 quarter 是 NULL（或空字符串），所有 DECODE 条件都不匹配，返回默认值 0

## 对引擎开发者的总结

1. Oracle 11g 首创原生 PIVOT/UNPIVOT 语法，SQL Server 也有类似支持。
2. PIVOT 的隐式 GROUP BY 是隐藏的陷阱，文档中应明确说明。
3. 动态 PIVOT 是所有数据库的共同难题，因为关系模型要求固定列数。
4. DECODE 是 Oracle 独有的遗留函数，新代码应优先使用 CASE WHEN。
5. UNPIVOT 的 EXCLUDE NULLS 行为被 '' = NULL 放大，需要注意。
