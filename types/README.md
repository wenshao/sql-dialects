# Types -- 数据类型

数据类型定义与操作，包含字符串、数值、日期时间、JSON、复合类型（ARRAY/MAP/STRUCT）等。

## 模块列表

| 模块 | 说明 | 对比表 |
|---|---|---|
| [array-map-struct](array-map-struct/) | 复合类型（ARRAY/MAP/STRUCT） | -- |
| [datetime](datetime/) | 日期时间类型 | [对比](datetime/_comparison.md) |
| [json](json/) | JSON 类型与操作 | [对比](json/_comparison.md) |
| [numeric](numeric/) | 数值类型 | [对比](numeric/_comparison.md) |
| [string](string/) | 字符串类型 | [对比](string/_comparison.md) |

## 学习建议

建议按 numeric → string → datetime → json → array-map-struct 的顺序学习。
数值和字符串是所有 SQL 的基础，日期时间是业务逻辑的核心，
JSON 和复合类型是现代数据处理的趋势，但并非所有方言都有完整支持。

## 关键差异概述

数据类型是跨方言迁移时最容易出错的领域。核心差异包括：整数溢出行为（MySQL 默认静默截断 vs PostgreSQL 报错）、
VARCHAR 长度上限（MySQL 65535 字节 vs PostgreSQL 1GB vs Oracle 4000/32767 字节）、
日期时间精度（MySQL DATETIME 默认秒级 vs PostgreSQL TIMESTAMP 默认微秒级）。

JSON 支持的成熟度差异巨大：PostgreSQL 的 JSONB 有索引支持和丰富运算符，MySQL 8.0 的 JSON 功能实用但不如 PostgreSQL 丰富，
SQLite 3.38.0+ 才内置 JSON 函数，而 ClickHouse/Hive 更偏好将 JSON 展开为独立列。

## 常见陷阱

- SQLite 是动态类型系统，声明的类型只是"亲和性"，任何列可以存任何类型的值
- MySQL 的 FLOAT/DOUBLE 存在精度丢失问题，金融场景必须用 DECIMAL
- Oracle 中空字符串 `''` 等于 NULL，这与所有其他数据库不同
- 大数据引擎通常不支持 CHAR（定长字符串），只有 STRING/VARCHAR
