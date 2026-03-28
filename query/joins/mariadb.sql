-- MariaDB: JOIN
-- 与 MySQL 语法相同, 优化器差异导致执行计划不同
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - JOIN Syntax
--       https://mariadb.com/kb/en/join-syntax/

-- ============================================================
-- 1. 基本 JOIN 类型
-- ============================================================
SELECT u.username, o.amount
FROM users u INNER JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount
FROM users u LEFT JOIN orders o ON u.id = o.user_id;

SELECT u.username, o.amount
FROM users u RIGHT JOIN orders o ON u.id = o.user_id;

SELECT u.username, p.name
FROM users u CROSS JOIN products p;

-- 自然连接
SELECT * FROM users NATURAL JOIN user_profiles;

-- ============================================================
-- 2. MariaDB 优化器差异
-- ============================================================
-- MariaDB 10.x 的优化器从 MySQL 5.5 fork 后独立发展:
--   - Hash Join: MariaDB 使用 Block Nested Loop Hash (BNLH)
--     MySQL 8.0.18+: 引入真正的 Hash Join
--   - 子查询优化: MariaDB 10.0+ 引入 Semi-Join 优化
--     先于 MySQL 在某些 semi-join 策略上更激进
--   - 表消除 (Table Elimination): MariaDB 独有优化
--     LEFT JOIN 的右表如果只提供唯一键但不被使用, 自动消除
--   - 条件下推 (Condition Pushdown): MariaDB 对派生表的条件下推更早实现
--
-- 这些差异意味着: 相同的 JOIN 查询在 MariaDB 和 MySQL 上可能有不同的执行计划

-- ============================================================
-- 3. 表消除优化 (MariaDB 独有)
-- ============================================================
SELECT u.username FROM users u
LEFT JOIN departments d ON u.dept_id = d.id;
-- 如果 d.id 是主键且 SELECT 中不引用 d 的列:
-- MariaDB 优化器会自动消除 departments 表的访问
-- MySQL 仍然会扫描 departments 表
-- 这在复杂视图和 ORM 生成的查询中价值很大

-- ============================================================
-- 4. 系统版本表的 JOIN
-- ============================================================
-- 可以对系统版本表的历史数据做 JOIN
SELECT c.client, p.name, p.price
FROM contracts c
JOIN products FOR SYSTEM_TIME AS OF c.row_start p ON c.product_id = p.id;
-- 获取合同签订时的产品价格 (时间旅行 JOIN)

-- ============================================================
-- 5. 对引擎开发者: JOIN 优化器实现
-- ============================================================
-- MariaDB fork 后优化器独立发展的启示:
--   1. 表消除是低成本高回报的优化 (AST 阶段即可完成)
--   2. Hash Join 的实现路径: MariaDB 用 BNLH, MySQL 用独立 Hash Join operator
--   3. 分布式 JOIN: 选择 Broadcast Join vs Shuffle Join 是分布式引擎的核心决策
--   4. 统计信息质量直接影响 JOIN 顺序选择 (MariaDB 的 histogram 实现与 MySQL 不同)
