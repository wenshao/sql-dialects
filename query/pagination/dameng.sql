-- DamengDB (达梦): 分页 (Pagination)
-- Oracle 兼容语法。
--
-- 参考资料:
--   [1] 达梦 SQL 语言使用指南 - SELECT
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] 达梦 DBA 管理手册
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html
--   [3] 达梦 SQL 程序设计 - 游标
--       https://eco.dameng.com/document/dm/zh-cn/plsql/index.html

-- ============================================================
-- 1. FETCH FIRST（SQL 标准语法，推荐）
-- ============================================================

-- SQL 标准 OFFSET / FETCH 语法（推荐使用）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- FETCH NEXT（等价于 FETCH FIRST）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 仅取前 N 行（标准语法）
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- FETCH FIRST with PERCENT（取前 N% 的行）
SELECT * FROM users ORDER BY age DESC FETCH FIRST 10 PERCENT ROWS ONLY;

-- ============================================================
-- 2. TOP 语法（达梦扩展，类似 SQL Server）
-- ============================================================

-- TOP N（取前 N 行，不支持跳过）
SELECT TOP 10 * FROM users ORDER BY id;

-- TOP with PERCENT
SELECT TOP 10 PERCENT * FROM users ORDER BY age;

-- 注意: TOP 不支持 OFFSET，如需跳过行请使用 FETCH FIRST

-- ============================================================
-- 3. ROWNUM（传统 Oracle 兼容方式）
-- ============================================================

-- ROWNUM 分页（经典 Oracle 写法，三层嵌套）
SELECT * FROM (
    SELECT t.*, ROWNUM AS rn FROM (
        SELECT * FROM users ORDER BY id
    ) t WHERE ROWNUM <= 30
) WHERE rn > 20;

-- ROWNUM 的陷阱:
--   WHERE ROWNUM > 10 永远返回空！
--   原因: ROWNUM 在 WHERE 过滤之前分配
--     第 1 行: ROWNUM = 1，> 10 不满足，被过滤
--     第 2 行: 仍然 ROWNUM = 1（因为前一行被过滤了），> 10 不满足
--     所有行都被过滤，结果为空
--   正确写法: 先在外层赋值 ROWNUM，再在外层过滤

-- ============================================================
-- 4. LIMIT 语法（MySQL 兼容模式）
-- ============================================================

-- 在 MySQL 兼容模式下，达梦也支持 LIMIT 语法
-- 设置兼容模式: ALTER SESSION SET COMPATIBLE_MODE = 4;
-- SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 注意: 默认模式下不支持 LIMIT 语法

-- ============================================================
-- 5. OFFSET 的性能问题
-- ============================================================

-- 大 OFFSET 的性能瓶颈:
--   即使有索引，仍需遍历索引叶子节点 OFFSET 次
--   时间复杂度: O(OFFSET + LIMIT)
--   达梦优化器会对 ORDER BY + FETCH FIRST 进行 Top-N 优化
--   但 OFFSET 的 O(N) 问题无法从优化器层面解决
--
-- 建议:
--   小数据量（< 10 万行）: FETCH FIRST / OFFSET 可用
--   大数据量: 推荐使用键集分页

-- ============================================================
-- 6. 键集分页（Keyset Pagination）: 高性能替代方案
-- ============================================================

-- 第一页
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- 后续页（已知上一页最后一条 id = 100）
SELECT * FROM users WHERE id > 100 ORDER BY id
FETCH FIRST 10 ROWS ONLY;
-- 时间复杂度: O(log n + limit)，与页码无关

-- 多列排序的键集分页
SELECT * FROM users
WHERE created_at > TO_DATE('2025-01-01', 'YYYY-MM-DD')
   OR (created_at = TO_DATE('2025-01-01', 'YYYY-MM-DD') AND id > 100)
ORDER BY created_at, id
FETCH FIRST 10 ROWS ONLY;

-- ============================================================
-- 7. 窗口函数辅助分页
-- ============================================================

-- ROW_NUMBER 分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 分组后 Top-N
SELECT * FROM (
    SELECT username, city, age,
        ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

-- ============================================================
-- 8. 服务端游标（DMPL/SQL 中使用）
-- ============================================================

-- 在存储过程中使用游标分页
-- DECLARE
--   CURSOR user_cur IS SELECT * FROM users ORDER BY id;
--   v_user users%ROWTYPE;
-- BEGIN
--   OPEN user_cur;
--   LOOP
--     FETCH user_cur INTO v_user;
--     EXIT WHEN user_cur%NOTFOUND;
--     -- 逐行处理
--   END LOOP;
--   CLOSE user_cur;
-- END;

-- ============================================================
-- 9. DamengDB 特有说明
-- ============================================================

-- 达梦的多种分页语法:
--   FETCH FIRST:  推荐使用（SQL 标准）
--   TOP:          达梦扩展（类似 SQL Server）
--   ROWNUM:       Oracle 兼容（传统方式，不推荐新代码使用）
--   LIMIT:        MySQL 兼容模式下支持
--
-- 达梦与 Oracle 的分页兼容性:
--   ROWNUM:          完全兼容
--   FETCH FIRST:     达梦支持（Oracle 12c+ 也支持）
--   Top-N 查询:      达梦支持 TOP（Oracle 不支持 TOP）

-- ============================================================
-- 10. 版本演进
-- ============================================================
-- Dameng V7:   ROWNUM + FETCH FIRST + TOP
-- Dameng V8:   增强优化器，窗口函数性能优化
-- DM8:         MySQL 兼容模式，LIMIT 支持

-- ============================================================
-- 11. 横向对比: 分页语法差异
-- ============================================================

-- 语法对比:
--   DamengDB:   FETCH FIRST + TOP + ROWNUM（最多语法选项）
--   Oracle:     FETCH FIRST (12c+) / ROWNUM（传统）/ TOP（不支持）
--   SQL Server: TOP + OFFSET-FETCH (2012+)
--   PostgreSQL: LIMIT / OFFSET + FETCH FIRST
--
-- 兼容模式对比:
--   达梦默认模式:     FETCH FIRST + TOP + ROWNUM
--   达梦 Oracle 模式: ROWNUM + FETCH FIRST（兼容 Oracle 应用）
--   达梦 MySQL 模式:  LIMIT / OFFSET（兼容 MySQL 应用迁移）
