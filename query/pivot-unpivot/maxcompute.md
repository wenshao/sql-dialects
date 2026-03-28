# MaxCompute (ODPS): PIVOT / UNPIVOT

> 参考资料:
> - [1] MaxCompute Documentation - SELECT
>   https://help.aliyun.com/zh/maxcompute/user-guide/select-syntax
> - [2] MaxCompute Documentation - LATERAL VIEW
>   https://help.aliyun.com/zh/maxcompute/user-guide/lateral-view


## 1. MaxCompute 没有原生 PIVOT / UNPIVOT 语法


 设计决策: 为什么不支持?
   PIVOT/UNPIVOT 是 SQL Server 2005 引入的非标准语法
   MaxCompute 继承 Hive 的 SQL 方言，Hive 也不支持
   通用替代方案: CASE WHEN + GROUP BY（PIVOT）、LATERAL VIEW（UNPIVOT）

   对比:
原生 PIVOT:   SQL Server(2005+) | Oracle(11g+) | BigQuery | Snowflake | Databricks
不支持 PIVOT: MaxCompute | Hive | PostgreSQL | MySQL | ClickHouse
   PostgreSQL/MySQL 不支持原生 PIVOT 但有 crosstab 扩展或程序化解决方案

## 2. PIVOT: CASE WHEN + GROUP BY（行转列）


场景: sales(product, quarter, amount) → 每个 product 一行，Q1~Q4 为列

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

IF 函数简写（MaxCompute/Hive 特有，更简洁）

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

 设计分析: CASE WHEN PIVOT 的局限
   必须预知所有 pivot 值（Q1, Q2, Q3, Q4）
   如果 pivot 值是动态的（事先不知道有哪些城市），需要:
### 1. 先查询所有 distinct 值

### 2. 在应用层（PyODPS/DataWorks）动态拼接 SQL

   这是"动态 PIVOT"问题 — 所有不支持原生 PIVOT 的引擎都面临此问题

## 3. UNPIVOT: LATERAL VIEW + explode(map())（列转行，推荐）


场景: quarterly_sales(product, Q1, Q2, Q3, Q4) → 每行一个季度

```sql
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW EXPLODE(
    MAP('Q1', Q1, 'Q2', Q2, 'Q3', Q3, 'Q4', Q4)
) t AS quarter, amount;

```

设计分析: MAP + EXPLODE 为什么是最佳 UNPIVOT 方案?
MAP('Q1', Q1, ...): 将多列构造为 key-value 对
EXPLODE: 将 MAP 展开为多行
LATERAL VIEW: 将展开结果与原表关联
一次扫描完成（不像 UNION ALL 需要多次扫描）

LATERAL VIEW + POSEXPLODE（带位置信息，但更复杂）

```sql
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW POSEXPLODE(
    ARRAY(Q1, Q2, Q3, Q4)
) t AS pos, amount
LATERAL VIEW POSEXPLODE(
    ARRAY('Q1', 'Q2', 'Q3', 'Q4')
) t2 AS pos2, quarter
WHERE t.pos = t2.pos2;

```

## 4. UNPIVOT: UNION ALL 方式（通用但性能差）


```sql
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;

```

 UNION ALL 方式的问题:
   每个 SELECT 扫描一次源表 → 4 列 = 4 次全表扫描
   对比 LATERAL VIEW: 一次扫描完成
   对 TB 级数据: UNION ALL 方式可能慢 4 倍

## 5. 过滤空值的 UNPIVOT


UNPIVOT 后过滤 NULL 或 0 值

```sql
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW EXPLODE(
    MAP('Q1', Q1, 'Q2', Q2, 'Q3', Q3, 'Q4', Q4)
) t AS quarter, amount
WHERE amount IS NOT NULL AND amount > 0;

```

 对比原生 UNPIVOT 语法（SQL Server/Oracle）:
 SELECT product, quarter, amount
 FROM quarterly_sales
 UNPIVOT (amount FOR quarter IN (Q1, Q2, Q3, Q4)) unpvt;
 原生语法自动过滤 NULL

## 6. 横向对比: PIVOT/UNPIVOT


 原生 PIVOT:
MaxCompute: 不支持（CASE WHEN）    | BigQuery: PIVOT 子句
SQL Server: PIVOT 子句（2005+）    | Oracle: PIVOT 子句（11g+）
Snowflake:  PIVOT 子句            | PostgreSQL: crosstab（扩展）
   Databricks: PIVOT 子句

 原生 UNPIVOT:
MaxCompute: 不支持（LATERAL VIEW） | BigQuery: UNPIVOT 子句
SQL Server: UNPIVOT 子句          | Oracle: UNPIVOT 子句
Snowflake:  UNPIVOT 子句          | PostgreSQL: UNNEST/crosstab

 LATERAL VIEW EXPLODE（Hive 风格 UNPIVOT）:
MaxCompute: 支持  | Hive: 支持   | Spark: 支持
BigQuery: UNNEST   | Presto: CROSS JOIN UNNEST

## 7. 对引擎开发者的启示


### 1. 原生 PIVOT/UNPIVOT 语法虽非标准但用户需求强烈

### 2. LATERAL VIEW + MAP + EXPLODE 是优雅的 UNPIVOT 替代方案

### 3. CASE WHEN PIVOT 的动态问题需要应用层支持（SQL 无法动态生成列）

### 4. UNION ALL UNPIVOT 的多次扫描问题是性能陷阱 — 应推荐 LATERAL VIEW

### 5. 如果要实现原生 PIVOT: 需要在编译期确定列名（静态 PIVOT）

    动态 PIVOT（运行时确定列名）需要特殊的查询协议
### 6. BigQuery/Snowflake 的 PIVOT 语法值得参考 — 简洁且直观

