-- PostgreSQL: 约束 (Constraints)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Constraints
--       https://www.postgresql.org/docs/current/ddl-constraints.html
--   [2] PostgreSQL Source - ri_triggers.c (FK enforcement)
--       https://github.com/postgres/postgres/blob/master/src/backend/utils/adt/ri_triggers.c

-- ============================================================
-- 1. 基本约束语法
-- ============================================================

-- PRIMARY KEY（自动创建 B-tree 唯一索引）
CREATE TABLE users (id BIGSERIAL PRIMARY KEY);
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (order_id, item_id)
);

-- UNIQUE（多个 NULL 默认视为不重复）
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
-- 15+: NULLS NOT DISTINCT（多个 NULL 视为重复）
ALTER TABLE users ADD CONSTRAINT uk_phone UNIQUE NULLS NOT DISTINCT (phone);

-- FOREIGN KEY
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE ON UPDATE CASCADE;
-- 动作: CASCADE / SET NULL / SET DEFAULT / RESTRICT / NO ACTION

-- NOT NULL / DEFAULT
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;

-- CHECK（可引用多列，从第一个版本就完美执行）
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE events ADD CONSTRAINT chk_dates CHECK (end_date > start_date);

-- ============================================================
-- 2. EXCLUDE 约束: PostgreSQL 独有的排他约束
-- ============================================================

-- EXCLUDE 约束确保任意两行在指定操作符上不冲突——GiST 索引驱动。
-- 典型场景: 防止时间/空间范围重叠
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 确保同一会议室不能在同一时段被预订两次
ALTER TABLE reservations ADD CONSTRAINT no_overlap
    EXCLUDE USING gist (room_id WITH =, period WITH &&);

-- 设计分析:
--   EXCLUDE 约束的本质是"广义唯一约束"。UNIQUE 是 EXCLUDE 的特例:
--     UNIQUE(a, b) ≡ EXCLUDE USING btree (a WITH =, b WITH =)
--   但 EXCLUDE 支持任意 GiST 索引操作符（&&重叠, <<前于, 等）。
--
-- 实现机制:
--   INSERT/UPDATE 时，用 GiST 索引扫描查找冲突行。
--   如果找到任何一行使所有操作符条件为 TRUE，则违反约束。
--
-- 对比:
--   MySQL:      无等价功能（需要应用层或触发器检查）
--   Oracle:     无等价功能
--   SQL Server: 无等价功能
--   这是 PostgreSQL 可扩展索引体系（GiST/SP-GiST/GIN）的直接成果。

-- ============================================================
-- 3. 可延迟约束: DEFERRABLE 的事务语义
-- ============================================================

-- 默认约束是 NOT DEFERRABLE（每条语句立即检查）
-- DEFERRABLE 约束可以推迟到事务提交时检查
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    DEFERRABLE INITIALLY DEFERRED;

-- 使用场景: 循环外键、批量导入时临时违反约束
-- 在事务中临时切换:
SET CONSTRAINTS fk_orders_user DEFERRED;   -- 延迟检查
SET CONSTRAINTS fk_orders_user IMMEDIATE;  -- 立即检查
SET CONSTRAINTS ALL DEFERRED;              -- 所有可延迟约束

-- 实现细节:
--   DEFERRED 约束的检查在 COMMIT 前的 AfterTriggerEndXact() 中执行。
--   每条违反约束的操作创建一个"延迟触发器事件"，COMMIT 时批量检查。
--   如果任一检查失败，整个事务回滚。
--
-- 对比:
--   Oracle:     完全支持 DEFERRABLE（语义相同）
--   SQL Server: 不支持 DEFERRABLE（外键总是立即检查）
--   MySQL:      不支持 DEFERRABLE（InnoDB 外键立即检查）

-- ============================================================
-- 4. NOT VALID: 分离定义与验证
-- ============================================================

-- NOT VALID 只对新数据执行约束，已有数据不检查
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0) NOT VALID;

-- 之后在低峰期验证已有数据（SHARE UPDATE EXCLUSIVE 锁，不阻塞写入）
ALTER TABLE users VALIDATE CONSTRAINT chk_age;

-- 外键同样支持:
ALTER TABLE orders ADD CONSTRAINT fk_user
    FOREIGN KEY (user_id) REFERENCES users(id) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT fk_user;

-- 设计智慧:
--   NOT VALID 的核心价值: DDL 加约束只需瞬间的 ACCESS EXCLUSIVE 锁，
--   而验证阶段用更弱的锁，读写都不阻塞。
--   这在大表（百万行+）上加约束时至关重要。

-- ============================================================
-- 5. 外键的内部实现: RI 触发器
-- ============================================================

-- PostgreSQL 的外键不是存储引擎层面的功能，而是通过系统触发器实现。
-- 创建外键时，PostgreSQL 自动生成:
--   子表 INSERT/UPDATE: RI_FKey_check_ins 触发器（检查父表是否存在）
--   父表 DELETE: RI_FKey_cascade_del 或 RI_FKey_restrict_del（按 ON DELETE 动作）
--   父表 UPDATE: RI_FKey_cascade_upd 或 RI_FKey_noaction_upd（按 ON UPDATE 动作）
--
-- 可以在 pg_trigger 中看到这些系统触发器:
SELECT tgname, tgtype FROM pg_trigger
WHERE tgconstrrelid = 'users'::regclass;

-- RESTRICT vs NO ACTION（微妙区别）:
--   RESTRICT: 立即检查，不可延迟
--   NO ACTION（默认）: 语句结束时检查，可配合 DEFERRABLE 延迟到事务结束
--   在非 DEFERRABLE 场景下两者行为完全相同

-- ============================================================
-- 6. 查看约束元数据
-- ============================================================

-- information_schema 方式（跨数据库兼容）
SELECT * FROM information_schema.table_constraints
WHERE table_name = 'users';

-- pg_constraint 方式（PostgreSQL 特有，信息更丰富）
SELECT conname, contype, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'users'::regclass;
-- contype: p=主键, u=唯一, c=检查, f=外键, x=排他

-- ============================================================
-- 7. 横向对比: 约束能力
-- ============================================================

-- 1. CHECK 约束:
--   PostgreSQL: 从第一个版本就完整支持（包括多列 CHECK）
--   MySQL:      5.7 解析但不执行！8.0.16+ 才真正生效（著名设计失误）
--   Oracle:     完整支持
--   SQL Server: 完整支持
--   BigQuery:   不支持 CHECK
--
-- 2. EXCLUDE 约束:
--   PostgreSQL: 独有（依赖 GiST 索引）
--   其他:       均不支持（需要应用层实现）
--
-- 3. DEFERRABLE:
--   PostgreSQL: 完整支持（CHECK, UNIQUE, FK 都可 DEFERRABLE）
--   Oracle:     完整支持
--   MySQL/SQL Server: 不支持
--
-- 4. NULLS NOT DISTINCT (15+):
--   PostgreSQL: 明确控制 NULL 在唯一约束中的行为
--   SQL Server: 默认就是 NULLS NOT DISTINCT（多个 NULL 视为重复）
--   MySQL:      NULL 总是视为不同（不可配置）
--   Oracle:     全 NULL 组合不参与唯一约束（完全忽略）

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================

-- (1) 约束即触发器: PostgreSQL 用触发器实现外键的做法
--     意味着外键检查完全在 SQL 层，不依赖存储引擎。
--     优点: 存储引擎无需感知外键，架构更简洁
--     缺点: 性能不如存储引擎原生支持（每次 INSERT 需要额外查询父表）
--
-- (2) EXCLUDE 约束展示了可扩展索引的价值:
--     有了 GiST 框架，约束不再局限于等值比较，
--     可以扩展到范围重叠、空间包含等复杂条件。
--
-- (3) NOT VALID 模式启示: DDL 操作应该允许"渐进式迁移"，
--     而非强制一次性全量验证。这在分布式系统中尤其重要。

-- ============================================================
-- 9. 版本演进
-- ============================================================
-- PostgreSQL 8.0:  基本 CHECK, UNIQUE, FK
-- PostgreSQL 9.0:  EXCLUDE 约束（排他约束）
-- PostgreSQL 9.1:  NOT VALID + VALIDATE CONSTRAINT
-- PostgreSQL 9.4:  ALTER TABLE ... ADD CONSTRAINT IF NOT EXISTS 模式
-- PostgreSQL 11:   分区表支持主键和唯一约束（必须包含分区键）
-- PostgreSQL 12:   外键可以引用分区表
-- PostgreSQL 15:   NULLS NOT DISTINCT 选项
-- PostgreSQL 17:   NOT NULL 约束可以加 NOT VALID
