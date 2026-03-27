# Advanced -- 高级特性

高级数据库特性，包含存储过程、触发器、事务、权限管理、执行计划、临时表、分区、动态 SQL、错误处理、锁机制等。

## 模块列表

| 模块 | 说明 | 对比表 |
|---|---|---|
| [dynamic-sql](dynamic-sql/) | 动态 SQL | [对比](dynamic-sql/_comparison.md) |
| [error-handling](error-handling/) | 错误处理 | [对比](error-handling/_comparison.md) |
| [explain](explain/) | 执行计划 | [对比](explain/_comparison.md) |
| [locking](locking/) | 锁机制 | -- |
| [partitioning](partitioning/) | 分区 | [对比](partitioning/_comparison.md) |
| [permissions](permissions/) | 权限管理 | [对比](permissions/_comparison.md) |
| [stored-procedures](stored-procedures/) | 存储过程 | [对比](stored-procedures/_comparison.md) |
| [temp-tables](temp-tables/) | 临时表 | [对比](temp-tables/_comparison.md) |
| [transactions](transactions/) | 事务 | [对比](transactions/_comparison.md) |
| [triggers](triggers/) | 触发器 | [对比](triggers/_comparison.md) |

## 学习建议

建议按 transactions → explain → temp-tables → partitioning → permissions → locking → stored-procedures → triggers → error-handling → dynamic-sql 的顺序学习。
事务和执行计划是生产环境必备技能，临时表和分区影响查询架构设计，
存储过程和触发器在现代架构中使用频率降低但在遗留系统中仍很重要。

## 关键差异概述

高级特性是方言差异最极端的领域。存储过程的语法在每个方言中几乎完全不同：
MySQL 的 BEGIN...END、PostgreSQL 的 PL/pgSQL、Oracle 的 PL/SQL、SQL Server 的 T-SQL 各成体系。
分析型引擎（BigQuery、ClickHouse、Hive）大多不支持或极度弱化存储过程和触发器。

事务隔离级别的实际行为差异巨大：MySQL InnoDB 默认 REPEATABLE READ 且通过间隙锁避免幻读，
PostgreSQL 默认 READ COMMITTED 使用 MVCC，Oracle 只支持 READ COMMITTED 和 SERIALIZABLE。

## 常见陷阱

- 存储过程代码几乎无法跨方言复用，迁移时通常需要完全重写
- 分析型引擎的"事务"概念与 OLTP 数据库完全不同，不要假设 ACID 保证
- EXPLAIN 输出格式差异巨大，优化经验不能直接跨方言套用
- 触发器的执行时机（BEFORE/AFTER/INSTEAD OF）各方言支持程度不同

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **存储过程** | 不支持 | 不支持 | 支持 Scripting/PROCEDURE | 各方言有独立过程式语言 |
| **触发器** | 支持 BEFORE/AFTER/INSTEAD OF | 不支持（物化视图替代） | 不支持 | 各方言支持程度不同 |
| **事务** | 完整 ACID（单写模型） | 无传统事务 | 无跨语句事务 | 完整 ACID 事务 |
| **权限** | 无 GRANT/REVOKE | 完整权限系统 | IAM 管理 | SQL GRANT/REVOKE |
| **锁机制** | 文件级锁 | 无行级锁 | 无锁概念 | 行级锁 + MVCC |
| **执行计划** | EXPLAIN QUERY PLAN（简单） | EXPLAIN + trace 日志 | EXPLAIN（侧重成本估算） | EXPLAIN (ANALYZE) 详细信息 |
| **分区** | 不支持 | 支持（PARTITION BY 表达式） | 支持（分区+聚簇） | 支持（RANGE/LIST/HASH） |
