-- Apache Doris: 约束
--
-- 参考资料:
--   [1] Doris Data Model
--       https://doris.apache.org/docs/table-design/data-model

-- ============================================================
-- 1. 约束哲学: OLAP 引擎为何不支持传统约束
-- ============================================================
-- Doris 不支持 PRIMARY KEY(SQL 意义)、UNIQUE、FOREIGN KEY、CHECK 约束。
-- 这不是功能缺失，而是架构设计的必然选择。
--
-- 设计分析:
--   传统约束(MySQL/PG)在 INSERT/UPDATE 时实时检查——依赖行级锁和索引。
--   分布式列存引擎的写入路径: 批量数据 → 多节点并行写入 → 异步 Compaction。
--   在此架构下，实时约束检查的代价:
--     UNIQUE: 需要跨节点查重(分布式共识)，延迟从微秒级变为毫秒级
--     FOREIGN KEY: 需要跨表查找(分布式 JOIN)，写入吞吐降低 10-100 倍
--     CHECK: 可以本地检查(代价较低)，但 Doris 选择不实现
--
-- 对比:
--   StarRocks:  同样不支持传统约束(同源架构)
--   ClickHouse: 不支持 UNIQUE/FK，但 22.6+ 支持 CHECK 约束
--   BigQuery:   PRIMARY KEY/FOREIGN KEY 是信息性的(不强制执行)
--   MySQL:      完整约束支持(InnoDB)
--   PostgreSQL: 最完整的约束支持(CHECK/EXCLUDE/FK)
--
-- 对引擎开发者的启示:
--   约束的取舍是 OLTP vs OLAP 的核心分歧。
--   OLTP: 数据正确性 > 写入性能 → 强制约束
--   OLAP: 写入吞吐 > 数据正确性 → 数据质量在 ETL 层保证
--   BigQuery 的"信息性约束"是折中方案——语法接受但不执行，用于优化器。

-- ============================================================
-- 2. NOT NULL (唯一强制执行的约束)
-- ============================================================
CREATE TABLE users (
    id       BIGINT       NOT NULL,       -- Key 列必须 NOT NULL
    username VARCHAR(64)  NOT NULL,
    email    VARCHAR(255)                  -- 默认允许 NULL
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- 设计分析:
--   Key 列(DUPLICATE/AGGREGATE/UNIQUE KEY 中定义的列)必须 NOT NULL。
--   Value 列默认允许 NULL。
--   NOT NULL 是唯一在存储层强制执行的约束——因为它不需要跨行/跨节点检查。

-- ============================================================
-- 3. UNIQUE KEY 模型: "约束"的替代方案
-- ============================================================
CREATE TABLE users_unique (
    id       BIGINT       NOT NULL,
    username VARCHAR(64),
    email    VARCHAR(255)
)
UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- Merge-on-Write(1.2+): 写入时即保证唯一
CREATE TABLE users_mow (
    id       BIGINT       NOT NULL,
    username VARCHAR(64),
    email    VARCHAR(255)
)
UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES ("enable_unique_key_merge_on_write" = "true");

-- 设计分析:
--   UNIQUE KEY 模型通过"覆盖"而非"拒绝"来保证唯一——
--   相同 Key 的新行替换旧行，而不是报错。
--   这与 MySQL 的 UNIQUE 约束(冲突时报错)语义完全不同。
--
--   Merge-on-Read:  后台 Compaction 时合并 → 查询时可能看到多版本
--   Merge-on-Write: 写入时原地更新 → 查询时保证唯一(1.2+)

-- ============================================================
-- 4. AGGREGATE KEY 模型: 隐式约束
-- ============================================================
CREATE TABLE daily_stats (
    date    DATE         NOT NULL,
    user_id BIGINT       NOT NULL,
    clicks  BIGINT       SUM DEFAULT '0',
    revenue DECIMAL(10,2) SUM DEFAULT '0'
)
AGGREGATE KEY(date, user_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 16;

-- Value 列必须指定聚合方式——这是一种"模式约束"。
-- 聚合方式: SUM, MIN, MAX, REPLACE, REPLACE_IF_NOT_NULL,
--           HLL_UNION, BITMAP_UNION

-- ============================================================
-- 5. DEFAULT 值
-- ============================================================
CREATE TABLE users_def (
    id         BIGINT       NOT NULL,
    status     INT          DEFAULT '1',
    created_at DATETIME     DEFAULT CURRENT_TIMESTAMP
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- ============================================================
-- 6. 不支持的约束一览
-- ============================================================
-- PRIMARY KEY (SQL 标准):  不支持。用 UNIQUE KEY 模型替代。
-- UNIQUE:                  不支持。用 UNIQUE KEY 模型替代。
-- FOREIGN KEY:             不支持。在 ETL 层保证引用完整性。
-- CHECK:                   不支持。在 ETL 层验证。
-- EXCLUDE:                 不支持。PostgreSQL 特有。
--
-- 对比 StarRocks: 同样不支持。但 StarRocks 有独立的 PRIMARY KEY 语法。

-- ============================================================
-- 7. 数据完整性替代方案
-- ============================================================
-- 1. UNIQUE KEY + MoW 模型: 保证主键唯一(通过覆盖)
-- 2. ETL/应用层: 写入前验证数据质量
-- 3. INSERT INTO ... SELECT: 写入时做数据清洗
-- 4. Stream Load max_filter_ratio: 允许一定比例的错误行

INSERT INTO users VALUES (1, 'alice', 'alice@example.com');
INSERT INTO users VALUES (1, 'alice_new', 'alice_new@example.com');
-- Unique Key 表: id=1 的旧行被新行覆盖(不报错)
-- Duplicate Key 表: 两行都保留

-- ============================================================
-- 8. 约束设计的引擎开发者视角
-- ============================================================
-- Key 列必须在表定义的最前面(排序键决定物理布局)
-- Key 列不能被 ALTER TABLE 修改(修改排序键 = 重写全表)
-- AGGREGATE KEY Value 列必须有聚合类型(存储层依赖此信息)
--
-- 对引擎开发者的启示:
--   如果要在分布式列存引擎上支持唯一约束，有两种路径:
--   A. Doris/StarRocks 路径: 通过数据模型保证(写入时合并/覆盖)
--   B. BigQuery/Snowflake 路径: 接受语法但不执行(信息性约束)
--   路径 A 更诚实，路径 B 对迁移更友好。
--   不推荐 MySQL 5.7 的做法(CHECK 解析但不执行且不告知用户)。
