# DDL -- 数据定义

数据定义语言（Data Definition Language），包含建表、改表、索引、约束、视图、序列等数据库对象的创建与管理操作。

## 模块列表

| 模块 | 说明 | 对比表 |
|---|---|---|
| [alter-table](alter-table/) | 改表语法对比 | [对比](alter-table/_comparison.md) |
| [constraints](constraints/) | 约束管理 | [对比](constraints/_comparison.md) |
| [create-table](create-table/) | 建表语法对比 | [对比](create-table/_comparison.md) |
| [indexes](indexes/) | 索引类型与创建 | [对比](indexes/_comparison.md) |
| [sequences](sequences/) | 序列与自增策略 | [对比](sequences/_comparison.md) |
| [users-databases](users-databases/) | 数据库/Schema/用户管理 | -- |
| [views](views/) | 视图（普通视图、物化视图） | [对比](views/_comparison.md) |

## 学习建议

建议按 create-table → constraints → indexes → alter-table → views → sequences → users-databases 的顺序学习。
建表是基础，约束和索引直接影响数据完整性和查询性能，改表是日常运维必备。
视图和序列属于进阶内容，users-databases 偏运维管理方向。

## 关键差异概述

DDL 在各方言中差异最大的领域是：自增策略（AUTO_INCREMENT vs SERIAL vs IDENTITY vs SEQUENCE）、
在线 DDL 能力（MySQL 8.0 ALGORITHM=INSTANT vs PostgreSQL 11+ 即时 ADD COLUMN WITH DEFAULT）、
以及约束执行方式（BigQuery/Snowflake 的约束是信息性的不强制执行）。

分析型引擎（ClickHouse、Hive、StarRocks）的建表语法与传统 RDBMS 差异极大，
需要指定存储引擎、排序键、分区策略、分桶策略等，这些概念在传统数据库中不存在或含义不同。

## 常见陷阱

- MySQL 的 `ALTER TABLE` 可能锁全表（5.6 之前），PostgreSQL 的 `ADD COLUMN` 带默认值在 11+ 才是即时的
- 分布式数据库的约束通常不强制执行（TiDB 6.6 之前不支持外键）
- 各方言的 `DROP COLUMN` 行为差异大：SQLite 3.35.0 之前完全不支持
- ClickHouse/Hive 没有传统意义上的 `ALTER COLUMN` 修改列类型

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **DDL 能力** | 受限：3.35.0 前无 DROP COLUMN，不支持 MODIFY COLUMN | 支持多数 DDL 但 ALTER 为异步 mutation | Serverless DDL 在线执行，无锁表 | 完整 DDL 支持 |
| **约束体系** | 支持但外键默认关闭 | 无传统约束（无 FK/CHECK/UNIQUE 强制执行） | 约束为信息性（NOT ENFORCED） | 完整约束体系 |
| **索引** | B-Tree 索引 + 部分索引 | 跳数索引（非传统索引） | 无索引（分区+聚簇替代） | 丰富索引类型 |
| **权限管理** | 无 GRANT/REVOKE | 完整权限系统 | IAM 权限管理 | SQL GRANT/REVOKE |
| **在线 DDL** | 单文件操作天然轻量 | ALTER 异步不阻塞查询 | Serverless 在线执行 | MySQL 部分支持 / PG 多数即时 |
