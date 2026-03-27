# MySQL

**分类**: 传统关系型数据库
**文件数**: 51 个 SQL 文件
**总行数**: 8956 行

## 概述与定位

MySQL 是全球最流行的开源关系型数据库，Web 应用的事实标准后端。从 LAMP 时代起，它就占据了互联网数据库的统治地位。MySQL 的核心竞争力不是功能最全，而是**上手最快、生态最广、读性能极强**。绝大多数 Web 开发者的第一个数据库就是 MySQL，这决定了它的设计哲学：宁可牺牲严格性，也要降低入门门槛。

在定位光谱上，MySQL 处于 SQLite（嵌入式）和 Oracle（企业级）之间：它是第一个让"免费 + 足够好"成为现实的服务端数据库。即使在 PostgreSQL 近年强势崛起后，MySQL 仍然在高并发 OLTP（电商、社交、游戏）场景中保持优势，尤其在中国互联网公司中占有率压倒性领先。

## 历史与演进

- **1995**: Monty Widenius 和 David Axmark 发布 MySQL 1.0，名字来源于 Monty 的女儿 My
- **2000**: 采用 GPL 双许可模式，奠定开源商业化先河
- **2005**: MySQL 5.0 引入存储过程、触发器、视图，开始追赶企业级功能
- **2008**: Sun Microsystems 以 10 亿美元收购 MySQL AB
- **2010**: Oracle 收购 Sun，社区恐慌，Monty 分叉创建 MariaDB
- **2013**: MySQL 5.6 引入 GTID 复制、全文索引（InnoDB）、EXPLAIN FORMAT=JSON
- **2016**: MySQL 5.7 引入 JSON 类型、Generated Columns、Group Replication
- **2018**: MySQL 8.0 — 里程碑版本：CTE、窗口函数、原子 DDL、角色、降序索引、不可见索引
- **2023**: MySQL 8.1+ 进入 Innovation Release 模式，与 LTS 并行
- **2024-2025**: MySQL 9.x 继续迭代，VECTOR 类型实验性支持

MySQL 的版本历史有一个显著特点：**功能追赶周期长**。窗口函数（SQL:2003 标准）直到 2018 年 8.0 才加入，比 PostgreSQL 晚了 7 年，比 Oracle 晚了 15 年。

## 核心设计思路

**可插拔存储引擎架构**是 MySQL 最独特的设计决策。SQL 解析层与存储层彻底分离，通过 Handler API 对接不同引擎：
- **InnoDB**（默认）：事务、行锁、MVCC、崩溃恢复 — 几乎等于"MySQL 本身"
- **MyISAM**（遗留）：表锁、无事务、全文索引先驱 — 2024 年已无正当使用理由
- **MEMORY**：纯内存哈希/B-tree，临时结果集处理
- **NDB Cluster**：分布式存储，MySQL Cluster 专用

这套架构在理论上很优雅，但实际上 InnoDB 已经"赢者通吃"。8.0 后系统表也迁入 InnoDB，MyISAM 成为纯遗留。

**宽松类型转换**：MySQL 默认允许隐式转换（字符串→数字、超范围截断），这在严格模式关闭时会静默丢失数据。这是"易用性优先"的典型体现，也是无数线上 Bug 的根源。

**user@host 权限模型**：权限绑定到 `'user'@'host'` 对而非单独用户，同一用户名从不同主机连接可以有不同权限。这在多数据中心场景有用，但概念上比其他数据库复杂。

## 独特特色（其他引擎没有的）

- **`ENGINE = xxx` 子句**：建表时指定存储引擎，全行业独此一家
- **`ON UPDATE CURRENT_TIMESTAMP`**：列级自动更新时间戳，声明式解决"最后修改时间"需求
- **`AUTO_INCREMENT`**：最简单的自增主键实现，无需单独的 SEQUENCE 对象
- **`GROUP_CONCAT()`**：行转列聚合函数，比标准 `LISTAGG` 更早出现，深入人心
- **`REPLACE INTO`**：先删后插的 UPSERT 变体（会触发 DELETE 触发器，慎用）
- **`INSERT ... SET col=val`**：用赋值语法代替 VALUES 列表，可读性更好
- **`INSERT ... ON DUPLICATE KEY UPDATE`**：真正的 UPSERT，比 `REPLACE` 更安全
- **`LAST_INSERT_ID()`**：连接级别的自增 ID 获取，无竞态
- **`STRAIGHT_JOIN`**：强制优化器按书写顺序连接，调优利器
- **多值 INSERT（早期支持）**：`INSERT INTO t VALUES (1,'a'), (2,'b')` — MySQL 很早就支持批量插入

## 已知的设计不足与历史包袱

- **`utf8` 不是 UTF-8**：MySQL 的 `utf8` 字符集只支持 3 字节（BMP），存不了 emoji。必须用 `utf8mb4`。这是 MySQL 历史上最臭名昭著的设计失误，至今仍在困扰迁移项目
- **CHECK 约束是摆设（8.0.16 前）**：语法接受但不执行，静默忽略。直到 8.0.16 才真正生效
- **不支持 FULL OUTER JOIN**：至今不支持，需要 `UNION` 模拟
- **DDL 隐式提交**：`CREATE TABLE`、`ALTER TABLE` 会自动提交当前事务，无法回滚 DDL
- **`ONLY_FULL_GROUP_BY` 曾默认关闭**：允许 SELECT 非聚合列不出现在 GROUP BY 中，结果不确定。5.7+ 才默认开启
- **不支持物化视图**：需要手工维护或用第三方方案
- **存储过程弱于 PL/SQL**：无 Package、无自治事务、调试困难
- **MERGE 语句不支持**：标准 SQL MERGE 在 MySQL 中用 `INSERT ... ON DUPLICATE KEY UPDATE` 替代
- **隐式类型转换**：`WHERE varchar_col = 123` 会导致全表扫描（索引失效），这是最常见的性能陷阱
- **Online DDL 限制**：虽然 8.0 改进很大，但部分 ALTER 仍需要拷贝表

## 兼容生态

MySQL 协议和 SQL 方言是数据库行业被兼容最多的目标：
- **TiDB**（PingCAP）：分布式 NewSQL，MySQL 协议兼容，目标替代分库分表
- **OceanBase**（蚂蚁）：MySQL 模式 + Oracle 模式双兼容
- **PolarDB**（阿里云）：MySQL 兼容的云原生数据库，计算存储分离
- **TDSQL**（腾讯）：金融级分布式 MySQL 兼容数据库
- **StarRocks / Doris**：OLAP 引擎，使用 MySQL 协议作为查询入口
- **MariaDB**：直接分叉，高度兼容但已在 10.6+ 出现不可忽略的差异
- **Vitess**（YouTube/PlanetScale）：MySQL 分片中间件

这个生态说明一个事实：**兼容 MySQL 是新数据库获取用户的最快路径**。

## 对引擎开发者的参考价值

- **写入路径**：InnoDB 的 Change Buffer（延迟二级索引更新）、redo log（WAL）+ undo log（MVCC 回滚）的双日志架构是教科书级设计
- **MVCC 实现**：基于 Read View 的快照读算法 — 每个事务维护一个活跃事务 ID 列表，判断行版本可见性。与 PostgreSQL 的元组版本化形成鲜明对比
- **间隙锁（Gap Lock）**：InnoDB 在 RR 隔离级别下使用间隙锁防止幻读，这是一个独特的并发控制策略，带来了特有的死锁模式
- **Buffer Pool 管理**：LRU 变体（young/old 分区）防止全表扫描冲刷热数据
- **Binlog 复制**：基于逻辑日志的主从复制架构，Statement/Row/Mixed 三种格式各有取舍
- **索引组织表**：InnoDB 的聚簇索引结构（数据按主键物理排序）与堆表组织（PostgreSQL）的对比，是存储引擎设计的核心抉择

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/mysql.sql) | ENGINE 可插拔架构，AUTO_INCREMENT 自增，utf8≠UTF-8 教训 |
| [改表](../ddl/alter-table/mysql.sql) | Online DDL (INSTANT/INPLACE/COPY)，pt-osc/gh-ost 生态 |
| [索引](../ddl/indexes/mysql.sql) | InnoDB 聚集索引+回表，8.0 函数索引/不可见索引 |
| [约束](../ddl/constraints/mysql.sql) | CHECK 约束 8.0.16 才执行（之前静默忽略），外键影响性能 |
| [视图](../ddl/views/mysql.sql) | MERGE/TEMPTABLE 算法，无物化视图 |
| [序列与自增](../ddl/sequences/mysql.sql) | AUTO_INCREMENT lock_mode 三种模式，无 SEQUENCE 对象 |
| [数据库/Schema/用户](../ddl/users-databases/mysql.sql) | user@host 独特权限模型 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/mysql.sql) | PREPARE/EXECUTE，存储过程内可用 |
| [错误处理](../advanced/error-handling/mysql.sql) | DECLARE HANDLER (CONTINUE/EXIT)，弱于 PL/SQL 异常 |
| [执行计划](../advanced/explain/mysql.sql) | EXPLAIN ANALYZE (8.0.18+)，JSON/TREE 格式 |
| [锁机制](../advanced/locking/mysql.sql) | InnoDB 行锁+间隙锁+Next-Key Lock，RR 默认有间隙锁 |
| [分区](../advanced/partitioning/mysql.sql) | 分区键必须在主键中（最大限制），RANGE/LIST/HASH |
| [权限](../advanced/permissions/mysql.sql) | user@host 模型，8.0 角色，Partial Revokes |
| [存储过程](../advanced/stored-procedures/mysql.sql) | DELIMITER 尴尬，无 Package/匿名块/BULK COLLECT |
| [临时表](../advanced/temp-tables/mysql.sql) | CREATE TEMPORARY TABLE，MEMORY/InnoDB 引擎 |
| [事务](../advanced/transactions/mysql.sql) | InnoDB MVCC (Read View)，默认 RR（历史原因），DDL 隐式提交 |
| [触发器](../advanced/triggers/mysql.sql) | 只有行级 FOR EACH ROW，无 INSTEAD OF/DDL 触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/mysql.sql) | DELETE+LIMIT（独有），TRUNCATE 不可回滚 |
| [插入](../dml/insert/mysql.sql) | INSERT...SET 独有语法，LOAD DATA 批量，multi-row VALUES |
| [更新](../dml/update/mysql.sql) | 多表 UPDATE JOIN 语法，SET 左到右求值 |
| [Upsert](../dml/upsert/mysql.sql) | ON DUPLICATE KEY UPDATE 推荐，REPLACE INTO 有隐患 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/mysql.sql) | GROUP_CONCAT 默认1024截断，无 GROUPING SETS/FILTER |
| [条件函数](../functions/conditional/mysql.sql) | IF() 函数，\|\| 是逻辑 OR 不是拼接 |
| [日期函数](../functions/date-functions/mysql.sql) | DATE_FORMAT %格式，NOW()=语句时间 |
| [数学函数](../functions/math-functions/mysql.sql) | 完整，UNSIGNED 废弃中 |
| [字符串函数](../functions/string-functions/mysql.sql) | CONCAT NULL 传播，\|\| 不是拼接（最大方言差异之一） |
| [类型转换](../functions/type-conversion/mysql.sql) | 隐式转换极宽松，可能导致索引失效 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/mysql.sql) | 8.0+，早期总是物化，递归只支持 UNION ALL |
| [全文搜索](../query/full-text-search/mysql.sql) | InnoDB FULLTEXT (5.6+)，ngram 中文分词 |
| [连接查询](../query/joins/mysql.sql) | 无 FULL OUTER JOIN，Hash Join (8.0.18+) |
| [分页](../query/pagination/mysql.sql) | LIMIT/OFFSET，深分页 O(offset) 问题 |
| [行列转换](../query/pivot-unpivot/mysql.sql) | 无原生 PIVOT，用 CASE+GROUP BY |
| [集合操作](../query/set-operations/mysql.sql) | INTERSECT/EXCEPT 8.0.31 才加入 |
| [子查询](../query/subquery/mysql.sql) | 5.x 性能噩梦已修复，8.0 semijoin 优化 |
| [窗口函数](../query/window-functions/mysql.sql) | 8.0+ 才支持（晚了15年），无 QUALIFY |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/mysql.sql) | 无 generate_series，需递归 CTE 或辅助表 |
| [去重](../scenarios/deduplication/mysql.sql) | DELETE+JOIN 或 ROW_NUMBER(8.0+) |
| [区间检测](../scenarios/gap-detection/mysql.sql) | LAG/LEAD(8.0+)，5.x 需变量模拟 |
| [层级查询](../scenarios/hierarchical-query/mysql.sql) | 递归 CTE(8.0+)，无 CONNECT BY |
| [JSON 展开](../scenarios/json-flatten/mysql.sql) | JSON_TABLE(8.0.4+) 功能完整 |
| [迁移速查](../scenarios/migration-cheatsheet/mysql.sql) | 重点关注隐式转换、utf8mb4、GROUP BY 语义 |
| [TopN](../scenarios/ranking-top-n/mysql.sql) | ROW_NUMBER(8.0+)，5.x 用变量模拟 |
| [累计求和](../scenarios/running-total/mysql.sql) | SUM() OVER(8.0+)，5.x 靠用户变量 |
| [缓慢变化维](../scenarios/slowly-changing-dim/mysql.sql) | 无 MERGE，用 ON DUPLICATE KEY UPDATE |
| [字符串拆分](../scenarios/string-split-to-rows/mysql.sql) | 无原生拆分，递归 CTE+SUBSTRING_INDEX |
| [窗口分析](../scenarios/window-analytics/mysql.sql) | 8.0 全窗口函数，frame 子句完整 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/mysql.sql) | 无 ARRAY/MAP/STRUCT，用 JSON 替代 |
| [日期时间](../types/datetime/mysql.sql) | DATETIME vs TIMESTAMP（2038问题），微秒精度 |
| [JSON](../types/json/mysql.sql) | 二进制存储，多值索引(8.0.17+)，partial update |
| [数值类型](../types/numeric/mysql.sql) | UNSIGNED 废弃趋势，DECIMAL BCD 精确 |
| [字符串类型](../types/string/mysql.sql) | utf8≠UTF-8（历史最大坑），TEXT 有诸多限制 |
