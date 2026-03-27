-- SQL Server: DELETE
--
-- 参考资料:
--   [1] SQL Server T-SQL - DELETE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/delete-transact-sql
--   [2] SQL Server T-SQL - TRUNCATE TABLE
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/truncate-table-transact-sql

-- ============================================================
-- 1. 基本语法
-- ============================================================

DELETE FROM users WHERE username = 'alice';

-- TOP: 限制删除行数（SQL Server 独有的 DML TOP 语法）
DELETE TOP (100) FROM users WHERE status = 0;

-- 注意: DELETE TOP 不保证顺序——如果需要删除"前 100 条"，应用 CTE:
;WITH oldest AS (
    SELECT TOP (100) id FROM users WHERE status = 0 ORDER BY created_at
)
DELETE FROM users WHERE id IN (SELECT id FROM oldest);

-- ============================================================
-- 2. OUTPUT 子句: SQL Server 的 RETURNING（对引擎开发者）
-- ============================================================

-- OUTPUT 是 SQL Server 最独特的 DML 特性之一。
-- 它在 INSERT/UPDATE/DELETE/MERGE 中都可用——比 PostgreSQL 的 RETURNING 更强大。

-- 返回被删除的行
DELETE FROM users
OUTPUT deleted.id, deleted.username, deleted.email
WHERE status = 0;

-- OUTPUT INTO: 将删除的行直接插入另一个表（原子操作）
DELETE FROM users
OUTPUT deleted.* INTO users_archive
WHERE status = 0;

-- 设计分析（对引擎开发者）:
--   OUTPUT 子句的内部实现使用 deleted 和 inserted 伪表（与触发器共享机制）。
--   DELETE 中只有 deleted 表，INSERT 中只有 inserted 表，
--   UPDATE 中两者都有（deleted = 旧值, inserted = 新值）。
--
-- 横向对比:
--   PostgreSQL: RETURNING 子句（DELETE ... RETURNING id, username）
--               功能类似但没有 OUTPUT INTO（不能直接插入另一个表）
--   MySQL:      不支持 RETURNING（必须先 SELECT 再 DELETE，需要事务保证原子性）
--   Oracle:     RETURNING ... INTO（只能在 PL/SQL 中使用，不能直接返回结果集）
--
-- 对引擎开发者的启示:
--   OUTPUT INTO 解决了"删除并归档"的原子性问题。没有它，需要:
--   BEGIN TRAN; INSERT INTO archive SELECT * FROM t WHERE ...; DELETE FROM t WHERE ...; COMMIT;
--   这种两步操作有并发问题（两条语句之间可能有其他事务修改数据）。
--   OUTPUT INTO 在引擎内部保证原子性。

-- ============================================================
-- 3. JOIN 删除: FROM 子句（T-SQL 扩展语法）
-- ============================================================

-- SQL Server 使用独特的 FROM 子句实现 JOIN 删除:
DELETE u FROM users u
JOIN blacklist b ON u.email = b.email;

-- 这等价于:
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- 设计分析:
--   "DELETE alias FROM table alias JOIN ..." 是 T-SQL 独有语法。
--   第一个 alias 指定要删除哪个表的行（在多表 JOIN 中很重要）。
--
-- 横向对比:
--   PostgreSQL: DELETE FROM t USING other_table WHERE ...（USING 子句）
--   MySQL:      DELETE t FROM t JOIN other ON ...（类似 SQL Server）
--   Oracle:     不支持 JOIN 删除（必须用子查询或 PL/SQL）

-- ============================================================
-- 4. CTE + DELETE（SQL Server 特色）
-- ============================================================

-- SQL Server 允许直接在 CTE 上执行 DELETE——不需要子查询
;WITH inactive AS (
    SELECT id, username, last_login FROM users
    WHERE last_login < '2023-01-01'
)
DELETE FROM inactive;  -- 直接删 CTE 中的行

-- 这是 SQL Server 最优雅的删除方式:
-- CTE 可以包含窗口函数，用于去重等复杂场景
;WITH duplicates AS (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
)
DELETE FROM duplicates WHERE rn > 1;  -- 保留每个 email 的最新记录

-- ============================================================
-- 5. DELETE vs TRUNCATE（对引擎开发者）
-- ============================================================

DELETE FROM users;          -- 逐行删除，记录日志，触发触发器
TRUNCATE TABLE users;       -- 释放数据页，重置 IDENTITY

-- SQL Server TRUNCATE 的独特行为:
--   (1) 可以在事务中回滚（MySQL 的 TRUNCATE 不能回滚——隐式提交）
--   (2) 重置 IDENTITY 值（DELETE 不会）
--   (3) 不触发 DELETE 触发器
--   (4) 需要 ALTER 权限（不是 DELETE 权限）
--   (5) 2016+: 支持分区级 TRUNCATE
TRUNCATE TABLE orders WITH (PARTITIONS (3, 5));  -- 只清空指定分区

-- 横向对比:
--   MySQL:      TRUNCATE 隐式提交事务，不能回滚
--   PostgreSQL: TRUNCATE 是事务性的（可回滚），支持级联 CASCADE
--   Oracle:     TRUNCATE 隐式提交，不能回滚
--
-- 对引擎开发者的启示:
--   TRUNCATE 的核心实现区别: 是释放整个数据段/页（O(1)），还是逐行删除（O(n)）。
--   SQL Server 的 TRUNCATE 是页释放操作，但记录了足够的日志信息以支持回滚。
--   这是比 MySQL/Oracle 更好的设计——兼顾了性能和事务安全。

-- ============================================================
-- 6. 大批量删除的最佳实践
-- ============================================================

-- 大表删除应分批进行，避免长时间持有锁和日志膨胀
DECLARE @batch INT = 10000;
WHILE 1 = 1
BEGIN
    DELETE TOP (@batch) FROM logs WHERE created_at < '2023-01-01';
    IF @@ROWCOUNT < @batch BREAK;
    -- 可选: WAITFOR DELAY '00:00:01';  -- 给其他事务喘息空间
END;

-- 对引擎开发者的启示:
--   大批量删除是数据库运维的经典问题。
--   理想的引擎应该在内部实现分批删除（如 Oracle 的 DBMS_PARALLEL_EXECUTE），
--   而不是让用户写循环。分区表的 TRUNCATE PARTITION 是最佳方案。
