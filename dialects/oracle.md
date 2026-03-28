# Oracle

**分类**: 传统关系型数据库
**文件数**: 51 个 SQL 文件
**总行数**: 8199 行

## 概述与定位

Oracle Database 是企业级关系型数据库的标杆，也是 SQL 语言实际演进的最大推动力。在 SQL 标准委员会讨论一个特性之前，Oracle 往往已经实现并在生产中验证了多年。窗口函数、物化视图、Flashback、多租户 — 这些后来被标准化或被其他数据库借鉴的功能，几乎都是 Oracle 先行。

Oracle 的定位极为明确：**为最苛刻的企业级工作负载提供最完善的功能集**。它的客户是银行、电信、政府 — 这些场景对数据一致性、高可用、安全合规的要求远超一般 Web 应用。Oracle 的许可费极高（按 CPU 核心计价），但对这些客户而言，数据库不可用一小时的损失远超许可费。

## 历史与演进

- **1977**: Larry Ellison、Bob Miner、Ed Oates 创立 Software Development Laboratories（后更名 Oracle）
- **1979**: Oracle V2 发布 — 第一个商业 SQL 关系型数据库（V1 从未发布）
- **1983**: Oracle V3 用 C 语言重写，实现跨平台可移植
- **1984**: Oracle V4 引入读一致性（Read Consistency）— 这是 Oracle MVCC 的起点
- **1988**: Oracle V6 引入行锁和 PL/SQL — 奠定了 Oracle 生态的两块基石
- **1992**: Oracle 7 引入存储过程、触发器、共享连接池
- **1999**: Oracle 8i — "i"代表 Internet，引入 Java VM、物化视图
- **2001**: Oracle 9i — 引入 Oracle RAC（Real Application Clusters）
- **2003**: Oracle 10g — "g"代表 Grid，引入 ASM（自动存储管理）、Flashback Database
- **2007**: Oracle 11g — 窗口函数增强、Result Cache、Real Application Testing
- **2013**: Oracle 12c — "c"代表 Cloud，引入多租户架构（CDB/PDB）、自增列（IDENTITY）
- **2018**: Oracle 18c/19c — 自治数据库概念，19c 成为长期支持版
- **2024**: Oracle 23ai — "ai"代表 AI，引入 AI Vector Search、JSON Relational Duality

Oracle 的版本命名史就是一部 IT 潮流史：Internet → Grid → Cloud → AI。

## 核心设计思路

**功能完备主义**：Oracle 的设计哲学是"如果某个功能有用，就在内核中实现它"。不依赖第三方扩展，不留给用户自己解决。这导致 Oracle 的功能集远超其他数据库，但也带来了极高的系统复杂度。

**PL/SQL 生态**：PL/SQL 不仅是一门存储过程语言，它是一个完整的应用开发平台。Package（包）将过程、函数、类型、常量封装为模块；自治事务允许在事务内部开启独立事务（审计日志的关键需求）；批量绑定（FORALL/BULK COLLECT）解决了逐行处理的性能问题。

**Undo-based MVCC**：Oracle 不像 PostgreSQL 那样在表中保留旧版本元组，而是将旧数据写入 Undo 表空间。读操作需要旧版本时，从 Undo 中重建。优点是表不会膨胀（无需 VACUUM），缺点是 Undo 空间耗尽时会报 `ORA-01555: snapshot too old`。

**Shared Pool 缓存**：SQL 语句解析结果缓存在共享池中，相同 SQL 文本可以复用执行计划。这是 Oracle 推荐使用绑定变量的根本原因 — 不同字面量导致硬解析，浪费 CPU 和共享池空间。

## 独特特色（其他引擎没有的）

- **`'' = NULL`**：Oracle 中空字符串等于 NULL，这与 SQL 标准和所有其他数据库都不同。这个 45 年的历史决定至今无法更改，因为无数应用依赖此行为
- **`CONNECT BY`**：层级查询的原创语法（`START WITH ... CONNECT BY PRIOR`），比标准 CTE 递归更早、对某些场景更简洁
- **PL/SQL Package**：将相关过程、函数、类型打包为一个逻辑单元，支持 public/private 可见性，是大型数据库应用架构的基石
- **自治事务（`PRAGMA AUTONOMOUS_TRANSACTION`）**：在事务内部开启独立事务，提交/回滚互不影响。审计日志的标准方案
- **Flashback 技术族**：Flashback Query（查询过去某时刻的数据）、Flashback Table（恢复误删的表）、Flashback Database（整库时间回退）— 基于 Undo 的时间旅行
- **物化视图（最完善实现）**：支持增量刷新（Fast Refresh）、Query Rewrite（优化器自动路由查询到物化视图），这两个能力其他数据库至今追赶
- **Bitmap 索引**：低基数列（性别、状态）的专用索引，多列交叉过滤时效率极高
- **`DECODE` 函数**：Oracle 版的 CASE 表达式，更紧凑但可读性争议大
- **DUAL 表**：单行单列的虚拟表，`SELECT sysdate FROM DUAL` — Oracle 的经典写法
- **`RATIO_TO_REPORT`**：窗口函数，直接计算占比，无需手写除法
- **`KEEP (DENSE_RANK FIRST/LAST)`**：在分组聚合中同时获取极值对应的其他列值
- **Virtual Private Database (VPD)**：在 SQL 解析层自动追加 WHERE 条件实现行级隔离，比 PostgreSQL RLS 更早、实现层次更深

## 已知的设计不足与历史包袱

- **`'' = NULL`**：这是 Oracle 最大的历史包袱。`LENGTH('') IS NULL` 为 true，`'' || 'abc' = 'abc'` — 空字符串在连接中消失。迁移到其他数据库时这是最大的痛点
- **不支持 DDL 回滚**：`CREATE TABLE` 是立即提交的，无法在事务中回滚。这一点不如 PostgreSQL
- **DUAL 表要求**：不能写 `SELECT 1+1`，必须写 `SELECT 1+1 FROM DUAL`（23ai 终于可以省略）
- **NUMBER 万能类型**：Oracle 的 NUMBER 类型不区分整数/浮点/定点，内部统一用变长十进制存储。灵活但牺牲了存储效率和计算性能
- **VARCHAR2 默认字节语义**：`VARCHAR2(100)` 默认是 100 字节而非 100 字符，中文可能只存 33 个。需要显式指定 `VARCHAR2(100 CHAR)`
- **许可证费用极高**：Enterprise Edition 按处理器核心收费，高级功能（RAC、Partitioning、In-Memory）需单独购买 Option Pack
- **客户端部署复杂**：历史上需要安装 Oracle Client / Instant Client，配置 tnsnames.ora。虽然近年简化了，但仍比 MySQL/PostgreSQL 的轻量客户端重得多
- **ALTER TABLE 限制**：不能直接缩短列长度、修改列类型的限制比其他数据库更多

## 兼容生态

Oracle 兼容性是中国国产数据库的主要赛道：
- **达梦（DM）**：中国最成熟的 Oracle 兼容数据库，政府/军工市场主导
- **人大金仓（KingbaseES）**：Oracle + PostgreSQL 双兼容模式
- **OceanBase Oracle 模式**：蚂蚁集团的分布式数据库，同时提供 MySQL 和 Oracle 兼容模式
- **GaussDB（华为）**：Oracle 兼容为主要目标之一
- **TDSQL（腾讯）**：部分 Oracle 兼容

Oracle 兼容生态的存在本身说明了一个问题：**Oracle 的锁定效应极强**，大量存量 PL/SQL 代码使迁移成本极高。

## 对引擎开发者的参考价值

- **标量子查询缓存**：Oracle 会缓存标量子查询的输入→输出映射，相同输入直接返回缓存结果。这对关联子查询的性能提升巨大，但其他数据库几乎都没实现
- **物化视图 Query Rewrite**：优化器自动检测查询是否可以从物化视图中回答，无需修改 SQL。这需要深入的查询等价性判断逻辑
- **Edition-Based Redefinition（EBR）**：在线应用升级方案 — 新旧版本代码通过"版本"隔离，同时运行。这是数据库领域独一无二的零停机升级设计
- **Flashback 架构**：基于 Undo 日志的时间旅行查询，不需要额外的历史表。这个设计对时态数据库和审计需求有极高参考价值
- **自适应游标共享（ACS）**：同一 SQL 根据绑定变量的不同值使用不同执行计划，解决了"绑定变量 vs. 执行计划偏斜"的经典矛盾
- **Result Cache**：SQL 结果集缓存在 SGA 中，DML 变更自动失效。这是数据库层面的查询缓存，比应用层缓存更精准

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/oracle.md) | NUMBER 万能类型，''=NULL（最大坑），IDENTITY(12c+) |
| [改表](../ddl/alter-table/oracle.md) | DDL 自动提交不可回滚，列类型修改限制多 |
| [索引](../ddl/indexes/oracle.md) | Bitmap 索引独有，函数索引成熟，IOT 索引组织表 |
| [约束](../ddl/constraints/oracle.md) | 延迟约束+不可见约束，企业级约束管理最完善 |
| [视图](../ddl/views/oracle.md) | 物化视图 Fast Refresh+Query Rewrite（业界最强实现） |
| [序列与自增](../ddl/sequences/oracle.md) | IDENTITY(12c+)+传统 SEQUENCE，缓存策略成熟 |
| [数据库/Schema/用户](../ddl/users-databases/oracle.md) | 多租户 CDB/PDB(12c+)，VPD 行级隔离比 RLS 更早 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/oracle.md) | EXECUTE IMMEDIATE+DBMS_SQL 双体系，绑定变量文化深入 |
| [错误处理](../advanced/error-handling/oracle.md) | EXCEPTION 命名异常+RAISE_APPLICATION_ERROR 自定义错误码 |
| [执行计划](../advanced/explain/oracle.md) | DBMS_XPLAN+AWR+SQL Monitor 实时诊断，最强调优工具链 |
| [锁机制](../advanced/locking/oracle.md) | 读永不阻塞写(Undo-based MVCC)，无锁升级，ORA-01555 是代价 |
| [分区](../advanced/partitioning/oracle.md) | 分区类型最丰富(RANGE/LIST/HASH/COMPOSITE/INTERVAL)，需单独购买 |
| [权限](../advanced/permissions/oracle.md) | VPD 行级安全+Fine-Grained Auditing，企业级权限最完善 |
| [存储过程](../advanced/stored-procedures/oracle.md) | PL/SQL Package（最强过程语言），BULK COLLECT/FORALL 批量绑定 |
| [临时表](../advanced/temp-tables/oracle.md) | 全局临时表需预先定义结构，Private Temp Table(18c+) 来得太晚 |
| [事务](../advanced/transactions/oracle.md) | 无显式 BEGIN，自治事务独有，Flashback 时间旅行，只有 RC/SERIALIZABLE |
| [触发器](../advanced/triggers/oracle.md) | COMPOUND 触发器(11g+)统一行/语句级，INSTEAD OF 触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/oracle.md) | Flashback Table 可恢复误删，TRUNCATE+REUSE STORAGE |
| [插入](../dml/insert/oracle.md) | INSERT ALL 多表插入独有，Direct-Path INSERT /*+ APPEND */ |
| [更新](../dml/update/oracle.md) | MERGE 更新最完善，可更新 JOIN 视图 |
| [Upsert](../dml/upsert/oracle.md) | MERGE 是 Oracle 首创(9i)，功能最完整，支持多分支 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/oracle.md) | KEEP(DENSE_RANK) 独有，LISTAGG(11g+)，统计聚合丰富 |
| [条件函数](../functions/conditional/oracle.md) | DECODE 可读性差但经典，CASE+NVL2+LNNVL 选择多 |
| [日期函数](../functions/date-functions/oracle.md) | 日期格式依赖 NLS_DATE_FORMAT 会话设置，隐式转换是大坑 |
| [数学函数](../functions/math-functions/oracle.md) | NUMBER 内部十进制运算无精度丢失 |
| [字符串函数](../functions/string-functions/oracle.md) | ''=NULL 是最大历史包袱，LENGTH('') IS NULL |
| [类型转换](../functions/type-conversion/oracle.md) | 隐式转换多且不可控，TO_NUMBER/TO_DATE 格式串必须精确匹配 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/oracle.md) | WITH 子句+/*+ MATERIALIZE */ 提示，可递归 |
| [全文搜索](../query/full-text-search/oracle.md) | Oracle Text 功能最完善但异步更新，CONTAINS/NEAR/FUZZY |
| [连接查询](../query/joins/oracle.md) | 旧式(+)语法是历史包袱，LATERAL(12c+)+CROSS APPLY(12c+) |
| [分页](../query/pagination/oracle.md) | 12c 前需 ROWNUM 嵌套三层，12c+ FETCH FIRST 标准语法 |
| [行列转换](../query/pivot-unpivot/oracle.md) | 原生 PIVOT/UNPIVOT(11g) 语法最早引入 |
| [集合操作](../query/set-operations/oracle.md) | 用 MINUS 而非标准 EXCEPT，UNION ALL+集合嵌套完善 |
| [子查询](../query/subquery/oracle.md) | 标量子查询缓存独有，关联子查询优化器展开强 |
| [窗口函数](../query/window-functions/oracle.md) | 8i 首创（业界最早），RATIO_TO_REPORT/KEEP/IGNORE NULLS 独有 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/oracle.md) | 无 generate_series，需 CONNECT BY LEVEL 模拟 |
| [去重](../scenarios/deduplication/oracle.md) | ROW_NUMBER+ROWID 直接定位物理行，删除效率高 |
| [区间检测](../scenarios/gap-detection/oracle.md) | 窗口函数+CONNECT BY LEVEL 填充序列 |
| [层级查询](../scenarios/hierarchical-query/oracle.md) | CONNECT BY 是层级查询的原创语法，SYS_CONNECT_BY_PATH 独有 |
| [JSON 展开](../scenarios/json-flatten/oracle.md) | JSON_TABLE(12c+) 最早支持标准语法，Duality View(23ai) |
| [迁移速查](../scenarios/migration-cheatsheet/oracle.md) | ''=NULL+DDL 自动提交+PL/SQL Package 依赖使迁移极难 |
| [TopN 查询](../scenarios/ranking-top-n/oracle.md) | FETCH FIRST WITH TIES(12c+)，ROWNUM 嵌套是经典写法 |
| [累计求和](../scenarios/running-total/oracle.md) | 窗口函数+MODEL 子句可做更复杂的行间计算 |
| [缓慢变化维](../scenarios/slowly-changing-dim/oracle.md) | MERGE 多分支+Flashback 历史查询辅助验证 |
| [字符串拆分](../scenarios/string-split-to-rows/oracle.md) | 无原生 split，需 CONNECT BY+REGEXP_SUBSTR 技巧 |
| [窗口分析](../scenarios/window-analytics/oracle.md) | 窗口函数种类最多，MODEL 子句做电子表格式计算 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/oracle.md) | VARRAY+嵌套表+OBJECT TYPE，PL/SQL 集合类型完整 |
| [日期时间](../types/datetime/oracle.md) | DATE 含时间到秒级易混淆，TIMESTAMP 精确，INTERVAL 类型完善 |
| [JSON](../types/json/oracle.md) | JSON_TABLE 最早标准实现，Duality View(23ai) 关系-文档双视图 |
| [数值类型](../types/numeric/oracle.md) | NUMBER 万能类型不区分整数/浮点，存储效率低 |
| [字符串类型](../types/string/oracle.md) | ''=NULL 是 45 年历史包袱，VARCHAR2(N) 默认字节语义 |
