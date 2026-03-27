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

| 模块 | 链接 |
|---|---|
| 建表 | [mysql.sql](../ddl/create-table/mysql.sql) |
| 改表 | [mysql.sql](../ddl/alter-table/mysql.sql) |
| 索引 | [mysql.sql](../ddl/indexes/mysql.sql) |
| 约束 | [mysql.sql](../ddl/constraints/mysql.sql) |
| 视图 | [mysql.sql](../ddl/views/mysql.sql) |
| 序列与自增 | [mysql.sql](../ddl/sequences/mysql.sql) |
| 数据库/Schema/用户 | [mysql.sql](../ddl/users-databases/mysql.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [mysql.sql](../advanced/dynamic-sql/mysql.sql) |
| 错误处理 | [mysql.sql](../advanced/error-handling/mysql.sql) |
| 执行计划 | [mysql.sql](../advanced/explain/mysql.sql) |
| 锁机制 | [mysql.sql](../advanced/locking/mysql.sql) |
| 分区 | [mysql.sql](../advanced/partitioning/mysql.sql) |
| 权限 | [mysql.sql](../advanced/permissions/mysql.sql) |
| 存储过程 | [mysql.sql](../advanced/stored-procedures/mysql.sql) |
| 临时表 | [mysql.sql](../advanced/temp-tables/mysql.sql) |
| 事务 | [mysql.sql](../advanced/transactions/mysql.sql) |
| 触发器 | [mysql.sql](../advanced/triggers/mysql.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [mysql.sql](../dml/delete/mysql.sql) |
| 插入 | [mysql.sql](../dml/insert/mysql.sql) |
| 更新 | [mysql.sql](../dml/update/mysql.sql) |
| Upsert | [mysql.sql](../dml/upsert/mysql.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [mysql.sql](../functions/aggregate/mysql.sql) |
| 条件函数 | [mysql.sql](../functions/conditional/mysql.sql) |
| 日期函数 | [mysql.sql](../functions/date-functions/mysql.sql) |
| 数学函数 | [mysql.sql](../functions/math-functions/mysql.sql) |
| 字符串函数 | [mysql.sql](../functions/string-functions/mysql.sql) |
| 类型转换 | [mysql.sql](../functions/type-conversion/mysql.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [mysql.sql](../query/cte/mysql.sql) |
| 全文搜索 | [mysql.sql](../query/full-text-search/mysql.sql) |
| 连接查询 | [mysql.sql](../query/joins/mysql.sql) |
| 分页 | [mysql.sql](../query/pagination/mysql.sql) |
| 行列转换 | [mysql.sql](../query/pivot-unpivot/mysql.sql) |
| 集合操作 | [mysql.sql](../query/set-operations/mysql.sql) |
| 子查询 | [mysql.sql](../query/subquery/mysql.sql) |
| 窗口函数 | [mysql.sql](../query/window-functions/mysql.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [mysql.sql](../scenarios/date-series-fill/mysql.sql) |
| 去重 | [mysql.sql](../scenarios/deduplication/mysql.sql) |
| 区间检测 | [mysql.sql](../scenarios/gap-detection/mysql.sql) |
| 层级查询 | [mysql.sql](../scenarios/hierarchical-query/mysql.sql) |
| JSON 展开 | [mysql.sql](../scenarios/json-flatten/mysql.sql) |
| 迁移速查 | [mysql.sql](../scenarios/migration-cheatsheet/mysql.sql) |
| TopN 查询 | [mysql.sql](../scenarios/ranking-top-n/mysql.sql) |
| 累计求和 | [mysql.sql](../scenarios/running-total/mysql.sql) |
| 缓慢变化维 | [mysql.sql](../scenarios/slowly-changing-dim/mysql.sql) |
| 字符串拆分 | [mysql.sql](../scenarios/string-split-to-rows/mysql.sql) |
| 窗口分析 | [mysql.sql](../scenarios/window-analytics/mysql.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [mysql.sql](../types/array-map-struct/mysql.sql) |
| 日期时间 | [mysql.sql](../types/datetime/mysql.sql) |
| JSON | [mysql.sql](../types/json/mysql.sql) |
| 数值类型 | [mysql.sql](../types/numeric/mysql.sql) |
| 字符串类型 | [mysql.sql](../types/string/mysql.sql) |
