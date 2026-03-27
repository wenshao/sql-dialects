# IBM Db2

**分类**: 传统关系型数据库（IBM）
**文件数**: 51 个 SQL 文件
**总行数**: 4539 行

## 概述与定位

IBM Db2 是关系型数据库领域的奠基者之一，其前身 System R 是 SQL 语言的发源地。Db2 涵盖从大型机（z/OS）到分布式系统（LUW: Linux/Unix/Windows）的完整产品线，长期服务于银行、保险、航空等对数据一致性和可靠性要求极高的行业。在 SQL 标准化进程中，Db2 团队深度参与了 ANSI/ISO SQL 标准的制定，许多 SQL 特性（窗口函数、CTE、MERGE）都在 Db2 中率先实现或验证。

## 历史与演进

- **1983 年**：Db2 for MVS（大型机版本）发布，成为第一款商用 SQL 关系数据库之一。
- **1993 年**：Db2 for Common Servers（后更名 Db2 LUW）发布，覆盖 Unix/Windows 平台。
- **2001 年**：Db2 8 引入 MQT（Materialized Query Table）与自动统计信息维护。
- **2006 年**：Db2 9 成为首个同时支持关系型和 XML 原生存储的数据库（pureXML）。
- **2009 年**：Db2 9.7 引入 Oracle 兼容模式，支持 PL/SQL 语法与 Oracle 数据类型映射。
- **2016 年**：Db2 11.1 引入 BLU Acceleration（内存列存加速）、自适应压缩。
- **2019 年**：Db2 11.5 引入 AI 驱动的自优化功能和 Db2 on Cloud 托管服务。
- **2023-2025 年**：持续增强 JSON 支持、REST API 接口、与 watsonx.data 的 Lakehouse 集成。

## 核心设计思路

1. **SQL 标准旗手**：Db2 是 SQL 标准最严格的追随者之一，FETCH FIRST、LATERAL、MERGE、窗口函数等均率先实现标准语法。
2. **平台分层**：z/OS 版本面向大型机事务处理，LUW 版本面向分布式系统，二者 SQL 方言高度一致但底层架构不同。
3. **自动化管理**：自动存储管理（Automatic Storage）、自动内存调优（STMM）、自动统计收集，减少 DBA 手动干预。
4. **混合负载**：BLU Acceleration 使同一张表同时支持行存 OLTP 查询和列存分析查询，无需数据搬运。

## 独特特色

| 特性 | 说明 |
|---|---|
| **FETCH FIRST n ROWS ONLY** | Db2 最早实现的标准分页语法，后被 SQL:2008 标准采纳，现已被 PostgreSQL/Oracle 等广泛支持。 |
| **Labeled Durations** | `CURRENT_DATE + 3 MONTHS` 这样的日期运算语法，比大多数数据库的 INTERVAL 写法更直观。 |
| **MQT（物化查询表）** | 物化视图的 Db2 实现，支持 REFRESH DEFERRED/IMMEDIATE，可被优化器自动路由。 |
| **FINAL TABLE** | `SELECT * FROM FINAL TABLE (INSERT INTO t VALUES (...))` 在 DML 中嵌套取回受影响行，无需 RETURNING。 |
| **pureXML** | 原生 XML 存储引擎，XML 数据以树形结构存储而非 CLOB，支持 XQuery 和 SQL/XML 混合查询。 |
| **Oracle 兼容模式** | 通过 `DB2_COMPATIBILITY_VECTOR` 参数启用，支持 PL/SQL 语法、Oracle 数据类型、NVL/DECODE 等函数。 |
| **时态查询** | 支持 BUSINESS_TIME 和 SYSTEM_TIME 双时态表，可进行 `FOR SYSTEM_TIME AS OF` 时间旅行查询。 |

## 已知不足

- **学习曲线陡峭**：z/OS 与 LUW 版本的差异、复杂的权限模型与 bufferpool 管理对新手不友好。
- **社区活跃度低**：相比 PostgreSQL/MySQL，Db2 的开源社区和第三方工具生态明显薄弱。
- **许可成本高**：企业版许可费用高昂，社区版（Community Edition）有数据容量和核心数限制。
- **JSON 支持起步晚**：原生 JSON 数据类型和 JSON_TABLE 的引入显著落后于 PostgreSQL 和 MySQL。
- **云原生步伐偏慢**：虽有 Db2 on Cloud，但在 Kubernetes 原生部署和 Serverless 模式上落后于云数仓竞品。

## 对引擎开发者的参考价值

- **FINAL TABLE 设计**：将 DML 语句当作表表达式使用的概念（"数据变更即查询"）比 RETURNING 更通用，对引擎的执行计划树设计有深刻启发。
- **SQL 标准实现参考**：Db2 的窗口函数、MERGE、LATERAL 实现几乎严格对齐 ISO SQL 标准文本，可作为标准合规性测试的基准。
- **Labeled Durations 解析**：将时间单位关键字（DAYS/MONTHS/YEARS）作为后缀运算符处理的解析器设计，比 INTERVAL 字面量更灵活。
- **BLU 列存加速**：在同一表上同时维护行存和列存副本的混合存储引擎设计，对 HTAP 引擎有重要参考。
- **pureXML 存储模型**：将层次化数据以原生树结构存储（而非序列化为文本）的做法，对 JSON 原生存储引擎的设计有借鉴意义。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/db2.sql) | ORGANIZE BY ROW/COLUMN 行列混存，IDENTITY 自增，隐式 Schema |
| [改表](../ddl/alter-table/db2.sql) | REORG 后才生效(独特)，在线重组支持 |
| [索引](../ddl/indexes/db2.sql) | MDC 多维聚集索引独有，块索引+区间索引 |
| [约束](../ddl/constraints/db2.sql) | CHECK/PK/FK/UNIQUE 完整，信息性约束+优化器利用 |
| [视图](../ddl/views/db2.sql) | MQT(物化查询表) 自动路由，REFRESH IMMEDIATE/DEFERRED |
| [序列与自增](../ddl/sequences/db2.sql) | IDENTITY+SEQUENCE 标准实现，缓存策略成熟 |
| [数据库/Schema/用户](../ddl/users-databases/db2.sql) | Instance→Database→Schema 三级架构，LBAC 标签安全 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/db2.sql) | PREPARE/EXECUTE+EXECUTE IMMEDIATE，嵌入式 SQL 传统深厚 |
| [错误处理](../advanced/error-handling/db2.sql) | DECLARE HANDLER+SQLSTATE/SQLCODE，GET DIAGNOSTICS 标准 |
| [执行计划](../advanced/explain/db2.sql) | db2expln/db2advis 工具链，EXPLAIN 表方式存储计划 |
| [锁机制](../advanced/locking/db2.sql) | CS/RR/UR/RS 四隔离级别，锁升级行→表，Currently Committed |
| [分区](../advanced/partitioning/db2.sql) | DISTRIBUTE BY HASH+ORGANIZE BY 数据分布，DPF 分布式分区 |
| [权限](../advanced/permissions/db2.sql) | LBAC 标签安全(行/列级)，SECADM 安全管理员角色 |
| [存储过程](../advanced/stored-procedures/db2.sql) | SQL PL 过程语言，COMPOUND 语句，Package 概念 |
| [临时表](../advanced/temp-tables/db2.sql) | DECLARE GLOBAL TEMPORARY TABLE 会话级，CGTT(12.1+) |
| [事务](../advanced/transactions/db2.sql) | ACID 完整，Currently Committed 避免锁等待，日志管理成熟 |
| [触发器](../advanced/triggers/db2.sql) | BEFORE/AFTER/INSTEAD OF 完整，行级+语句级 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/db2.sql) | DELETE 标准，TRUNCATE 即时释放空间 |
| [插入](../dml/insert/db2.sql) | INSERT+SELECT，LOAD 工具批量导入，NOT LOGGED INITIALLY |
| [更新](../dml/update/db2.sql) | UPDATE 标准，可更新游标 |
| [Upsert](../dml/upsert/db2.sql) | MERGE 标准实现完整(早期支持) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/db2.sql) | LISTAGG/GROUPING SETS/CUBE/ROLLUP 完整 |
| [条件函数](../functions/conditional/db2.sql) | CASE/DECODE/NULLIF/COALESCE 标准 |
| [日期函数](../functions/date-functions/db2.sql) | DATE/TIME/TIMESTAMP 严格分类，TIMESTAMPDIFF，特殊寄存器 |
| [数学函数](../functions/math-functions/db2.sql) | 完整数学函数，DECFLOAT 十进制浮点 |
| [字符串函数](../functions/string-functions/db2.sql) | || 拼接标准，REGEXP_LIKE/REPLACE(10.5+) |
| [类型转换](../functions/type-conversion/db2.sql) | CAST 标准，DECFLOAT 十进制浮点独有 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/db2.sql) | WITH 标准+递归 CTE(业界最早支持之一) |
| [全文搜索](../query/full-text-search/db2.sql) | TEXT SEARCH INDEX(Net Search Extender)，需单独安装 |
| [连接查询](../query/joins/db2.sql) | JOIN 完整，LATERAL(9.7+) 支持 |
| [分页](../query/pagination/db2.sql) | FETCH FIRST N ROWS ONLY(最早实现之一)，OFFSET(11.1+) |
| [行列转换](../query/pivot-unpivot/db2.sql) | 无原生 PIVOT，CASE+GROUP BY 模拟 |
| [集合操作](../query/set-operations/db2.sql) | UNION/INTERSECT/EXCEPT 完整(最早标准实现之一) |
| [子查询](../query/subquery/db2.sql) | 关联子查询优化好，标量子查询支持 |
| [窗口函数](../query/window-functions/db2.sql) | 早期支持(7.x)，OLAP 函数名称(RANK/DENSE_RANK/ROW_NUMBER) |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/db2.sql) | 递归 CTE 生成日期序列(CTE 先驱) |
| [去重](../scenarios/deduplication/db2.sql) | ROW_NUMBER+CTE 去重 |
| [区间检测](../scenarios/gap-detection/db2.sql) | 窗口函数+递归 CTE |
| [层级查询](../scenarios/hierarchical-query/db2.sql) | 递归 CTE(最早实现之一)，无 CONNECT BY |
| [JSON 展开](../scenarios/json-flatten/db2.sql) | JSON_TABLE(11.1+)，BSON 存储支持 |
| [迁移速查](../scenarios/migration-cheatsheet/db2.sql) | REORG 要求+LBAC 安全+嵌入式 SQL 传统是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/db2.sql) | ROW_NUMBER+FETCH FIRST，标准语法 |
| [累计求和](../scenarios/running-total/db2.sql) | SUM() OVER 标准，早期窗口函数支持 |
| [缓慢变化维](../scenarios/slowly-changing-dim/db2.sql) | MERGE 标准实现(早期支持) |
| [字符串拆分](../scenarios/string-split-to-rows/db2.sql) | XMLTABLE+递归 CTE 模拟 |
| [窗口分析](../scenarios/window-analytics/db2.sql) | 窗口函数完整(早期支持)，OLAP 函数集 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/db2.sql) | ROW 类型+ARRAY(10.5+)，结构化类型 |
| [日期时间](../types/datetime/db2.sql) | DATE/TIME/TIMESTAMP 严格分离，TIMESTAMP(12) 皮秒精度 |
| [JSON](../types/json/db2.sql) | JSON_TABLE/JSON_VALUE(11.1+)，BSON 存储 |
| [数值类型](../types/numeric/db2.sql) | DECFLOAT 十进制浮点独有，INTEGER/DECIMAL 标准 |
| [字符串类型](../types/string/db2.sql) | VARCHAR/CLOB，CCSID 字符集管理 |
