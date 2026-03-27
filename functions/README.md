# Functions -- 内置函数

内置函数对比，包含字符串函数、日期函数、聚合函数、条件函数、数学函数、类型转换等。

## 模块列表

| 模块 | 说明 | 对比表 |
|---|---|---|
| [aggregate](aggregate/) | 聚合函数 | [对比](aggregate/_comparison.md) |
| [conditional](conditional/) | 条件函数 | [对比](conditional/_comparison.md) |
| [date-functions](date-functions/) | 日期函数 | [对比](date-functions/_comparison.md) |
| [math-functions](math-functions/) | 数学函数 | [对比](math-functions/_comparison.md) |
| [string-functions](string-functions/) | 字符串函数 | [对比](string-functions/_comparison.md) |
| [type-conversion](type-conversion/) | 类型转换 | [对比](type-conversion/_comparison.md) |

## 学习建议

建议按 conditional → aggregate → string-functions → date-functions → type-conversion → math-functions 的顺序学习。
CASE/COALESCE 几乎每条查询都用得到，聚合函数是报表分析的基础，
字符串和日期函数是业务逻辑处理的核心，类型转换在跨方言迁移时不可避免。

## 关键差异概述

函数是方言差异最直观的领域。同一功能在不同方言中函数名完全不同：字符串拼接
（MySQL CONCAT() vs Oracle `||` vs SQL Server `+`）、日期加减（MySQL DATE_ADD() vs PostgreSQL `interval` 运算 vs
Oracle ADD_MONTHS()）、类型转换（标准 CAST() vs MySQL CONVERT() vs PostgreSQL `::` 运算符）。

聚合函数中差异最大的是字符串聚合：MySQL 的 GROUP_CONCAT()、PostgreSQL 的 STRING_AGG()、
Oracle 的 LISTAGG()、SQL Server 的 STRING_AGG()（2017+），函数名和参数顺序都不同。

## 常见陷阱

- `COUNT(column)` 不计 NULL 值，`COUNT(*)` 计所有行，混淆会导致统计错误
- ROUND() 的银行家舍入 vs 四舍五入行为在不同方言中不一致
- Oracle 的 NVL() 不是标准函数，跨方言迁移时应改用 COALESCE()
- 日期格式化字符串在每个方言中都不同（%Y vs YYYY vs yyyy），这是迁移时的高频问题

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **函数丰富度** | 基本函数集较小，可通过 C API 扩展 | 极其丰富的函数库（数百个内置函数） | 丰富的标准函数集 | 各方言函数集完整但名称差异大 |
| **日期函数** | 有限：date()/time()/strftime() | 极丰富：toDate/addDays/dateDiff 等专用函数 | 统一命名的 DATE_xxx 系列函数 | 各方言命名和参数完全不同 |
| **聚合函数** | 基本聚合 + GROUP_CONCAT | 标准聚合 + 大量近似聚合（uniqHLL12 等） | 标准聚合 + APPROX 系列 | 完整聚合函数 |
| **类型转换** | 动态类型使转换概念淡化 | 严格类型 + 专用转换函数（toInt32 等） | CAST / SAFE_CAST | CAST / PG :: / MySQL CONVERT |
| **自定义函数** | C API 注册自定义函数 | C++/SQL UDF | SQL/JavaScript UDF | 各方言有 UDF 支持 |
