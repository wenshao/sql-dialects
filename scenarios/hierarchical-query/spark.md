# Spark SQL: 层次查询与树形结构 (Hierarchical Query)

> 参考资料:
> - [1] Spark SQL - CTE
>   https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-cte.html
> - [2] GraphFrames
>   https://graphframes.github.io/graphframes/


## 示例数据

```sql
CREATE TEMPORARY VIEW employees AS
SELECT * FROM VALUES
    (1,'CEO',CAST(NULL AS INT),'总裁办'),(2,'CTO',1,'技术部'),(3,'CFO',1,'财务部'),
    (4,'VP工程',2,'技术部'),(5,'VP产品',2,'技术部'),
    (6,'开发经理',4,'技术部'),(7,'测试经理',4,'技术部'),
    (8,'开发工程师A',6,'技术部'),(9,'开发工程师B',6,'技术部'),
    (10,'测试工程师',7,'技术部'),(11,'会计主管',3,'财务部'),
    (12,'出纳',11,'财务部')
AS t(id, name, parent_id, dept);

```

## 1. 核心挑战: Spark SQL 长期缺乏递归 CTE


 递归 CTE（WITH RECURSIVE）是层次查询的标准解法。
 Spark SQL 直到 3.4+ 才实验性支持，之前只能使用替代方案。

 对比:
   PostgreSQL: WITH RECURSIVE 从 8.4 (2009) 开始支持
   Oracle:     CONNECT BY 从 7.0 开始 + WITH RECURSIVE 从 11g R2
   MySQL:      WITH RECURSIVE 从 8.0 (2018) 开始
   SQL Server: WITH RECURSIVE 从 2005 开始（MAXRECURSION 限制深度）
   Hive:       不支持递归 CTE
   Flink SQL:  不支持递归 CTE
   BigQuery:   WITH RECURSIVE 支持（有迭代次数限制）

## 2. 方案一: 多层自连接（已知深度时）


```sql
SELECT
    e1.name AS level_0,
    e2.name AS level_1,
    e3.name AS level_2,
    e4.name AS level_3
FROM employees e1
LEFT JOIN employees e2 ON e2.parent_id = e1.id
LEFT JOIN employees e3 ON e3.parent_id = e2.id
LEFT JOIN employees e4 ON e4.parent_id = e3.id
WHERE e1.parent_id IS NULL;

```

 限制: 必须提前知道层级深度，每增加一层需要多加一个 JOIN

## 3. 方案二: 路径枚举模型（推荐）


```sql
CREATE TEMPORARY VIEW categories AS
SELECT * FROM VALUES
    (1,'电子产品','1'),(2,'手机','1/2'),(3,'电脑','1/3'),
    (4,'苹果手机','1/2/4'),(5,'安卓手机','1/2/5'),
    (6,'笔记本','1/3/6')
AS t(id, name, path);

```

查询子树: LIKE 前缀匹配

```sql
SELECT * FROM categories WHERE path LIKE '1/2%';

```

计算深度

```sql
SELECT *, SIZE(SPLIT(path, '/')) - 1 AS depth FROM categories;

```

查询祖先链

```sql
SELECT c2.*
FROM categories c1
LATERAL VIEW EXPLODE(SPLIT(c1.path, '/')) t AS ancestor_id
JOIN categories c2 ON c2.id = CAST(t.ancestor_id AS INT)
WHERE c1.id = 4;

```

 路径枚举模型的优缺点:
   优点: 查询简单高效（前缀匹配即可遍历子树），不需要递归
   缺点: 插入/移动节点时需要更新所有后代的路径字符串

## 4. 方案三: 闭包表模型


```sql
CREATE TEMPORARY VIEW tree_closure AS
SELECT * FROM VALUES
    (1,1,0),(1,2,1),(1,3,1),(1,4,2),(1,5,2),
    (2,2,0),(2,4,1),(2,5,1),(2,6,2),(2,7,2),
    (3,3,0),(3,11,1),(3,12,2)
AS t(ancestor, descendant, depth);

```

查询某节点的所有后代

```sql
SELECT e.* FROM tree_closure tc
JOIN employees e ON e.id = tc.descendant
WHERE tc.ancestor = 2 AND tc.depth > 0;

```

 闭包表: 空间换时间，查询 O(1) 但存储量 O(n^2)

## 5. 方案四: GraphFrames（复杂图遍历）


 GraphFrames 提供 BFS、连通分量等图算法:
 from graphframes import GraphFrame
 vertices = spark.createDataFrame([(1,"CEO"), (2,"CTO"), ...], ["id", "name"])
 edges = spark.createDataFrame([(2,1), (3,1), ...], ["src", "dst"])
 g = GraphFrame(vertices, edges)
 g.bfs(fromExpr="id = 1", toExpr="id = 8")
 g.connectedComponents()

## 6. 方案五: DataFrame 迭代（PySpark）


 result = spark.sql("SELECT *, 0 AS level FROM employees WHERE parent_id IS NULL")
 level = 0
 while True:
     result.createOrReplaceTempView('current_level')
     next_level = spark.sql(f"""
         SELECT e.*, {level + 1} AS level
         FROM employees e
         JOIN current_level c ON e.parent_id = c.id
     """)
     if next_level.count() == 0: break
     result = result.union(next_level)
     level += 1

## 7. 递归 CTE（Spark 3.4+, 实验性）


 SET spark.sql.legacy.ctePrecedencePolicy = CORRECTED;
 WITH RECURSIVE hierarchy AS (
     SELECT id, name, parent_id, 1 AS level, CAST(name AS STRING) AS path
     FROM employees WHERE parent_id IS NULL
     UNION ALL
     SELECT e.id, e.name, e.parent_id, h.level + 1,
            CONCAT(h.path, ' > ', e.name)
     FROM employees e JOIN hierarchy h ON e.parent_id = h.id
 )
 SELECT * FROM hierarchy ORDER BY level, id;

## 8. 版本演进

Spark 2.0: 多层自连接, LATERAL VIEW 路径查询
Spark 3.0: GraphFrames 集成改进
Spark 3.4: 递归 CTE（实验性）
Spark 4.0: 递归 CTE 稳定性改进

推荐方案选择:
已知固定深度: 多层自连接（最简单）
动态深度 + 高读取频率: 路径枚举模型
动态深度 + 高写入频率: 邻接表 + DataFrame 迭代
复杂图结构: GraphFrames
Spark 3.4+: 递归 CTE（最标准但实验性）

