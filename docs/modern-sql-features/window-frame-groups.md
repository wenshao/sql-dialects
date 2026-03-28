# 窗口帧的 GROUPS 模式

SQL:2011 引入的第三种窗口帧模式——按对等组（peer group）而非物理行或逻辑值范围定义窗口边界。

## 支持矩阵

| 引擎 | ROWS | RANGE | GROUPS | EXCLUDE | 版本 |
|------|------|-------|--------|---------|------|
| PostgreSQL | 支持 | 支持 | 支持 | 支持 | 11+ (2018) |
| SQLite | 支持 | 支持 | 支持 | 支持 | 3.28.0+ (2019) |
| DuckDB | 支持 | 支持 | 支持 | 支持 | 0.3.0+ |
| MariaDB | 支持 | 支持 | 支持 | 不支持 | 10.9+ |
| MySQL | 支持 | 支持 | 不支持 | 不支持 | 8.0+ |
| SQL Server | 支持 | 支持 | 不支持 | 不支持 | 2012+ |
| Oracle | 支持 | 支持 | 不支持 | 不支持 | 8i+ |
| BigQuery | 支持 | 支持 | 不支持 | 不支持 | GA |
| Snowflake | 支持 | 部分 | 不支持 | 不支持 | GA |
| ClickHouse | 支持 | 不支持 | 不支持 | 不支持 | 21.1+ |
| Trino | 支持 | 支持 | 支持 | 不支持 | 最新版本 |

## 三种帧模式的本质区别

SQL 窗口函数中，帧（frame）定义了"当前行参与计算时，哪些行应该被包含在内"。SQL 标准定义了三种帧模式：

### ROWS: 物理行计数

```sql
-- ROWS: 以物理行为单位
-- 当前行前 2 行 + 当前行 + 当前行后 2 行 = 最多 5 行
SUM(val) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING)
```

ROWS 严格按行的物理位置计数。如果 ORDER BY 列有重复值，相同值的不同行可能被区别对待。

### RANGE: 逻辑值范围

```sql
-- RANGE: 以 ORDER BY 列的值范围为单位
-- 当前行的值 - 10 到 当前行的值 + 10 的范围内所有行
SUM(val) OVER (ORDER BY score RANGE BETWEEN 10 PRECEDING AND 10 FOLLOWING)
```

RANGE 按 ORDER BY 列的值计算范围。所有值相同的行（对等组）要么全部包含，要么全部排除。

### GROUPS: 对等组计数

```sql
-- GROUPS: 以对等组为单位
-- 当前组前 1 个组 + 当前组 + 当前组后 1 个组 = 最多 3 个组
SUM(val) OVER (ORDER BY category GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING)
```

GROUPS 将 ORDER BY 值相同的行视为一个"组"，然后按组计数。这是 ROWS 和 RANGE 之间的中间语义。

## 设计动机: 为什么需要第三种模式

### 问题: ROWS 和 RANGE 各有局限

考虑一个场景：计算每个学生分数与相邻分数段学生的平均分。

```
score: 80, 80, 85, 85, 85, 90, 95
```

**ROWS 的问题**——同分数的行被割裂：

```sql
-- ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
-- 对于第一个 85: 帧 = {80, 85, 85}，缺少第三个 85
-- 对于第三个 85: 帧 = {85, 85, 90}，缺少第一个 85
-- 同分数的学生看到不同结果!
```

**RANGE 的问题**——只支持值偏移，不支持"组数"：

```sql
-- RANGE BETWEEN 5 PRECEDING AND 5 FOLLOWING
-- 对于 85: 帧 = {80, 80, 85, 85, 85, 90}
-- 包含了 80 和 90，但不包含 95
-- 如果想要"相邻的 1 个组"，RANGE 无法精确表达
```

### GROUPS 的解决方案

```sql
-- GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING
-- 对于 85 (作为一个组):
--   前 1 组 = {80, 80}
--   当前组 = {85, 85, 85}
--   后 1 组 = {90}
--   帧 = {80, 80, 85, 85, 85, 90}
-- 所有 score=85 的行看到相同的帧!
```

GROUPS 模式的优势：
1. 同值行总是被一致对待（不像 ROWS）
2. 用组数而非值偏移定义范围（不像 RANGE）
3. 对非数值类型的 ORDER BY 也适用

## 语法详解

### 完整的窗口帧语法

```sql
window_function OVER (
    [PARTITION BY expr_list]
    ORDER BY expr_list
    { ROWS | RANGE | GROUPS }
    BETWEEN
        { UNBOUNDED PRECEDING | n PRECEDING | CURRENT ROW | n FOLLOWING | UNBOUNDED FOLLOWING }
    AND
        { UNBOUNDED PRECEDING | n PRECEDING | CURRENT ROW | n FOLLOWING | UNBOUNDED FOLLOWING }
    [EXCLUDE { CURRENT ROW | GROUP | TIES | NO OTHERS }]
)
```

### GROUPS 模式具体示例（PostgreSQL 11+ / SQLite 3.28+）

```sql
-- 示例数据
CREATE TABLE scores (student TEXT, score INT);
INSERT INTO scores VALUES
    ('Alice', 80), ('Bob', 80),
    ('Carol', 85), ('Dave', 85), ('Eve', 85),
    ('Frank', 90), ('Grace', 95);

-- GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING
SELECT student, score,
    AVG(score) OVER (
        ORDER BY score
        GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING
    ) AS avg_nearby
FROM scores;

-- 结果:
-- Alice  80  82.0   (组: {80,80,85,85,85})
-- Bob    80  82.0   (组: {80,80,85,85,85})
-- Carol  85  84.3   (组: {80,80,85,85,85,90})
-- Dave   85  84.3   (同上)
-- Eve    85  84.3   (同上)
-- Frank  90  90.0   (组: {85,85,85,90,95})
-- Grace  95  92.5   (组: {90,95})
```

### 三种模式对比（数据: score = 80, 80, 85, 85, 85, 90, 95）

| score=85 的帧 | ROWS (前后各1行) | RANGE (值+/-5) | GROUPS (前后各1组) |
|---------------|-----------------|----------------|-------------------|
| 第1个85 | {80, 85, 85} | {80,80,85,85,85,90} | {80,80,85,85,85,90} |
| 第2个85 | {85, 85, 85} | 同上 | 同上 |
| 第3个85 | {85, 85, 90} | 同上 | 同上 |

关键区别: ROWS 下三个 85 看到不同帧; GROUPS 下三个 85 帧完全一致。

## EXCLUDE 子句

SQL:2011 同时引入了 EXCLUDE 子句，可与 GROUPS 配合使用（也可用于 ROWS/RANGE）。

| EXCLUDE 选项 | 语义 | 典型用途 |
|-------------|------|---------|
| `NO OTHERS` | 不排除（默认） | - |
| `CURRENT ROW` | 排除当前行，保留同组其他行 | 除自己外的组内均值 |
| `GROUP` | 排除当前行的整个对等组 | 只看相邻组 |
| `TIES` | 排除对等行，保留当前行自身 | 当前行 vs 同值其他行 |

```sql
-- 计算每个学生与同分段其他学生的分差
SELECT student, score,
    score - AVG(score) OVER (
        ORDER BY score GROUPS BETWEEN 0 PRECEDING AND 0 FOLLOWING
        EXCLUDE CURRENT ROW
    ) AS diff_from_peers
FROM scores;
```

## 不支持 GROUPS 的引擎如何替代

### MySQL / SQL Server / Oracle

```sql
-- 模拟 GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING:
-- 步骤 1: 为每个值分配组号
-- 步骤 2: 用 RANGE 或自连接实现组级窗口

-- 方案: DENSE_RANK + 自连接
WITH grouped AS (
    SELECT *, DENSE_RANK() OVER (ORDER BY score) AS grp
    FROM scores
)
SELECT a.student, a.score,
    AVG(b.score) AS avg_nearby
FROM grouped a
JOIN grouped b ON b.grp BETWEEN a.grp - 1 AND a.grp + 1
GROUP BY a.student, a.score;
```

## 对引擎开发者的实现建议

1. 语法解析

在窗口帧的语法产生式中新增 GROUPS 关键字：

```
frame_clause:
    frame_mode frame_extent [frame_exclusion]

frame_mode:
    ROWS | RANGE | GROUPS    -- GROUPS 为新增

frame_exclusion:
    EXCLUDE CURRENT ROW
  | EXCLUDE GROUP
  | EXCLUDE TIES
  | EXCLUDE NO OTHERS
```

2. 对等组边界的维护

GROUPS 模式的核心实现挑战是在帧计算中高效维护对等组边界。

```
数据: [80, 80, 85, 85, 85, 90, 95]
对等组: [{80,80}, {85,85,85}, {90}, {95}]
组索引:    0        1           2     3
```

实现方案：

**方案 A: 预计算组边界数组**

```
1. 排序后扫描一遍，记录每个组的起止位置:
   groups[] = [{start:0, end:1}, {start:2, end:4}, {start:5, end:5}, {start:6, end:6}]
2. 对每行，找到其所在组索引 g
3. 帧 = groups[g-n] 到 groups[g+m] 的所有行
```

**方案 B: 双指针滑动窗口**

```
维护两个指针: frame_start_group, frame_end_group
当当前行移动到下一个组时，调整帧的组指针
在组边界处批量添加/移除整组行
```

3. EXCLUDE 子句的实现

EXCLUDE 在帧计算后做过滤：

```
帧的行集合 = 由 GROUPS/ROWS/RANGE 确定的行
EXCLUDE CURRENT ROW: 从帧行集合中移除当前行
EXCLUDE GROUP: 从帧行集合中移除所有与当前行 ORDER BY 值相等的行
EXCLUDE TIES: 移除与当前行相等的行，但保留当前行自身
```

EXCLUDE GROUP 和 EXCLUDE TIES 的区别仅在于是否保留当前行，实现时可以共享组边界检测逻辑。

4. 聚合函数的增量计算

对于 SUM/COUNT/AVG 等可增量计算的聚合函数，GROUPS 模式可以优化：

- 组边界处批量 add/remove 一整组的值
- 相比 ROWS 逐行 add/remove，GROUPS 在组内行不需要更新帧

5. 与 ROWS/RANGE 的代码复用

三种帧模式可以共享大部分窗口计算基础设施，只在"帧边界确定"逻辑上不同：

| 模式 | 帧边界确定方式 |
|------|---------------|
| ROWS | 物理行偏移: current_row_idx +/- N |
| RANGE | 值比较: ORDER BY 列值在 [current_val - N, current_val + N] 范围内 |
| GROUPS | 组偏移: current_group_idx +/- N，然后展开为组内所有行 |

## 实际应用场景

```sql
-- 场景 1: 滑动窗口按评分等级（不是按固定行数）
-- 计算每个产品与相邻评分等级产品的平均评分
SELECT product_name, rating,
    AVG(rating) OVER (
        ORDER BY rating
        GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING
    ) AS avg_nearby_ratings
FROM products;

-- 场景 2: 时间序列中按日期分组的滑动平均
-- (多个事件可能发生在同一天)
SELECT event_date, event_count,
    SUM(event_count) OVER (
        ORDER BY event_date
        GROUPS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS last_7_date_groups_total
FROM daily_events;
```

## 参考资料

- SQL:2011 标准: ISO/IEC 9075-2:2011 Section 7.11 `<window clause>`
- PostgreSQL: [Window Function Calls](https://www.postgresql.org/docs/current/sql-expressions.html#SYNTAX-WINDOW-FUNCTIONS)
- SQLite: [Window Functions](https://www.sqlite.org/windowfunctions.html)
- Modern SQL: [GROUPS frame type](https://modern-sql.com/blog/2019-02/postgresql-11)
