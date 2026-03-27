-- Oracle: 约束 (Constraints)
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Constraints
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/constraint.html
--   [2] Oracle Database Concepts - Data Integrity
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/cncpt/data-integrity.html

-- ============================================================
-- 1. 基本约束类型
-- ============================================================

-- PRIMARY KEY
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);

-- UNIQUE
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

-- FOREIGN KEY
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE;

-- NOT NULL（Oracle 中 NOT NULL 是 CHECK 约束的语法糖）
ALTER TABLE users MODIFY (email NOT NULL);
ALTER TABLE users MODIFY (email NULL);          -- 去除 NOT NULL

-- CHECK
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE events ADD CONSTRAINT chk_dates CHECK (end_date > start_date);

-- DEFAULT
ALTER TABLE users MODIFY (status DEFAULT 1);

-- ============================================================
-- 2. 约束设计决策分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 ON DELETE vs ON UPDATE: Oracle 的不完整外键支持
-- Oracle 的 FOREIGN KEY 有一个显著限制: 不支持 ON UPDATE CASCADE/SET NULL
-- ON DELETE: 支持 CASCADE / SET NULL / NO ACTION（默认）
-- ON UPDATE: 只有隐式的 RESTRICT 行为（不支持 CASCADE）
--
-- 横向对比:
--   Oracle:     ON DELETE (CASCADE|SET NULL)，无 ON UPDATE
--   PostgreSQL: ON DELETE + ON UPDATE，都支持 CASCADE/SET NULL/SET DEFAULT/RESTRICT/NO ACTION
--   MySQL:      ON DELETE + ON UPDATE，都完整支持
--   SQL Server: ON DELETE + ON UPDATE，都完整支持
--
-- 为什么 Oracle 不支持 ON UPDATE CASCADE?
--   Oracle 的设计哲学: 主键一旦确定不应修改（surrogate key 不需要更新）。
--   如果需要 ON UPDATE CASCADE 的效果，Oracle 要求用触发器实现。
--
-- 对引擎开发者的启示:
--   ON UPDATE CASCADE 的实现需要级联更新检测和循环依赖检测，
--   复杂度比 ON DELETE CASCADE 高。Oracle 选择不支持是工程权衡，
--   但现代引擎应完整实现 SQL 标准的外键行为。

-- 2.2 可延迟约束: Oracle 的独特能力
-- Oracle 支持 DEFERRABLE 约束，允许在事务提交时才检查约束
ALTER TABLE orders ADD CONSTRAINT fk_orders_user2
    FOREIGN KEY (user_id) REFERENCES users (id)
    DEFERRABLE INITIALLY DEFERRED;

-- 使用: 延迟检查直到 COMMIT
SET CONSTRAINT fk_orders_user2 DEFERRED;
-- ... 可以临时违反约束的操作 ...
SET CONSTRAINT fk_orders_user2 IMMEDIATE;

-- 或者一次性设置所有约束
SET CONSTRAINTS ALL DEFERRED;

-- 横向对比:
--   Oracle:     完整支持 DEFERRABLE INITIALLY DEFERRED/IMMEDIATE
--   PostgreSQL: 完整支持（语法相同）
--   MySQL:      不支持可延迟约束
--   SQL Server: 不支持可延迟约束
--
-- 场景: 循环外键（A 引用 B，B 引用 A），只有可延迟约束能处理
-- 对引擎开发者的启示:
--   实现可延迟约束需要在事务层维护待检查约束的列表，
--   在 COMMIT 时批量验证。这增加了事务管理器的复杂度。

-- 2.3 ENABLE / DISABLE / VALIDATE / NOVALIDATE: 约束状态矩阵
-- Oracle 约束有 4 种状态组合（其他数据库通常只有启用/禁用）:
--
-- ENABLE  + VALIDATE   : 默认状态，新旧数据都检查
-- ENABLE  + NOVALIDATE : 新数据检查，已有数据不检查
-- DISABLE + VALIDATE   : 禁止 DML，但保证数据满足约束（极少使用）
-- DISABLE + NOVALIDATE : 完全不检查（数据加载时使用）

ALTER TABLE users DISABLE CONSTRAINT chk_age;
ALTER TABLE users ENABLE CONSTRAINT chk_age;
ALTER TABLE users ENABLE NOVALIDATE CONSTRAINT chk_age;

-- 典型用法: 批量数据加载
ALTER TABLE users DISABLE CONSTRAINT chk_age;
-- ... 批量加载 ...
ALTER TABLE users ENABLE NOVALIDATE CONSTRAINT chk_age;
-- 新数据受约束保护，但不回头检查已加载的数据（性能优化）

-- 横向对比:
--   PostgreSQL: ALTER TABLE t ALTER CONSTRAINT ... NOT VALID（类似 NOVALIDATE）
--               但只支持 FK 和 CHECK
--   MySQL:      SET FOREIGN_KEY_CHECKS = 0（全局开关，粗粒度）
--   SQL Server: ALTER TABLE t NOCHECK CONSTRAINT / CHECK CONSTRAINT

-- ============================================================
-- 3. '' = NULL 对约束的影响
-- ============================================================

-- NOT NULL 约束 + 空字符串:
-- Oracle 中 '' = NULL，所以:
--   INSERT INTO users (email) VALUES ('');
-- 等于:
--   INSERT INTO users (email) VALUES (NULL);
-- 如果 email 有 NOT NULL 约束，上面的 INSERT 会报错！

-- UNIQUE 约束 + NULL:
-- Oracle 允许多个 NULL 值在 UNIQUE 列中（NULL != NULL）
-- 但由于 '' = NULL，多个空字符串也被允许（因为都是 NULL）

-- CHECK 约束中的 NULL 陷阱:
ALTER TABLE users ADD CONSTRAINT chk_name_not_empty
    CHECK (LENGTH(name) > 0);
-- 注意: 这个约束不会阻止 NULL（CHECK 对 NULL 求值为 UNKNOWN，不违反）
-- 也不会阻止 ''（因为 '' 就是 NULL）
-- 要同时阻止: 需要 NOT NULL + CHECK

-- ============================================================
-- 4. 删除约束
-- ============================================================
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE users DROP CONSTRAINT uk_email CASCADE;  -- 级联删除依赖的约束
ALTER TABLE users DROP PRIMARY KEY;                   -- 直接删主键

-- ============================================================
-- 5. 数据字典查询（Oracle 三层视图）
-- ============================================================
SELECT constraint_name, constraint_type, status, validated, deferrable, deferred
FROM user_constraints
WHERE table_name = 'USERS';
-- constraint_type: P=PK, U=UNIQUE, R=FK, C=CHECK/NOT NULL

SELECT * FROM user_cons_columns WHERE table_name = 'USERS';

-- 查看外键关系
SELECT a.constraint_name, a.table_name, b.table_name AS ref_table,
       a.delete_rule
FROM user_constraints a
JOIN user_constraints b ON a.r_constraint_name = b.constraint_name
WHERE a.constraint_type = 'R';

-- ============================================================
-- 6. 对引擎开发者的启示
-- ============================================================
-- 1. Oracle 的约束状态矩阵（ENABLE/DISABLE x VALIDATE/NOVALIDATE）是最灵活的，
--    但增加了实现复杂度。最小可行方案是只支持 ENABLE/DISABLE。
-- 2. 可延迟约束对 ORM 和复杂业务逻辑非常重要，值得投入实现。
-- 3. '' = NULL 的设计导致了约束行为的许多反直觉情况，
--    这是新引擎应该避免的设计选择。
-- 4. Oracle 不支持 ON UPDATE CASCADE 说明即使是成熟的商业引擎，
--    也会基于哲学判断选择不实现某些标准特性。
