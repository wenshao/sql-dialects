-- SQLite: 索引（Indexes）
--
-- 参考资料:
--   [1] SQLite Documentation - CREATE INDEX
--       https://www.sqlite.org/lang_createindex.html
--   [2] SQLite Documentation - Query Planner
--       https://www.sqlite.org/queryplanner.html
--   [3] SQLite Internals - B-Tree Implementation
--       https://www.sqlite.org/btreemodule.html

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 普通索引
CREATE INDEX idx_age ON users (age);

-- 唯一索引
CREATE UNIQUE INDEX uk_email ON users (email);

-- 复合索引（最左前缀原则适用）
CREATE INDEX idx_city_age ON users (city, age);

-- IF NOT EXISTS
CREATE INDEX IF NOT EXISTS idx_age ON users (age);

-- 部分索引（3.8.0+，只索引满足条件的行）
CREATE INDEX idx_active_users ON users (username) WHERE status = 1;

-- 表达式索引（3.9.0+）
CREATE INDEX idx_lower_email ON users (lower(email));

-- 降序索引
CREATE INDEX idx_age_desc ON users (age DESC);

-- 删除索引
DROP INDEX idx_age;
DROP INDEX IF EXISTS idx_age;

-- ============================================================
-- 2. SQLite 索引的内部实现（对引擎开发者）
-- ============================================================

-- 2.1 B-Tree 索引结构
-- SQLite 的整个数据库文件就是一个 B-Tree 的集合。
-- 每个表是一棵 B-Tree（以 rowid 为键），每个索引也是一棵独立的 B-Tree。
--
-- 索引 B-Tree 的叶节点存储: (索引列值, rowid)
-- 查询流程: 索引 B-Tree → 找到 rowid → 表 B-Tree → 取完整行
-- 这称为"回表"（index lookup + table lookup），与 MySQL InnoDB 二级索引相同。
--
-- 覆盖索引（Covering Index）:
-- 如果查询只需要索引中的列，不需要回表:
CREATE INDEX idx_covering ON users (city, age, username);
-- SELECT username FROM users WHERE city = 'NYC' AND age > 25;
-- → 只扫描索引 B-Tree，不回表

-- 2.2 单文件中的多棵 B-Tree
-- SQLite 的独特之处: 所有 B-Tree（表 + 索引）存储在同一个文件中。
-- 每棵 B-Tree 的根节点页号记录在 sqlite_master 表中。
--
-- 设计 trade-off:
--   优点: 单文件 = 部署简单、备份简单（复制一个文件）、无需安装
--   缺点: 并发写入受限（文件级锁，WAL 模式下可多读单写）
--         索引过多会增加文件大小和 I/O（所有索引在同一文件中竞争缓存）
--
-- 对比:
--   MySQL InnoDB: 每个表一个 .ibd 文件（file-per-table），索引在表空间内
--   PostgreSQL:   每个索引是独立的文件（fork）
--   SQL Server:   索引在 filegroup 中，可以分布到不同磁盘

-- ============================================================
-- 3. 索引类型的局限（只有 B-Tree）
-- ============================================================

-- SQLite 只支持 B-Tree 索引。不支持:
--   Hash 索引:   PostgreSQL 和 MySQL MEMORY 引擎支持
--   GiST/GIN:    PostgreSQL 的高级索引（地理数据、全文搜索）
--   R-Tree:      但 SQLite 通过虚拟表模块提供 R-Tree!（见下文）
--   倒排索引:    但通过 FTS5 虚拟表实现全文搜索
--   Bitmap 索引: Oracle 支持，适合低基数列
--
-- 为什么只有 B-Tree?
-- (a) 简单性: 嵌入式数据库追求最小实现
-- (b) 通用性: B-Tree 覆盖绝大多数查询模式（范围、等值、排序）
-- (c) 虚拟表机制: 特殊需求通过虚拟表扩展，不增加核心复杂度

-- ============================================================
-- 4. 虚拟表索引（FTS5 和 R*Tree）
-- ============================================================

-- 4.1 FTS5: 全文搜索（3.9.0+）
-- FTS5 是 SQLite 内置的全文搜索引擎，使用倒排索引
CREATE VIRTUAL TABLE docs_fts USING fts5(title, body);

INSERT INTO docs_fts (title, body) VALUES
    ('SQLite Tutorial', 'Learn SQLite basics and advanced topics'),
    ('SQL Guide', 'Comprehensive SQL reference for developers');

-- 全文搜索查询
SELECT * FROM docs_fts WHERE docs_fts MATCH 'SQLite AND tutorial';
SELECT * FROM docs_fts WHERE docs_fts MATCH 'sql*';       -- 前缀匹配
SELECT highlight(docs_fts, 1, '<b>', '</b>') FROM docs_fts
WHERE docs_fts MATCH 'SQLite';                             -- 高亮结果

-- BM25 排序（相关性评分）
SELECT *, rank FROM docs_fts WHERE docs_fts MATCH 'SQL'
ORDER BY rank;

-- 4.2 R*Tree: 空间索引（编译时启用）
-- R*Tree 虚拟表用于地理位置或多维范围查询
CREATE VIRTUAL TABLE spatial_idx USING rtree(
    id,
    min_x, max_x,    -- X 轴范围
    min_y, max_y     -- Y 轴范围
);

-- 范围查询（查找指定区域内的对象）
SELECT * FROM spatial_idx
WHERE min_x >= 10 AND max_x <= 50 AND min_y >= 20 AND max_y <= 60;

-- 设计分析:
--   通过虚拟表机制提供 FTS 和 R*Tree，而非在核心引擎中实现:
--   优点: 核心引擎保持简洁，不需要特殊索引的应用无额外开销
--   缺点: 虚拟表与普通表的交互受限（不能 JOIN 后用索引加速）
--   对比: PostgreSQL 将 GIN/GiST/BRIN 直接集成到核心索引接口

-- ============================================================
-- 5. 索引选择与查询计划
-- ============================================================

-- 查看索引
PRAGMA index_list('users');      -- 列出表的所有索引
PRAGMA index_info('idx_age');    -- 索引包含的列
PRAGMA index_xinfo('idx_age');   -- 3.10.0+，包含 rowid 列

-- 查看查询使用的索引
EXPLAIN QUERY PLAN SELECT * FROM users WHERE age > 25;
-- 输出示例: SEARCH TABLE users USING INDEX idx_age (age>?)

-- SQLite 查询计划器的特点:
--   (a) 基于成本的优化器（Cost-Based Optimizer），但统计信息有限
--   (b) ANALYZE 命令收集统计信息（存入 sqlite_stat1/stat4 表）
ANALYZE;                          -- 分析所有表
ANALYZE users;                    -- 分析指定表
--   (c) 不支持 FORCE INDEX / USE INDEX（不能强制使用某个索引）
--       → 通过 INDEXED BY 实现:
SELECT * FROM users INDEXED BY idx_age WHERE age > 25;
--       → 如果指定索引不适用，查询报错（而非退回全表扫描）

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- SQLite 索引设计的核心特征:
--   (1) 只有 B-Tree → 简洁但覆盖大多数场景
--   (2) 虚拟表扩展 → FTS5/R*Tree 不增加核心复杂度
--   (3) 单文件多 B-Tree → 部署简单但并发受限
--   (4) 部分索引 + 表达式索引 → 功能不输大型数据库
--   (5) INDEXED BY → 精确控制但不灵活（相比 MySQL 的 FORCE INDEX）
--
-- 对引擎开发者的启示:
--   嵌入式引擎的索引设计应遵循"核心精简 + 可扩展"的原则。
--   SQLite 用虚拟表机制将特殊索引（FTS/R*Tree）从核心中剥离，
--   这比 PostgreSQL 的"所有索引类型集成到核心"更适合嵌入式场景。
--   部分索引和表达式索引应该是现代引擎的标配，实现成本低但价值高。
