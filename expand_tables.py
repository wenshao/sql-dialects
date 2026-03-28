#!/usr/bin/env python3
"""Expand module tables in dialect markdown files to match bigquery.md depth."""

import re
import sys

# Each dialect's expanded descriptions, keyed by dialect name
# Format: { "dialect": { "link_text_fragment": "new description" } }
# link_text_fragment is used to match the row, e.g. "create-table/postgres"

EXPANSIONS = {
    "postgres": {
        # DDL
        "create-table/postgres": "**IDENTITY（10+）替代 SERIAL 是现代最佳实践**——SERIAL 实际创建隐式 SEQUENCE 且 DROP TABLE 不会自动删除。TEXT=VARCHAR 无性能差异（对比 MySQL/Oracle 区分多种字符串类型）。DDL 可在事务中回滚——这是 PG 相对 MySQL/Oracle 的最大优势，使数据库迁移脚本可做到原子性。",
        "alter-table/postgres": "**DDL 事务性可回滚是 PG 最大优势**——ALTER TABLE 在事务中执行，失败可 ROLLBACK（对比 MySQL/Oracle 的 DDL 自动提交不可回滚）。PG 11+ ADD COLUMN WITH DEFAULT 秒级完成（之前需重写全表长达 20 年的缺陷）。CONCURRENTLY 选项允许不锁表重建索引。",
        "indexes/postgres": "**GiST/GIN/BRIN/SP-GiST 四种可扩展索引框架是 PG 独有优势**——GIN 倒排索引支撑 JSONB 查询和全文搜索，GiST 支撑地理空间和范围查询，BRIN 适合时序大表（极低存储开销）。部分索引（Partial Index）只索引满足条件的行（对比 SQL Server 的 Filtered Index 类似）。CONCURRENTLY 创建索引不锁表。",
        "constraints/postgres": "**EXCLUDE 排斥约束是 PG 独有能力**——基于 GiST 索引可表达\"时间区间不重叠\"等复杂业务规则（对比 MariaDB WITHOUT OVERLAPS 类似但更受限）。CHECK/FK 完整强制执行（对比 MySQL 8.0.16 前 CHECK 不执行）。支持延迟约束 DEFERRABLE（事务提交时才检查，对比 Oracle 也支持）。",
        "views/postgres": "**物化视图 REFRESH CONCURRENTLY 不锁查询**——但需唯一索引支持。无自动增量刷新（对比 BigQuery 自动增量刷新+智能查询重写、Oracle 的 Fast Refresh+Query Rewrite 业界最强）。物化视图需手动 REFRESH，生产中通常配合 pg_cron 定时刷新。",
        "sequences/postgres": "**IDENTITY（10+）是推荐的自增方案**——替代传统 SERIAL（SERIAL 有 DROP TABLE 不自动删除 SEQUENCE 的问题）。SEQUENCE 对象独立灵活——可跨表共享、设置步长/缓存/循环（对比 MySQL 无 SEQUENCE 对象、BigQuery 无自增列）。对比 Snowflake 的 AUTOINCREMENT 不保证连续。",
        "users-databases/postgres": "**Schema 多租户隔离+RLS 行级安全策略是 PG 权限的亮点**——Schema 可实现同一数据库内的逻辑隔离（对比 MySQL 的 Database=Schema 一级结构）。pg_hba.conf 控制认证链（host/SSL/方法）。RLS 行级安全策略内核级实现（对比 BigQuery 的 Row Access Policy 更声明式、Oracle 的 VPD 更早但更复杂）。",
        # Advanced
        "dynamic-sql/postgres": "**EXECUTE format() 是 PG 动态 SQL 的标准方式**——`format()` 函数使用 `%I`（标识符）和 `%L`（字面值）自动防 SQL 注入（对比 Oracle 的 EXECUTE IMMEDIATE 需手动绑定变量、MySQL 的 PREPARE/EXECUTE 语法冗长）。PL/pgSQL 内嵌动态 SQL 功能完善，支持 RETURN QUERY EXECUTE 返回动态结果集。",
        "error-handling/postgres": "**EXCEPTION WHEN 块提供完整的过程式错误处理**——支持 SQLSTATE 标准错误码精细匹配（如 '23505'=唯一冲突）、GET STACKED DIAGNOSTICS 获取错误详情。对比 Oracle 的命名异常更直观，但 PG 的 SQLSTATE 体系更标准。对比 MySQL 的 DECLARE HANDLER 功能明显更弱。",
        "explain/postgres": "**EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) 是最全面的执行计划分析**——ANALYZE 显示实际行数和耗时，BUFFERS 显示缓冲区命中/读取（I/O 分析关键）。pg_stat_statements 扩展提供历史查询统计（对比 MySQL 8.0.18+ 才有 EXPLAIN ANALYZE，且无内置历史统计）。对比 Oracle 的 DBMS_XPLAN+AWR 工具链更专业。",
        "locking/postgres": "**Advisory Locks 是 PG 独有的应用级分布式锁**——无需额外中间件即可实现跨连接的协调锁。MVCC 元组版本化实现读不阻塞写（对比 SQL Server 默认锁式并发读阻塞写）。无锁升级机制（对比 SQL Server 行锁→页锁→表锁自动升级）。代价是需要 VACUUM 回收死元组。",
        "partitioning/postgres": "**声明式分区（10+）支持 RANGE/LIST/HASH 三种方式**——每个分区可独立创建索引、设置表空间。对比 MySQL 的\"分区键必须在主键中\"限制，PG 无此约束更灵活。对比 BigQuery/Snowflake 的自动分区，PG 需手动管理分区生命周期。分区可以有子分区（多级分区）。",
        "permissions/postgres": "**RLS 行级安全策略是 PG 的企业级安全亮点**——通过 CREATE POLICY 为不同角色定义行过滤规则，多租户场景无需修改查询即可实现数据隔离（对比 Oracle VPD 更早但 PG 的 RLS 语法更简洁标准）。GRANT/REVOKE 标准语法。pg_hba.conf 控制连接级认证。无 DENY 权限（对比 SQL Server 独有的显式拒绝）。",
        "stored-procedures/postgres": "**PL/pgSQL + PL/Python/PL/V8 多语言是 PG 存储过程的核心优势**——可用 Python 处理复杂逻辑、用 JavaScript 处理 JSON。$$ Dollar Quoting 彻底解决引号转义。无 Package（对比 Oracle PL/SQL 的包封装是最大缺失）。PROCEDURE（11+）支持事务控制（COMMIT/ROLLBACK），之前只有 FUNCTION。",
        "temp-tables/postgres": "**ON COMMIT DROP/DELETE ROWS 两种临时表策略**——DROP 在事务结束后自动销毁表，DELETE ROWS 保留结构清空数据。会话级临时表不需预定义结构（对比 Oracle 的 GTT 需预先定义）。临时表的统计信息不影响共享缓存。对比 SQL Server 的 #temp（本地）/##temp（全局）命名约定。",
        "transactions/postgres": "**SSI（Serializable Snapshot Isolation，9.1+）是 PG 的并发控制创新**——基于快照隔离实现可串行化，无需传统两阶段锁，性能远优于锁式 SERIALIZABLE（对比 SQL Server/MySQL 的锁式隔离）。DDL 事务性——CREATE TABLE 可回滚。Advisory Locks 提供应用级协调。Savepoint 支持部分回滚。",
        "triggers/postgres": "**BEFORE/AFTER/INSTEAD OF 三种触发器类型完整**——行级+语句级均支持（对比 MySQL 只有行级）。事件触发器（Event Trigger, 9.3+）可监控 DDL 操作（CREATE/ALTER/DROP）——对审计和权限控制极有价值（对比 Oracle 的 DDL Trigger 类似）。支持 WHEN 条件触发器（仅在满足条件时触发）。",
        # DML
        "delete/postgres": "**RETURNING 返回被删行是 PG 的独有优势**——`DELETE FROM t WHERE... RETURNING *` 一步完成删除和获取被删数据（对比 MySQL 需额外 SELECT、SQL Server 用 OUTPUT DELETED）。USING 子句实现多表关联删除。DELETE 可在事务中回滚。TRUNCATE 也支持事务回滚（对比 MySQL TRUNCATE 不可回滚）。",
        "insert/postgres": "**RETURNING 子句是 PG INSERT 的最大亮点**——`INSERT INTO t... RETURNING id, created_at` 一步完成插入和获取含自增 ID 的完整行（对比 MySQL 的 LAST_INSERT_ID() 仅返回 ID）。COPY 是批量导入最快方式（二进制模式更快）。INSERT...SELECT 跨表插入标准。对比 Oracle 的 INSERT ALL 多表插入（独有）。",
        "update/postgres": "**UPDATE...FROM 多表更新+RETURNING 是 PG 的组合优势**——`UPDATE t1 SET... FROM t2 WHERE t1.id=t2.id RETURNING t1.*` 同时完成关联更新和结果获取。对比 MySQL 的 JOIN UPDATE 语法不同但功能等效。PG 的 UPDATE 内部创建新元组版本（MVCC），旧版本由 VACUUM 回收（对比 InnoDB 原地修改+Undo Log）。",
        "upsert/postgres": "**ON CONFLICT DO UPDATE（9.5+）是 PG 的 UPSERT 方案**——可指定冲突列或约束名（对比 MySQL ON DUPLICATE KEY UPDATE 基于所有唯一索引冲突），`ON CONFLICT DO NOTHING` 静默跳过冲突行。MERGE 语句 15+ 才引入（对比 Oracle 9i 首创 MERGE、SQL Server 2008 引入）。",
        # Functions
        "aggregate/postgres": "**FILTER 子句是 PG 独有的优雅条件聚合**——`COUNT(*) FILTER (WHERE status='active')` 比 CASE WHEN 清晰得多（对比 ClickHouse 的 countIf 后缀、BigQuery 的 COUNTIF 函数）。GROUPING SETS/CUBE/ROLLUP 完整支持。string_agg 聚合字符串。对比 MySQL 无 FILTER 子句、无 GROUPING SETS（8.0 有限支持）。",
        "conditional/postgres": "**标准 CASE/COALESCE/NULLIF 完整实现**——布尔类型原生支持（TRUE/FALSE/NULL 三值逻辑，对比 MySQL 用 TINYINT(1) 模拟布尔）。无 IIF 函数（对比 SQL Server/DuckDB），但 CASE WHEN 语法更标准。类型系统严格——不做隐式转换（对比 MySQL 的宽松隐式转换是常见 Bug 源）。",
        "date-functions/postgres": "**INTERVAL 类型是 PG 日期运算的优势**——`NOW() + INTERVAL '3 months 2 days'` 语法自然（对比 MySQL 的 DATE_ADD 函数调用）。generate_series(start, end, interval) 生成时间序列——日期填充的利器（对比 MySQL 无此功能，BigQuery 的 GENERATE_DATE_ARRAY 类似）。age() 计算两个日期的精确差值。",
        "math-functions/postgres": "**NUMERIC 任意精度是 PG 数学运算的基石**——可以存储和计算任意精度的数字而不丢失精度（对比 MySQL 的 DECIMAL 最大 65 位、BigQuery 的 BIGNUMERIC 76 位）。除零会报错（对比 MySQL/BigQuery 返回 NULL）。完整数学函数库。无 SAFE_DIVIDE（对比 BigQuery 独有的 SAFE_ 前缀安全函数）。",
        "string-functions/postgres": "**`||` 拼接是 SQL 标准运算符**——PG 严格遵循标准（对比 MySQL 中 `||` 是逻辑 OR 是最大方言差异之一）。regexp_match/regexp_replace 正则功能强大。string_agg 聚合拼接。对比 BigQuery 的 SPLIT 返回 ARRAY 和 ClickHouse 的 extractAll 正则提取，PG 方案更标准但稍繁琐。",
        "type-conversion/postgres": "**`::` 类型转换运算符是 PG 独有的简洁语法**——`'2024-01-01'::date` 比 `CAST(x AS date)` 简短（Snowflake/Redshift 也借鉴了此语法）。类型系统严格不做隐式转换——`WHERE int_col = '123'` 需显式 CAST（对比 MySQL 宽松隐式转换导致索引失效）。至今无内置 TRY_CAST（对比 SQL Server/BigQuery/Snowflake 均有安全转换）。",
        # Query
        "cte/postgres": "**可写 CTE 是 PG 独有的强大能力**——`WITH deleted AS (DELETE FROM t RETURNING *) INSERT INTO archive SELECT * FROM deleted` 在一条语句中完成删除+归档。MATERIALIZED/NOT MATERIALIZED 提示（12+）控制 CTE 物化策略。递归 CTE 支持 UNION ALL 和 UNION DISTINCT。对比 MySQL 8.0 的 CTE 无可写能力。",
        "full-text-search/postgres": "**tsvector/tsquery + GIN 索引是内置的全文搜索引擎**——支持分词、词干提取、权重排序、短语搜索。pg_trgm 扩展提供模糊匹配（LIKE/ILIKE 也可用 GIN 加速）。多语言分词器（含中文 zhparser 扩展）。对比 MySQL 的 InnoDB FULLTEXT 功能较基础、Elasticsearch 专业但需独立部署。",
        "joins/postgres": "**LATERAL JOIN（9.3+）是 PG 的标准关联表表达式**——允许右侧子查询引用左侧表的列（对比 SQL Server 更早的 CROSS APPLY 非标准但功能等效）。支持所有 JOIN 类型包括 FULL OUTER JOIN（对比 MySQL 不支持 FULL OUTER）。优化器自动选择 Hash/Merge/Nested Loop 三种 JOIN 策略。",
        "pagination/postgres": "**LIMIT/OFFSET 标准分页语法**——对比 Oracle 12c 前需 ROWNUM 嵌套三层。深分页 O(offset) 问题同样存在，推荐 Keyset 分页（`WHERE id > last_id ORDER BY id LIMIT N`）。FETCH FIRST（SQL 标准语法）也支持。对比 BigQuery 按扫描量计费无论 OFFSET 多大成本不变。",
        "pivot-unpivot/postgres": "**无原生 PIVOT/UNPIVOT 语法**——需使用 crosstab() 函数（tablefunc 扩展）或 CASE+GROUP BY 手工模拟。对比 Oracle 11g/SQL Server/BigQuery/Snowflake/DuckDB 均有原生 PIVOT 语法更简洁。crosstab 需指定固定列名，动态 PIVOT 仍需拼接动态 SQL。",
        "set-operations/postgres": "**UNION/INTERSECT/EXCEPT 完整支持，含 ALL 变体**——严格遵循 SQL 标准。EXCEPT 而非 Oracle 的 MINUS（非标准命名）。所有集合操作支持 ORDER BY（作用于最终结果）。对比 MySQL 8.0.31 前无 INTERSECT/EXCEPT，ClickHouse UNION 默认 ALL（与标准相反）。",
        "subquery/postgres": "**LATERAL 子查询（9.3+）是 PG 子查询的独有优势**——允许子查询引用外层表的列，对每行执行一次子查询。ANY/ALL/EXISTS 标准支持。优化器善于将子查询转为 JOIN。对比 MySQL 5.x 子查询性能噩梦（IN 转 EXISTS 导致灾难性能，8.0 修复）。",
        "window-functions/postgres": "**8.4 起支持窗口函数（2009 年，比 MySQL 8.0 早 9 年）**——FILTER 子句可对窗口函数条件聚合。GROUPS 帧类型（11+）基于分组而非行/范围。WINDOW 命名子句允许复用窗口定义。NTH_VALUE 支持。无 QUALIFY 子句（对比 BigQuery/Snowflake/DuckDB 直接过滤窗口函数结果）。",
        # Scenarios
        "date-series-fill/postgres": "**generate_series(date, date, interval) 是日期填充的最简方案**——一行函数调用生成日期序列，LEFT JOIN 填充缺失。对比 MySQL 需递归 CTE（冗长）、BigQuery 的 GENERATE_DATE_ARRAY（类似但返回 ARRAY 需 UNNEST）、ClickHouse 的 WITH FILL（更简洁但不同范式）。PG 方案最经典最广泛使用。",
        "deduplication/postgres": "**DISTINCT ON 是 PG 独有的简洁去重写法**——`SELECT DISTINCT ON (key) * FROM t ORDER BY key, ts DESC` 一行取每组最新行（对比其他引擎需 ROW_NUMBER 子查询包装）。也可用 ROW_NUMBER+CTE 标准方案。对比 BigQuery/DuckDB 的 QUALIFY ROW_NUMBER() 同样简洁但语法不同。",
        "gap-detection/postgres": "**generate_series 填充+LEFT JOIN 是最直观的间隙检测方案**——先生成完整序列再与实际数据 LEFT JOIN，NULL 即为缺失。窗口函数 LAG/LEAD 辅助检测相邻行差距。对比 MySQL 无 generate_series、ClickHouse 的 WITH FILL 自动填充（更简洁）。",
        "hierarchical-query/postgres": "**递归 CTE 是 PG 的层级查询标准方案**——`WITH RECURSIVE` 语法清晰（SQL 标准）。无 Oracle 的 CONNECT BY（更简洁的原创语法，SYS_CONNECT_BY_PATH 独有）。ltree 扩展提供物化路径运算（如 `'1.2.3' <@ '1.2'` 祖先检测），是 PG 独有的层级查询增强。",
        "json-flatten/postgres": "**JSONB + GIN 索引是业界最强的关系型 JSON 实现**——支持 @> 包含查询、? 键存在查询，GIN 索引加速。json_to_recordset 将 JSON 数组转为关系行集。JSON_TABLE（17+）标准语法（对比 Oracle 12c 最早支持）。对比 BigQuery 的 STRUCT 原生嵌套和 Snowflake 的 VARIANT 更灵活。",
        "migration-cheatsheet/postgres": "**迁移核心差异：类型严格（无隐式转换，对比 MySQL 宽松）、DDL 可回滚（优势）、`||` 是拼接（对比 MySQL 是 OR）**。从 MySQL 迁入注意 utf8mb4→UTF-8 天然支持、AUTO_INCREMENT→SERIAL/IDENTITY。从 Oracle 迁入注意 ''=NULL 差异、PL/SQL Package→无 Package 需重构。",
        "ranking-top-n/postgres": "**DISTINCT ON 分组取一行是 PG 独有简洁写法**——无需窗口函数子查询。FETCH FIRST WITH TIES（13+）包含排名并列的额外行（对比 SQL Server 的 TOP WITH TIES、Oracle 12c+）。ROW_NUMBER+CTE 是通用 TopN 方案。无 QUALIFY（对比 BigQuery/Snowflake 一行搞定）。",
        "running-total/postgres": "**SUM() OVER(ORDER BY ...) 标准窗口函数**——8.4 起即支持（比 MySQL 8.0 早 9 年）。完整帧子句 ROWS/RANGE/GROUPS。对比 MySQL 5.x 时代需用户变量 @running 模拟（不确定行为）。BigQuery/Snowflake 方案相同但在分布式引擎上 Slot/Warehouse 自动扩展。",
        "slowly-changing-dim/postgres": "**MERGE（15+）标准 SQL 支持——但比其他引擎来得晚**（对比 Oracle 9i 首创、SQL Server 2008、BigQuery/Snowflake 早已支持）。15 之前用 INSERT...ON CONFLICT 模拟 SCD Type 1。Type 2 需手动处理历史行关闭+新行插入。对比 SQL Server 的 Temporal Tables 自动维护历史版本。",
        "string-split-to-rows/postgres": "**string_to_table（14+）是最简洁的字符串拆分方案**——一行函数调用（对比 MySQL 需递归 CTE+SUBSTRING_INDEX 极其繁琐）。regexp_split_to_table 支持正则拆分。unnest(string_to_array()) 是旧版替代方案。对比 SQL Server 的 STRING_SPLIT 和 ClickHouse 的 splitByChar+arrayJoin。",
        "window-analytics/postgres": "**窗口函数完整且最早支持之一**——FILTER 子句条件聚合（独有）、GROUPS 帧类型（11+，基于分组而非行）、NTH_VALUE、WINDOW 命名子句。对比 MySQL 8.0 的窗口函数功能完整但无 FILTER/GROUPS，BigQuery/DuckDB 有 QUALIFY 子句 PG 没有。",
        # Types
        "array-map-struct/postgres": "**原生 ARRAY 类型+运算符是 PG 的类型系统亮点**——`int[]` 可直接作为列类型，支持 @>（包含）、&&（重叠）等运算符和 GIN 索引加速。自定义复合类型（CREATE TYPE）可模拟 STRUCT。hstore 扩展提供键值存储。对比 BigQuery 的 STRUCT/ARRAY 一等公民和 ClickHouse 的 Array/Tuple/Map。",
        "datetime/postgres": "**TIMESTAMP WITH/WITHOUT TIME ZONE 是 PG 时间类型的核心区分**——TIMESTAMPTZ 以 UTC 存储并在显示时转换为会话时区（推荐使用）。INTERVAL 类型极其灵活（`'2 years 3 months 4 days'::interval`）。无 2038 问题（对比 MySQL 的 TIMESTAMP 受 32 位限制）。对比 Snowflake 的三种 TIMESTAMP（NTZ/LTZ/TZ）认知负担更重。",
        "json/postgres": "**JSONB + GIN 索引是关系型数据库中最强的 JSON 实现**——二进制存储、倒排索引、@> 包含查询、jsonpath 查询（12+）。JSON_TABLE（17+）符合 SQL 标准。对比 MySQL 的 JSON 二进制存储但索引能力弱、BigQuery 的 JSON 类型（2022+）功能较新、Snowflake 的 VARIANT 更灵活但不同范式。",
        "numeric/postgres": "**NUMERIC 任意精度是 PG 数值类型的核心能力**——存储和计算不丢失精度，适合金融场景。SMALLINT/INT/BIGINT 标准整数类型。无 UNSIGNED（对比 MySQL 的 UNSIGNED 正在废弃）。对比 Oracle 的 NUMBER 万能类型（灵活但存储效率低）和 BigQuery 只有 INT64 一种整数（极简）。",
        "string/postgres": "**TEXT=VARCHAR 无性能差异是 PG 字符串设计的优雅之处**——无需纠结 VARCHAR(N) 的 N 值（对比 MySQL 的 TEXT 有索引限制、Oracle 的 VARCHAR2 默认字节语义）。字符语义默认（不是字节语义）。排序规则（Collation）灵活可按列指定。对比 BigQuery 的 STRING 无长度限制极简设计类似。",
    },
    "oracle": {
        # DDL
        "create-table/oracle": "**NUMBER 万能类型不区分整数/浮点/定点**——灵活但牺牲存储效率和计算性能（对比 PG 的 SMALLINT/INT/BIGINT 分级、BigQuery 的 INT64/FLOAT64 明确）。`''=NULL` 是 45 年历史包袱，空字符串等于 NULL 与所有其他数据库不同。IDENTITY（12c+）终于支持自增列（之前只能 SEQUENCE+TRIGGER）。",
        "alter-table/oracle": "**DDL 自动提交不可回滚**——CREATE/ALTER/DROP TABLE 立即生效无法在事务中撤销（对比 PG 的 DDL 事务性可回滚是核心优势）。列类型修改限制多（不能缩短长度、不能改大部分类型）。Edition-Based Redefinition（EBR）是零停机 Schema 升级的独有高级方案。",
        "indexes/oracle": "**Bitmap 索引是 Oracle 独有的低基数列专用索引**——性别、状态等列的多列交叉过滤效率极高（对比 PG 无 Bitmap 索引、Greenplum 有）。函数索引早于其他数据库成熟。IOT（索引组织表）将数据按主键物理排序存储（类似 InnoDB 聚簇索引）。对比 BigQuery/Snowflake 无任何用户可创建索引。",
        "constraints/oracle": "**延迟约束+不可见约束使 Oracle 约束管理最完善**——DEFERRABLE INITIALLY DEFERRED 在事务提交时才检查约束（对比 PG 也支持但 MySQL 不支持）。ENABLE NOVALIDATE 可跳过存量数据校验。对比 BigQuery/Snowflake 的 NOT ENFORCED 约束仅作元数据提示，Oracle 的约束是真正强制执行的。",
        "views/oracle": "**物化视图 Fast Refresh + Query Rewrite 是业界最强实现**——增量刷新只处理变更数据（对比 PG 的 REFRESH MATERIALIZED VIEW 全量刷新），优化器自动将普通表查询路由到物化视图加速（对比 BigQuery 也有自动查询重写但成熟度不及 Oracle）。需创建物化视图日志（MV Log）支持增量刷新。",
        "sequences/oracle": "**IDENTITY（12c+）+ 传统 SEQUENCE 双体系**——IDENTITY 简化自增列定义，SEQUENCE 对象独立灵活可跨表共享。缓存策略成熟（CACHE/NOCACHE/ORDER 选项）。对比 MySQL 无 SEQUENCE 对象、PG 的 IDENTITY（10+）推荐替代 SERIAL。Oracle 的 SEQUENCE 实现是行业标杆。",
        "users-databases/oracle": "**多租户 CDB/PDB（12c+）是 Oracle 的独创架构**——一个容器数据库（CDB）包含多个可插拔数据库（PDB），实现资源隔离和快速克隆。VPD（Virtual Private Database）在 SQL 解析层自动追加 WHERE 条件实现行级隔离（比 PG RLS 更早、实现层次更深）。对比 BigQuery 的 Project.Dataset 三级命名空间。",
        # Advanced
        "dynamic-sql/oracle": "**EXECUTE IMMEDIATE + DBMS_SQL 双体系是 Oracle 动态 SQL 的完整方案**——EXECUTE IMMEDIATE 适合简单动态 SQL，DBMS_SQL 适合列数/类型运行时未知的复杂场景。绑定变量文化深入（避免硬解析消耗 Shared Pool）。对比 PG 的 EXECUTE format() 更简洁、MySQL 的 PREPARE/EXECUTE 功能更弱。",
        "error-handling/oracle": "**命名异常+RAISE_APPLICATION_ERROR 是 PL/SQL 错误处理的特色**——可定义具名异常（如 NO_DATA_FOUND、TOO_MANY_ROWS），RAISE_APPLICATION_ERROR 抛出自定义错误码（-20000~-20999）。对比 PG 的 SQLSTATE 标准体系更标准但 Oracle 的命名异常更直观。对比 MySQL 的 DECLARE HANDLER 功能明显更弱。",
        "explain/oracle": "**DBMS_XPLAN + AWR + SQL Monitor 构成最强调优工具链**——DBMS_XPLAN.DISPLAY_CURSOR 显示实际执行计划，AWR（Automatic Workload Repository）存储历史性能数据，SQL Monitor 实时可视化复杂查询的执行进度。对比 PG 的 EXPLAIN ANALYZE+pg_stat_statements 功能接近但工具集成度不如 Oracle。",
        "locking/oracle": "**Undo-based MVCC 实现读永不阻塞写**——旧版本通过 Undo 表空间重建，表不膨胀无需 VACUUM（对比 PG 需要 VACUUM 回收死元组）。代价是 Undo 空间耗尽时报 ORA-01555: snapshot too old。无锁升级机制。仅支持 READ COMMITTED 和 SERIALIZABLE 两种隔离级别（对比 PG 的 SSI 更先进）。",
        "partitioning/oracle": "**分区类型最丰富是 Oracle 的企业级优势**——RANGE/LIST/HASH/COMPOSITE/INTERVAL（自动创建新分区）/REFERENCE（子表继承父表分区）。但分区功能需单独购买 Partitioning Option（高额费用）。对比 PG 免费但类型较少、BigQuery/Snowflake 自动管理。",
        "permissions/oracle": "**VPD + Fine-Grained Auditing 是 Oracle 安全的核心优势**——VPD 在 SQL 解析层自动追加 WHERE 条件，应用无需修改查询即可实现行级隔离。FGA 细粒度审计可审计特定列的 SELECT 访问。对比 PG 的 RLS（语法更简洁）、BigQuery 的 Row Access Policy（更声明式）。",
        "stored-procedures/oracle": "**PL/SQL Package 是最强的过程化编程体系**——将过程、函数、类型、常量封装为模块，支持 public/private 可见性。BULK COLLECT/FORALL 批量绑定解决逐行处理性能问题。自治事务（PRAGMA AUTONOMOUS_TRANSACTION）独有。对比 PG 无 Package（最大缺失）、MySQL 的过程化能力最弱。",
        "temp-tables/oracle": "**全局临时表（GTT）需预先定义结构是 Oracle 的设计特色**——ON COMMIT DELETE ROWS/PRESERVE ROWS 控制事务/会话级数据保留。Private Temp Table（18c+）不需预定义但来得太晚。对比 PG/MySQL 的临时表不需预定义更灵活、SQL Server 的 #temp 表语法最简洁。",
        "transactions/oracle": "**无显式 BEGIN——Oracle 事务自动开始是独特设计**。自治事务（PRAGMA AUTONOMOUS_TRANSACTION）允许在事务内开启独立事务（审计日志标准方案，对比其他数据库均无此能力）。Flashback 技术族基于 Undo 实现时间旅行。仅支持 READ COMMITTED/SERIALIZABLE 两种隔离级别。",
        "triggers/oracle": "**COMPOUND 触发器（11g+）统一行级/语句级逻辑是 Oracle 独有设计**——在一个触发器体中定义 BEFORE STATEMENT/BEFORE EACH ROW/AFTER EACH ROW/AFTER STATEMENT 四个时间点。INSTEAD OF 触发器用于可更新视图。DDL 触发器监控 Schema 变更。对比 PG 也支持完整触发器但无 COMPOUND 概念。",
        # DML
        "delete/oracle": "**Flashback Table 可恢复误删的表**——`FLASHBACK TABLE t TO BEFORE DROP`（基于 Recyclebin），降低人为误操作风险（对比 Snowflake 的 UNDROP TABLE 类似）。TRUNCATE + REUSE STORAGE 保留分配的存储空间。对比 PG 的 DELETE RETURNING 返回被删行，Oracle 无 RETURNING on DELETE（但有 RETURNING on INSERT/UPDATE）。",
        "insert/oracle": "**INSERT ALL 多表插入是 Oracle 独有能力**——一条 INSERT 同时写入多个目标表（条件分发或无条件广播），ETL 场景极高效。Direct-Path INSERT `/*+ APPEND */` 绕过 Buffer Cache 直接写数据文件（批量加载最快方式）。对比 PG/MySQL 只能逐表 INSERT、BigQuery 的 LOAD JOB 免费批量加载。",
        "update/oracle": "**MERGE 更新是 Oracle 最完善的数据合并方案**——支持 WHEN MATCHED UPDATE + WHEN NOT MATCHED INSERT + DELETE WHERE 多分支逻辑。可更新 JOIN 视图允许通过视图直接 UPDATE 基表。对比 PG 的 UPDATE...FROM+RETURNING 组合优势、SQL Server 的 OUTPUT INSERTED/DELETED 获取修改前后值。",
        "upsert/oracle": "**MERGE 是 Oracle 首创（9i）且功能最完整的 UPSERT 方案**——支持多个 WHEN MATCHED/WHEN NOT MATCHED 分支，可同时包含 UPDATE、INSERT 和 DELETE 操作。对比 PG 的 ON CONFLICT 语法更简洁但功能较少，MySQL 用 ON DUPLICATE KEY UPDATE 替代（无标准 MERGE）。MERGE 性能在大数据量下优于逐行 UPSERT。",
        # Functions
        "aggregate/oracle": "**KEEP(DENSE_RANK FIRST/LAST) 是 Oracle 独有的分组极值关联查询**——在 GROUP BY 中同时获取最大/最小值对应的其他列值，无需子查询。LISTAGG（11g+）字符串聚合。统计聚合函数丰富（STATS_T_TEST、REGR_SLOPE 等）。对比 PG 的 FILTER 子句条件聚合（Oracle 无此语法）。",
        "conditional/oracle": "**DECODE 是 Oracle 的经典条件函数**——比 CASE WHEN 更紧凑但可读性争议大。NVL2(expr, not_null_val, null_val) 三参数空值处理独有。LNNVL 反转 NULL 逻辑也独有。对比 SQL Server 的 IIF 更简洁、BigQuery 的 SAFE_ 前缀安全函数理念不同。",
        "date-functions/oracle": "**日期格式依赖 NLS_DATE_FORMAT 会话设置是 Oracle 最大的隐式转换陷阱**——不同会话可能以不同格式显示日期，TO_CHAR/TO_DATE 必须显式指定格式避免歧义。SYSDATE 返回 DATE 类型（含时间到秒），SYSTIMESTAMP 返回带时区的高精度时间戳。对比 PG 的 now() 和 MySQL 的 NOW() 更直观。",
        "math-functions/oracle": "**NUMBER 内部十进制运算保证无精度丢失**——所有数值统一使用 NUMBER 变长十进制存储（对比 PG 区分 INTEGER/NUMERIC/FLOAT 更精确但选择更多）。除零会报错（ORA-01476）。ROUND/TRUNC 函数同时适用于数字和日期。对比 BigQuery 的 SAFE_DIVIDE 除零返回 NULL 更安全。",
        "string-functions/oracle": "**`''=NULL` 是 Oracle 字符串函数的最大历史包袱**——LENGTH('') IS NULL 为 true，'' || 'abc' = 'abc'（空字符串在连接中消失）。这与所有其他数据库的行为都不同，是迁移最大痛点。对比 PG/MySQL 中 '' 是空字符串而非 NULL。LISTAGG 字符串聚合（11g+）。",
        "type-conversion/oracle": "**隐式转换多且不可控是 Oracle 类型转换的风险**——TO_NUMBER/TO_DATE 格式串必须精确匹配（'DD-MON-YYYY' vs 'YYYY-MM-DD'），错误格式直接报 ORA 异常。无 TRY_CAST 安全转换（对比 SQL Server TRY_CAST/BigQuery SAFE_CAST 失败返回 NULL）。依赖 NLS 设置的隐式日期转换是常见生产事故源。",
        # Query
        "cte/oracle": "**WITH 子句 + `/*+ MATERIALIZE */` 提示控制物化策略**——优化器默认可能内联也可能物化 CTE，MATERIALIZE 提示强制物化。递归 CTE（11gR2+）支持。对比 PG 的 MATERIALIZED/NOT MATERIALIZED 关键字（12+）更正式，Oracle 用 Hint 更灵活但不标准。无可写 CTE（PG 独有）。",
        "full-text-search/oracle": "**Oracle Text 是功能最完善的数据库内置全文搜索引擎**——CONTAINS 全文查询、NEAR 近邻搜索、FUZZY 模糊匹配、THESAURUS 同义词扩展。但索引更新默认异步（SYNC ON COMMIT 选项可改为同步）。对比 PG 的 tsvector+GIN 更轻量、Elasticsearch 专业搜索但需独立部署。",
        "joins/oracle": "**旧式 (+) 语法是 Oracle 历史包袱**——`WHERE t1.id = t2.id(+)` 等价于 LEFT JOIN 但可读性差，新代码应使用标准 JOIN 语法。LATERAL（12c+）和 CROSS APPLY（12c+）均支持关联表表达式。对比 SQL Server 更早普及 CROSS APPLY。Oracle 优化器的 JOIN 策略选择（NL/Hash/Sort-Merge）极为成熟。",
        "pagination/oracle": "**12c 前分页需 ROWNUM 嵌套三层是 Oracle 的经典痛点**——`SELECT * FROM (SELECT a.*, ROWNUM rn FROM (query ORDER BY...) a WHERE ROWNUM <= 20) WHERE rn > 10`。12c+ 引入 FETCH FIRST N ROWS ONLY 标准语法（对比 Db2 最早实现此标准语法）。OFFSET...FETCH 语法糖。",
        "pivot-unpivot/oracle": "**Oracle 11g 率先引入原生 PIVOT/UNPIVOT 语法**——`SELECT * FROM t PIVOT (SUM(amount) FOR year IN (2023, 2024))`。是最早提供此语法的主流数据库（对比 SQL Server 随后跟进、BigQuery 2021+ 支持）。PIVOT 需要枚举值（不支持动态值，需用动态 SQL 拼接）。",
        "set-operations/oracle": "**使用 MINUS 而非标准 EXCEPT 是 Oracle 的非标准命名**——功能等价但迁移到其他数据库时需替换关键字。UNION ALL/UNION DISTINCT、INTERSECT 完整支持。集合操作嵌套完善。对比 MySQL 8.0.31 前连 INTERSECT 都不支持，PG 严格使用标准 EXCEPT。",
        "subquery/oracle": "**标量子查询缓存是 Oracle 独有的性能优化**——缓存标量子查询的输入→输出映射，相同输入直接返回缓存结果，对关联子查询性能提升巨大（对比其他数据库几乎都没实现此优化）。优化器善于将子查询展开（unnesting）为 JOIN。",
        "window-functions/oracle": "**Oracle 8i 首创窗口函数（业界最早，1999 年）**——RATIO_TO_REPORT 直接计算占比（独有）、KEEP(DENSE_RANK FIRST/LAST) 获取极值关联列（独有）、IGNORE NULLS 选项。对比 PG 8.4（2009 年）、MySQL 8.0（2018 年）支持时间远晚于 Oracle。窗口函数种类和优化成熟度行业领先。",
        # Scenarios
        "date-series-fill/oracle": "**无 generate_series，需 CONNECT BY LEVEL 模拟**——`SELECT TRUNC(SYSDATE) - LEVEL + 1 FROM DUAL CONNECT BY LEVEL <= 30` 是 Oracle 独有的序列生成技巧。对比 PG 的 generate_series 一行搞定、BigQuery 的 GENERATE_DATE_ARRAY 更直观。CONNECT BY 本为层级查询设计，用于序列生成是创造性用法。",
        "deduplication/oracle": "**ROW_NUMBER + ROWID 直接定位物理行**——可以用 ROWID 精确定位并删除重复行，效率高于重建表。DELETE WHERE ROWID NOT IN (SELECT MIN(ROWID) FROM t GROUP BY key) 是经典去重写法。对比 PG 的 DISTINCT ON 更简洁、BigQuery 的 QUALIFY 无需子查询。",
        "gap-detection/oracle": "**窗口函数 + CONNECT BY LEVEL 填充序列检测间隙**——LAG/LEAD 比较相邻行，CONNECT BY LEVEL 生成完整序列 LEFT JOIN 检测缺失。对比 PG 的 generate_series 方案更直观、ClickHouse 的 WITH FILL 自动填充最简洁。",
        "hierarchical-query/oracle": "**CONNECT BY 是层级查询的原创语法（Oracle 独有）**——`START WITH parent_id IS NULL CONNECT BY PRIOR id = parent_id` 比递归 CTE 更简洁。SYS_CONNECT_BY_PATH 生成路径字符串、CONNECT_BY_ROOT 获取根节点、LEVEL 伪列获取深度——这些辅助功能递归 CTE 需额外计算。对比标准递归 CTE 更通用但更冗长。",
        "json-flatten/oracle": "**JSON_TABLE（12c+）是最早支持 SQL 标准 JSON 表化的实现**——将 JSON 数据映射为关系表行列。23ai 的 Duality View 实现关系-文档双视图（独有创新）——同一数据既可以 SQL 查询也可以 JSON API 访问。对比 PG 的 JSONB+GIN 索引查询更强、Snowflake 的 FLATTEN 语法更简洁。",
        "migration-cheatsheet/oracle": "**迁移极难的三大原因：`''=NULL` 行为差异（无数应用依赖）、DDL 自动提交不可回滚、PL/SQL Package 大量存量代码**。FROM DUAL 要求（23ai 才可省略）。NUMBER 万能类型→目标库需精确映射。CONNECT BY→递归 CTE 重写。Oracle 兼容性是国产数据库的主要赛道。",
        "ranking-top-n/oracle": "**FETCH FIRST WITH TIES（12c+）包含排名并列行**——对比标准 LIMIT 可能截断同分行。12c 前经典写法：`SELECT * FROM (SELECT t.*, ROWNUM rn FROM (query ORDER BY...) t WHERE ROWNUM <= N) WHERE rn >= M`（ROWNUM 三层嵌套）。ROW_NUMBER 窗口函数是通用方案。",
        "running-total/oracle": "**窗口函数 + MODEL 子句可做更复杂的行间计算**——MODEL 子句（10g+）将结果集当作电子表格操作，可定义单元格间的计算规则（对比所有其他数据库均无此能力）。标准 SUM() OVER 满足常规累计求和。Oracle 的窗口函数优化器最成熟（8i 首创）。",
        "slowly-changing-dim/oracle": "**MERGE 多分支 + Flashback 历史查询是 Oracle SCD 的完整方案**——MERGE WHEN MATCHED/WHEN NOT MATCHED 实现 Type 1/Type 2 SCD。Flashback Query 可查询过去某时刻数据辅助验证变更正确性。对比 SQL Server 的 Temporal Tables 自动维护历史版本、BigQuery/Snowflake 的 Time Travel。",
        "string-split-to-rows/oracle": "**无原生 split 函数，需 CONNECT BY + REGEXP_SUBSTR 技巧**——`SELECT REGEXP_SUBSTR(str, '[^,]+', 1, LEVEL) FROM DUAL CONNECT BY LEVEL <= REGEXP_COUNT(str, ',') + 1` 是经典但晦涩的写法。对比 PG 14 的 string_to_table 一行搞定、SQL Server 的 STRING_SPLIT，Oracle 方案最繁琐。",
        "window-analytics/oracle": "**窗口函数种类最多、优化最成熟**——RATIO_TO_REPORT 直接计算占比（独有）、MODEL 子句做电子表格式计算（独有）、KEEP(DENSE_RANK) 获取极值关联列（独有）。ROWS/RANGE 帧支持完整。对比 PG 有 FILTER 子句（Oracle 无）、BigQuery/DuckDB 有 QUALIFY（Oracle 无）。",
        # Types
        "array-map-struct/oracle": "**VARRAY + 嵌套表 + OBJECT TYPE 构成 PL/SQL 集合类型体系**——VARRAY 定长数组、嵌套表变长集合、OBJECT TYPE 自定义对象类型（面向对象特性）。但 SQL 层使用复合类型不如 PG 的原生 ARRAY 或 BigQuery 的 STRUCT 直观。TABLE() 函数将集合转为关系行集。",
        "datetime/oracle": "**DATE 类型含时间到秒级容易混淆**——Oracle 的 DATE 等于其他数据库的 DATETIME（含时分秒），不是纯日期（对比 PG/MySQL 的 DATE 只有年月日）。TIMESTAMP 提供更高精度（纳秒）。INTERVAL YEAR TO MONTH / DAY TO SECOND 两种间隔类型完善（对比 PG 的单一 INTERVAL 更灵活）。",
        "json/oracle": "**JSON_TABLE 是最早的标准实现（12c+），Duality View（23ai）是最新创新**——Duality View 让同一数据同时以关系表和 JSON 文档两种视角访问，是行业首创。对比 PG 的 JSONB+GIN 索引查询性能最强、Snowflake 的 VARIANT 半结构化存储更灵活。Oracle 的 JSON 支持从追赶到创新。",
        "numeric/oracle": "**NUMBER 万能类型是 Oracle 的历史设计选择**——不区分整数/浮点/定点，`NUMBER(10)` 是 10 位整数、`NUMBER(10,2)` 是定点小数、`NUMBER` 不限精度。内部变长十进制存储保证精确但存储效率低于定长整数类型。对比 PG 的 INTEGER/BIGINT/NUMERIC 分级更清晰、BigQuery 的 INT64 单一整数更极简。",
        "string/oracle": "**`''=NULL` 是 45 年历史包袱，是 Oracle 迁移最大痛点**——所有依赖空字符串的逻辑在迁出 Oracle 时都需要审查。VARCHAR2(N) 默认字节语义——中文可能只存 N/3 个字符，需显式 `VARCHAR2(N CHAR)` 指定字符语义。VARCHAR2 最大 4000/32767 字节（取决于 MAX_STRING_SIZE 参数）。",
    },
}

# I'll apply these via a simpler mechanism - just print the file content
# But given the scale, let me use a different approach for the remaining files

if __name__ == "__main__":
    print("Script for reference only - actual edits done via Edit tool")
