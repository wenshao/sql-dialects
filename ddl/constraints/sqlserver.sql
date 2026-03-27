-- SQL Server: 约束 (Constraints)
--
-- 参考资料:
--   [1] SQL Server T-SQL - Table Constraints
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-table-table-constraint-transact-sql
--   [2] SQL Server T-SQL - WITH NOCHECK
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-table-transact-sql

-- ============================================================
-- 1. 基本约束语法
-- ============================================================

-- PRIMARY KEY（默认创建聚集索引）
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);

-- 非聚集主键（当聚集索引需要用在其他列上时）
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY NONCLUSTERED (id);

-- UNIQUE
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

-- FOREIGN KEY
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE ON UPDATE CASCADE;
-- 动作: CASCADE / SET NULL / SET DEFAULT / NO ACTION

-- NOT NULL（通过 ALTER COLUMN 实现——不是独立的约束对象）
ALTER TABLE users ALTER COLUMN email NVARCHAR(255) NOT NULL;

-- DEFAULT（SQL Server 独有: 默认值是命名约束对象）
ALTER TABLE users ADD CONSTRAINT df_status DEFAULT 1 FOR status;

-- CHECK
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE users ADD CONSTRAINT chk_dates CHECK (end_date > start_date);

-- ============================================================
-- 2. 约束命名哲学（对引擎开发者）
-- ============================================================

-- SQL Server 要求所有约束都是独立的命名对象（在 sys.objects 中有记录）。
-- 这包括 DEFAULT、CHECK、PRIMARY KEY、UNIQUE、FOREIGN KEY。
-- 约束名在数据库级别唯一（不是表级别）。
--
-- 设计 trade-off:
--   优点: 约束有全局唯一名，便于管理、生成脚本、审计
--   缺点: 命名负担重，匿名约束得到系统生成的随机名（如 DF__users__stat__3B75D760）
--         删除列前必须先查出并删除其上的所有约束
--
-- 横向对比:
--   MySQL:      PRIMARY KEY 无名字，CHECK/FK 有名字但可省略
--   PostgreSQL: 约束有名字，可省略（系统自动生成可预测的名字如 tablename_colname_pkey）
--   Oracle:     同 SQL Server，约束是命名对象
--
-- 对引擎开发者的启示:
--   PostgreSQL 的命名策略最优: 系统自动生成可预测的约束名（无需用户操心），
--   且约束名在 schema 级别唯一（不是数据库级别），避免命名冲突。

-- ============================================================
-- 3. WITH NOCHECK: SQL Server 独有的约束信任机制
-- ============================================================

-- 添加约束时不校验已有数据（SQL Server 独有能力）
ALTER TABLE users WITH NOCHECK
    ADD CONSTRAINT chk_age CHECK (age >= 0);

-- WITH NOCHECK 的约束被标记为"不信任的"（is_not_trusted = 1）
-- 后果: 优化器不会利用不信任的约束来简化查询计划
-- 例如: 如果 CHECK (age >= 0) 是 trusted 的，
--       WHERE age >= 0 可以被优化掉；untrusted 则不行

-- 让约束变为 trusted:
ALTER TABLE users WITH CHECK CHECK CONSTRAINT chk_age;
-- 注意: WITH CHECK CHECK 不是笔误——第一个 CHECK 是验证选项，第二个是操作类型

-- 查看约束信任状态:
SELECT name, is_not_trusted
FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID('users');

-- 设计分析（对引擎开发者）:
--   WITH NOCHECK 解决了一个实际问题: 大表上添加约束需要全表扫描，
--   在生产环境中可能需要数小时。WITH NOCHECK 允许先加约束再异步验证。
--   但"不信任"状态影响优化器，这是一个隐藏的性能陷阱。
--
--   PostgreSQL 的做法: ALTER TABLE ... ADD CONSTRAINT ... NOT VALID;
--   然后 ALTER TABLE ... VALIDATE CONSTRAINT ...; （语义更清晰）

-- ============================================================
-- 4. 禁用/启用约束（对引擎开发者）
-- ============================================================

-- SQL Server 允许禁用 CHECK 和 FK 约束（不删除）
ALTER TABLE users NOCHECK CONSTRAINT chk_age;       -- 禁用
ALTER TABLE users CHECK CONSTRAINT chk_age;          -- 启用
ALTER TABLE users NOCHECK CONSTRAINT ALL;            -- 禁用所有

-- 典型场景: 批量数据加载时禁用 FK 检查，加载完后启用
-- 横向对比:
--   MySQL:      SET FOREIGN_KEY_CHECKS = 0（全局，所有表）
--   PostgreSQL: ALTER TABLE ... DISABLE TRIGGER ALL（禁用触发器，FK 通过触发器实现）
--               或 SET CONSTRAINTS ... DEFERRED（延迟到事务结束检查）
--   Oracle:     ALTER TABLE ... DISABLE CONSTRAINT（同 SQL Server）
--
-- 对引擎开发者的启示:
--   ETL 场景频繁需要临时禁用约束。引擎应提供表级别的精确控制，
--   而不是全局开关（MySQL 的做法风险太大）。
--   延迟约束检查（DEFERRED）是更优雅的方案，SQL Server 不支持。

-- ============================================================
-- 5. 聚集索引与主键的关系
-- ============================================================

-- SQL Server 中，PRIMARY KEY 默认创建 CLUSTERED INDEX。
-- 这意味着主键 = 表的物理排列顺序（InnoDB 也是如此）。
-- 但 SQL Server 允许显式分离:
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY NONCLUSTERED (id);
CREATE CLUSTERED INDEX ix_created ON users (created_at);
-- 此时数据按 created_at 物理排列，id 上是非聚集索引

-- 设计考量:
--   如果查询以时间范围为主（如日志表），聚集索引应在时间列上。
--   如果查询以主键查找为主，聚集索引应在主键上（默认行为）。
--
-- 横向对比:
--   MySQL InnoDB: 主键 = 聚集索引，无法分离（这是硬限制）
--   PostgreSQL:   无聚集索引概念，所有索引指向堆表的 ctid
--   Oracle:       默认堆表，IOT（CREATE TABLE ... ORGANIZATION INDEX）需显式创建
--
-- 对引擎开发者的启示:
--   聚集索引与主键可分离是 SQL Server 的优势，给了 DBA 更多调优空间。
--   InnoDB 的强绑定简化了实现但减少了灵活性。

-- ============================================================
-- 6. 删除约束与 IF EXISTS
-- ============================================================

ALTER TABLE users DROP CONSTRAINT uk_email;
-- 2016+:
ALTER TABLE users DROP CONSTRAINT IF EXISTS uk_email;

-- 查看约束元数据
SELECT * FROM sys.check_constraints WHERE parent_object_id = OBJECT_ID('users');
SELECT * FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('orders');
SELECT * FROM sys.key_constraints WHERE parent_object_id = OBJECT_ID('users');
EXEC sp_helpconstraint 'users';

-- ============================================================
-- 7. 外键的 SET DEFAULT 行为
-- ============================================================

-- SQL Server 的 ON DELETE SET DEFAULT 要求列有显式 DEFAULT 约束。
-- 如果没有 DEFAULT 约束，SET DEFAULT 会把值设为类型默认值（INT→0, VARCHAR→''）。
-- 这是一个容易出错的行为——其他数据库通常要求 DEFAULT 约束必须存在。

-- ============================================================
-- 版本演进
-- ============================================================
-- SQL Server 2005+ : WITH NOCHECK, NOCHECK CONSTRAINT
-- SQL Server 2008+ : 过滤索引（间接影响约束设计）
-- SQL Server 2016  : IF EXISTS 语法
-- SQL Server 2019  : 在线索引恢复（RESUMABLE）
