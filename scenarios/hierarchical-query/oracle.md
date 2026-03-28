# Oracle: 层次查询

> 参考资料:
> - [Oracle SQL Language Reference - Hierarchical Queries (CONNECT BY)](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Hierarchical-Queries.html)

## 准备数据

```sql
CREATE TABLE employees (
    id        NUMBER(10) PRIMARY KEY,
    name      VARCHAR2(100) NOT NULL,
    parent_id NUMBER(10) REFERENCES employees(id),
    dept      VARCHAR2(100)
);
INSERT ALL
    INTO employees VALUES (1,'CEO',NULL,'exec')
    INTO employees VALUES (2,'CTO',1,'tech')
    INTO employees VALUES (3,'CFO',1,'finance')
    INTO employees VALUES (4,'VP Eng',2,'tech')
    INTO employees VALUES (5,'VP Product',2,'tech')
    INTO employees VALUES (6,'Dev Lead',4,'tech')
    INTO employees VALUES (7,'QA Lead',4,'tech')
    INTO employees VALUES (8,'Dev A',6,'tech')
    INTO employees VALUES (9,'Dev B',6,'tech')
    INTO employees VALUES (10,'QA Eng',7,'tech')
SELECT 1 FROM DUAL;
```

## CONNECT BY（Oracle 独有的经典层次查询，所有版本）

```sql
SELECT id,
       LPAD(' ', 2 * (LEVEL - 1)) || name AS indented_name,
       LEVEL AS depth,
       SYS_CONNECT_BY_PATH(name, ' > ') AS path,
       CONNECT_BY_ISLEAF AS is_leaf,
       CONNECT_BY_ROOT name AS root_name
FROM employees
START WITH parent_id IS NULL
CONNECT BY PRIOR id = parent_id
ORDER SIBLINGS BY name;
```

CONNECT BY 独有的伪列和函数:
  LEVEL: 层级深度（根 = 1）
  SYS_CONNECT_BY_PATH(col, sep): 从根到当前节点的路径
  CONNECT_BY_ROOT col: 根节点的列值
  CONNECT_BY_ISLEAF: 是否叶子节点（1/0）
  ORDER SIBLINGS BY: 同级节点排序（保持层次结构）

自底向上遍历
```sql
SELECT id, name, LEVEL AS depth,
       SYS_CONNECT_BY_PATH(name, ' > ') AS path
FROM employees
START WITH name = 'Dev A'
CONNECT BY PRIOR parent_id = id;
```

循环检测
```sql
SELECT LEVEL, name, CONNECT_BY_ISCYCLE AS is_cycle
FROM employees
START WITH parent_id IS NULL
CONNECT BY NOCYCLE PRIOR id = parent_id;
```

## 递归 CTE（11g R2+，SQL 标准方式）

```sql
WITH org_tree (id, name, parent_id, lvl, path) AS (
    SELECT id, name, parent_id, 0,
           CAST(name AS VARCHAR2(4000))
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.lvl + 1,
           t.path || ' > ' || e.name
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT id, LPAD(' ', 2 * lvl) || name AS indented_name, lvl, path
FROM org_tree ORDER BY path;
```

## SEARCH / CYCLE 子句（11g R2+）

```sql
WITH org_tree (id, name, parent_id, lvl) AS (
    SELECT id, name, parent_id, 0
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.lvl + 1
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SEARCH DEPTH FIRST BY name SET order_col
CYCLE id SET is_cycle TO 'Y' DEFAULT 'N'
SELECT LPAD(' ', 2 * lvl) || name AS indented_name, lvl
FROM org_tree WHERE is_cycle = 'N'
ORDER BY order_col;
```

## CONNECT BY vs 递归 CTE 对比

CONNECT BY 优势:
  - 语法简洁（一条 SELECT，无需 CTE 包装）
  - 内置 LEVEL, SYS_CONNECT_BY_PATH, CONNECT_BY_ISLEAF
  - ORDER SIBLINGS BY 保持层次排序
  - 比递归 CTE 早 10+ 年（所有 Oracle 版本都支持）

递归 CTE 优势:
  - SQL 标准（所有主流数据库支持）
  - 更通用（不限于树结构，可以表达任意递归）
  - 可以在递归中做聚合和复杂计算

对引擎开发者的启示:
  实现递归 CTE（SQL 标准），不要实现 CONNECT BY。
  SEARCH/CYCLE 子句值得支持（PostgreSQL 14+ 已跟进）。

## 子树聚合（CONNECT BY 的强大能力）

```sql
SELECT id, name,
       (SELECT COUNT(*) - 1
        FROM employees START WITH id = e.id
        CONNECT BY PRIOR id = parent_id) AS subordinate_count
FROM employees e ORDER BY subordinate_count DESC;
```

## 路径枚举模型

```sql
CREATE TABLE categories (
    id   NUMBER(10) PRIMARY KEY,
    name VARCHAR2(100),
    path VARCHAR2(500)                         -- 物化路径: '1/2/4'
);
```

查找某节点的所有子节点
```sql
SELECT * FROM categories WHERE path LIKE '1/2%';
```

路径枚举 vs 邻接表 vs 嵌套集:
  邻接表: parent_id 列（最自然，CONNECT BY/递归CTE 查询）
  路径枚举: 物化路径（查找简单，移动节点需更新所有后代）
  嵌套集: left/right 值（查找快，修改慢）
  闭包表: 独立关系表存储所有祖先-后代关系（最灵活但空间大）

## 对引擎开发者的总结

1. CONNECT BY 是 Oracle 独有且强大的层次查询语法，但可移植性为零。
2. 递归 CTE 是 SQL 标准，所有主流数据库支持，应优先实现。
3. SEARCH DEPTH/BREADTH FIRST 和 CYCLE 检测是重要的递归 CTE 扩展。
4. SYS_CONNECT_BY_PATH 等伪列在递归 CTE 中需要手动构建。
5. 层次查询是数据库的常见需求，引擎应确保递归 CTE 性能良好。
