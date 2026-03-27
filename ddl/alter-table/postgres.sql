-- PostgreSQL: ALTER TABLE
--
-- 参考资料:
--   [1] PostgreSQL Documentation - ALTER TABLE
--       https://www.postgresql.org/docs/current/sql-altertable.html
--   [2] PostgreSQL Source - ATExecCmd / AlterTableGetLockLevel
--       https://github.com/postgres/postgres/blob/master/src/backend/commands/tablecmds.c

-- ============================================================
-- 1. 基本 ALTER TABLE 操作
-- ============================================================

-- 添加列（总是追加到末尾，不支持 AFTER / FIRST）
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN status INTEGER NOT NULL DEFAULT 1;

-- 修改列类型（需要 USING 指定转换表达式当类型不兼容时）
ALTER TABLE users ALTER COLUMN phone TYPE VARCHAR(32);
ALTER TABLE users ALTER COLUMN age TYPE TEXT USING age::TEXT;

-- 重命名列 / 表
ALTER TABLE users RENAME COLUMN phone TO mobile;
ALTER TABLE users RENAME TO members;

-- 删除列
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN IF EXISTS phone CASCADE;

-- 多操作合并（单次 ACCESS EXCLUSIVE 锁）
ALTER TABLE users
    ADD COLUMN city VARCHAR(64),
    ADD COLUMN country VARCHAR(64),
    DROP COLUMN IF EXISTS phone;

-- 默认值 / NOT NULL
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

-- 修改 schema
ALTER TABLE users SET SCHEMA archive;

-- ============================================================
-- 2. 设计决策分析: 为什么不支持 AFTER / FIRST
-- ============================================================

-- PostgreSQL 的 heap tuple 中列顺序由 pg_attribute.attnum 决定。
-- 列的物理存储顺序由 CREATE TABLE 时的定义固定，ADD COLUMN 只能追加。
-- 设计原因:
--   (a) 列顺序应该不影响语义——SQL 标准要求 SELECT * 按定义顺序，
--       但应用不应依赖列顺序，应该显式列出列名
--   (b) 允许任意位置插入列需要重写所有行或维护逻辑→物理映射表，
--       代价过高且收益有限
--   (c) 11+ 的 ADD COLUMN + DEFAULT 零重写优化依赖"追加到末尾"的不变量
--
-- 对比:
--   MySQL:      ALTER TABLE ADD COLUMN ... AFTER col / FIRST（需要重写表）
--   Oracle:     不支持 AFTER / FIRST（同 PostgreSQL）
--   SQL Server: 不支持 AFTER / FIRST（同 PostgreSQL）

-- ============================================================
-- 3. 内部实现: 锁级别与重写判定
-- ============================================================

-- PostgreSQL ALTER TABLE 的锁级别由 AlterTableGetLockLevel() 决定:
--   ACCESS EXCLUSIVE (Level 8): ADD/DROP COLUMN, 改类型, 加 NOT NULL
--   SHARE UPDATE EXCLUSIVE (Level 4): ADD INDEX CONCURRENTLY, VALIDATE CONSTRAINT
--   SHARE ROW EXCLUSIVE (Level 5): ADD 触发器
--   ROW EXCLUSIVE (Level 3): DISABLE/ENABLE TRIGGER
--
-- 是否需要重写表（table rewrite）:
--   需要重写: ALTER TYPE（类型不兼容）, SET NOT NULL（检查所有行）
--   不重写:   ADD COLUMN + DEFAULT（11+）, RENAME, DROP DEFAULT, SET STATISTICS
--   部分重写: ADD COLUMN + volatile default（需要填充每一行）
--
-- 11+ ADD COLUMN + DEFAULT 零重写的实现:
--   新列的默认值记录在 pg_attrdef，已有行读取时由 executor 填充
--   heap_getattr() 检查 natts < 物理列数时触发 "missing attribute" 路径
--   这是一个巨大的性能优化——之前百万行表加列需要分钟级，现在瞬间完成

-- ============================================================
-- 4. ALTER TYPE ... USING: 类型转换的内部机制
-- ============================================================

-- 类型变更时，PostgreSQL 检查:
--   (1) 是否存在隐式 cast（如 VARCHAR(50) → VARCHAR(100)，无需重写）
--   (2) 是否需要 USING 表达式（如 TEXT → INTEGER，需要显式转换规则）
--   (3) 依赖对象是否兼容（索引、视图、约束引用该列）
ALTER TABLE users ALTER COLUMN age TYPE NUMERIC USING age::NUMERIC;

-- 复杂转换示例: 枚举字符串→整数
ALTER TABLE orders ALTER COLUMN status TYPE INTEGER
    USING CASE status
        WHEN 'pending'   THEN 0
        WHEN 'active'    THEN 1
        WHEN 'completed' THEN 2
        ELSE -1
    END;

-- 对比:
--   MySQL:   ALTER TABLE MODIFY COLUMN（隐式转换更宽松，可能丢数据不报错）
--   Oracle:  ALTER TABLE MODIFY（非空列改类型限制更多）
--   ClickHouse: ALTER TABLE MODIFY COLUMN（异步 mutation，后台重写）

-- ============================================================
-- 5. NOT VALID + VALIDATE CONSTRAINT: 大表加约束的最佳实践
-- ============================================================

-- 传统方式: ACCESS EXCLUSIVE 锁 + 全表扫描验证
ALTER TABLE orders ADD CONSTRAINT chk_amount CHECK (amount > 0);

-- 最佳实践（两步法）:
-- 步骤 1: NOT VALID 只对新数据生效（瞬间完成，短暂 ACCESS EXCLUSIVE）
ALTER TABLE orders ADD CONSTRAINT chk_amount CHECK (amount > 0) NOT VALID;

-- 步骤 2: VALIDATE 扫描已有数据（只需 SHARE UPDATE EXCLUSIVE，不阻塞写入）
ALTER TABLE orders VALIDATE CONSTRAINT chk_amount;

-- 同样适用于外键:
ALTER TABLE orders ADD CONSTRAINT fk_user FOREIGN KEY (user_id)
    REFERENCES users(id) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT fk_user;

-- 设计启示:
--   分离"定义约束"和"验证约束"是 PostgreSQL 的精妙设计。
--   MySQL 没有类似机制——加外键时必须锁表扫描。
--   这对引擎开发者的教训: DDL 操作应尽量允许"非阻塞验证"阶段。

-- ============================================================
-- 6. 横向对比: ALTER TABLE 行为差异
-- ============================================================

-- 1. DDL 事务性:
--   PostgreSQL: ALTER TABLE 是事务性的！可以 BEGIN; ALTER ...; ROLLBACK;
--   MySQL:      DDL 隐式提交（ALTER TABLE 前后各一个 COMMIT）
--   Oracle:     DDL 隐式提交（同 MySQL）
--   SQL Server: DDL 是事务性的（同 PostgreSQL）
--
-- 2. Online DDL:
--   PostgreSQL: 大多数 ALTER 需要 ACCESS EXCLUSIVE，但 11+ ADD COLUMN+DEFAULT 瞬间
--               CREATE INDEX CONCURRENTLY 不阻塞写入
--   MySQL:      5.6+ Online DDL，8.0.12+ ALGORITHM=INSTANT
--   Oracle:     Online DDL + Edition-Based Redefinition（最完善）
--   SQL Server: ONLINE = ON（仅 Enterprise 版）
--
-- 3. 列顺序:
--   PostgreSQL: 不支持 AFTER/FIRST（设计选择）
--   MySQL:      支持 AFTER/FIRST（需重写表）
--   Oracle/SQL Server: 不支持（同 PostgreSQL）
--
-- 4. 社区工具补充:
--   pg_repack: 在线重建表（不锁表），类似 MySQL pt-online-schema-change
--   pgroll:    零停机 schema 迁移，支持新旧 schema 双写

-- ============================================================
-- 7. 对引擎开发者的启示
-- ============================================================

-- (1) 锁分级设计: PostgreSQL 的 8 级表锁体系值得学习。
--     不同 ALTER 操作需要不同锁级别，避免一刀切的 EXCLUSIVE。
--
-- (2) 延迟物化: 11+ 的 ADD COLUMN + DEFAULT 零重写是教科书级优化。
--     原理: 元数据记录默认值，读取时按需填充（lazy evaluation）。
--     这种"把计算推迟到读取时"的思路在列存引擎中也常见。
--
-- (3) NOT VALID 模式: 将 DDL 拆分为"定义+验证"两步，
--     允许验证阶段使用更弱的锁，是减少停机时间的关键设计。
--
-- (4) DDL 事务性: PostgreSQL 的 DDL 可回滚是其最独特的优势之一。
--     实现原理: DDL 操作修改系统表（pg_class, pg_attribute 等），
--     这些系统表本身就是普通堆表，受 MVCC 保护。

-- ============================================================
-- 8. 版本演进
-- ============================================================
-- PostgreSQL 8.0:  基本 ALTER TABLE 操作
-- PostgreSQL 9.1:  ADD COLUMN IF NOT EXISTS
-- PostgreSQL 9.2:  DROP COLUMN IF EXISTS
-- PostgreSQL 11:   ADD COLUMN + non-null DEFAULT 零重写（里程碑优化）
-- PostgreSQL 12:   ALTER TABLE ... ATTACH/DETACH PARTITION 性能提升
-- PostgreSQL 14:   DETACH PARTITION CONCURRENTLY
-- PostgreSQL 15:   SET ACCESS METHOD（更换存储引擎）
-- PostgreSQL 17:   ALTER TABLE ... SET LOGGED/UNLOGGED 不再需要重写表
