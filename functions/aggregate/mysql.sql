-- MySQL: 聚合函数
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - Aggregate Functions
--       https://dev.mysql.com/doc/refman/8.0/en/aggregate-functions.html
--   [2] MySQL 8.0 Reference Manual - GROUP BY Handling
--       https://dev.mysql.com/doc/refman/8.0/en/group-by-handling.html
--   [3] MySQL 8.0 Reference Manual - Server SQL Modes
--       https://dev.mysql.com/doc/refman/8.0/en/sql-mode.html

-- ============================================================
-- 1. 基本聚合语法
-- ============================================================
SELECT COUNT(*) FROM users;                          -- 总行数（含 NULL）
SELECT COUNT(email) FROM users;                      -- 非 NULL 行数
SELECT COUNT(DISTINCT city) FROM users;              -- 去重计数
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount), MAX(amount) FROM orders;

-- GROUP BY + HAVING
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city
HAVING cnt > 10;

-- GROUP BY 位置引用（MySQL 扩展，非 SQL 标准）
SELECT city, COUNT(*) FROM users GROUP BY 1;         -- 按第 1 列分组

-- WITH ROLLUP: 层级汇总
SELECT city, COUNT(*) FROM users GROUP BY city WITH ROLLUP;
-- 结果最后一行: city=NULL, COUNT(*)=总数（超级聚合行）

-- ============================================================
-- 2. ONLY_FULL_GROUP_BY: 一个重要的设计决策（对引擎开发者）
-- ============================================================

-- 2.1 问题背景
-- 以下查询在 5.7.5 之前是合法的:
--   SELECT city, username, COUNT(*) FROM users GROUP BY city;
-- username 不在 GROUP BY 中，也不在聚合函数中 → 结果是不确定的！
-- MySQL 会从每组中随机返回一个 username（实际上是存储引擎碰巧先读到的值）
-- 这违反了 SQL 标准，但 MySQL 出于 "灵活性" 允许了它。

-- 2.2 ONLY_FULL_GROUP_BY 模式（5.7.5+ 默认启用）
-- 启用后，非聚合列必须出现在 GROUP BY 中，否则报错:
--   ERROR 1055: Expression #2 of SELECT list is not in GROUP BY clause
-- 这是 MySQL 向 SQL 标准靠拢的重要一步。
--
-- 例外: 函数依赖 (Functional Dependency)
-- 如果 GROUP BY 包含主键，则该表的其他列允许出现在 SELECT 中:
SELECT users.id, users.username, users.city, COUNT(orders.id)
FROM users LEFT JOIN orders ON users.id = orders.user_id
GROUP BY users.id;
-- 合法: users.id 是主键，username 和 city 函数依赖于 id

-- 2.3 ANY_VALUE() 函数: 显式声明"我知道这是不确定的"
SELECT city, ANY_VALUE(username) AS sample_user, COUNT(*)
FROM users GROUP BY city;
-- ANY_VALUE 告诉 MySQL: 从组内任意取一个值，我接受不确定性

-- 2.4 对引擎开发者的启示
-- 关闭 ONLY_FULL_GROUP_BY 导致的问题:
--   1. 查询结果不可复现（不同执行计划可能返回不同的 username）
--   2. 应用层基于不确定数据做决策 → 隐蔽的 bug
--   3. 大量遗留代码依赖这个宽松行为 → 升级到 5.7.5+ 后大规模报错
--
-- 设计教训:
--   宽松模式看似"用户友好"，实则积累技术债务。
--   PostgreSQL 从一开始就拒绝非标准 GROUP BY → 没有这个历史包袱。
--   如果要实现宽松模式，应通过 ANY_VALUE() 这样的显式 opt-in 机制。
--
-- 横向对比:
--   PostgreSQL: 一直强制 FULL_GROUP_BY，9.1+ 支持函数依赖推导
--   Oracle:     一直强制 FULL_GROUP_BY
--   SQL Server: 一直强制 FULL_GROUP_BY
--   SQLite:     默认宽松（选择 min/max 行的非聚合列有定义行为 — 这是 SQLite 的特色）
--   ClickHouse: 宽松模式（选择任意值），但这在分析场景中通常可接受

-- ============================================================
-- 3. GROUP_CONCAT: 默认截断问题
-- ============================================================

-- 3.1 基本用法
SELECT city, GROUP_CONCAT(username ORDER BY username SEPARATOR ', ')
FROM users GROUP BY city;

-- 去重
SELECT GROUP_CONCAT(DISTINCT city ORDER BY city SEPARATOR ' | ') FROM users;

-- 3.2 默认截断: group_concat_max_len = 1024 字节
-- 超过 1024 字节的结果被静默截断！不报错，只产生 warning。
-- 这是生产事故的常见来源:
--   场景: 拼接用户 ID 列表 → 前 1024 字节正常，后面的 ID 丢失
--   后果: 基于截断结果的下游查询遗漏数据
--
-- 调整方式:
SET SESSION group_concat_max_len = 1048576;  -- 调到 1MB
SET GLOBAL group_concat_max_len = 1048576;   -- 全局生效
-- 最大值: 受 max_allowed_packet 限制

-- 3.3 为什么默认 1024？
-- MySQL 设计者的考虑: GROUP_CONCAT 结果存在内存临时表中，
-- 无限增长可能导致 OOM。1024 是保守的安全阈值。
-- 但"静默截断"而非报错是错误的设计选择 -- 应该像 SQL Server 的
-- STRING_AGG 一样在超过限制时报错或至少默认为更大的值。

-- 3.4 横向对比: 字符串聚合函数
--   MySQL:      GROUP_CONCAT(...  SEPARATOR ',')     5.7+
--               默认 1024 截断，需要手动调大
--   PostgreSQL: STRING_AGG(col, ',')                  9.0+
--               无长度限制（受内存限制）
--               支持 WITHIN GROUP 和 ORDER BY
--   Oracle:     LISTAGG(col, ',') WITHIN GROUP (ORDER BY col)   11gR2+
--               默认截断为 4000 字节（VARCHAR2 限制）
--               12c+: ON OVERFLOW TRUNCATE/ERROR 显式控制
--   SQL Server: STRING_AGG(col, ',')                  2017+
--               最大 8000/NVARCHAR(MAX) 字节
--               WITHIN GROUP (ORDER BY ...) 控制顺序
--   BigQuery:   STRING_AGG(col, ',' ORDER BY col)
--               无显式长度限制
--   ClickHouse: groupArray(col) → 返回数组，arrayStringConcat 转字符串
--               groupConcat(col, ',') (24.3+)
--   Snowflake:  LISTAGG(col, ',') WITHIN GROUP (ORDER BY col)
--               与 Oracle 语法兼容
--
-- 对引擎开发者的启示:
--   1. 字符串聚合是高频需求，必须内置支持
--   2. 不要静默截断 -- 数据丢失比内存溢出更严重
--   3. STRING_AGG 是 SQL 标准方向（SQL:2016），建议优先实现

-- ============================================================
-- 4. JSON 聚合 (5.7.22+)
-- ============================================================
SELECT JSON_ARRAYAGG(username) FROM users;
-- 结果: ["alice", "bob", "charlie"]

SELECT JSON_OBJECTAGG(username, age) FROM users;
-- 结果: {"alice": 25, "bob": 30, "charlie": 28}
-- 注意: 键重复时行为未定义（实际保留最后一个值）

-- 横向对比:
--   PostgreSQL: json_agg(row) / jsonb_agg(col)，更灵活（可聚合整行）
--   SQL Server: FOR JSON PATH（不是聚合函数，而是输出格式）
--   Oracle:     JSON_ARRAYAGG / JSON_OBJECTAGG（19c+）
--   BigQuery:   TO_JSON_STRING + ARRAY_AGG

-- ============================================================
-- 5. 统计聚合和 BIT 聚合
-- ============================================================
-- 统计
SELECT STD(amount) FROM orders;       -- 标准差（总体）
SELECT STDDEV_SAMP(amount) FROM orders; -- 标准差（样本，SQL 标准名）
SELECT VARIANCE(amount) FROM orders;  -- 方差（总体）
SELECT VAR_SAMP(amount) FROM orders;  -- 方差（样本）

-- BIT 聚合: 按位运算
SELECT BIT_AND(flags) FROM settings;  -- 所有值按位与
SELECT BIT_OR(flags) FROM settings;   -- 所有值按位或
SELECT BIT_XOR(flags) FROM settings;  -- 所有值按位异或

-- ============================================================
-- 6. MySQL 不支持的聚合特性
-- ============================================================

-- 6.1 GROUPING SETS / CUBE（SQL 标准，MySQL 不支持）
-- PostgreSQL/Oracle/SQL Server 支持:
--   SELECT city, category, SUM(amount)
--   FROM orders GROUP BY GROUPING SETS ((city), (category), ());
-- MySQL 替代: 多个 GROUP BY + UNION ALL 模拟

-- 6.2 FILTER 子句（SQL 标准，MySQL 不支持）
-- PostgreSQL: SELECT COUNT(*) FILTER (WHERE age > 20) FROM users;
-- MySQL 替代: SELECT SUM(CASE WHEN age > 20 THEN 1 ELSE 0 END) FROM users;

-- 6.3 WITHIN GROUP 排序（MySQL 的 GROUP_CONCAT 用 ORDER BY 替代）
-- 标准: LISTAGG(col, ',') WITHIN GROUP (ORDER BY col)
-- MySQL: GROUP_CONCAT(col ORDER BY col SEPARATOR ',')

-- 横向对比:
--   MySQL:      不支持 GROUPING SETS, CUBE, FILTER
--   PostgreSQL: 全部支持（9.5+ GROUPING SETS, 9.4+ FILTER）
--   Oracle:     全部支持（GROUPING SETS 最早的实现）
--   SQL Server: 支持 GROUPING SETS / CUBE / ROLLUP
--   ClickHouse: 支持 WITH ROLLUP / WITH CUBE（21.1+）

-- ============================================================
-- 7. 版本演进与最佳实践
-- ============================================================
-- MySQL 5.7.5:  ONLY_FULL_GROUP_BY 默认启用
-- MySQL 5.7.22: JSON_ARRAYAGG / JSON_OBJECTAGG
-- MySQL 8.0:    窗口函数（与聚合函数结合: SUM() OVER()）
-- MySQL 8.0.31: INTERSECT / EXCEPT（集合操作，非聚合但相关）
--
-- 实践建议:
--   1. 不要关闭 ONLY_FULL_GROUP_BY -- 宽松模式是 bug 的温床
--   2. 使用 GROUP_CONCAT 前先设置 group_concat_max_len（至少 1MB）
--   3. 需要 GROUPING SETS 时考虑 WITH ROLLUP（MySQL 唯一原生支持的多维聚合）
--   4. 大数据量聚合考虑 COUNT(DISTINCT) 的内存开销 -- 基数很高时可能 OOM
--   5. ANY_VALUE() 比关闭 sql_mode 更好 -- 显式优于隐式
