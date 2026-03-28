-- Snowflake: DELETE
--
-- 参考资料:
--   [1] Snowflake SQL Reference - DELETE
--       https://docs.snowflake.com/en/sql-reference/sql/delete
--   [2] Snowflake SQL Reference - TRUNCATE TABLE
--       https://docs.snowflake.com/en/sql-reference/sql/truncate-table

-- ============================================================
-- 1. 基本语法
-- ============================================================

DELETE FROM users WHERE username = 'alice';

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- EXISTS 子查询
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = u.email);

-- USING 子句（多表删除，Snowflake 独有语法）
DELETE FROM users
USING blacklist
WHERE users.email = blacklist.email;

-- 多表 USING
DELETE FROM users
USING blacklist b, suspension s
WHERE users.email = b.email OR users.id = s.user_id;

-- CTE + DELETE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- 删除所有行
DELETE FROM users;

-- TRUNCATE（更快，重置统计信息）
TRUNCATE TABLE users;

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 DELETE 的微分区实现
-- Snowflake 的 DELETE 不是原地删除行（微分区不可变）:
--   (a) 扫描所有包含目标行的微分区
--   (b) 读取这些微分区的数据
--   (c) 过滤掉被删除的行
--   (d) 将剩余行写入新的微分区
--   (e) 原子替换元数据指向新分区
--
-- 这意味着:
--   - DELETE 的成本与受影响的微分区数量成正比（不是行数）
--   - 删除 1 行如果涉及 1 个微分区: 重写 ~500MB 数据
--   - 删除分散在 1000 个微分区中的 1000 行: 重写 ~500GB 数据!
--   - 对比 InnoDB: 删除 1 行只需标记 UNDO + 删除标志，非常快
--
-- 对比:
--   MySQL InnoDB: 标记删除（标记 + UNDO 日志），后台 purge 清理
--   PostgreSQL:   标记删除（dead tuple），VACUUM 清理
--   Oracle:       DELETE 写 UNDO，行标记删除
--   BigQuery:     DML 流式操作，内部 merge-on-read
--   Redshift:     标记删除，需要 VACUUM DELETE
--   Databricks:   Delta Lake 写 tombstone 文件，VACUUM 清理
--
-- 对引擎开发者的启示:
--   不可变文件存储的 DELETE 天然更昂贵（需要重写整个文件）。
--   优化策略: 延迟重写（标记 + 后台合并）或 merge-on-read。
--   Databricks Delta Lake 的 deletion vectors 是一个优化: 只记录被删行的位图，
--   读取时跳过，后台异步合并。Iceberg 的 positional deletes 类似。

-- 2.2 DELETE vs TRUNCATE
-- TRUNCATE 不逐行删除，而是直接释放所有微分区的元数据:
--   DELETE FROM users;   → 扫描所有分区 → 产生空的新分区 → 慢
--   TRUNCATE TABLE users; → 原子清除元数据指针 → 瞬时
-- 两者都支持 Time Travel 恢复（与 Oracle 不同: Oracle TRUNCATE 不可回退）
--
-- 对比:
--   MySQL:      TRUNCATE 重建表文件，不记录 binlog（不可回退）
--   PostgreSQL: TRUNCATE 是事务性的（可以 ROLLBACK）
--   Oracle:     TRUNCATE 不可回退（DDL 隐式提交）
--   Snowflake:  TRUNCATE 可通过 Time Travel 恢复（独特优势）

-- 2.3 USING 子句 vs 标准 SQL
-- USING 是 Snowflake/PostgreSQL 的 DELETE 扩展:
--   标准 SQL:  DELETE FROM t WHERE id IN (SELECT id FROM s)
--   USING:     DELETE FROM t USING s WHERE t.id = s.id
--   语义相同，USING 语法更简洁（避免子查询）
--
-- 对比:
--   PostgreSQL: 也支持 USING 语法
--   MySQL:      使用 JOIN 语法: DELETE t FROM t JOIN s ON t.id = s.id
--   Oracle:     不支持 USING/JOIN 删除，只能用子查询
--   SQL Server: DELETE FROM t FROM t JOIN s ON t.id = s.id

-- ============================================================
-- 3. Time Travel 恢复删除的数据
-- ============================================================

-- 查看 5 分钟前的数据（Time Travel）:
-- SELECT * FROM users AT(OFFSET => -300);

-- 从特定时间点恢复:
-- CREATE TABLE users_restored CLONE users AT(TIMESTAMP => '2024-01-15'::TIMESTAMP_NTZ);

-- UNDROP 恢复整个表:
-- DROP TABLE users;
-- UNDROP TABLE users;

-- 恢复特定查询之前的状态:
-- SELECT * FROM users BEFORE(STATEMENT => '<query_id>');

-- 对引擎开发者的启示:
--   Time Travel 使得 DELETE 成为"可逆操作"，极大降低了误操作风险。
--   传统数据库需要备份/binlog 才能恢复删除的数据（操作复杂、恢复慢）。
--   不可变微分区架构天然支持 Time Travel（旧分区保留，不立即物理删除）。

-- ============================================================
-- 4. CASE 条件删除
-- ============================================================
DELETE FROM users
WHERE CASE
    WHEN status = 0 AND last_login < '2023-01-01' THEN TRUE
    WHEN status = -1 THEN TRUE
    ELSE FALSE
END;

-- ============================================================
-- 横向对比: DELETE 能力矩阵
-- ============================================================
-- 能力            | Snowflake       | BigQuery     | PostgreSQL   | MySQL
-- 基本 DELETE     | 支持            | 支持         | 支持         | 支持
-- USING/JOIN 删除 | USING           | 不支持       | USING        | JOIN
-- CTE + DELETE    | 支持            | 支持         | 支持         | 不支持(8.0-)
-- TRUNCATE        | 支持(可恢复)    | 支持         | 支持(事务性) | 支持(不可逆)
-- 返回删除行      | 不支持          | 不支持       | RETURNING    | 不支持
-- 删除后恢复      | Time Travel     | 7天快照      | 无原生       | binlog
-- 软删除          | 应用层实现      | 应用层       | 应用层       | 应用层
-- LIMIT 删除      | 不支持          | 不支持       | 不支持       | 支持
