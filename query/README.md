# Query -- 查询

查询语法，包含连接查询、子查询、窗口函数、CTE、分页、全文搜索、集合操作、行列转换等。

## 模块列表

| 模块 | 说明 | 对比表 |
|---|---|---|
| [cte](cte/) | 公共表表达式（CTE） | [对比](cte/_comparison.md) |
| [full-text-search](full-text-search/) | 全文搜索 | [对比](full-text-search/_comparison.md) |
| [joins](joins/) | 连接查询 | [对比](joins/_comparison.md) |
| [pagination](pagination/) | 分页 | [对比](pagination/_comparison.md) |
| [pivot-unpivot](pivot-unpivot/) | 行列转换 | [对比](pivot-unpivot/_comparison.md) |
| [set-operations](set-operations/) | 集合操作（UNION/INTERSECT/EXCEPT） | [对比](set-operations/_comparison.md) |
| [subquery](subquery/) | 子查询 | [对比](subquery/_comparison.md) |
| [window-functions](window-functions/) | 窗口函数 | [对比](window-functions/_comparison.md) |

## 学习建议

建议按 joins → subquery → set-operations → cte → window-functions → pagination → pivot-unpivot → full-text-search 的顺序学习。
JOIN 和子查询是 SQL 查询的基石，CTE 和窗口函数是现代 SQL 的核心竞争力，
分页和行列转换是业务开发高频需求，全文搜索偏专项功能。

## 关键差异概述

查询语法在各方言中差异集中在：JOIN 类型支持（LATERAL JOIN 并非所有方言都支持、ClickHouse 有独特的 JOIN 引擎）、
窗口函数能力（MySQL 8.0 才引入窗口函数、ClickHouse 的窗口函数覆盖不如 PostgreSQL 全面）、
CTE 支持（MySQL 8.0+/SQLite 3.8.3+ 才支持 CTE，递归 CTE 的深度限制各方言不同）。

分页是最经典的"每个方言都不一样"的领域：MySQL/PostgreSQL 用 LIMIT/OFFSET，
Oracle 12c 之前用 ROWNUM，SQL Server 用 OFFSET FETCH 或 TOP，分析型引擎各有各的限制。

## 常见陷阱

- `OFFSET` 分页在大偏移量时性能极差，应改用键集分页（Keyset Pagination）
- MySQL 8.0 之前没有窗口函数，需要用变量模拟 ROW_NUMBER()
- `FULL OUTER JOIN` 在 MySQL/MariaDB 中不支持，需要用 UNION 模拟
- 递归 CTE 无终止条件会导致无限循环，各方言默认递归深度不同
