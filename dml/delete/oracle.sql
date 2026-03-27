-- Oracle: DELETE
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - DELETE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/DELETE.html
--   [2] Oracle SQL Language Reference - TRUNCATE TABLE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/TRUNCATE-TABLE.html

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 关联子查询删除
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = u.email);

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- RETURNING（PL/SQL 中获取被删除行的值）
DECLARE v_id NUMBER;
BEGIN
    DELETE FROM users WHERE username = 'alice' RETURNING id INTO v_id;
    DBMS_OUTPUT.PUT_LINE('Deleted user id: ' || v_id);
END;
/

-- ============================================================
-- 2. Oracle 独有的删除方式
-- ============================================================

-- 2.1 ROWNUM 限制删除行数（所有版本）
DELETE FROM users WHERE status = 0 AND ROWNUM <= 100;

-- 注意 ROWNUM 的陷阱: ROWNUM 在 WHERE 评估时分配，不与 ORDER BY 配合。
-- 上面的语句删除"满足条件的前 100 行"，但不保证是哪 100 行。
--
-- 如果要删除"按时间排序的前 100 行":
DELETE FROM (
    SELECT * FROM users WHERE status = 0 ORDER BY created_at
    FETCH FIRST 100 ROWS ONLY                  -- 12c+
);

-- 12c 之前的写法:
DELETE FROM users WHERE ROWID IN (
    SELECT ROWID FROM (
        SELECT ROWID FROM users WHERE status = 0 ORDER BY created_at
    ) WHERE ROWNUM <= 100
);

-- 横向对比:
--   Oracle:     ROWNUM（在 WHERE 前分配）或 FETCH FIRST (12c+)
--   MySQL:      DELETE ... ORDER BY ... LIMIT n（语法最直观）
--   PostgreSQL: DELETE ... WHERE ctid IN (SELECT ctid ... LIMIT n)
--   SQL Server: DELETE TOP (n) ... 或 CTE + ROW_NUMBER

-- 2.2 批量删除（大表删除的 Oracle 最佳实践）
-- 大表直接 DELETE 会生成大量 undo/redo，可能撑满回滚段。
-- Oracle 经典的分批删除模式:
BEGIN
    LOOP
        DELETE FROM logs WHERE log_date < SYSDATE - 90 AND ROWNUM <= 10000;
        EXIT WHEN SQL%ROWCOUNT = 0;
        COMMIT;  -- 每批提交，释放 undo 空间
    END LOOP;
    COMMIT;
END;
/

-- ============================================================
-- 3. TRUNCATE TABLE
-- ============================================================

DELETE FROM users;                             -- 逐行删除，可回滚
TRUNCATE TABLE users;                          -- 瞬间清空，不可回滚

-- TRUNCATE 的本质:
--   DDL 操作（不是 DML），隐式 COMMIT
--   重置高水位线（High Water Mark），回收存储空间
--   不触发 DELETE 触发器
--   不记录逐行 undo（只记录 extent 级信息）

-- 12c+: 级联截断
TRUNCATE TABLE orders CASCADE;                 -- 级联截断引用此表的子表

-- 横向对比:
--   Oracle:     TRUNCATE 是 DDL，隐式提交，CASCADE (12c+)
--   PostgreSQL: TRUNCATE 可以在事务中回滚!（DDL 事务性）
--   MySQL:      TRUNCATE 是 DDL，隐式提交（同 Oracle）
--   SQL Server: TRUNCATE 可以在事务中回滚（同 PostgreSQL）

-- ============================================================
-- 4. Flashback: 恢复误删数据（Oracle 独有杀手级特性）
-- ============================================================

-- 4.1 Flashback Query: 查询历史时间点的数据
SELECT * FROM users AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR);
SELECT * FROM users AS OF SCN 123456789;

-- 4.2 恢复误删数据
INSERT INTO users
SELECT * FROM users AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR)
WHERE id NOT IN (SELECT id FROM users);

-- 4.3 Flashback Table: 整表恢复到某个时间点
FLASHBACK TABLE users TO TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR);

-- 4.4 Flashback Drop: 从回收站恢复删除的表
DROP TABLE users;                              -- 表进入回收站
FLASHBACK TABLE users TO BEFORE DROP;          -- 从回收站恢复

-- 设计分析:
--   Flashback 基于 Undo 段中的历史数据（不是备份）。
--   Undo 保留时间由 UNDO_RETENTION 参数控制（默认 900 秒）。
--   超过保留期的数据可能被覆盖（ORA-01555: snapshot too old）。
--
-- 横向对比:
--   Oracle:     Flashback 系列（最完善的历史数据查询能力）
--   PostgreSQL: 无原生 Flashback（需要依赖 PITR 备份恢复）
--   MySQL:      无原生 Flashback（需要 binlog 回放）
--   SQL Server: Temporal Tables (2016+)（类似但面向审计而非恢复）
--
-- 对引擎开发者的启示:
--   Flashback 的核心是 MVCC 的 Undo 日志复用:
--   正常的 MVCC 读一致性 + 时间点查询 共享同一套 Undo 机制。
--   实现成本低（已有 Undo 基础设施），用户价值高（误操作恢复）。
--   新引擎如果已经实现了 MVCC，应该考虑暴露历史版本查询接口。

-- ============================================================
-- 5. '' = NULL 对 DELETE 的影响
-- ============================================================

-- 删除空字符串行:
DELETE FROM users WHERE bio = '';
-- 注意: 这在 Oracle 中不会删除任何行!
-- 因为 '' = NULL，上面等于 WHERE bio = NULL，而 NULL = NULL 是 UNKNOWN

-- 正确做法:
DELETE FROM users WHERE bio IS NULL;
-- 但这也会删除真正的 NULL 行（Oracle 中无法区分 '' 和 NULL）

-- ============================================================
-- 6. 对引擎开发者的总结
-- ============================================================
-- 1. ROWNUM 在 WHERE 前分配是 Oracle 最经典的陷阱，12c 的 FETCH FIRST 解决了这个问题。
-- 2. Flashback 是 MVCC Undo 日志的高价值复用，实现成本低但用户价值极高。
-- 3. TRUNCATE 的事务性在不同数据库间有本质差异（DDL 事务性问题的缩影）。
-- 4. 大表删除应分批进行，Oracle 的 ROWNUM + LOOP + COMMIT 是经典模式。
