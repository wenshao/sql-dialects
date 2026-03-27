# Scenarios -- 实战场景

常见实战场景的最佳实践，每个场景覆盖 45 种方言的惯用写法，包含 TopN 查询、累计求和、数据去重、层级查询、日期填充等。

## 模块列表

| 模块 | 说明 | 对比表 |
|---|---|---|
| [date-series-fill](date-series-fill/) | 日期序列填充 | [对比](date-series-fill/_comparison.md) |
| [deduplication](deduplication/) | 数据去重 | [对比](deduplication/_comparison.md) |
| [gap-detection](gap-detection/) | 区间缺失检测 | [对比](gap-detection/_comparison.md) |
| [hierarchical-query](hierarchical-query/) | 层级查询 | [对比](hierarchical-query/_comparison.md) |
| [json-flatten](json-flatten/) | JSON 展开 | [对比](json-flatten/_comparison.md) |
| [migration-cheatsheet](migration-cheatsheet/) | 迁移速查表 | [对比](migration-cheatsheet/_comparison.md) |
| [ranking-top-n](ranking-top-n/) | TopN 查询 | [对比](ranking-top-n/_comparison.md) |
| [running-total](running-total/) | 累计求和 | [对比](running-total/_comparison.md) |
| [slowly-changing-dim](slowly-changing-dim/) | 缓慢变化维（SCD） | [对比](slowly-changing-dim/_comparison.md) |
| [string-split-to-rows](string-split-to-rows/) | 字符串拆分为多行 | [对比](string-split-to-rows/_comparison.md) |
| [window-analytics](window-analytics/) | 窗口分析（移动平均、同环比、占比） | -- |

## 学习建议

建议按使用频率排序学习：ranking-top-n → deduplication → running-total → window-analytics → date-series-fill → hierarchical-query。
TopN 查询和去重几乎每个项目都会遇到，累计求和和窗口分析是报表开发的核心，
层级查询和 SCD 偏数仓方向，迁移速查在做数据库迁移项目时再查阅。

## 关键差异概述

实战场景的跨方言差异主要体现在可用工具的不同：有窗口函数的方言（MySQL 8.0+、PostgreSQL 8.4+）
可以优雅地解决大部分场景，没有窗口函数的老版本或简单引擎需要用自连接或变量模拟。

日期序列生成是差异最大的场景：PostgreSQL 的 generate_series() 最优雅，MySQL 需要递归 CTE 或辅助数字表，
Oracle 用 CONNECT BY LEVEL，BigQuery 用 UNNEST(GENERATE_DATE_ARRAY())，几乎每个方言都不同。

## 常见陷阱

- 去重场景中用 DELETE + 子查询在大表上性能极差，应考虑 CREATE TABLE AS SELECT 重建
- 层级查询的递归深度需要控制，否则可能导致查询无限运行
- 窗口函数在分布式引擎中可能触发数据 shuffle，大数据量时注意 PARTITION BY 的基数
