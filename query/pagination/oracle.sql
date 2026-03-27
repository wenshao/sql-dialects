-- Oracle: 分页 (Pagination)
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Row Limiting Clause
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html
--   [2] Oracle SQL Language Reference - ROWNUM Pseudocolumn
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/ROWNUM-Pseudocolumn.html

-- ============================================================
-- 1. 12c+ 标准语法: OFFSET / FETCH（推荐）
-- ============================================================

SELECT * FROM users ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 取前 N 行
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- 百分比
SELECT * FROM users ORDER BY id FETCH FIRST 10 PERCENT ROWS ONLY;

-- WITH TIES（包含排序值相同的行）
SELECT * FROM users ORDER BY age FETCH FIRST 10 ROWS WITH TIES;

-- ============================================================
-- 2. ROWNUM 分页（Pre-12c，Oracle 最经典的陷阱）
-- ============================================================

-- ROWNUM 的致命设计缺陷:
-- ROWNUM 在 WHERE 评估阶段分配，在 ORDER BY 之前!
-- 这意味着:
SELECT * FROM users WHERE ROWNUM <= 10 ORDER BY id;
-- 先随机取 10 行，再排序 -- 结果不是 "id 最小的 10 行"!

-- 正确写法: 三层嵌套（Oracle 分页的经典模式）
SELECT * FROM (
    SELECT t.*, ROWNUM AS rn FROM (
        SELECT * FROM users ORDER BY id      -- 最内层: 排序
    ) t
    WHERE ROWNUM <= 30                        -- 中间层: 上界
)
WHERE rn > 20;                                -- 最外层: 下界

-- 设计分析:
--   ROWNUM 在 WHERE 前分配的设计源于 Oracle 的执行模型:
--   每次 fetch 一行时分配 ROWNUM，如果 WHERE 不满足则丢弃重新 fetch。
--   这意味着 ROWNUM > N 永远为 false（因为第一行的 ROWNUM 是 1，
--   如果条件是 ROWNUM > 5，第一行不满足被丢弃，下一行又是 ROWNUM=1...）
--
--   SELECT * FROM users WHERE ROWNUM > 5;  -- 永远返回 0 行!
--
--   这是数据库历史上最著名的设计陷阱之一。
--   12c 的 FETCH FIRST 语法正是为了解决这个问题。
--
-- 横向对比:
--   Oracle <12c: 三层嵌套 ROWNUM（最复杂）
--   Oracle 12c+: OFFSET ... FETCH（SQL 标准）
--   MySQL:       LIMIT offset, count（最简单）
--   PostgreSQL:  LIMIT count OFFSET offset（简单）
--   SQL Server:  OFFSET ... FETCH（2012+，同 Oracle 12c）
--                TOP N ... ORDER BY（旧语法）
--
-- 对引擎开发者的启示:
--   LIMIT/OFFSET 是用户最常用的功能之一，必须语法简单。
--   Oracle 的 ROWNUM 教训: 伪列与 ORDER BY 的交互必须有明确语义。
--   推荐: 直接实现 LIMIT/OFFSET 或 FETCH FIRST 语法，避免 ROWNUM 式设计。

-- ============================================================
-- 3. ROW_NUMBER() 分页（8i+，分析函数方式）
-- ============================================================

SELECT * FROM (
    SELECT u.*, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users u
) t
WHERE rn BETWEEN 21 AND 30;

-- 这种方式比 ROWNUM 更直观，但仍需要子查询包装。
-- Oracle 优化器可以将 ROW_NUMBER + WHERE rn <= N 优化为 Top-N 排序。

-- ============================================================
-- 4. Keyset 分页（游标分页，高性能方案）
-- ============================================================

-- 传统 OFFSET 分页的问题: OFFSET 越大性能越差（需要跳过 N 行）
-- Keyset 分页: 基于上一页最后一行的值定位

-- 第一页
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- 下一页（假设上一页最后的 id 是 10）
SELECT * FROM users WHERE id > 10 ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- Keyset 分页的优势:
--   性能恒定（不随页码增长），适合无限滚动场景。
--   所有数据库都支持（只是 WHERE + ORDER BY + LIMIT）。

-- ============================================================
-- 5. '' = NULL 对分页的影响
-- ============================================================

-- ORDER BY 中 NULL 的位置:
-- Oracle 默认: NULL 排在最后（ASC 时）
-- 可以用 NULLS FIRST / NULLS LAST 控制:
SELECT * FROM users ORDER BY bio NULLS FIRST FETCH FIRST 10 ROWS ONLY;

-- 由于 '' = NULL，空字符串会和 NULL 一起排到最后（或最前）
-- 这与其他数据库行为不同（其他数据库中 '' 排在 'a' 之前）

-- ============================================================
-- 6. 对引擎开发者的总结
-- ============================================================
-- 1. ROWNUM 是数据库设计史上最经典的语义陷阱，新引擎必须避免。
-- 2. 标准的 OFFSET/FETCH 或 LIMIT/OFFSET 应作为基本功能优先实现。
-- 3. 优化器应识别 ROW_NUMBER() + WHERE rn <= N 模式并优化为 Top-N 排序。
-- 4. Keyset 分页（WHERE id > last_id）性能恒定，引擎应确保这种查询走索引。
-- 5. WITH TIES 需要优化器在达到 N 行后继续检查排序键相同的行。
