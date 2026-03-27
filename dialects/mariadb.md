# MariaDB

**分类**: MySQL 兼容分支
**文件数**: 51 个 SQL 文件
**总行数**: 4792 行

## 概述与定位

MariaDB 是 MySQL 的社区驱动分叉，由 MySQL 原始创始人 Michael "Monty" Widenius 于 2009 年创建。它定位为 MySQL 的"增强型替代品"（drop-in replacement），在保持协议级和 SQL 级兼容的前提下，独立推进许多 MySQL 未能实现或推迟实现的特性。MariaDB 既适用于 OLTP 场景，也通过 ColumnStore 存储引擎涵盖分析型负载，形成了"一个内核、多引擎"的混合定位。

## 历史与演进

- **2009 年**：Monty 在 Oracle 收购 Sun/MySQL 之前启动 MariaDB 分叉，初始代码基于 MySQL 5.1。
- **2012 年**：MariaDB 5.5 成为第一个被多数 Linux 发行版默认采用的版本（替换 MySQL）。
- **2013 年**：10.0 引入多源复制（multi-source replication）与并行复制，开始与 MySQL 版本号脱钩。
- **2017 年**：10.2 支持窗口函数与 CTE，比 MySQL 8.0 更早交付。
- **2018 年**：10.3 引入 SEQUENCE 引擎、系统版本表（System-Versioned Tables）与 INTERSECT/EXCEPT。
- **2021 年**：10.5+ 引入 RETURNING 子句、INVISIBLE 列、IF NOT EXISTS 对更多语句的支持。
- **2023 年**：10.11 成为长期支持版本，引入 WITHOUT OVERLAPS 约束、UUID v7 函数。
- **2024-2025 年**：11.x 系列持续推进原子 DDL、向量索引预研、增强 JSON 表函数。

## 核心设计思路

1. **引擎可插拔**：InnoDB（默认）、Aria（崩溃安全 MyISAM 替代）、Spider（分片联邦）、ColumnStore（列存分析）、SEQUENCE（虚拟序列引擎）等多引擎共存。
2. **SQL 标准优先**：在 MySQL 滞后时率先实现标准语法——窗口函数、CTE、INTERSECT/EXCEPT、NATURAL FULL OUTER JOIN。
3. **向后兼容**：协议、复制格式与 MySQL 保持最大程度兼容，方便用户无缝切换。
4. **社区开放**：所有新特性默认贡献到开源主干；不存在仅商业版可用的功能。

## 独特特色

| 特性 | 说明 |
|---|---|
| **SEQUENCE 引擎（10.3+）** | `SELECT * FROM seq_1_to_100` 即可生成序列，无需建表，用于日期填充、批量测试极为方便。 |
| **系统版本表** | `WITH SYSTEM VERSIONING` 使表自动记录所有行的历史版本，支持 `FOR SYSTEM_TIME AS OF` 时间旅行查询。 |
| **RETURNING** | INSERT/DELETE/REPLACE 语句可附加 `RETURNING` 子句，一步返回受影响行，减少额外 SELECT。 |
| **INVISIBLE 列** | 列可标记为 `INVISIBLE`，`SELECT *` 不返回，但可显式引用，适合审计字段与内部字段。 |
| **WITHOUT OVERLAPS** | 主键/唯一键中使用 `WITHOUT OVERLAPS` 即可在数据库层面防止时间区间重叠，原生实现 temporal 约束。 |
| **Oracle 兼容模式** | `SET sql_mode='ORACLE'` 后可直接执行 PL/SQL 风格代码，包括 `%ROWTYPE`、包变量、异常处理。 |
| **多源复制** | 一个从库同时从多个主库复制，适合数据汇聚场景。 |

## 已知不足

- **生态分裂**：与 MySQL 的差异逐版本扩大，部分 ORM/驱动（如特定版本的 MySQL Connector）可能出现兼容问题。
- **Group Replication 缺失**：MariaDB 使用 Galera Cluster 实现多主同步复制，但与 MySQL 的 Group Replication/InnoDB Cluster 不兼容。
- **文档与社区体量**：相比 MySQL/PostgreSQL，中文技术社区资料相对较少。
- **ColumnStore 成熟度**：列存引擎功能在快速迭代中，与专业 OLAP 引擎相比仍有差距。
- **JSON 函数滞后**：部分 JSON 路径操作（如 JSON_TABLE）引入晚于 MySQL 8.0。

## 对引擎开发者的参考价值

- **SEQUENCE 引擎的实现**：通过虚拟存储引擎生成序列值，是"引擎即函数"设计的优秀范例，值得嵌入式引擎参考。
- **系统版本表架构**：在存储引擎层透明维护行版本，对实现时间旅行查询（temporal query）的引擎有直接借鉴意义。
- **WITHOUT OVERLAPS 约束**：将区间不重叠校验下沉到索引层，展示了约束检查与索引结构耦合的设计路径。
- **Oracle 兼容模式**：通过 sql_mode 切换语法解析器行为，是多方言兼容的可行实现方案。
- **RETURNING 子句实现**：在 DML 执行路径中插入结果集返回节点，对减少客户端往返有参考价值。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/mariadb.sql) | MySQL 分叉，兼容 ENGINE 架构，增加 SEQUENCE(10.3+)/虚拟列 |
| [改表](../ddl/alter-table/mariadb.sql) | Online DDL 改进(INSTANT ADD COLUMN)，ALGORITHM 指定 |
| [索引](../ddl/indexes/mariadb.sql) | InnoDB/Aria 引擎索引，与 MySQL 高度兼容 |
| [约束](../ddl/constraints/mariadb.sql) | CHECK 约束真正执行(10.2+，早于 MySQL 8.0.16) |
| [视图](../ddl/views/mariadb.sql) | 与 MySQL 兼容，无物化视图 |
| [序列与自增](../ddl/sequences/mariadb.sql) | SEQUENCE 对象(10.3+，MySQL 无此功能)，AUTO_INCREMENT 兼容 |
| [数据库/Schema/用户](../ddl/users-databases/mariadb.sql) | user@host 模型(同 MySQL)，角色(10.0.5+) |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/mariadb.sql) | PREPARE/EXECUTE(同 MySQL)，EXECUTE IMMEDIATE(10.2+)简化 |
| [错误处理](../advanced/error-handling/mariadb.sql) | DECLARE HANDLER(同 MySQL)，SIGNAL/RESIGNAL |
| [执行计划](../advanced/explain/mariadb.sql) | EXPLAIN ANALYZE(10.1+)，EXPLAIN FORMAT=JSON |
| [锁机制](../advanced/locking/mariadb.sql) | InnoDB 行锁+间隙锁(同 MySQL)，Aria 引擎崩溃安全 |
| [分区](../advanced/partitioning/mariadb.sql) | RANGE/LIST/HASH/KEY 分区(同 MySQL)，SYSTEM_TIME 分区独有 |
| [权限](../advanced/permissions/mariadb.sql) | user@host 模型，角色(10.0.5+，早于 MySQL 8.0) |
| [存储过程](../advanced/stored-procedures/mariadb.sql) | PL/SQL 兼容模式(10.3+ sql_mode=ORACLE)，独特卖点 |
| [临时表](../advanced/temp-tables/mariadb.sql) | CREATE TEMPORARY TABLE(同 MySQL)，Aria 引擎临时表 |
| [事务](../advanced/transactions/mariadb.sql) | InnoDB MVCC(同 MySQL)，默认 RR，支持 XA 事务 |
| [触发器](../advanced/triggers/mariadb.sql) | FOR EACH ROW(同 MySQL)，无 INSTEAD OF/语句级 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/mariadb.sql) | DELETE+LIMIT(同 MySQL)，TRUNCATE 不可回滚 |
| [插入](../dml/insert/mariadb.sql) | INSERT...SET/RETURNING(10.5+)，LOAD DATA 批量 |
| [更新](../dml/update/mariadb.sql) | 多表 UPDATE JOIN(同 MySQL)，UPDATE...RETURNING(10.5+) |
| [Upsert](../dml/upsert/mariadb.sql) | ON DUPLICATE KEY UPDATE(同 MySQL)，INSERT...RETURNING |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/mariadb.sql) | GROUP_CONCAT(同 MySQL)，无 GROUPING SETS |
| [条件函数](../functions/conditional/mariadb.sql) | IF()/CASE(同 MySQL)，DECODE(Oracle 兼容模式) |
| [日期函数](../functions/date-functions/mariadb.sql) | DATE_FORMAT(同 MySQL)，与 MySQL 高度兼容 |
| [数学函数](../functions/math-functions/mariadb.sql) | 与 MySQL 兼容，完整数学函数 |
| [字符串函数](../functions/string-functions/mariadb.sql) | CONCAT(同 MySQL)，|| 在 sql_mode=ORACLE 时为拼接 |
| [类型转换](../functions/type-conversion/mariadb.sql) | CAST/CONVERT(同 MySQL)，隐式转换行为与 MySQL 一致 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/mariadb.sql) | 递归 CTE(10.2+，早于 MySQL 8.0)，WITH 标准语法 |
| [全文搜索](../query/full-text-search/mariadb.sql) | InnoDB/Mroonga FULLTEXT，Mroonga 引擎 CJK 分词更强 |
| [连接查询](../query/joins/mariadb.sql) | 无 FULL OUTER JOIN(同 MySQL)，标准 JOIN 完整 |
| [分页](../query/pagination/mariadb.sql) | LIMIT/OFFSET(同 MySQL)，LIMIT...ROWS EXAMINED 独有 |
| [行列转换](../query/pivot-unpivot/mariadb.sql) | 无原生 PIVOT，用 CASE+GROUP BY(同 MySQL) |
| [集合操作](../query/set-operations/mariadb.sql) | INTERSECT/EXCEPT(10.3+，早于 MySQL 8.0.31) |
| [子查询](../query/subquery/mariadb.sql) | 优化器改进优于早期 MySQL，semi-join 优化 |
| [窗口函数](../query/window-functions/mariadb.sql) | 10.2+ 支持（早于 MySQL 8.0），CUME_DIST/PERCENT_RANK |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/mariadb.sql) | seq_1_to_N 序列引擎独有，无需递归 CTE |
| [去重](../scenarios/deduplication/mariadb.sql) | ROW_NUMBER+CTE 或 DELETE+JOIN |
| [区间检测](../scenarios/gap-detection/mariadb.sql) | 窗口函数(10.2+)+seq 序列引擎辅助 |
| [层级查询](../scenarios/hierarchical-query/mariadb.sql) | 递归 CTE(10.2+)，无 CONNECT BY |
| [JSON 展开](../scenarios/json-flatten/mariadb.sql) | JSON_TABLE(10.6+)，JSON_EXTRACT 路径查询 |
| [迁移速查](../scenarios/migration-cheatsheet/mariadb.sql) | 与 MySQL 高度兼容但 10.6+ 出现不可忽略差异 |
| [TopN 查询](../scenarios/ranking-top-n/mariadb.sql) | ROW_NUMBER(10.2+)+CTE，LIMIT 直接 TopN |
| [累计求和](../scenarios/running-total/mariadb.sql) | SUM() OVER(10.2+)，窗口函数早于 MySQL |
| [缓慢变化维](../scenarios/slowly-changing-dim/mariadb.sql) | 无 MERGE 语句，ON DUPLICATE KEY UPDATE 替代 |
| [字符串拆分](../scenarios/string-split-to-rows/mariadb.sql) | 无原生拆分，JSON_TABLE(10.6+) 或递归 CTE 模拟 |
| [窗口分析](../scenarios/window-analytics/mariadb.sql) | 10.2+ 窗口函数，早于 MySQL，帧子句完整 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/mariadb.sql) | 无 ARRAY/STRUCT，JSON 替代(同 MySQL) |
| [日期时间](../types/datetime/mariadb.sql) | DATETIME vs TIMESTAMP(同 MySQL)，微秒精度 |
| [JSON](../types/json/mariadb.sql) | JSON 别名 LONGTEXT(非二进制)，JSON_TABLE(10.6+)，不如 MySQL JSONB |
| [数值类型](../types/numeric/mariadb.sql) | 与 MySQL 兼容，DECIMAL 精确，UNSIGNED 保留 |
| [字符串类型](../types/string/mariadb.sql) | utf8=utf8mb3(同 MySQL)，utf8mb4 推荐 |
