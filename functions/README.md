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
