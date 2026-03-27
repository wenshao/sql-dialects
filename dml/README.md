# DML -- 数据操作

数据操作语言（Data Manipulation Language），包含数据的插入、更新、删除、合并（UPSERT）等操作。

## 模块列表

| 模块 | 说明 | 对比表 |
|---|---|---|
| [delete](delete/) | 删除语法对比 | [对比](delete/_comparison.md) |
| [insert](insert/) | 插入语法对比 | [对比](insert/_comparison.md) |
| [update](update/) | 更新语法对比 | [对比](update/_comparison.md) |
| [upsert](upsert/) | 插入或更新（UPSERT/MERGE） | [对比](upsert/_comparison.md) |

## 学习建议

建议按 insert → update → delete → upsert 的顺序学习。INSERT 是基础，UPDATE/DELETE 需要理解 WHERE 条件的重要性，
UPSERT 是最复杂的 DML 操作，各方言语法差异也最大，建议最后学习。

## 关键差异概述

DML 的核心差异在于：批量插入方式（MySQL 的多值 INSERT vs Oracle 12c 之前只能 INSERT ALL）、
多表关联更新/删除语法（MySQL 用 JOIN 直接写在 UPDATE/DELETE 中，PostgreSQL 用 FROM 子句，Oracle 用子查询），
以及 UPSERT 的实现路径（MySQL ON DUPLICATE KEY UPDATE vs PostgreSQL ON CONFLICT vs SQL 标准 MERGE）。

分析型引擎通常对 DML 有严格限制：ClickHouse 的 UPDATE/DELETE 是异步的 mutation 操作而非即时生效，
Hive 需要开启 ACID 事务表才支持 UPDATE/DELETE，BigQuery 的 DML 有配额限制。

## 常见陷阱

- 忘记 WHERE 子句的 UPDATE/DELETE 会影响全表，生产环境务必先用 SELECT 验证
- MySQL 的 `INSERT ... ON DUPLICATE KEY UPDATE` 在并发下可能产生死锁
- 分析型引擎的 DML 操作通常不是真正的行级修改，而是重写整个分区或段
- Oracle 12c 之前不支持多行 VALUES 语法，必须用 INSERT ALL 或 UNION ALL 子查询

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **INSERT** | 标准 INSERT，单写模型 | INSERT-only 哲学，批量写入高效 | 流式 INSERT 和 Load Job 两种模式，有 DML 配额 | 标准 INSERT，行级锁并发 |
| **UPDATE/DELETE** | 标准即时操作 | 异步 mutation，非即时生效，代价高 | 标准语法但有 DML 配额限制（每表每天 1500 次） | 标准即时操作 |
| **UPSERT** | ON CONFLICT（3.24.0+）/ REPLACE INTO | 无原生 UPSERT，ReplacingMergeTree 最终去重 | MERGE 语法 | MySQL ON DUPLICATE KEY / PG ON CONFLICT / MERGE |
| **事务 DML** | ACID 事务内 DML | 无传统事务，INSERT 批次原子性 | 无跨语句事务 | 完整事务 DML |
| **并发限制** | 文件级单写 | 多节点并发 INSERT，mutation 串行 | DML 配额限制并发 | 行级锁高并发 |
