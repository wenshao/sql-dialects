# SQL Server: PIVOT/UNPIVOT

> 参考资料:
> - [SQL Server - FROM clause PIVOT and UNPIVOT](https://learn.microsoft.com/en-us/sql/t-sql/queries/from-using-pivot-and-unpivot)

## PIVOT: 行转列

```sql
SELECT product, [Q1], [Q2], [Q3], [Q4]
FROM (SELECT product, quarter, amount FROM sales) AS src
PIVOT (SUM(amount) FOR quarter IN ([Q1], [Q2], [Q3], [Q4])) AS pvt;
```

设计分析（对引擎开发者）:
  SQL Server 的 PIVOT 有一个隐含规则: 源子查询中未出现在 FOR 和聚合中的列
  自动成为分组列。这意味着源子查询必须精确选择需要的列——多余的列会导致
  意外的分组行为。

  典型陷阱: 如果源查询包含 id 列，每行会独立成组（因为 id 唯一），
  PIVOT 结果可能完全不是预期的。

横向对比:
  PostgreSQL: 无原生 PIVOT（使用 CASE WHEN 或 crosstab 扩展）
  MySQL:      无原生 PIVOT（使用 CASE WHEN）
  Oracle:     11g+ PIVOT（语法与 SQL Server 几乎相同）
  SQL Server: 2005+ 原生支持

对引擎开发者的启示:
  PIVOT 的隐式分组行为是易错设计。Oracle 12c 的 PIVOT 文档中明确建议
  总是在源子查询中限制列。引擎如果要实现 PIVOT，应考虑提供明确的
  GROUP BY 控制而非隐式推导。

## PIVOT: CASE WHEN 替代（全版本，更灵活）

```sql
SELECT product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales GROUP BY product;
```

CASE WHEN 的优势: 可以使用多个聚合函数（PIVOT 每次只能一个）

## UNPIVOT: 列转行

```sql
SELECT product, quarter, amount
FROM quarterly_sales
UNPIVOT (amount FOR quarter IN ([Q1], [Q2], [Q3], [Q4])) AS unpvt;
```

UNPIVOT 不保留 NULL 值的行（这是一个重要的行为差异）
如需保留，先替换 NULL:
```sql
SELECT product, quarter, amount
FROM (SELECT product, ISNULL(Q1,0) AS Q1, ISNULL(Q2,0) AS Q2,
             ISNULL(Q3,0) AS Q3, ISNULL(Q4,0) AS Q4
      FROM quarterly_sales) src
UNPIVOT (amount FOR quarter IN ([Q1],[Q2],[Q3],[Q4])) AS unpvt;
```

## CROSS APPLY + VALUES: UNPIVOT 的更灵活替代

这是 SQL Server 中 UNPIVOT 的最佳替代方案——更灵活，保留 NULL
```sql
SELECT s.product, v.quarter, v.amount
FROM quarterly_sales s
CROSS APPLY (VALUES
    ('Q1', s.Q1), ('Q2', s.Q2), ('Q3', s.Q3), ('Q4', s.Q4)
) AS v(quarter, amount);
```

过滤 NULL
```sql
SELECT s.product, v.quarter, v.amount
FROM quarterly_sales s
CROSS APPLY (VALUES
    ('Q1', s.Q1), ('Q2', s.Q2), ('Q3', s.Q3), ('Q4', s.Q4)
) AS v(quarter, amount)
WHERE v.amount IS NOT NULL;
```

设计分析（对引擎开发者）:
  CROSS APPLY + VALUES 组合是 SQL Server 社区中广泛使用的"模式"。
  它比 UNPIVOT 更灵活: 可以处理不同类型的列，可以保留 NULL，
  可以同时展开多组列。

  PostgreSQL 的等价: LATERAL JOIN + VALUES 或 UNNEST
  MySQL 的等价: UNION ALL（最原始的方式）

## 动态 PIVOT（必须使用动态 SQL）

```sql
DECLARE @cols NVARCHAR(MAX), @sql NVARCHAR(MAX);
```

2017+: 使用 STRING_AGG 构建列名列表
```sql
SELECT @cols = STRING_AGG(QUOTENAME(quarter), ', ')
FROM (SELECT DISTINCT quarter FROM sales) AS q;

SET @sql = N'SELECT product, ' + @cols + N'
FROM (SELECT product, quarter, amount FROM sales) AS src
PIVOT (SUM(amount) FOR quarter IN (' + @cols + N')) AS pvt';

EXEC sp_executesql @sql;
```

2016 之前: 使用 FOR XML PATH 替代 STRING_AGG
```sql
SELECT @cols = STUFF((
    SELECT DISTINCT ', ' + QUOTENAME(quarter) FROM sales
    FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, '');
```

设计分析（对引擎开发者）:
  动态 PIVOT 是 SQL Server 中最常见的动态 SQL 场景。
  PIVOT 的 IN 子句必须是编译时已知的常量列表——不能用子查询。
  这迫使用户使用动态 SQL，增加了 SQL 注入风险和代码复杂度。

  Oracle 11g+ 也有同样的限制。
  PostgreSQL 的 crosstab 函数同样需要预知列名。

对引擎开发者的启示:
  动态列名是 SQL 类型系统的根本限制——列名和类型必须在编译时确定。
  解决方案: JSON/MAP 类型（动态键值对），避免将维度值映射到列名。

## 动态 UNPIVOT

```sql
DECLARE @unpivot_cols NVARCHAR(MAX), @unpivot_sql NVARCHAR(MAX);

SELECT @unpivot_cols = STRING_AGG(QUOTENAME(COLUMN_NAME), ', ')
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'quarterly_sales' AND COLUMN_NAME LIKE 'Q%';

SET @unpivot_sql = N'SELECT product, quarter, amount
FROM quarterly_sales
UNPIVOT (amount FOR quarter IN (' + @unpivot_cols + N')) AS unpvt';

EXEC sp_executesql @unpivot_sql;
```

> **注意**: PIVOT 中只能使用一个聚合函数
> **注意**: UNPIVOT 默认不保留 NULL 值的行
> **注意**: CROSS APPLY + VALUES 是 UNPIVOT 的更灵活替代
> **注意**: 动态 PIVOT 使用 QUOTENAME 防止 SQL 注入
