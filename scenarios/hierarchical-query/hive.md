# Hive: 层级查询 (无递归 CTE, 替代方案)

> 参考资料:
> - [1] Apache Hive Language Manual - SELECT
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select
> - [2] Apache Hive - LATERAL VIEW
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+LateralView


## 1. Hive 不支持递归 CTE / CONNECT BY

 这是 Hive 作为批处理引擎的限制:
 递归的迭代次数不确定，与 MapReduce/Tez 的固定 DAG 不兼容。
 替代方案: 多层自连接 / 路径枚举 / 闭包表 / 外部处理

 示例数据:
 CREATE TABLE employees (id INT, name STRING, parent_id INT);

## 2. 多层自连接 (固定深度)

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

 限制: 深度固定，需要提前知道最大层级

## 3. 路径枚举模型 (推荐)

```sql
CREATE TABLE categories (id INT, name STRING, path STRING) STORED AS ORC;
```

path 存储从根到当前节点的路径: '1/2/4'

查询子孙

```sql
SELECT * FROM categories WHERE path LIKE '1/2%';

```

查询深度

```sql
SELECT *, SIZE(SPLIT(path, '/')) - 1 AS depth FROM categories;

```

查询祖先路径中的所有节点

```sql
SELECT c2.* FROM categories c1
LATERAL VIEW EXPLODE(SPLIT(c1.path, '/')) t AS ancestor_id
JOIN categories c2 ON c2.id = CAST(t.ancestor_id AS INT)
WHERE c1.id = 4;

```

 路径枚举的设计 trade-off:
 优点: 查询简单高效（LIKE 前缀匹配）
 缺点: 路径需要在写入时维护，节点移动需要更新所有子孙的路径

## 4. 闭包表模型 (Closure Table)

```sql
CREATE TABLE tree_closure (ancestor INT, descendant INT, depth INT) STORED AS ORC;
```

预计算所有祖先-后代关系

查询某节点的所有子孙

```sql
SELECT e.* FROM tree_closure tc
JOIN employees e ON e.id = tc.descendant
WHERE tc.ancestor = 2 AND tc.depth > 0;

```

查询某节点的所有祖先

```sql
SELECT e.* FROM tree_closure tc
JOIN employees e ON e.id = tc.ancestor
WHERE tc.descendant = 8 AND tc.depth > 0;

```

子树聚合

```sql
SELECT tc.ancestor, e.name, COUNT(*) - 1 AS subordinate_count
FROM tree_closure tc JOIN employees e ON e.id = tc.ancestor
GROUP BY tc.ancestor, e.name HAVING COUNT(*) > 1;

```

## 5. 迭代方法 (多次 INSERT)

通过调度工具（Airflow）多次执行 INSERT 模拟递归

```sql
CREATE TABLE tree_result (id INT, name STRING, level INT, path STRING) STORED AS ORC;

```

第0层: 根节点

```sql
INSERT INTO tree_result
SELECT id, name, 0, CAST(id AS STRING) FROM employees WHERE parent_id IS NULL;

```

第1层

```sql
INSERT INTO tree_result
SELECT e.id, e.name, 1, CONCAT(t.path, '/', CAST(e.id AS STRING))
FROM employees e JOIN tree_result t ON e.parent_id = t.id WHERE t.level = 0;

```

 重复直到无新行...（由调度工具控制循环）

## 6. 跨引擎对比: 层级查询

 引擎          递归 CTE    CONNECT BY    替代方案
 MySQL(8.0+)   支持        不支持        递归 CTE
 PostgreSQL    支持        不支持        递归 CTE (最佳)
 Oracle        支持        支持(原创)    CONNECT BY
 Hive          不支持      不支持        路径枚举/闭包表/迭代
 Spark SQL     不支持      不支持        DataFrame 循环
 BigQuery      支持        不支持        递归 CTE

## 7. 对引擎开发者的启示

1. 递归 CTE 在大数据引擎中不实用: 迭代次数不确定，无法生成固定 DAG

2. 路径枚举是最实用的替代方案: 利用 LIKE 前缀匹配，查询简单

3. LATERAL VIEW EXPLODE 可以用来拆解路径: Hive 的嵌套类型处理能力在这里发挥作用

4. 闭包表适合频繁查询的场景: 空间换时间，预计算所有关系

