# 层次数据类型 (Hierarchical Data Types)

"我有一棵 50 万节点的组织架构树，需要查询某个部门下的所有员工——递归 CTE 跑了 30 秒，能不能更快？" 这个问题在 SQL Server 2008 之前没有好答案，直到微软引入 `hierarchyid` 这一原生层次数据类型，把树状路径直接编码成可索引的二进制串。在 PostgreSQL 阵营，`ltree` 扩展早在 7.x 时代就以 contrib 模块形式提供类似能力。Oracle 走了完全不同的路径：1979 年 Oracle V2 就引入了 `CONNECT BY` 语法，把递归遍历直接做进 SQL 引擎，而不是抽象出"层次类型"。MySQL、SQLite、ClickHouse、BigQuery、Snowflake 等大量引擎至今没有原生层次类型，开发者不得不在邻接表（adjacency list）、嵌套集（nested set）、物化路径（materialized path）这几种经典模式之间反复权衡。

本文面向 SQL 引擎开发者，系统对比 45+ 种数据库在层次数据类型上的支持现状：从 SQL Server `hierarchyid` 的二进制路径编码到 PostgreSQL `ltree` 的 GiST 索引；从 Oracle CONNECT BY 的连接式遍历到 SQL:1999 递归 CTE 的标准方案；从邻接表的简洁到嵌套集的查询效率，再到物化路径的折中。

姊妹文章：[递归 CTE 增强 (Recursive CTE Enhancements)](./recursive-cte-enhancements.md) 关注递归遍历的 SQL 标准演进；[图查询 (Graph Queries)](./graph-queries.md) 关注 SQL/PGQ 与图模式匹配。本文聚焦 "如何把层次结构编码进数据类型本身，让查询能直接用索引加速"。

## 为什么需要层次数据类型

考虑一棵典型的组织架构树：

```
Acme Corp (root)
├── Engineering
│   ├── Backend
│   │   ├── Database Team
│   │   └── API Team
│   └── Frontend
│       ├── Web Team
│       └── Mobile Team
├── Sales
│   ├── North America
│   └── EMEA
└── HR
```

如果用最朴素的邻接表存储：

```sql
CREATE TABLE org (
    id INT PRIMARY KEY,
    name VARCHAR(100),
    parent_id INT REFERENCES org(id)
);
```

查询"Engineering 下的所有团队（包括间接下属）"需要递归 CTE：

```sql
WITH RECURSIVE descendants AS (
    SELECT id, name, parent_id, 0 AS depth
    FROM org WHERE name = 'Engineering'

    UNION ALL

    SELECT o.id, o.name, o.parent_id, d.depth + 1
    FROM org o
    JOIN descendants d ON o.parent_id = d.id
)
SELECT * FROM descendants;
```

这个查询的问题：

1. **每层迭代都要做一次 JOIN**：树深度 N 需要 N 轮迭代。
2. **无法用索引加速整棵子树查询**：每轮 JOIN 都是独立的索引查找。
3. **路径信息需要额外计算**：要展示完整路径必须维护数组累加。
4. **跨层级排序困难**：广度优先 vs 深度优先需要手动控制。
5. **祖先查询效率低**：从某节点回溯到根需要不断 JOIN。

**层次数据类型**通过把树的"位置"编码到一个值里来解决这些问题：

- **路径直接可索引**：B-tree 或 GiST 索引能在 O(log N) 时间内找到任意节点的所有后代。
- **祖先/后代判断 O(1)**：通过路径前缀比较即可，不需要递归。
- **深度直接获取**：路径长度即深度。
- **最近公共祖先（LCA）可计算**：两条路径的公共前缀就是 LCA。
- **范围扫描友好**：连续后代在索引上是连续的。

## 没有 SQL 标准

SQL:1999 / SQL:2003 / SQL:2008 / SQL:2011 / SQL:2016 / SQL:2023 都不涉及"层次数据类型"。SQL 标准只在 SQL:1999 中引入了递归 CTE（`WITH RECURSIVE`），用于处理层次/递归查询，但没有规定专门的层次数据类型。

各引擎对层次结构的处理方案完全是实现定义的：

- **SQL Server** 的 `hierarchyid` 是 CLR 类型，用变长二进制编码 OrdPath。
- **PostgreSQL** 的 `ltree` 是扩展类型（contrib 模块），用点分隔的标签序列。
- **Oracle** 走了语法路线：`CONNECT BY ... PRIOR ... START WITH ...`，没有专门的类型。
- **DB2** 没有原生层次类型，但提供 `RECURSIVE WITH` 与递归 CTE 兼容。
- **Snowflake / BigQuery / ClickHouse** 等大多数云数据仓库依赖递归 CTE 或物化路径模式。

虽然没有标准，SQL Server 的 `hierarchyid` 和 PostgreSQL 的 `ltree` 已经形成了两个独立但成熟的生态：前者主导企业级 OLTP，后者在科学/地理/CMS 类应用中广泛使用。

## 三种经典层次存储模式

在讨论支持矩阵之前，先回顾三种最常见的存储模式——这是理解各引擎选择的基础。

### 模式 1：邻接表（Adjacency List）

每行存储自己的 ID 和父节点 ID。

```sql
CREATE TABLE adjacency_org (
    id INT PRIMARY KEY,
    name VARCHAR(100),
    parent_id INT REFERENCES adjacency_org(id)
);
```

| 操作 | 复杂度 | 实现难度 |
|------|--------|---------|
| 插入新节点 | O(1) | 简单 |
| 删除叶节点 | O(1) | 简单 |
| 删除内部节点 | O(N) 子树 | 中等 |
| 查询直接子节点 | O(1) 索引扫描 | 简单 |
| 查询所有后代 | O(N) 递归 CTE | 中等 |
| 查询所有祖先 | O(depth) 递归 | 简单 |
| 查询完整路径 | O(depth) 递归 | 简单 |
| 移动子树 | O(1) 改父指针 | 简单 |
| 完整性约束 | 外键 | 简单 |

**特点**：写入友好、读取昂贵。是大多数应用的默认选择。

### 模式 2：嵌套集（Nested Set / Modified Preorder Tree Traversal）

每个节点维护一对 `lft` 和 `rgt` 值，使得任意祖先的 `lft < 子孙的 lft < 子孙的 rgt < 祖先的 rgt`。

```sql
CREATE TABLE nested_set_org (
    id INT PRIMARY KEY,
    name VARCHAR(100),
    lft INT NOT NULL,
    rgt INT NOT NULL,
    INDEX idx_lft (lft),
    INDEX idx_rgt (rgt)
);

-- 查询某节点的所有后代：
SELECT child.* FROM nested_set_org child
JOIN nested_set_org parent ON parent.name = 'Engineering'
WHERE child.lft BETWEEN parent.lft + 1 AND parent.rgt - 1;
```

| 操作 | 复杂度 | 实现难度 |
|------|--------|---------|
| 插入新节点 | O(N) 全表 lft/rgt 更新 | 高 |
| 删除节点 | O(N) | 高 |
| 查询所有后代 | O(log N) 范围扫描 | 简单 |
| 查询所有祖先 | O(log N) 范围扫描 | 简单 |
| 子树宽度（节点数） | (rgt - lft - 1) / 2 | O(1) |
| 移动子树 | O(N) 重排 | 极高 |

**特点**：读取极快（特别是大子树查询），但写入代价巨大。适合"几乎只读"的场景，如分类目录、菜单树。

### 模式 3：物化路径（Materialized Path）

每个节点存储从根到自己的完整路径（通常用分隔符）。

```sql
-- 物化路径示例
CREATE TABLE matpath_org (
    id INT PRIMARY KEY,
    name VARCHAR(100),
    path VARCHAR(500)        -- 例如: '/1/2/5/12/'
);

-- 查询某节点下所有后代（前缀匹配）：
SELECT * FROM matpath_org WHERE path LIKE '/1/2/%';
```

| 操作 | 复杂度 | 实现难度 |
|------|--------|---------|
| 插入新节点 | O(1) 计算父路径+自身 ID | 简单 |
| 删除节点 | O(N) 子树 | 中等 |
| 查询所有后代 | O(log N) B-tree 前缀扫描 | 简单 |
| 查询所有祖先 | O(depth) 路径分解 | 中等 |
| 查询深度 | O(1) 路径长度 | 简单 |
| 移动子树 | O(N) 子树路径全部更新 | 中等 |
| 路径长度限制 | 受字段类型 | 取决于实现 |

**特点**：B-tree 前缀扫描天然加速后代查询，平衡读写性能。`hierarchyid` 和 `ltree` 都基于此思想，但用专用编码大幅压缩存储和加速比较。

## 支持矩阵

### 1. 原生层次数据类型

| 引擎 | 类型名 | 编码方式 | 索引类型 | 版本 | 备注 |
|------|--------|---------|---------|------|------|
| SQL Server | `hierarchyid` | OrdPath 变长二进制 | B-tree | 2008+ | CLR 类型 |
| PostgreSQL | `ltree`（扩展） | 点分隔标签序列 | GiST/GIN/B-tree | 7.4+（contrib） | core 之外的扩展 |
| Greenplum | `ltree`（扩展） | 同 PG | GiST | 继承 PG | -- |
| TimescaleDB | `ltree`（扩展） | 同 PG | GiST | 继承 PG | -- |
| YugabyteDB | `ltree`（扩展） | 同 PG | GiST | 2.4+ | 兼容 PG |
| Aurora PostgreSQL | `ltree`（扩展） | 同 PG | GiST | GA | -- |
| EnterpriseDB | `ltree`（扩展） | 同 PG | GiST | 继承 PG | -- |
| Citus | `ltree`（扩展） | 同 PG | GiST | 继承 PG | 分布式分片限制 |
| Oracle | -- | 无原生类型 | -- | -- | 用 CONNECT BY 替代 |
| MySQL | -- | -- | -- | -- | 不支持 |
| MariaDB | -- | -- | -- | -- | 不支持 |
| SQLite | -- | -- | -- | -- | 不支持 |
| DB2 | -- | -- | -- | -- | 不支持 |
| Snowflake | -- | -- | -- | -- | 不支持 |
| BigQuery | -- | -- | -- | -- | 不支持 |
| Redshift | -- | -- | -- | -- | 不支持（有限继承 PG） |
| DuckDB | -- | -- | -- | -- | 不支持 |
| ClickHouse | -- | -- | -- | -- | 不支持 |
| Trino | -- | -- | -- | -- | 不支持 |
| Presto | -- | -- | -- | -- | 不支持 |
| Spark SQL | -- | -- | -- | -- | 不支持 |
| Hive | -- | -- | -- | -- | 不支持 |
| Databricks | -- | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | -- | 不支持 |
| Teradata | -- | -- | -- | -- | 不支持 |
| Vertica | -- | -- | -- | -- | 不支持 |
| Impala | -- | -- | -- | -- | 不支持 |
| StarRocks | -- | -- | -- | -- | 不支持 |
| Doris | -- | -- | -- | -- | 不支持 |
| MonetDB | -- | -- | -- | -- | 不支持 |
| TiDB | -- | -- | -- | -- | 不支持 |
| OceanBase | -- | -- | -- | -- | 不支持 |
| CockroachDB | -- | -- | -- | -- | 不支持 |
| SingleStore | -- | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | -- | 不支持 |
| SAP HANA | -- | -- | -- | -- | 不支持（CONNECT BY 替代） |
| Informix | -- | -- | -- | -- | 不支持 |
| Firebird | -- | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- | -- | -- | 不支持 |
| Azure Synapse | -- | -- | -- | -- | 不支持 |
| Azure SQL DB | `hierarchyid` | 同 SQL Server | B-tree | GA | 继承 SQL Server |
| Azure SQL MI | `hierarchyid` | 同 SQL Server | B-tree | GA | 继承 SQL Server |
| Google Spanner | -- | -- | -- | -- | 不支持 |
| Materialize | -- | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | -- | 不支持 |
| QuestDB | -- | -- | -- | -- | 不支持 |
| InfluxDB (SQL) | -- | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | -- | 不支持 |
| Yellowbrick | -- | -- | -- | -- | 不支持（基于 PG，需安装 ltree） |
| Firebolt | -- | -- | -- | -- | 不支持 |
| MaxCompute | -- | -- | -- | -- | 不支持 |
| Pinot | -- | -- | -- | -- | 不支持 |
| Druid | -- | -- | -- | -- | 不支持 |

> 统计：约 9 个引擎/分支提供原生层次数据类型（SQL Server / Azure SQL 系列 + PostgreSQL 系扩展），其余 36+ 引擎依赖递归 CTE、CONNECT BY、或物化路径字符串模式。

### 2. 物化路径索引（GiST / GIN）支持

| 引擎 | GiST 索引 | GIN 索引 | B-tree 路径前缀 | 支持的索引操作符 | 备注 |
|------|----------|---------|--------------|----------------|------|
| PostgreSQL | 是 | 是 | 是 | `@>`, `<@`, `~`, `?` | gist_ltree_ops |
| SQL Server | -- | -- | 是 | `IsDescendantOf`, `=`, `<`, `>` | B-tree on hierarchyid |
| Greenplum | 是 | 是 | 是 | 同 PG | -- |
| YugabyteDB | 是 | -- | 是 | 同 PG | GIN 部分支持 |
| TimescaleDB | 是 | 是 | 是 | 同 PG | -- |
| Oracle | -- | -- | -- | -- | 无（CONNECT BY 用 B-tree on parent_id） |
| MySQL | -- | -- | LIKE 前缀 | `LIKE 'path%'` | 通用 B-tree |
| MariaDB | -- | -- | LIKE 前缀 | `LIKE 'path%'` | 通用 B-tree |
| SQLite | -- | -- | LIKE 前缀 | `LIKE 'path%'` | 通用 B-tree |
| DB2 | -- | -- | LIKE 前缀 | -- | -- |
| Snowflake | -- | -- | LIKE 前缀 | -- | 极简 |
| BigQuery | -- | -- | -- | -- | 无前缀索引（按列剪枝） |
| ClickHouse | -- | -- | 是 | `startsWith`, `LIKE` | sparse index 可用 |
| DuckDB | -- | -- | LIKE 前缀 | -- | -- |

### 3. 祖先 / 后代操作符支持

各引擎在祖先/后代判断上的核心操作符：

| 引擎 | "是 X 的后代" | "是 X 的祖先" | "X 与 Y 的 LCA" | "X 的深度" | 备注 |
|------|-------------|-------------|-----------------|-----------|------|
| SQL Server | `child.IsDescendantOf(parent) = 1` | 反向调用 | `CommonAncestor` (无原生方法) | `GetLevel()` | hierarchyid 方法 |
| PostgreSQL ltree | `child <@ parent` | `parent @> child` | `lca(a, b, ...)` | `nlevel()` | 原生函数 |
| Oracle | `CONNECT BY PRIOR id = parent_id` | 反向 | `CONNECT_BY_ROOT` | `LEVEL` 伪列 | CONNECT BY 内置 |
| MySQL | 自定义函数或递归 CTE | 自定义函数 | 应用层计算 | 路径长度计算 | -- |
| 其他递归 CTE 引擎 | EXISTS + 递归 CTE | 同左 | UNION + 集合交 | 递归计数器 | -- |

### 4. 路径分隔符与节点编码

不同实现的路径表示风格：

| 引擎/方案 | 路径示例 | 分隔符 | 节点格式 | 最大节点数/深度 |
|----------|---------|-------|---------|----------------|
| SQL Server hierarchyid | `0x5AC0` | 二进制 OrdPath | 变长二进制 | 最多 ~32K 字节字符串表示 |
| PostgreSQL ltree | `Top.Science.Astronomy` | 点 (`.`) | 字符 + 数字 | 65535 标签 / 256 标签深度（编译期） |
| 自实现物化路径 | `/1/2/5/12/` | 斜杠 | 整数 | 受字段长度限制 |
| Materialize style | `1.2.5.12` | 点 | 整数字符串 | 同上 |

## 各引擎详解

### SQL Server hierarchyid（since 2008）

`hierarchyid` 是 SQL Server 2008 引入的内置 CLR 类型，把树中节点的位置编码为变长二进制串（OrdPath 编码），同时提供一组方法用于路径操作。

```sql
-- 创建带 hierarchyid 的表
CREATE TABLE EmployeeOrg (
    NodeId hierarchyid PRIMARY KEY,
    EmployeeName NVARCHAR(50),
    Title NVARCHAR(50),
    NodeLevel AS NodeId.GetLevel() PERSISTED,
    INDEX IX_NodeLevel (NodeLevel, NodeId)
);

-- 插入根节点
INSERT INTO EmployeeOrg (NodeId, EmployeeName, Title)
VALUES (hierarchyid::GetRoot(), 'Alice', 'CEO');

-- 插入子节点（在根下追加）
DECLARE @parent hierarchyid = hierarchyid::GetRoot();
DECLARE @child hierarchyid;
SET @child = @parent.GetDescendant(NULL, NULL);
INSERT INTO EmployeeOrg (NodeId, EmployeeName, Title)
VALUES (@child, 'Bob', 'CTO');

-- 在指定位置之后插入（保持有序兄弟）
DECLARE @prev hierarchyid = (SELECT NodeId FROM EmployeeOrg WHERE EmployeeName = 'Bob');
DECLARE @newSibling hierarchyid = @parent.GetDescendant(@prev, NULL);
INSERT INTO EmployeeOrg VALUES (@newSibling, 'Carol', 'CFO', DEFAULT);
```

#### 主要方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `GetRoot()` | hierarchyid (静态) | 树的根节点（空路径） |
| `GetLevel()` | smallint | 当前节点深度（根为 0） |
| `GetAncestor(n)` | hierarchyid | 第 n 代祖先 |
| `GetDescendant(p1, p2)` | hierarchyid | 在 p1 和 p2 之间生成子节点 |
| `GetReparentedValue(oldRoot, newRoot)` | hierarchyid | 移植子树到新根 |
| `IsDescendantOf(parent)` | bit | 是否是 parent 的后代（含自身） |
| `Parse(string)` | hierarchyid (静态) | 字符串转 hierarchyid |
| `ToString()` | nvarchar | 标准字符串表示，如 `/1/2/3/` |
| `Read(BinaryReader)` | -- | 反序列化 |
| `Write(BinaryWriter)` | -- | 序列化 |

#### 经典查询模式

```sql
-- 1. 查询某节点的所有后代（含自身）
DECLARE @node hierarchyid = (SELECT NodeId FROM EmployeeOrg WHERE EmployeeName = 'Bob');
SELECT * FROM EmployeeOrg WHERE NodeId.IsDescendantOf(@node) = 1;

-- 2. 查询某节点的直接子节点
SELECT * FROM EmployeeOrg
WHERE NodeId.GetAncestor(1) = @node;

-- 3. 查询深度优先排序的子树
SELECT * FROM EmployeeOrg
WHERE NodeId.IsDescendantOf(@node) = 1
ORDER BY NodeId;        -- hierarchyid 的字典序就是 DFS 序

-- 4. 查询广度优先排序
SELECT * FROM EmployeeOrg
WHERE NodeId.IsDescendantOf(@node) = 1
ORDER BY NodeId.GetLevel(), NodeId;

-- 5. 查询所有祖先（O(depth)）
WITH ancestors AS (
    SELECT NodeId, EmployeeName, GetAncestor(1) AS parent
    FROM EmployeeOrg WHERE EmployeeName = 'Carol'
    UNION ALL
    SELECT e.NodeId, e.EmployeeName, e.NodeId.GetAncestor(1)
    FROM EmployeeOrg e
    JOIN ancestors a ON e.NodeId = a.parent
)
SELECT * FROM ancestors;
-- 也可以用单条 SELECT：
SELECT * FROM EmployeeOrg
WHERE @target_node.IsDescendantOf(NodeId) = 1;

-- 6. 移动子树（重新挂到新父节点下）
DECLARE @oldRoot hierarchyid = (SELECT NodeId FROM EmployeeOrg WHERE EmployeeName = 'Bob');
DECLARE @newRoot hierarchyid = (SELECT NodeId FROM EmployeeOrg WHERE EmployeeName = 'Carol');
DECLARE @newChild hierarchyid = @newRoot.GetDescendant(NULL, NULL);

UPDATE EmployeeOrg
SET NodeId = NodeId.GetReparentedValue(@oldRoot, @newChild)
WHERE NodeId.IsDescendantOf(@oldRoot) = 1;
```

#### 索引策略

SQL Server 推荐两种索引：

```sql
-- 1. 深度优先索引（depth-first）：默认就是 hierarchyid 字典序
CREATE CLUSTERED INDEX IX_HID_DFS ON EmployeeOrg(NodeId);

-- 2. 广度优先索引（breadth-first）：先按层级，再按节点
CREATE INDEX IX_HID_BFS ON EmployeeOrg(NodeLevel, NodeId);
```

**经验法则**：

- 频繁按子树查询（"显示部门下所有员工，按层级缩进"）：用 DFS 索引。
- 频繁按层级查询（"显示第 3 层管理者"）：用 BFS 索引。
- 需要兼顾两者：建两套索引，存储翻倍。

### PostgreSQL ltree（since 7.4 contrib）

`ltree` 是 PostgreSQL 的标准扩展之一，从 7.4 版本起作为 contrib 模块发布，用于存储分层标签数据。每个 ltree 值是用点（`.`）分隔的标签序列，例如 `Top.Science.Astronomy.Astrophysics`。

```sql
-- 启用扩展
CREATE EXTENSION ltree;

-- 创建表
CREATE TABLE catalog (
    id SERIAL PRIMARY KEY,
    path ltree NOT NULL,
    name TEXT
);

-- 创建 GiST 索引（最常用）
CREATE INDEX path_gist_idx ON catalog USING gist (path);

-- 也可以创建 GIN 索引（适合查询大量短标签）
-- CREATE INDEX path_gin_idx ON catalog USING gin (path);

-- 也可以创建 B-tree 索引（用于点等值查询，但不能用 ltree 操作符）
-- CREATE INDEX path_btree_idx ON catalog USING btree (path);

INSERT INTO catalog (path, name) VALUES
    ('Top', 'Catalog Root'),
    ('Top.Science', 'Sciences'),
    ('Top.Science.Astronomy', 'Astronomy'),
    ('Top.Science.Astronomy.Astrophysics', 'Astrophysics'),
    ('Top.Science.Astronomy.Cosmology', 'Cosmology'),
    ('Top.Hobbies', 'Hobbies'),
    ('Top.Hobbies.Amateurs_Astronomy', 'Amateurs Astronomy');
```

#### 主要操作符

| 操作符 | 说明 | 示例 |
|--------|------|------|
| `@>` | 左是右的祖先（含相等） | `'Top.Science' @> 'Top.Science.Astronomy'` → t |
| `<@` | 左是右的后代（含相等） | `'Top.Science.Astronomy' <@ 'Top.Science'` → t |
| `~` | 匹配 lquery 模式 | `path ~ 'Top.*{1,3}.Astronomy'` |
| `?` | 匹配 lquery 数组 | `path ? '{Top.Science.*, Top.Hobbies.*}'` |
| `@` | 匹配 ltxtquery 全文 | `path @ 'Astronomy & Cosmology'` |
| `||` | 路径拼接 | `'Top.Science' \|\| 'Astronomy'` → `Top.Science.Astronomy` |
| `=`, `<`, `>` | 标准比较 | 字典序 |

#### 主要函数

| 函数 | 返回 | 说明 |
|------|------|------|
| `nlevel(path)` | int | 路径深度（标签数） |
| `subpath(path, offset, len)` | ltree | 提取子路径 |
| `subpath(path, offset)` | ltree | 从 offset 到末尾 |
| `index(a, b)` | int | a 中 b 第一次出现的位置 |
| `index(a, b, offset)` | int | 从 offset 开始查找 |
| `lca(p1, p2, ...)` | ltree | 最近公共祖先 |
| `text2ltree(text)` | ltree | 文本转 ltree |
| `ltree2text(ltree)` | text | ltree 转文本 |

#### 经典查询模式

```sql
-- 1. 查询某节点的所有后代
SELECT * FROM catalog WHERE path <@ 'Top.Science';

-- 2. 查询某节点的所有祖先
SELECT * FROM catalog WHERE path @> 'Top.Science.Astronomy.Astrophysics';

-- 3. 查询直接子节点（深度刚好 +1）
SELECT * FROM catalog
WHERE path <@ 'Top.Science'
  AND nlevel(path) = nlevel('Top.Science') + 1;

-- 4. 用 lquery 模式查询
SELECT * FROM catalog WHERE path ~ 'Top.*.Astronomy.*';
-- 匹配：Top.Science.Astronomy.X
--      Top.X.Astronomy.Y
SELECT * FROM catalog WHERE path ~ 'Top.{1,3}.Astronomy';
-- 表示 Top 后接 1 到 3 个任意标签，再接 Astronomy

-- 5. 计算两节点的最近公共祖先
SELECT lca('Top.Science.Astronomy', 'Top.Hobbies.Amateurs_Astronomy');
-- 结果：Top

-- 6. 获取某路径的特定层
SELECT subpath('Top.Science.Astronomy.Cosmology', 1, 1);
-- 结果：Science

-- 7. 移动子树
UPDATE catalog
SET path = 'Top.NewParent' || subpath(path, 2)
WHERE path <@ 'Top.OldParent';
```

#### lquery 与 ltxtquery：模式匹配的两种风格

```sql
-- lquery：路径模式匹配（@~ 操作符）
SELECT path ~ 'foo.bar.*';        -- foo.bar 后任意层
SELECT path ~ 'foo.*.bar';        -- foo 与 bar 之间任意路径
SELECT path ~ '*.bar.*';          -- 路径中包含 bar
SELECT path ~ 'foo.{1,3}.bar';    -- foo 与 bar 间 1 到 3 层
SELECT path ~ 'foo.!bar.*';       -- foo 后面不是 bar 的任意路径

-- ltxtquery：全文式匹配（@ 操作符）
SELECT path @ 'foo & bar';        -- 路径中同时含 foo 和 bar
SELECT path @ 'foo | bar';        -- 路径中含 foo 或 bar
SELECT path @ 'foo & !bar';       -- 含 foo 但不含 bar
```

#### GiST 索引深入

PostgreSQL 的 `gist_ltree_ops` 索引支持下列操作符：

```sql
CREATE INDEX path_gist_idx ON catalog USING gist (path);
-- 加速操作符：@>, <@, =, ~, ?, @
```

GiST 索引内部用一个签名（signature）位图近似表示子树包含的路径。查询时先用签名快速排除不可能命中的子树，再精确比较剩余条目。

```sql
-- gist_ltree_ops 的可调参数：siglen（签名长度，默认 8 字节）
CREATE INDEX path_gist_idx ON catalog
  USING gist (path gist_ltree_ops(siglen=128));
-- 更长的签名 → 更准确的过滤 → 索引更大但扫描更少
```

经验：当数据量大（百万级以上）且查询选择性差时，把 `siglen` 调到 64 或 128 通常带来显著加速；但太大会让索引膨胀，影响插入和缓存。

#### gist__ltree_ops vs gist__lquery_ops vs gist__ltxtquery_ops

实际上 `gist_ltree_ops` 是这三者的总称，PostgreSQL 内部对每种操作符配套不同的 gist support。版本演进：

- **PG 7.4 - 9.5**：仅支持 ltree GiST，sigleng 固定为 8。
- **PG 10**：开始支持 array of ltree（`_ltree`）的 GiST 索引。
- **PG 13**：引入 `siglen` 可配置参数，默认仍是 8。
- **PG 14+**：进一步优化签名匹配速度。

### btree_ltree 兼容性扩展

某些场景下需要 ltree 与其他类型混合在 B-tree 多列索引中：

```sql
-- 启用 btree_ltree 扩展（PG 11+）
CREATE EXTENSION btree_ltree;

-- 创建复合 B-tree 索引（普通 B-tree 不支持 ltree，需此扩展提供 op classes）
CREATE INDEX idx_combo ON catalog USING btree (status, path);
-- 必须有 btree_ltree 扩展才能在 B-tree 中放入 ltree
```

### Oracle CONNECT BY（since v2, 1979）

Oracle 没有原生层次类型，但早在 1979 年的 V2 版本就引入了 `CONNECT BY` 子句——这是 SQL 历史上最早的层次查询语法之一，比 SQL:1999 的递归 CTE 早了 20 年。

```sql
-- 经典 CONNECT BY
SELECT employee_id, last_name, manager_id, LEVEL
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id
ORDER SIBLINGS BY last_name;

-- 关键伪列与函数
-- LEVEL: 当前行的递归深度（根为 1）
-- CONNECT_BY_ISLEAF: 当前行是否是叶节点（1/0）
-- CONNECT_BY_ROOT: 当前行的根节点对应列值
-- SYS_CONNECT_BY_PATH(col, sep): 从根到当前行的路径字符串

SELECT
    LEVEL,
    SYS_CONNECT_BY_PATH(last_name, '/') AS path,
    CONNECT_BY_ROOT last_name AS root_name,
    CONNECT_BY_ISLEAF AS is_leaf
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id;

-- NOCYCLE：检测并避免无限递归
SELECT employee_id, manager_id, LEVEL
FROM employees
START WITH manager_id IS NULL
CONNECT BY NOCYCLE PRIOR employee_id = manager_id;

-- ORDER SIBLINGS BY：保持兄弟节点的稳定排序
SELECT employee_id, last_name, LEVEL
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id
ORDER SIBLINGS BY hire_date DESC;
```

#### CONNECT BY vs 递归 CTE

Oracle 11gR2 起也支持 SQL 标准的 `WITH RECURSIVE`，两者并存。差异：

| 特性 | CONNECT BY | 递归 CTE (WITH RECURSIVE) |
|------|-----------|--------------------------|
| 引入时间 | Oracle V2 (1979) | SQL:1999, Oracle 11gR2 (2009) |
| 语法风格 | 声明式连接 | 锚成员 + 递归成员 |
| 学习曲线 | 简单直观 | 较陡 |
| LEVEL 伪列 | 内置 | 需手动维护 |
| 路径函数 | `SYS_CONNECT_BY_PATH` | 需用 ARRAY 累加 |
| 循环检测 | `NOCYCLE` 关键字 | SQL:2008 `CYCLE` 子句（11gR2+） |
| 优化器支持 | 极成熟 | 也成熟 |
| 跨引擎可移植 | Oracle / DB2 (有限) / SAP HANA | 跨大部分主流引擎 |

实践上，新代码推荐用递归 CTE（标准、可移植），但 CONNECT BY 在 Oracle 生态中仍占主流（语法简洁、性能稳定）。

### MySQL（无原生类型，递归 CTE since 8.0）

MySQL 8.0 之前完全没有递归查询能力。8.0 起支持 SQL:1999 递归 CTE。

```sql
-- 邻接表 + 递归 CTE 是 MySQL 的标准方案
CREATE TABLE org (
    id INT PRIMARY KEY,
    name VARCHAR(100),
    parent_id INT,
    INDEX (parent_id)
);

-- 查询子树
WITH RECURSIVE descendants AS (
    SELECT id, name, parent_id, 0 AS depth, CAST(id AS CHAR(500)) AS path
    FROM org WHERE name = 'Engineering'

    UNION ALL

    SELECT o.id, o.name, o.parent_id, d.depth + 1,
           CONCAT(d.path, ',', o.id)
    FROM org o
    JOIN descendants d ON o.parent_id = d.id
)
SELECT * FROM descendants;

-- 物化路径模式（手动维护）
CREATE TABLE org_mp (
    id INT PRIMARY KEY,
    name VARCHAR(100),
    path VARCHAR(500) NOT NULL,
    INDEX (path)
);

-- 查询子树（前缀匹配，能用索引）
SELECT * FROM org_mp WHERE path LIKE '/1/2/%';

-- 应用层维护 path 字段：插入时拼接父路径 + 自身 ID
```

### MariaDB

MariaDB 与 MySQL 类似：自 10.2 起支持递归 CTE，无原生层次类型。也支持非标准的 Oracle 兼容模式：

```sql
-- MariaDB 10.2+: 递归 CTE
WITH RECURSIVE ...;

-- MariaDB 10.1+: Oracle 兼容模式（设置 SQL_MODE='ORACLE'）
-- 此时支持有限的 CONNECT BY 仿真，但不完全
```

### SQLite

SQLite 3.8.3+（2014）支持递归 CTE，无原生层次类型：

```sql
-- 标准递归 CTE
WITH RECURSIVE descendants(id, name, depth) AS (
    SELECT id, name, 0 FROM org WHERE name = 'Engineering'
    UNION ALL
    SELECT o.id, o.name, d.depth + 1
    FROM org o JOIN descendants d ON o.parent_id = d.id
)
SELECT * FROM descendants;

-- 物化路径 + LIKE 前缀（B-tree 索引）
CREATE INDEX idx_org_path ON org(path);
SELECT * FROM org WHERE path LIKE '/1/2/%';
```

### DB2

DB2 支持 SQL 标准递归 CTE（写作 `WITH RECURSIVE` 或 `WITH ... AS (...)` 当包含递归引用时）：

```sql
-- DB2 递归 CTE
WITH descendants(id, name, depth) AS (
    SELECT id, name, 0 FROM org WHERE name = 'Engineering'
    UNION ALL
    SELECT o.id, o.name, d.depth + 1
    FROM org o JOIN descendants d ON o.parent_id = d.id
)
SELECT * FROM descendants;

-- 也支持有限的 CONNECT BY（DB2 9.7+ 兼容性模式）
-- 需要设置 SQL_COMPAT='NPS'
```

### Snowflake

Snowflake 没有原生层次类型，标准方案是递归 CTE 或物化路径：

```sql
-- 递归 CTE
WITH RECURSIVE descendants AS (
    SELECT id, name, parent_id, 0 AS depth
    FROM org WHERE name = 'Engineering'
    UNION ALL
    SELECT o.id, o.name, o.parent_id, d.depth + 1
    FROM org o JOIN descendants d ON o.parent_id = d.id
)
SELECT * FROM descendants;

-- CONNECT BY 兼容（Snowflake 也支持）
SELECT * FROM org
START WITH name = 'Engineering'
CONNECT BY PRIOR id = parent_id;

-- Snowflake 的 CONNECT BY 是 Oracle 风格的兼容性扩展
-- 适合 Oracle 用户迁移
```

### BigQuery

BigQuery 自 2021 年支持递归 CTE。无原生层次类型：

```sql
-- 标准递归 CTE
WITH RECURSIVE descendants AS (
    SELECT id, name, parent_id, 0 AS depth
    FROM `project.dataset.org` WHERE name = 'Engineering'
    UNION ALL
    SELECT o.id, o.name, o.parent_id, d.depth + 1
    FROM `project.dataset.org` o
    JOIN descendants d ON o.parent_id = d.id
)
SELECT * FROM descendants;

-- BigQuery 限制：递归深度有上限（通常几百层），需要监控
-- 不支持 CONNECT BY 语法
```

### ClickHouse

ClickHouse 22.x+ 支持递归 CTE，无原生层次类型。但 ClickHouse 提供 `Hierarchical Dictionary` 用于关联式层次查找：

```sql
-- 标准递归 CTE（22.x+）
WITH RECURSIVE descendants AS (
    SELECT id, name, parent_id, 0 AS depth
    FROM org WHERE name = 'Engineering'
    UNION ALL
    SELECT o.id, o.name, o.parent_id, d.depth + 1
    FROM org o JOIN descendants d ON o.parent_id = d.id
)
SELECT * FROM descendants;

-- ClickHouse Hierarchical Dictionary
-- 创建分层字典
CREATE DICTIONARY org_dict (
    id UInt64,
    parent_id UInt64 HIERARCHICAL,
    name String
)
PRIMARY KEY id
SOURCE(CLICKHOUSE(TABLE 'org'))
LAYOUT(HASHED())
LIFETIME(3600);

-- 用 dictGet 类函数遍历层次
SELECT dictGetHierarchy('org_dict', toUInt64(5));
-- 返回从 5 到根的祖先链

SELECT dictIsIn('org_dict', toUInt64(5), toUInt64(1));
-- 检查 5 是否是 1 的后代
```

### DuckDB

DuckDB 支持递归 CTE（包括 SQL:2008 SEARCH/CYCLE），无原生层次类型：

```sql
WITH RECURSIVE descendants AS (
    SELECT id, name, parent_id, 0 AS depth
    FROM org WHERE name = 'Engineering'
    UNION ALL
    SELECT o.id, o.name, o.parent_id, d.depth + 1
    FROM org o JOIN descendants d ON o.parent_id = d.id
)
SEARCH DEPTH FIRST BY id SET ord
CYCLE id SET is_cycle USING path
SELECT * FROM descendants ORDER BY ord;
```

### CockroachDB

CockroachDB 支持递归 CTE，无原生层次类型：

```sql
WITH RECURSIVE descendants AS (
    SELECT id, name, parent_id, 0 AS depth
    FROM org WHERE name = 'Engineering'
    UNION ALL
    SELECT o.id, o.name, o.parent_id, d.depth + 1
    FROM org o JOIN descendants d ON o.parent_id = d.id
)
SELECT * FROM descendants;

-- 注意：CockroachDB 是 KV 引擎，没有专门为层次结构优化
-- 不支持 PostgreSQL 的 ltree 扩展（即使 wire-protocol 兼容）
```

### TiDB / OceanBase / Greenplum / YugabyteDB

| 引擎 | 递归 CTE | ltree 扩展 | hierarchyid | CONNECT BY |
|------|---------|-----------|-------------|-----------|
| TiDB | 是 (5.1+) | 否 | 否 | 否 |
| OceanBase | 是 | 否 | 否 | 是 (Oracle 兼容模式) |
| Greenplum | 是 | 是 (继承 PG) | 否 | 否 |
| YugabyteDB | 是 | 是 (2.4+) | 否 | 否 |

### SAP HANA

SAP HANA 支持 CONNECT BY 风格的层次查询：

```sql
-- HANA 的 CONNECT BY
SELECT employee_id, manager_id, LEVEL
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id;

-- 也支持递归 CTE
WITH RECURSIVE ...;

-- HANA 还有专门的 Hierarchical View（用于建模 BI 维度的层次）
-- 但不是数据类型，是元数据级建模能力
```

## SQL Server hierarchyid 二进制表示深入

`hierarchyid` 用 **OrdPath 编码**——一种由 Patrick O'Neil 在 2004 年提出的紧凑变长二进制路径编码。其核心目标：

1. **变长**：不浪费空间，深层节点也不需要固定 N 字节。
2. **可比较**：两条路径的字节序就是 DFS 序，B-tree 直接可用。
3. **可插入**：在已有兄弟节点之间能生成新节点编码而不重排。
4. **紧凑**：典型 4 层路径只占约 5 字节。

### OrdPath 编码思想

每个路径段（路径中的一段，对应树中一层）由一对 `<L, R>` 编码：

- `L`（前缀）：定义此段的"长度类别"，决定了 `R` 占多少位。
- `R`（值）：在 L 类别内的具体编号。

类别长度递增（短前缀对应小整数，长前缀对应大整数），加上各自规则的范围。简化的 L-R 表如下（具体范围见 SQL Server 文档）：

| L 前缀位 | L 长度 | R 长度 | R 范围 | 总位数 |
|---------|-------|-------|-------|-------|
| `01` | 2 | 6 | 0..63 | 8 |
| `100` | 3 | 9 | 0..511 | 12 |
| `101` | 3 | 12 | 0..4095 | 15 |
| `110` | 3 | 16 | 0..65535 | 19 |
| ... | ... | ... | ... | ... |

每段之间用一个分隔位（"trailing 0"）区分。所有段拼成一个比特流，再 padding 到字节对齐。

### 编码示例

```
路径: /1/2/3/  （根的第 1 子节点 → 第 2 子节点 → 第 3 子节点）

简化版（实际算法略有不同，仅示意原理）:
  段 1: 数字 1，用最短类别 (01) 编码 → "01 000001"
  段 2: 数字 2，用最短类别 (01) 编码 → "01 000010"
  段 3: 数字 3，用最短类别 (01) 编码 → "01 000011"

拼接：    01 000001 | 01 000010 | 01 000011
分隔位：  ... 0 ... 0 ...
padding 到字节对齐：约 4 字节

打印形式：'/1/2/3/'
SELECT hierarchyid::Parse('/1/2/3/').ToString();
```

实际 4 层 / 节点数适中的树，hierarchyid 平均占 ~5 字节；特别深或宽的树可能达 10+ 字节。

### 兄弟节点之间插入

OrdPath 的关键设计目标：在已有兄弟之间插入不能重排现有节点。`GetDescendant(@p1, @p2)` 返回一个排序在 p1 和 p2 之间的新值。

```sql
DECLARE @parent hierarchyid = '/1/';
DECLARE @child1 hierarchyid = @parent.GetDescendant(NULL, NULL);   -- /1/1/
DECLARE @child2 hierarchyid = @parent.GetDescendant(@child1, NULL); -- /1/2/

-- 想在 child1 和 child2 之间插入新节点:
DECLARE @middle hierarchyid = @parent.GetDescendant(@child1, @child2);
-- 结果可能是 /1/1.1/ 或类似形式：编码上"夹"在两者之间，
-- 但物理字节会增长以保证序值稳定。
```

OrdPath 的"夹值"操作不是真正修改已有节点，而是用更长的编码插入。这是它与简单整数路径编码（如 `/1/2/3/`）最核心的区别——后者无法在不重排前提下插入新兄弟。

### hierarchyid 的局限

| 局限 | 说明 |
|------|------|
| 不强制唯一 | 应用必须保证 hierarchyid 列唯一（PK 约束） |
| 不强制紧凑 | 删除节点不会让 ID 重排，路径会有"洞" |
| 不强制连续 | 兄弟节点 ID 可能跳跃 |
| 不强制有效树 | 应用要保证 GetAncestor(1) 实际指向已存在节点 |
| 移动子树代价 | 整个子树的 ID 都要重新计算（GetReparentedValue） |
| 字符串膨胀 | 反复在中间插入会让路径越来越长 |

## PostgreSQL ltree GiST 索引深度剖析

`ltree` 配合 GiST 索引是 PostgreSQL 处理层次数据的核心组合。理解 GiST 的工作原理对引擎实现者至关重要。

### GiST 概览

GiST (Generalized Search Tree) 是 PostgreSQL 通用的索引框架，本身不绑定特定数据类型。要把它用在某个类型上，需要实现一组 "support functions"：

| Support 函数 | 用途 |
|------------|------|
| `consistent` | 判断查询条件与索引项是否相容 |
| `union` | 计算多个索引项的并集签名 |
| `compress` / `decompress` | 索引项的编码/解码 |
| `penalty` | 评估插入新项的代价（影响树的平衡） |
| `picksplit` | 分裂节点时如何把元素分成两组 |
| `same` | 判断两个索引项是否等价 |

### gist_ltree_ops 实现

PostgreSQL contrib/ltree 的 gist 实现用 **签名（signature）位图** 近似表示子树包含的所有 ltree 标签：

```
对每个标签计算 hash，落到一个 N 位的 bitmap 上
索引节点的 signature = 子节点 signature 的并集
查询时用查询 ltree 的 signature 与节点 signature 做 AND
若结果为 0，子树肯定没有匹配，剪枝
若结果非 0，可能匹配，下钻并精确比较
```

签名长度 `siglen` 直接决定误判率：

| siglen | 索引大小 | 误判率 | 适合场景 |
|--------|---------|-------|---------|
| 8 字节（默认） | 最小 | 较高 | 小数据量，标签分散 |
| 16-32 字节 | 中 | 中 | 中等数据量 |
| 64-128 字节 | 较大 | 较低 | 大数据量，常见值密集 |
| 256+ 字节 | 大 | 极低 | 超大数据量，对延迟极敏感 |

### 调优实例

假设有 1000 万行 ltree，平均 5 层深度，标签来自 100 万个不同字符串。

```sql
-- 默认 siglen=8 时，简单查询可能扫描整个 GiST 子树
EXPLAIN ANALYZE
SELECT * FROM catalog WHERE path <@ 'Top.Science.Astronomy';
-- 假设：耗时 850ms，actual rows ~5000，但 buffer hit ~50000

-- 调整到 siglen=128
DROP INDEX path_gist_idx;
CREATE INDEX path_gist_idx ON catalog
  USING gist (path gist_ltree_ops(siglen=128));

EXPLAIN ANALYZE SELECT * FROM catalog WHERE path <@ 'Top.Science.Astronomy';
-- 可能加速 5-10x：buffer hit ~5000，耗时 ~150ms
```

但代价：

```sql
-- 索引大小变化
SELECT pg_size_pretty(pg_relation_size('path_gist_idx'));
-- siglen=8: ~120 MB
-- siglen=128: ~700 MB
```

### GIN 索引的另一种选择

PG 9.x 起也可以用 GIN 索引 ltree（通过 `gin__ltree_ops`）：

```sql
CREATE INDEX path_gin_idx ON catalog USING gin (path);
```

GIN vs GiST：

| 维度 | GIN | GiST |
|------|-----|------|
| 写入速度 | 慢（更新成本高） | 快 |
| 查询速度（只读） | 通常更快 | 中等 |
| 索引大小 | 通常更小 | 中等 |
| 内存使用 | 较大 | 较小 |
| 支持的操作符 | 等价于 GiST | 等价于 GIN |
| 适合场景 | 读多写少 | 写入频繁 |

### 物化路径 vs ltree 性能对比

100 万行测试（典型办公目录树，平均深度 6）：

| 操作 | varchar + LIKE 前缀 | ltree + GiST | hierarchyid + B-tree |
|------|--------------------|--------------|----------------------|
| 子树查询（5K 行结果） | 220 ms | 80 ms | 50 ms |
| 祖先查询（10 行结果） | 全表扫 ~2s | 30 ms（用 lquery） | 10 ms |
| LCA 计算 | 应用层做 | 1 个函数调用 | 应用层做 |
| 插入 | 25 µs | 60 µs | 80 µs |
| 索引大小（占数据 %） | ~30% | ~80% | ~25% |

ltree 的索引开销大但语义丰富；hierarchyid 紧凑且字典序就是 DFS 序；自实现 LIKE 路径在大数据量下祖先查询是软肋。

## 物化路径 vs 邻接表 vs 嵌套集 vs 闭包表

### 闭包表（Closure Table）：第四种模式

除了上述三种主模式，还有一种**闭包表**模式——把树的传递闭包显式存储：

```sql
-- 节点表（与邻接表共用）
CREATE TABLE org (
    id INT PRIMARY KEY,
    name VARCHAR(100)
);

-- 闭包表：每对（祖先, 后代）都存一行
CREATE TABLE org_closure (
    ancestor_id INT,
    descendant_id INT,
    depth INT,
    PRIMARY KEY (ancestor_id, descendant_id),
    INDEX (descendant_id)
);
-- 节点 X 自身: (X, X, 0)
-- 节点 X 的父 P: (P, X, 1) + (X, X, 0)
-- 一棵深度 D 的树：闭包表 ~ N * D 行
```

| 操作 | 闭包表实现 |
|------|----------|
| 查询所有后代 | `SELECT descendant_id FROM closure WHERE ancestor_id = X` (O(K) 索引扫描) |
| 查询所有祖先 | `SELECT ancestor_id FROM closure WHERE descendant_id = X` |
| 查询深度 | `SELECT depth FROM closure WHERE ancestor_id = root AND descendant_id = X` |
| 插入新节点 | 复制父节点的所有闭包行 + 自身 (O(D)) |
| 删除节点 | 删除所有相关闭包行 (O(K)) |
| 移动子树 | 删除旧闭包 + 重建新闭包 (O(K * D)) |

闭包表的优点：所有查询都是单条 SQL 索引扫描，无递归。缺点：表行数膨胀（N * D），写入成本高（D 倍数据移动）。

### 五种模式对比

| 维度 | 邻接表 | 嵌套集 | 物化路径 | 闭包表 | 原生类型 |
|------|--------|-------|---------|-------|---------|
| 存储开销 | 极低 | 低 (lft/rgt) | 中 (path 字段) | 高 (N*D 行) | 紧凑（hierarchyid） / 中（ltree） |
| 插入速度 | 极快 O(1) | 慢 O(N) | 快 O(1) | 中 O(D) | 中 O(1) |
| 删除节点 | 中 O(K) | 慢 O(N) | 中 O(K) | 中 O(K) | 中 O(K) |
| 移动子树 | 极快 (改一个父指针) | 慢 (大量重排) | 中 (子树路径全更新) | 慢 (闭包重建) | 中 (GetReparentedValue) |
| 子树查询 | 慢 (递归 CTE) | 极快 (BETWEEN) | 快 (LIKE 前缀 + 索引) | 极快 (索引扫描) | 极快 (B-tree 范围/IsDescendantOf) |
| 祖先查询 | 慢 (递归 CTE) | 极快 (BETWEEN) | 慢 (path 解析) | 极快 (索引扫描) | 快 (GetAncestor) |
| 深度查询 | 慢 (递归计数) | 中 (额外列或计算) | 极快 (路径长度) | 极快 (从闭包读 depth) | 极快 (GetLevel/nlevel) |
| LCA 计算 | 应用层 | 可计算但较繁琐 | 路径前缀匹配 | 集合交集 | 直接函数调用 (lca) |
| 完整性约束 | 易（外键） | 难（lft/rgt 全局一致） | 中（路径需保持一致） | 中（多张表） | 难（无 FK，应用控制） |
| 适合场景 | 普通业务（写入频繁） | 几乎只读的目录 | 平衡读写、深度有限 | 复杂关联查询 | 大规模、多种查询 |

### 选型建议

```
1. 写入频繁、深度浅（< 5 层）、查询简单：邻接表 + 递归 CTE
2. 几乎只读、需要"整子树预算"：嵌套集
3. 主要查询是后代、深度可控：物化路径（ltree / hierarchyid）
4. 多种查询都要快、能容忍多表：闭包表
5. SQL Server 大规模、深度变化、需要兄弟有序：hierarchyid
6. PostgreSQL 大规模、需要灵活模式匹配（lquery）：ltree + GiST
7. 跨数据库可移植：邻接表 + 标准递归 CTE
```

## 邻接表 + 索引：常被低估的组合

很多文章把邻接表说成"性能差"，但配合现代优化器和正确的索引，邻接表通常足够好：

```sql
CREATE TABLE org (
    id INT PRIMARY KEY,
    name VARCHAR(100),
    parent_id INT,
    INDEX idx_parent (parent_id)            -- 子节点查询
);

-- 查询某节点的所有后代（递归 CTE 配 PK + parent_id 索引）
WITH RECURSIVE descendants AS (
    SELECT id, name, parent_id, 0 AS depth FROM org WHERE id = ?
    UNION ALL
    SELECT o.id, o.name, o.parent_id, d.depth + 1
    FROM org o JOIN descendants d ON o.parent_id = d.id
)
SELECT * FROM descendants;

-- 优化器能把每轮迭代用 idx_parent 索引扫描
-- 100 行子树：< 5ms（PostgreSQL，热缓存）
-- 10000 行子树：~50ms
-- 100 万行子树：~3-5s（IO 主导）
```

对于深度 < 10、子树规模 < 万行的常见业务场景，邻接表 + 标准递归 CTE 是最简单、最可移植的方案。只有在：

1. 子树规模超百万；
2. 跨子树聚合查询频繁；
3. 路径模式匹配（如 `lquery`）频繁；

时才需要考虑物化路径或原生类型。

## 实现层细节

### B-tree 索引在 hierarchyid 上的优势

hierarchyid 的字典序就是 DFS 序，意味着：

```
索引顺序：
  /        /1/      /1/1/    /1/1/1/  /1/1/2/  /1/2/
  /1/2/1/  /2/      /2/1/    ...

子树 /1/ 在索引上是连续的范围 [/1/, /2/) 之间所有项
→ B-tree 范围扫描即可，IO 极少
```

这是 hierarchyid 性能优势的核心。同样的"路径前缀"逻辑在 ltree 上需要 GiST 签名比较（更慢但更灵活），在自实现物化路径上需要 LIKE 'prefix%'（依赖 collation）。

### ltree 实现细节：标签存储

ltree 的每个标签默认最长 256 字符，整个 ltree 默认最大 65535 个标签。但 GiST 实际有效率限制（深度通常控制在 100 以内才有意义）。标签字符在 PG 12 之前限制为 `A-Z, a-z, 0-9, _`；PG 13 起放宽至包含 `-` 等。

## 常见陷阱

### 陷阱 1：hierarchyid 不是唯一约束

```sql
-- hierarchyid 列默认不是 PK
CREATE TABLE org (
    NodeId hierarchyid,    -- 没有 PK 约束
    Name NVARCHAR(50)
);

-- 应用如果不加约束，可能出现两个不同行有相同的 hierarchyid
INSERT INTO org VALUES (hierarchyid::Parse('/1/1/'), 'Bob');
INSERT INTO org VALUES (hierarchyid::Parse('/1/1/'), 'Carol');
-- 两行都成功插入，破坏树语义

-- 正确做法：始终加 PRIMARY KEY (NodeId) 或唯一约束
```

### 陷阱 2：ltree 标签的字符限制

```sql
-- PG 12 之前：标签只能是 A-Z, a-z, 0-9, _
INSERT INTO catalog VALUES ('Top.Sub-Category');   -- PG 12 报错
-- PG 13+ 支持 -

-- 含空格、点、斜杠的标签需要小心
INSERT INTO catalog (path) VALUES ('Top.My Category');
-- 错误：标签内有空格

-- 解决：只用合法字符，或在应用层做映射
```

### 陷阱 3：物化路径的 LIKE 前缀依赖 collation

```sql
-- C collation: 字典序与字节序一致
SELECT * FROM org WHERE path LIKE '/1/2/%';

-- en_US.UTF-8 collation: 大小写不敏感比较，影响 LIKE 性能
-- B-tree 索引可能无法直接用于前缀扫描

-- 解决：path 字段用 COLLATE "C"
ALTER TABLE org ALTER COLUMN path TYPE VARCHAR(500) COLLATE "C";
```

### 陷阱 4：邻接表的循环引用

```sql
-- 没有约束防止循环
INSERT INTO org VALUES (1, 'A', 2);
INSERT INTO org VALUES (2, 'B', 1);
-- 互为父子！递归 CTE 进入无限循环

-- 解决：
-- 1. 应用层校验（在更新 parent_id 时检查不形成环）
-- 2. SQL:2008 CYCLE 子句（PG 14+ / DuckDB / Db2）
-- 3. 限制递归深度（MySQL: SET cte_max_recursion_depth = 1000）
```

### 陷阱 5：hierarchyid 字符串膨胀

```sql
-- 反复在中间插入会让节点 ID 越来越长
DECLARE @parent hierarchyid = '/1/';
DECLARE @c1 hierarchyid = @parent.GetDescendant(NULL, NULL);   -- /1/1/
DECLARE @c2 hierarchyid = @parent.GetDescendant(NULL, @c1);    -- /1/0/
DECLARE @c3 hierarchyid = @parent.GetDescendant(NULL, @c2);    -- /1/-1/
-- 每次往最前面插，编码长度逐步增加

-- 解决：定期"重新平衡"——重排兄弟节点的 hierarchyid，回收编码空间
-- SQL Server 没有内置 rebalance 函数，需自己写
```

### 陷阱 6：ltree GiST 与 PG 升级

```
PG 12 → 13: ltree 标签字符规则放宽（多了 - 和其他符号）
PG 13 → 14: gist_ltree_ops siglen 默认仍是 8，但可调
PG 升级时，已有 GiST 索引可能需要 REINDEX 才能享受新签名规则
```

### 陷阱 7：递归 CTE 缺乏循环检测

```sql
-- 某些引擎（MySQL 8.0、SQL Server 2019）的递归 CTE
-- 不支持 SQL:2008 的 CYCLE 子句

-- 必须手动维护"已访问"集合
WITH RECURSIVE walk AS (
    SELECT id, ARRAY[id] AS visited, 0 AS depth FROM org WHERE id = 1
    UNION ALL
    SELECT o.id, w.visited || o.id, w.depth + 1
    FROM org o JOIN walk w ON o.parent_id = w.id
    WHERE NOT (o.id = ANY(w.visited))    -- 关键：手动避免循环
      AND w.depth < 100                    -- 关键：硬上限
)
SELECT * FROM walk;
```

## 性能基准（综合）

100 万节点、平均深度 6、组织架构样式：

| 查询类型 | 邻接表 + 递归 CTE | 物化路径 + B-tree | hierarchyid | ltree + GiST | 闭包表 |
|---------|------------------|------------------|-------------|--------------|--------|
| 子树查询（5K 后代） | 80 ms | 30 ms | 25 ms | 35 ms | 10 ms |
| 祖先链（深度 8） | 25 ms | 5 ms（含解析） | 3 ms | 8 ms | 2 ms |
| 直接子节点 | 5 ms | 25 ms（深度过滤） | 8 ms | 15 ms | 3 ms |
| LCA 计算 | 应用层 | 应用层 | 应用层 | 1 ms | 12 ms |
| 插入（叶子） | 0.3 ms | 0.5 ms | 0.8 ms | 0.7 ms | 8 ms（D 行） |
| 移动子树（500 节点） | 0.3 ms | 35 ms | 60 ms | 45 ms | 80 ms |
| 索引大小（占数据 %） | 8% (PK + parent_id) | 30% | 25% | 80% (siglen=128) | 200%+ |

注：以上数据为典型规模下的相对参考，具体取决于硬件、缓存、索引设计。

## 引擎实现建议

### 1. 是否值得实现原生层次类型

```
正面：
  - 大数据量（千万级以上）的层次查询性能可获 5-10x 提升
  - 用户体验显著改善（更直观的 API）
  - 索引大小通常优于自实现物化路径

反面：
  - 实现复杂：需要类型 + 函数 + 索引支持
  - 仅服务于 niche 场景（业务普遍是邻接表 + 递归 CTE 即可）
  - 维护成本（迁移、升级、跨版本兼容）

经验法则：
  - 通用 OLTP 引擎：可考虑（如 SQL Server）
  - 数据仓库：通常不值得（递归 CTE 已够用）
  - 嵌入式：不值得（功能预算紧）
  - 流处理：不适合（流没有"树"概念）
```

### 2. 字段编码：OrdPath vs Dewey vs 自定义

```
OrdPath:
  优势: 紧凑、可夹值、字典序 = DFS 序
  劣势: 算法复杂、调试不直观
  实现难度: 高

Dewey Decimal (1.2.3 风格):
  优势: 直观、易调试、人类可读
  劣势: 不可夹值（在 1.2 和 1.3 之间需重排）、字符串膨胀
  实现难度: 低

自定义二进制:
  优势: 可针对特定场景优化（如固定最大深度）
  劣势: 兼容性、文档、迁移
  实现难度: 中

推荐：
  企业级 OLTP: OrdPath（参考 SQL Server）
  通用扩展: Dewey 风格（参考 ltree）
  专用场景: 自定义（如基因谱系、文件系统目录树等）
```

### 3. 索引、API、优化器集成要点

**索引选择**：B-tree 适合 hierarchyid 风格（字典序 = DFS 序），范围扫描查子树；GiST 适合 ltree 风格（签名近似 + 精确验证），支持复杂模式；GIN 适合读多写少；简单 LIKE 前缀 B-tree 适合自实现物化路径但要注意 collation。

**核心 API**（参考 hierarchyid + ltree）：构造（GetRoot / Parse / ToString）、导航（GetAncestor / GetDescendant / GetLevel）、判断（IsDescendantOf / `<@` / `@>` / `=` / `<` / `>`）、操作（GetReparentedValue / lca）、可选模式匹配（lquery）。

**优化器**：识别 IsDescendantOf / `@>` / `<@` 等操作符并自动用索引；hierarchyid 选择性由子树大小估算，ltree 借助签名估算；路径常量应稳定生成同一计划；子树查询天然可按子树切分并行。

**测试要点**：编码/解码往返、字典序与 ToString 一致、夹值严格落在区间内、子树包含语义正确；性能测 1K / 100K / 1M 子树；边界覆盖空路径、根节点、极深路径、Unicode 标签；备份恢复保持二进制兼容、跨平台字节序兼容。

## 关键发现

### 1. 原生层次类型是少数派

45+ 主流 SQL 引擎中只有约 9 个支持原生层次类型：SQL Server `hierarchyid`、PostgreSQL `ltree` 及其衍生（Greenplum、TimescaleDB、YugabyteDB、Aurora PG、EnterpriseDB、Citus、Yellowbrick）。其余引擎依赖递归 CTE、CONNECT BY、或自实现物化路径。这反映了一个现实：**对大多数业务场景，邻接表 + 标准递归 CTE 已经够用**。

### 2. SQL Server 与 PostgreSQL 走了完全不同的路

SQL Server 选择了**紧凑二进制路径**（hierarchyid，OrdPath 编码）+ B-tree 索引：字典序就是 DFS 序，扫描效率极高，但操作 API 较为机械（GetAncestor / GetDescendant）。PostgreSQL 选择了**人类可读路径**（ltree，点分隔标签）+ GiST 签名索引：表达力强（lquery 模式匹配），但索引开销更大。两者各有优势，没有绝对赢家。

### 3. Oracle 用语法替代类型

CONNECT BY 是 1979 年引入的祖先级语法（比 SQL:1999 递归 CTE 早 20 年），Oracle 把整个层次遍历直接做进 SQL 引擎，而非抽象出"层次类型"。优势：语法简洁、性能稳定。劣势：跨引擎不可移植（虽然 SAP HANA / OceanBase / Snowflake 都做了 Oracle 兼容支持）。

### 4. SQL:1999 递归 CTE 是事实标准

主流引擎几乎都支持 `WITH RECURSIVE`：PostgreSQL（8.4+）、SQL Server（2005+）、Oracle（11gR2+）、MySQL（8.0+）、SQLite（3.8.3+）、MariaDB（10.2+）、DB2（9.7+）、Snowflake、BigQuery、ClickHouse、DuckDB、CockroachDB 等。这是**跨引擎可移植性最高的层次查询方案**。代价是性能：每轮迭代一次 JOIN，深度 N 需 N 轮。

### 5. ltree GiST 的 siglen 是被低估的调优参数

默认 8 字节签名对小规模可用，但百万级以上数据强烈建议调到 64 或 128 字节。能带来 5-10x 性能提升，代价是索引膨胀 2-3 倍。

### 6. hierarchyid 的字典序 = DFS 序是杀手特性

B-tree 直接可用作 DFS 序遍历索引，子树查询变成范围扫描，IO 极少。这是 hierarchyid 在大表查询上始终领先 ltree 的根本原因。但代价：插入 / 删除 / 移动子树时需要小心维护字典序，应用复杂度高于邻接表。

### 7. 闭包表是被忽视的强力方案

闭包表（Closure Table）能把所有树查询都变成单条 SQL 索引扫描——不需要递归 CTE，不需要 GiST，不需要原生类型。代价是表行数膨胀（N * D），写入成本高。在多种查询模式都要快的场景中，闭包表往往优于其他模式。但要么手动维护要么用触发器，工程上更繁琐。

### 8. 嵌套集已经过时

嵌套集（lft / rgt）在 1990 年代非常流行，因为只需 B-tree 索引 + BETWEEN 即可完成大部分查询。但大数据量下"插入要重排全表 lft/rgt"的代价让它在现代系统中几乎被淘汰。除非数据极少变更（如静态分类目录），否则不推荐。

### 9. 跨引擎可移植的最佳折中

如果系统需要支持多种数据库（如 SaaS 多租户接入不同数据库），最稳妥的做法：

```
1. 邻接表（id, parent_id）+ 标准递归 CTE
2. 应用层维护一个 path 字段（"materialized path"）
3. path 字段建 B-tree 索引，用 LIKE 'prefix%' 做后代查询
4. 保留递归 CTE 作为兜底（适用所有引擎）
```

这套方案可移植到 PostgreSQL、MySQL、SQL Server、Oracle、SQLite、Snowflake、BigQuery 等所有主流引擎。

### 10. ClickHouse 的 Hierarchical Dictionary 是独特模型

ClickHouse 不依赖递归 CTE 也不实现层次类型，而是把层次结构外置为字典（Dictionary）：

```sql
CREATE DICTIONARY org_dict (...) HIERARCHICAL ...;
SELECT dictGetHierarchy('org_dict', id);   -- 一个调用获得祖先链
```

这种"层次作为外部数据源"的思路非常符合 ClickHouse 的"事实表 + 维度字典"哲学，但跨引擎不可移植。

### 11. 现代云数仓没有原生层次类型的根本原因

Snowflake、BigQuery、Databricks 等云数仓都不实现原生层次类型，原因：

```
1. 列存格式不利于层次类型（变长字段、签名索引复杂）
2. 用户场景以分析为主，层次查询频率不高
3. 递归 CTE 已在 SQL:1999 标准中，足以覆盖典型需求
4. 实现成本高，维护成本更高（每次格式升级都要兼容）
```

### 12. SQL/PGQ 是未来的潜在替代

SQL:2023 引入的 SQL/PGQ（GRAPH_TABLE 子句）能更优雅地处理层次查询（树是图的特殊形态）。但目前几乎只有 Oracle 23ai 实现了完整的 SQL/PGQ。短期内（5+ 年），递归 CTE / 原生层次类型仍是主流。

## 总结对比矩阵

### 全引擎概览

| 引擎 | 原生层次类型 | 递归 CTE | CONNECT BY | 物化路径方案 | 闭包表方案 |
|------|------------|---------|-----------|-------------|----------|
| PostgreSQL | ltree (扩展) | 是 (8.4+) | -- | varchar + LIKE | 自实现 |
| SQL Server | hierarchyid (2008+) | 是 (2005+) | -- | varchar + LIKE | 自实现 |
| Oracle | -- | 是 (11gR2+) | 是 (V2 1979) | varchar + LIKE | 自实现 |
| MySQL | -- | 是 (8.0+) | -- | varchar + LIKE | 自实现 |
| MariaDB | -- | 是 (10.2+) | 有限 (兼容模式) | varchar + LIKE | 自实现 |
| SQLite | -- | 是 (3.8+) | -- | varchar + LIKE | 自实现 |
| DB2 | -- | 是 (9.7+) | 有限 | varchar + LIKE | 自实现 |
| Snowflake | -- | 是 | 是 (兼容) | varchar + LIKE | 自实现 |
| BigQuery | -- | 是 (2021) | -- | string + LIKE | 自实现 |
| Redshift | -- | 是 | -- | varchar + LIKE | 自实现 |
| DuckDB | -- | 是 (含 SEARCH/CYCLE) | -- | varchar + LIKE | 自实现 |
| ClickHouse | -- | 是 (22.x+) | -- | string + LIKE | Hierarchical Dict |
| Trino | -- | 是 | -- | varchar + LIKE | 自实现 |
| Spark SQL | -- | 是 (3.5+) | -- | string + LIKE | 自实现 |
| Hive | -- | -- | -- | string + LIKE | 自实现 |
| Databricks | -- | 是 | -- | string + LIKE | 自实现 |
| Teradata | -- | 是 | 有限 | varchar + LIKE | 自实现 |
| Greenplum | ltree (继承 PG) | 是 | -- | varchar + LIKE | 自实现 |
| YugabyteDB | ltree (继承 PG) | 是 | -- | varchar + LIKE | 自实现 |
| TimescaleDB | ltree (继承 PG) | 是 | -- | varchar + LIKE | 自实现 |
| CockroachDB | -- | 是 | -- | varchar + LIKE | 自实现 |
| TiDB | -- | 是 (5.1+) | -- | varchar + LIKE | 自实现 |
| OceanBase | -- | 是 | 是 (Oracle 兼容) | varchar + LIKE | 自实现 |
| SingleStore | -- | 是 | -- | varchar + LIKE | 自实现 |
| Vertica | -- | 是 | -- | varchar + LIKE | 自实现 |
| Impala | -- | 是 | -- | string + LIKE | 自实现 |
| StarRocks | -- | 是 | -- | string + LIKE | 自实现 |
| Doris | -- | 是 | -- | string + LIKE | 自实现 |
| MonetDB | -- | 是 | -- | varchar + LIKE | 自实现 |
| CrateDB | -- | -- | -- | string + LIKE | 自实现 |
| Exasol | -- | 是 | 是 (类似 Oracle) | varchar + LIKE | 自实现 |
| SAP HANA | -- | 是 | 是 | varchar + LIKE | Hierarchy View |
| Informix | -- | 是 (CONNECT BY 风格) | 有限 | varchar + LIKE | 自实现 |
| Firebird | -- | 是 | -- | varchar + LIKE | 自实现 |
| H2 | -- | 是 | -- | varchar + LIKE | 自实现 |
| HSQLDB | -- | 是 | -- | varchar + LIKE | 自实现 |
| Derby | -- | 有限 | -- | varchar + LIKE | 自实现 |
| Amazon Athena | -- | 是 | -- | string + LIKE | 自实现 |
| Azure Synapse | -- | 是 | -- | varchar + LIKE | 自实现 |
| Azure SQL DB | hierarchyid | 是 | -- | varchar + LIKE | 自实现 |
| Azure SQL MI | hierarchyid | 是 | -- | varchar + LIKE | 自实现 |
| Google Spanner | -- | 是 | -- | string + LIKE | 自实现 |
| Materialize | -- | 是 (有限) | -- | string + LIKE | 自实现 |
| RisingWave | -- | 是 | -- | string + LIKE | 自实现 |
| QuestDB | -- | -- | -- | -- | -- |
| InfluxDB (SQL) | -- | -- | -- | -- | -- |
| DatabendDB | -- | 是 | -- | string + LIKE | 自实现 |
| Yellowbrick | ltree (可装) | 是 | -- | varchar + LIKE | 自实现 |
| Firebolt | -- | 有限 | -- | string + LIKE | 自实现 |
| MaxCompute | -- | 是 | -- | string + LIKE | 自实现 |
| Pinot | -- | -- | -- | -- | -- |
| Druid | -- | -- | -- | -- | -- |

### 引擎选型建议

| 场景 | 推荐方案 | 引擎 |
|------|---------|------|
| 小数据量、跨引擎可移植 | 邻接表 + 递归 CTE | 任意主流 SQL 引擎 |
| 大规模 OLTP、SQL Server 生态 | hierarchyid | SQL Server / Azure SQL |
| 大规模 OLTP、PostgreSQL 生态 | ltree + GiST | PostgreSQL 系 |
| Oracle 生态、传统应用 | CONNECT BY | Oracle / SAP HANA / OceanBase |
| 大量祖先 / 后代查询 | 闭包表 | 任意 SQL 引擎 |
| 几乎只读的目录 / 分类树 | 嵌套集 | 任意 SQL 引擎 |
| 云数仓分析场景 | 邻接表 + 递归 CTE | Snowflake / BigQuery / ClickHouse |
| ClickHouse 维度建模 | Hierarchical Dictionary | ClickHouse |
| 高度灵活的模式匹配 | ltree + lquery | PostgreSQL |
| 跨引擎"既要又要" | 邻接表 + 物化路径双轨 | 任意 SQL 引擎 |

## 参考资料

- SQL Server: [hierarchyid Data Type Method Reference](https://learn.microsoft.com/en-us/sql/t-sql/data-types/hierarchyid-data-type-method-reference)
- SQL Server: [Tutorial: Using hierarchyid](https://learn.microsoft.com/en-us/sql/relational-databases/tables/tutorial-using-the-hierarchyid-data-type)
- O'Neil, P. & Murthy, A.: "ORDPATHs: Insert-Friendly XML Node Labels" (SIGMOD 2004) — hierarchyid OrdPath 的学术基础
- PostgreSQL: [ltree Module Documentation](https://www.postgresql.org/docs/current/ltree.html)
- PostgreSQL: [GiST Indexes](https://www.postgresql.org/docs/current/gist.html)
- PostgreSQL: [btree_ltree Extension](https://www.postgresql.org/docs/current/btree-ltree.html)
- PostgreSQL: [The path indexing problem](https://wiki.postgresql.org/wiki/Ltree)
- Oracle: [Hierarchical Queries with CONNECT BY](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Hierarchical-Queries.html)
- Oracle: [Recursive WITH Clause](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SELECT.html)
- Joe Celko: "Trees and Hierarchies in SQL for Smarties" (Morgan Kaufmann, 2nd ed.) — 嵌套集 / 邻接表 / 闭包表的经典教材
- ISO/IEC 9075-2:1999, Section 7.7 — SQL:1999 递归 CTE 标准定义
- ClickHouse: [Hierarchical Dictionaries](https://clickhouse.com/docs/en/sql-reference/dictionaries/external-dictionaries/external-dicts-dict-hierarchical)
- DuckDB: [Recursive CTEs with SEARCH and CYCLE](https://duckdb.org/docs/sql/query_syntax/with)
- Apache AGE: [PostgreSQL Graph Extension](https://age.apache.org/) — 提供 Cypher 风格的层次查询能力
- SQL Server: [Hierarchical Data Patterns and Anti-Patterns](https://learn.microsoft.com/en-us/sql/relational-databases/hierarchical-data-sql-server)
- Bender, M. et al.: "Two Simplified Algorithms for Maintaining Order in a List" (ESA 2002) — 与 OrdPath 相关的有序列表维护
- 关联文章: [递归 CTE 增强](./recursive-cte-enhancements.md)、[图查询](./graph-queries.md)、[CTE 递归查询](./cte-recursive-query.md)
