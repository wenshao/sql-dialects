# 递归 CTE 增强

从基本递归查询到搜索顺序控制和循环检测——SQL 标准递归 CTE 的现代增强特性。

## 支持矩阵

| 引擎 | 基本递归 CTE | SEARCH DEPTH/BREADTH FIRST | CYCLE 检测 | 版本 | 备注 |
|------|------------|---------------------------|-----------|------|------|
| PostgreSQL | 支持 | 支持 | 支持 | 8.4+ / 14+ | 14+ 支持 SEARCH/CYCLE |
| Oracle | 支持 | 支持 | 支持 | 11gR2+ | 也有非标准 CONNECT BY |
| SQL Server | 支持 | 不支持 | 不支持 | 2005+ | MAXRECURSION hint |
| MySQL | 支持 | 不支持 | 不支持 | 8.0+ | 仅 UNION ALL |
| SQLite | 支持 | 不支持 | 不支持 | 3.8.3+ | - |
| MariaDB | 支持 | 不支持 | 不支持 | 10.2+ | - |
| BigQuery | 支持 | 不支持 | 不支持 | GA | 有递归深度限制 |
| Snowflake | 支持 | 不支持 | 不支持 | GA | - |
| DuckDB | 支持 | 支持 | 支持 | 0.8.0+ | - |
| Trino | 支持 | 不支持 | 不支持 | 340+ | - |
| Db2 | 支持 | 支持 | 支持 | 9.7+ | - |

## 基本递归 CTE (SQL:1999)

### 核心结构

```sql
-- 递归 CTE 由两部分组成: 锚成员 + 递归成员
WITH RECURSIVE cte_name AS (
    -- 锚成员 (Anchor): 递归的起点
    SELECT ... FROM base_table WHERE ...

    UNION ALL    -- 或 UNION（去重）

    -- 递归成员 (Recursive): 引用自身
    SELECT ... FROM cte_name JOIN other_table ON ...
)
SELECT * FROM cte_name;
```

### 经典场景: 组织架构树

```sql
-- 组织架构表
CREATE TABLE employees (
    id INT PRIMARY KEY,
    name VARCHAR(100),
    manager_id INT REFERENCES employees(id)
);

-- 查询某员工的所有下属（包括间接下属）
WITH RECURSIVE subordinates AS (
    -- 锚: 从指定管理者开始
    SELECT id, name, manager_id, 0 AS depth
    FROM employees
    WHERE id = 1                          -- CEO

    UNION ALL

    -- 递归: 查找每个已找到员工的直接下属
    SELECT e.id, e.name, e.manager_id, s.depth + 1
    FROM employees e
    JOIN subordinates s ON e.manager_id = s.id
)
SELECT * FROM subordinates ORDER BY depth, name;
```

### 执行原理

```
迭代 0 (锚成员):  找到 CEO → {1}
迭代 1 (递归):    找到 CEO 的直接下属 → {2, 3, 4}
迭代 2 (递归):    找到上一轮结果的直接下属 → {5, 6, 7, 8}
迭代 3 (递归):    找到上一轮结果的直接下属 → {9, 10}
迭代 4 (递归):    没有新行产生 → 终止

UNION ALL: 累积所有迭代的结果
最终结果: {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
```

## SEARCH 子句: 搜索顺序控制 (SQL:2008)

### 问题: 默认搜索顺序不确定

```sql
-- 基本递归 CTE 的结果顺序取决于迭代执行顺序
-- 实际上是广度优先（BFS）的：先处理完一层，再处理下一层
-- 但如果需要深度优先（DFS）顺序呢？
-- 例如: 需要按组织架构的"缩进"方式展示

-- 没有 SEARCH 子句时，模拟 DFS 需要手动维护路径数组:
WITH RECURSIVE org AS (
    SELECT id, name, manager_id, ARRAY[id] AS path
    FROM employees WHERE manager_id IS NULL

    UNION ALL

    SELECT e.id, e.name, e.manager_id, o.path || e.id
    FROM employees e
    JOIN org o ON e.manager_id = o.id
)
SELECT id, name, REPEAT('  ', array_length(path, 1) - 1) || name AS display
FROM org
ORDER BY path;  -- 按路径排序实现 DFS 顺序
```

### SEARCH DEPTH FIRST / BREADTH FIRST (PostgreSQL 14+, Oracle 11gR2+)

```sql
-- SEARCH DEPTH FIRST: 深度优先（先纵深再回溯）
WITH RECURSIVE org AS (
    SELECT id, name, manager_id
    FROM employees WHERE manager_id IS NULL

    UNION ALL

    SELECT e.id, e.name, e.manager_id
    FROM employees e
    JOIN org o ON e.manager_id = o.id
)
SEARCH DEPTH FIRST BY name SET ordercol      -- 按 name 排序同级节点
SELECT * FROM org ORDER BY ordercol;

-- 输出（缩进仅示意）:
-- id | name           ← DFS 顺序
-- 1  | CEO
-- 2  |   Engineering VP
-- 5  |     Backend Lead
-- 9  |       Backend Dev
-- 6  |     Frontend Lead
-- 3  |   Sales VP
-- 7  |     Sales Rep 1
-- 8  |     Sales Rep 2

-- SEARCH BREADTH FIRST: 广度优先（先同级再下级）
WITH RECURSIVE org AS (
    SELECT id, name, manager_id
    FROM employees WHERE manager_id IS NULL

    UNION ALL

    SELECT e.id, e.name, e.manager_id
    FROM employees e
    JOIN org o ON e.manager_id = o.id
)
SEARCH BREADTH FIRST BY name SET ordercol
SELECT * FROM org ORDER BY ordercol;

-- 输出:
-- id | name           ← BFS 顺序
-- 1  | CEO
-- 2  |   Engineering VP
-- 3  |   Sales VP
-- 5  |     Backend Lead
-- 6  |     Frontend Lead
-- 7  |     Sales Rep 1
-- 8  |     Sales Rep 2
-- 9  |       Backend Dev

-- SET ordercol: 生成一个排序列，按指定顺序排列
-- BY name: 同级节点按 name 排序
-- 可以 BY 多个列: SEARCH DEPTH FIRST BY dept_id, name SET ordercol
```

## CYCLE 子句: 循环检测 (SQL:2008)

### 问题: 数据中的环导致无限递归

```sql
-- 如果数据有环（A → B → C → A），递归 CTE 会无限循环
-- 不同引擎的默认保护:
-- PostgreSQL: cte_max_recursion_depth（默认无限制，可能 OOM）
-- SQL Server: MAXRECURSION 100（默认最多递归 100 次）
-- MySQL: cte_max_recursion_depth = 1000
-- BigQuery: 最多 500 次迭代

-- 没有 CYCLE 子句时，手动检测循环:
WITH RECURSIVE graph AS (
    SELECT id, parent_id, ARRAY[id] AS path, false AS is_cycle
    FROM nodes WHERE id = 1

    UNION ALL

    SELECT n.id, n.parent_id, g.path || n.id, n.id = ANY(g.path)
    FROM nodes n
    JOIN graph g ON n.parent_id = g.id
    WHERE NOT g.is_cycle                -- 检测到环时停止
)
SELECT * FROM graph WHERE NOT is_cycle;
```

### CYCLE 子句 (PostgreSQL 14+, Oracle 11gR2+)

```sql
-- CYCLE 子句自动检测并标记循环
WITH RECURSIVE graph AS (
    SELECT id, parent_id, data
    FROM nodes WHERE id = 1

    UNION ALL

    SELECT n.id, n.parent_id, n.data
    FROM nodes n
    JOIN graph g ON n.parent_id = g.id
)
CYCLE id SET is_cycle USING path
SELECT * FROM graph;

-- CYCLE id: 用 id 列检测循环（当 id 值在路径中重复出现时认为有环）
-- SET is_cycle: 生成布尔列 is_cycle，标记是否检测到环
-- USING path: 生成路径列 path，记录访问过的 id 值序列
-- 检测到环的行仍然在结果中（is_cycle = true），但不继续递归

-- 可以 CYCLE 多个列:
CYCLE id, parent_id SET is_cycle USING path
-- 当 (id, parent_id) 的组合重复出现时认为有环

-- 自定义循环标记值:
CYCLE id SET is_cycle TO 'Y' DEFAULT 'N' USING path
-- is_cycle 列的值为 'Y' 或 'N' 而不是 true/false
```

## Oracle CONNECT BY 对比

```sql
-- Oracle 的 CONNECT BY 是递归查询的早期实现（Oracle 2, 1977 年）
-- 比 SQL:1999 的递归 CTE 早了 20 多年

-- CONNECT BY 语法
SELECT
    id, name, manager_id,
    LEVEL AS depth,                          -- 伪列: 当前层级
    SYS_CONNECT_BY_PATH(name, '/') AS path,  -- 路径
    CONNECT_BY_ISLEAF AS is_leaf,            -- 是否叶节点
    CONNECT_BY_ISCYCLE AS is_cycle            -- 是否检测到环
FROM employees
START WITH manager_id IS NULL               -- 起始条件（锚成员）
CONNECT BY NOCYCLE                          -- 检测到环时停止
    PRIOR id = manager_id                    -- 递归条件
ORDER SIBLINGS BY name;                     -- 同级排序

-- CONNECT BY 独有特性:
-- LEVEL 伪列: 无需手动维护 depth 计数器
-- SYS_CONNECT_BY_PATH: 内置路径构建
-- CONNECT_BY_ISLEAF: 叶节点检测
-- CONNECT_BY_ROOT: 获取根节点的列值
-- ORDER SIBLINGS BY: 保持层级结构的同级排序

-- CONNECT BY vs 递归 CTE 的等价改写:
-- CONNECT BY:
SELECT LEVEL, id, name
FROM employees
START WITH id = 1
CONNECT BY PRIOR id = manager_id;

-- 等价递归 CTE:
WITH RECURSIVE org AS (
    SELECT 1 AS lvl, id, name FROM employees WHERE id = 1
    UNION ALL
    SELECT o.lvl + 1, e.id, e.name
    FROM employees e JOIN org o ON e.manager_id = o.id
)
SELECT lvl, id, name FROM org;
```

### CONNECT BY 的优劣势

```
优势:
- 语法更简洁（无需 UNION ALL 结构）
- 内置伪列（LEVEL, PATH, ISLEAF）
- ORDER SIBLINGS BY 非常方便

劣势:
- Oracle 专有语法，不可移植
- 不如递归 CTE 灵活（CTE 支持复杂的锚和递归条件）
- 大数据引擎基本不支持
- 现代引擎倾向实现标准递归 CTE
```

## MySQL 8.0 的限制

```sql
-- MySQL 8.0 支持递归 CTE，但有重要限制:

-- 1. 只支持 UNION ALL，不支持 UNION
-- 这意味着: 无法通过 UNION 自动去重来防止循环
WITH RECURSIVE graph AS (
    SELECT id, parent_id FROM nodes WHERE id = 1
    UNION      -- ❌ MySQL 8.0 不支持递归 CTE 中的 UNION
    SELECT n.id, n.parent_id FROM nodes n JOIN graph g ON n.parent_id = g.id
)
SELECT * FROM graph;
-- ERROR: Recursive CTE can only use UNION ALL

-- 必须用 UNION ALL + 手动防环:
WITH RECURSIVE graph AS (
    SELECT id, parent_id, CAST(id AS CHAR(500)) AS path
    FROM nodes WHERE id = 1
    UNION ALL
    SELECT n.id, n.parent_id, CONCAT(g.path, ',', n.id)
    FROM nodes n
    JOIN graph g ON n.parent_id = g.id
    WHERE FIND_IN_SET(n.id, g.path) = 0    -- 手动检查路径中是否有重复
)
SELECT * FROM graph;

-- 2. 默认递归深度限制 1000
SHOW VARIABLES LIKE 'cte_max_recursion_depth';
-- 默认 1000，可调整:
SET cte_max_recursion_depth = 10000;

-- 3. 不支持 SEARCH / CYCLE 子句
-- 需要手动实现深度优先排序和循环检测
```

## SQL Server: MAXRECURSION hint

```sql
-- SQL Server 默认最多递归 100 次
-- 超过时报错: "The maximum recursion 100 has been exhausted..."

-- 调整递归深度限制
WITH org AS (
    SELECT id, name, manager_id, 0 AS depth
    FROM employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id, o.depth + 1
    FROM employees e JOIN org o ON e.manager_id = o.id
)
SELECT * FROM org
OPTION (MAXRECURSION 1000);    -- 允许最多 1000 次递归

-- MAXRECURSION 0: 无限制（危险！可能导致无限循环）
OPTION (MAXRECURSION 0);

-- SQL Server 不支持 SEARCH 和 CYCLE 子句
-- 手动实现 DFS 排序:
WITH org AS (
    SELECT id, name, manager_id,
           CAST(RIGHT('000' + CAST(id AS VARCHAR), 4) AS VARCHAR(MAX)) AS sort_path
    FROM employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id,
           o.sort_path + '.' + RIGHT('000' + CAST(e.id AS VARCHAR), 4)
    FROM employees e JOIN org o ON e.manager_id = o.id
)
SELECT * FROM org ORDER BY sort_path;
```

## 实现原理

### BFS 用队列

```
-- 广度优先执行（递归 CTE 的默认实现）:
WorkTable = 锚成员结果         -- 初始工作表
Result = WorkTable              -- 累积结果

while WorkTable is not empty:
    NewRows = 执行递归成员(输入 = WorkTable)    -- 用当前 WorkTable 执行递归部分
    Result = Result ∪ NewRows                    -- 累积到结果
    WorkTable = NewRows                          -- 新行成为下一轮的工作表

return Result
```

### DFS 用栈

```
-- 深度优先执行（SEARCH DEPTH FIRST 的实现）:
Stack = 锚成员结果（按排序键排序）
Result = empty

while Stack is not empty:
    Row = Stack.pop()                           -- 取出栈顶元素
    Result.append(Row)
    Children = 执行递归成员(输入 = {Row})       -- 仅对这一行执行递归
    Stack.push(Children, sorted)                -- 子节点压入栈顶

return Result
```

### CYCLE 用路径数组

```
-- 循环检测实现:
每行维护一个 path 数组（访问过的 CYCLE 列值）

fn process_row(row, parent_path):
    cycle_value = row[cycle_column]
    if cycle_value in parent_path:
        row.is_cycle = true
        return                              -- 不继续递归
    row.path = parent_path + [cycle_value]
    row.is_cycle = false
    for child in get_children(row):
        process_row(child, row.path)
```

## 对引擎开发者的实现建议

1. 递归深度保护

必须有默认的递归深度限制，防止数据中的环或用户错误导致无限循环：

```
建议: 默认 1000 次，可通过 SET 调整
超过限制时报错，错误信息包含当前深度和建议
```

2. 内存管理

递归 CTE 的 WorkTable 需要在内存中维护。如果某层产出大量行，内存会快速增长：

```
策略:
- 小结果集: 纯内存 WorkTable
- 大结果集: WorkTable 溢出到磁盘（与 Hash Join 的溢出机制类似）
- 限制: 设置 WorkTable 的最大内存使用量
```

3. SEARCH/CYCLE 作为语法糖

SEARCH 和 CYCLE 可以在 planner 阶段改写为等价的手动实现：

```sql
-- SEARCH DEPTH FIRST BY name SET ordercol
-- 改写为: 在递归成员中维护排序路径

-- CYCLE id SET is_cycle USING path
-- 改写为: 在递归成员中维护 path 数组并检查重复
```

这种实现方式最简单，但不如专用算子高效。生产引擎建议在执行层直接支持。

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-2:1999, Section 7.13 (recursive query)
- SQL:2008 标准: SEARCH and CYCLE clauses
- PostgreSQL: [WITH Queries (CTEs)](https://www.postgresql.org/docs/current/queries-with.html)
- Oracle: [Hierarchical Queries](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Hierarchical-Queries.html)
- SQL Server: [WITH common_table_expression](https://learn.microsoft.com/en-us/sql/t-sql/queries/with-common-table-expression-transact-sql)
- MySQL: [Recursive CTEs](https://dev.mysql.com/doc/refman/8.0/en/with.html#common-table-expressions-recursive)
