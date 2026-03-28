# MaxCompute (ODPS): 层次查询与树形结构

> 参考资料:
> - [1] MaxCompute SQL Reference
>   https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview


## 1. MaxCompute 不支持递归 CTE —— 需要替代方案


 不支持 WITH RECURSIVE（分布式迭代实现复杂）
 不支持 CONNECT BY ... START WITH（Oracle 专有）
 替代方案: 多层 JOIN / 路径枚举 / 闭包表

## 2. 多层自连接（固定深度，最简单）


假设: employees(id, name, parent_id)

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
WHERE e1.parent_id IS NULL;                 -- 根节点

```

 限制: 只能查询固定层数（需要预知最大深度）
 适用: 组织架构（通常 4-6 层）

## 3. 路径枚举模型（推荐方案）


表设计: 每行存储从根到当前节点的完整路径

```sql
CREATE TABLE IF NOT EXISTS categories (
    id        BIGINT,
    name      STRING,
    parent_id BIGINT,
    path      STRING                        -- '1/2/5/12'
);

```

查找所有子节点

```sql
SELECT * FROM categories WHERE path LIKE '1/2%';

```

查找所有祖先

```sql
SELECT * FROM categories WHERE '1/2/5/12' LIKE CONCAT(path, '%');

```

查找直接子节点

```sql
SELECT * FROM categories WHERE parent_id = 2;

```

计算层级深度

```sql
SELECT name, SIZE(SPLIT(path, '/')) - 1 AS depth FROM categories;

```

 路径枚举的优缺点:
   优点: 查询简单高效（LIKE 前缀匹配），无需递归
   缺点: 插入/移动节点需要更新所有子节点的 path
   适用: 读多写少的场景（如商品分类、组织架构）

## 4. 闭包表模型（关系最完整）


```sql
CREATE TABLE IF NOT EXISTS tree_closure (
    ancestor   BIGINT,
    descendant BIGINT,
    depth      INT
);

```

查找所有子节点

```sql
SELECT e.* FROM tree_closure tc
JOIN employees e ON e.id = tc.descendant
WHERE tc.ancestor = 2 AND tc.depth > 0;

```

查找所有祖先

```sql
SELECT e.* FROM tree_closure tc
JOIN employees e ON e.id = tc.ancestor
WHERE tc.descendant = 12 AND tc.depth > 0;

```

查找直接子节点（depth = 1）

```sql
SELECT e.* FROM tree_closure tc
JOIN employees e ON e.id = tc.descendant
WHERE tc.ancestor = 2 AND tc.depth = 1;

```

 闭包表的优缺点:
   优点: 查询灵活（任意祖先/后代关系），标准 JOIN
   缺点: 存储空间大（O(N^2) 最坏情况），维护复杂
   适用: 频繁查询各种层级关系的场景

## 5. 物化路径 + MaxCompute 批处理模式


MaxCompute ETL 中常见的做法:
在 DataWorks 调度中预计算层级关系（固定层数展开）


```sql
INSERT OVERWRITE TABLE dim_org_flat
SELECT
    e1.id AS level1_id, e1.name AS level1_name,
    e2.id AS level2_id, e2.name AS level2_name,
    e3.id AS level3_id, e3.name AS level3_name,
    e4.id AS level4_id, e4.name AS level4_name
FROM employees e1
LEFT JOIN employees e2 ON e2.parent_id = e1.id
LEFT JOIN employees e3 ON e3.parent_id = e2.id
LEFT JOIN employees e4 ON e4.parent_id = e3.id
WHERE e1.parent_id IS NULL;

```

 查询时直接使用展开后的扁平表（无需递归）

## 6. 横向对比与引擎开发者启示


 递归查询支持:
MaxCompute: 不支持         | BigQuery: WITH RECURSIVE（有迭代上限）
Hive:       不支持         | PostgreSQL: WITH RECURSIVE
Spark SQL:  不支持         | Snowflake: WITH RECURSIVE
MySQL 8.0+: WITH RECURSIVE | Oracle: CONNECT BY（最早的层次查询）

 对引擎开发者:
1. 递归 CTE 用户需求强烈 — BigQuery 的有限递归（最大迭代次数）是好的折中

2. 路径枚举是无递归 CTE 时最实用的替代方案 — 文档应推荐

3. 批处理引擎可以用 ETL 预计算替代运行时递归 — 物化扁平表

4. 闭包表是最灵活但最占空间的方案 — 适合元数据表

