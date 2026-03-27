-- SQLite: 约束（Constraints）
--
-- 参考资料:
--   [1] SQLite Documentation - CREATE TABLE (Constraints)
--       https://www.sqlite.org/lang_createtable.html
--   [2] SQLite Documentation - Foreign Key Support
--       https://www.sqlite.org/foreignkeys.html
--   [3] SQLite Documentation - STRICT Tables (3.37.0+)
--       https://www.sqlite.org/stricttables.html

-- ============================================================
-- 1. 基本约束语法
-- ============================================================

-- PRIMARY KEY
CREATE TABLE users (
    id INTEGER PRIMARY KEY    -- INTEGER PRIMARY KEY = rowid 别名（见下文分析）
);

-- 复合主键
CREATE TABLE order_items (
    order_id INTEGER NOT NULL,
    item_id  INTEGER NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (order_id, item_id)
);

-- UNIQUE
CREATE TABLE users (
    id       INTEGER PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    email    TEXT NOT NULL,
    UNIQUE (email)
);

-- NOT NULL + DEFAULT
CREATE TABLE users (
    id     INTEGER PRIMARY KEY,
    status INTEGER NOT NULL DEFAULT 1,
    name   TEXT    NOT NULL DEFAULT 'anonymous'
);

-- CHECK（从 3.0 起就支持，比 MySQL 早了 20 年）
CREATE TABLE users (
    id  INTEGER PRIMARY KEY,
    age INTEGER CHECK (age >= 0 AND age <= 200),
    CHECK (length(username) >= 2)  -- 表级 CHECK
);

-- FOREIGN KEY（必须显式启用！）
PRAGMA foreign_keys = ON;    -- 默认 OFF，这是 SQLite 最大的约束设计陷阱

CREATE TABLE orders (
    id      INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

-- ============================================================
-- 2. INTEGER PRIMARY KEY 与 rowid 的关系（对引擎开发者）
-- ============================================================

-- 2.1 SQLite 的 rowid 机制
-- SQLite 的每个普通表都有一个隐藏的 64 位整数 rowid 列。
-- 当声明 INTEGER PRIMARY KEY 时，该列成为 rowid 的别名。
-- 这是 SQLite 最独特的设计决策之一:
--
--   CREATE TABLE t (id INTEGER PRIMARY KEY);
--   → id 就是 rowid，存储在 B-Tree 内部节点中
--   → 不需要额外的主键索引（零开销）
--   → INSERT 时未指定 id 会自动分配 MAX(rowid)+1
--
-- 注意类型必须是 INTEGER（不是 INT、BIGINT、SMALLINT）:
--   CREATE TABLE t (id INT PRIMARY KEY);
--   → 这里 INT 不是 INTEGER 的别名！id 不会成为 rowid 的别名
--   → 会创建单独的主键索引（额外开销）
--   → 这是 SQLite 动态类型系统的一个容易踩的坑
--
-- 对比:
--   MySQL InnoDB:  主键就是聚集索引键（类似 rowid 概念）
--   PostgreSQL:    有 ctid（物理位置），但不是用户可见的主键
--   SQL Server:    聚集索引决定物理排列，但语法上与主键独立

-- 2.2 AUTOINCREMENT vs 默认行为
-- 不加 AUTOINCREMENT: id = MAX(rowid) + 1，删除后 ID 可能被复用
-- 加 AUTOINCREMENT:   id 严格递增，绝不复用（维护 sqlite_sequence 表）
--
-- AUTOINCREMENT 的开销:
--   - 维护额外的 sqlite_sequence 表
--   - 每次 INSERT 需要查询该表
--   - 官方文档明确说"通常不需要 AUTOINCREMENT"
--
-- 对比:
--   MySQL:      AUTO_INCREMENT 默认不复用 ID（8.0+ 持久化到 redo log）
--   PostgreSQL: SERIAL 基于 SEQUENCE，默认不复用但可能有间隙

-- ============================================================
-- 3. 动态类型对约束的影响（SQLite 最独特的设计）
-- ============================================================

-- 3.1 类型亲和性（Type Affinity）不是约束
-- SQLite 的列类型是"建议"而非强制。任何列可以存储任何类型:
--   INSERT INTO users (age) VALUES ('not a number');  -- 成功！
--   INSERT INTO users (age) VALUES (NULL);            -- 成功（即使有 INT 类型声明）
--
-- 类型亲和性只影响隐式转换优先级:
--   TEXT:    存储为文本（除非值是 NULL）
--   NUMERIC: 如果能无损转换为整数或实数则转换，否则保持原样
--   INTEGER: 类似 NUMERIC 但优先转为整数
--   REAL:    类似 NUMERIC 但优先转为浮点数
--   BLOB:    原样存储
--
-- 这意味着: CHECK 约束在 SQLite 中格外重要!
-- 因为类型系统不帮你验证，只有 CHECK 能保证数据质量。

-- 3.2 STRICT 模式（3.37.0+）: 为什么等了 21 年才添加
-- SQLite 的动态类型是其嵌入式定位的核心设计: 简单、灵活、容错。
-- 但随着 SQLite 用于生产后端（而不仅仅是嵌入式），类型安全需求增长。
--
-- STRICT 表强制类型检查:
CREATE TABLE strict_users (
    id       INTEGER PRIMARY KEY,
    username TEXT    NOT NULL,
    age      INTEGER,
    balance  REAL,
    data     BLOB
) STRICT;

-- STRICT 模式下:
--   INSERT INTO strict_users (age) VALUES ('text');  -- 报错!
--   允许的类型: INT, INTEGER, REAL, TEXT, BLOB, ANY
--   ANY 类型: 允许任何值（保持动态类型行为）
--
-- 为什么到 3.37.0 才添加:
--   (a) 不想破坏向后兼容（20 年的嵌入式应用）
--   (b) 作为表级 opt-in 而非全局设置，平衡了兼容与安全
--   (c) Litestream/Turso 等项目将 SQLite 推向服务端，倒逼类型安全

-- ============================================================
-- 4. 外键的特殊设计（对引擎开发者）
-- ============================================================

-- 4.1 为什么外键默认关闭
-- PRAGMA foreign_keys = OFF 是默认值，原因:
--   (a) 向后兼容: 早期 SQLite 不支持外键，老应用可能有不满足外键的数据
--   (b) 嵌入式场景: 外键检查增加 I/O（需要查询父表），嵌入式设备资源有限
--   (c) 每个连接独立: PRAGMA 设置不持久化，每次打开数据库需要重新设置
--
-- 这是一个有争议的设计: 很多开发者不知道外键默认不生效
-- 最佳实践: 应用启动时立即执行 PRAGMA foreign_keys = ON

-- 4.2 外键动作
-- 支持所有标准动作: CASCADE / SET NULL / SET DEFAULT / RESTRICT / NO ACTION
-- NO ACTION 是默认值（与 SQL 标准一致）
-- RESTRICT vs NO ACTION: RESTRICT 立即检查，NO ACTION 延迟到语句结束

-- 4.3 延迟约束（DEFERRABLE）
CREATE TABLE nodes (
    id        INTEGER PRIMARY KEY,
    parent_id INTEGER,
    FOREIGN KEY (parent_id) REFERENCES nodes (id)
        DEFERRABLE INITIALLY DEFERRED    -- 延迟到事务提交时检查
);
-- 延迟外键对树形/图形数据很有用: 先插入所有节点，最后统一检查引用完整性

-- ============================================================
-- 5. 约束的不可变性（无法 ALTER 约束）
-- ============================================================

-- SQLite 不支持 ALTER TABLE ADD/DROP CONSTRAINT!
-- 修改约束的唯一方法是重建表（见 alter-table/sqlite.sql）。
--
-- 原因: 约束定义存储在 sqlite_master 表的 CREATE TABLE SQL 文本中。
-- 修改约束需要解析并重写这段 SQL 文本，SQLite 选择不实现这个功能。
--
-- 检查现有约束:
PRAGMA table_info('users');           -- 列名、类型、NOT NULL、默认值、主键
PRAGMA foreign_key_list('orders');    -- 外键引用关系
PRAGMA index_list('users');           -- 索引（UNIQUE 约束创建的索引也在这里）
PRAGMA foreign_key_check;            -- 检查所有外键完整性违规

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- SQLite 的约束设计反映了"嵌入式优先"的哲学:
--   (1) 动态类型 → CHECK 约束比类型声明更重要
--   (2) 外键默认关闭 → 性能和兼容优先于完整性
--   (3) 约束不可变 → 简化实现，用重建表替代
--   (4) STRICT 模式晚期添加 → 向后兼容的优先级极高
--   (5) INTEGER PRIMARY KEY = rowid → 零开销主键，独特而高效
--
-- 对引擎开发者的启示:
--   如果设计嵌入式数据库，需要决定类型系统的严格程度。
--   SQLite 证明了"先宽松后收紧"（通过 STRICT opt-in）比反过来容易。
--   外键默认关闭是争议设计 -- 如果要实现，建议默认开启但允许关闭。
