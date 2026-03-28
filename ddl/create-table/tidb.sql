-- TiDB: CREATE TABLE
--
-- 参考资料:
--   [1] TiDB SQL Reference - CREATE TABLE
--       https://docs.pingcap.com/tidb/stable/sql-statement-create-table
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB AUTO_RANDOM
--       https://docs.pingcap.com/tidb/stable/auto-random

-- ============================================================
-- 1. 基本语法
-- ============================================================
CREATE TABLE users (
    id         BIGINT       NOT NULL AUTO_RANDOM,
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        TEXT,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id) CLUSTERED,
    UNIQUE KEY uk_username (username),
    UNIQUE KEY uk_email (email)
);

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 AUTO_RANDOM: 分布式自增的核心创新
-- TiDB 最独特的设计是 AUTO_RANDOM（3.1+），解决分布式环境下自增热点问题。
--
-- 设计原理:
--   AUTO_INCREMENT 在 TiDB 中虽然兼容 MySQL 语法，但会导致写入热点:
--   所有递增 ID 的行都路由到同一个 TiKV Region（因为 Key 是有序的）。
--   AUTO_RANDOM 将 ID 的高位随机化，使写入分散到多个 Region。
--
-- 实现细节:
--   默认 SHARD_BITS = 5（32 个分片），可指定 AUTO_RANDOM(N)
--   ID = [符号位(1)] + [随机位(N)] + [自增位(64-1-N)]
--   AUTO_RANDOM(5): 高 5 位随机 → 32 个分片均匀写入
--   AUTO_RANDOM(3): 高 3 位随机 → 8 个分片（分片少但 ID 空间更大）
--
-- 对比其他分布式引擎的热点规避策略:
--   CockroachDB:  UUID (gen_random_uuid()) 或 unique_rowid()（时间戳+节点ID）
--   Spanner:      无自增，用 UUID 或 bit-reversed sequence
--   OceanBase:    AUTO_INCREMENT（依赖分区分散写入）
--   YugabyteDB:   Hash-sharded 主键
--
-- 对引擎开发者的启示:
--   分布式 OLTP 引擎如果要兼容 MySQL，AUTO_INCREMENT 是必须的但要标记为不推荐。
--   更好的方案是提供类似 AUTO_RANDOM 的内置替代品，对应用层透明。
--   UUID 虽然不会热点，但 128 位占用空间大，且无序导致 B+树分裂频繁。

CREATE TABLE orders (
    id BIGINT NOT NULL AUTO_RANDOM(5),   -- 5 bits = 32 shards
    user_id BIGINT NOT NULL,
    amount DECIMAL(10,2),
    PRIMARY KEY (id) CLUSTERED
);

-- 2.2 CLUSTERED vs NONCLUSTERED 主键（5.0+）
-- TiDB 独有的主键存储模式选择，暴露了分布式引擎的内部存储决策。
--
-- CLUSTERED:   行数据直接存储在主键索引中（类似 InnoDB 聚集索引）
--              Key = TablePrefix + TableID + PKValue → Row Data
-- NONCLUSTERED: 行数据用隐藏的 _tidb_rowid 存储，主键是二级索引
--              Key = TablePrefix + TableID + RowID → Row Data
--              PK Index: PKValue → RowID
--
-- 设计 trade-off:
--   CLUSTERED:    点查快（少一次索引查找），但主键值大时占用更多二级索引空间
--   NONCLUSTERED: 二级索引更紧凑（只存 RowID），但点查需要回表
--
-- 对比:
--   MySQL InnoDB:   总是 CLUSTERED，无选择
--   CockroachDB:    总是 CLUSTERED（主键即数据排列顺序）
--   PostgreSQL:     总是 NONCLUSTERED（堆表 + ctid）
--   SQL Server:     可选 CLUSTERED/NONCLUSTERED，与 TiDB 类似

CREATE TABLE accounts (
    id   BIGINT NOT NULL,
    name VARCHAR(64),
    PRIMARY KEY (id) NONCLUSTERED
);

-- 2.3 SHARD_ROW_ID_BITS: 无整数主键表的分片策略
-- 当表没有整数主键时，TiDB 自动生成 _tidb_rowid 作为隐式行 ID。
-- 默认 _tidb_rowid 递增 → 热点问题。SHARD_ROW_ID_BITS 将其打散。
--
-- PRE_SPLIT_REGIONS: 建表时预分裂 Region，避免初始写入集中。
--   SHARD_ROW_ID_BITS = 4 → 最多 16 个分片
--   PRE_SPLIT_REGIONS = 3 → 预创建 2^3 = 8 个 Region

CREATE TABLE logs (
    ts      DATETIME NOT NULL,
    message TEXT
) SHARD_ROW_ID_BITS = 4 PRE_SPLIT_REGIONS = 3;

-- ============================================================
-- 3. 分布式特有功能
-- ============================================================

-- 3.1 Placement Rules（数据放置策略，6.0+）
-- 控制数据副本在哪些区域/数据中心存储 — 这是分布式引擎独有的能力。
-- 核心应用: 数据合规（GDPR 要求数据不离开特定区域）、就近读取（降低延迟）
CREATE PLACEMENT POLICY us_east_policy
    PRIMARY_REGION = "us-east-1"
    REGIONS = "us-east-1,us-east-2"
    FOLLOWERS = 2;

CREATE TABLE sensitive_data (
    id   BIGINT NOT NULL AUTO_RANDOM,
    data TEXT,
    PRIMARY KEY (id)
) PLACEMENT POLICY = us_east_policy;

-- 对比其他分布式引擎的数据放置:
--   CockroachDB: LOCALITY REGIONAL BY ROW / GLOBAL（更细粒度，行级控制）
--   Spanner:     Instance-level placement（配置实例时选择区域）
--   OceanBase:   LOCALITY 和 PRIMARY_ZONE（副本级别控制）

-- 3.2 TiFlash 列存副本（4.0+）
-- TiDB 的 HTAP 核心: 同一张表同时有 TiKV（行存）和 TiFlash（列存）副本。
-- Raft Learner 机制异步复制，OLAP 查询自动路由到 TiFlash。
ALTER TABLE users SET TIFLASH REPLICA 1;

-- 设计分析:
--   优点: OLTP 和 OLAP 在同一集群，数据一致性由 Raft 保证，无需 ETL
--   缺点: 额外存储开销，列存副本有数据复制延迟（通常 < 1 秒）
--   对比: Oracle RAC + Exadata（行列混合但架构不同），SQL Server Columnstore Index

-- ============================================================
-- 4. 分区表（MySQL 兼容语法 + 分布式特性）
-- ============================================================
CREATE TABLE events (
    id         BIGINT NOT NULL AUTO_RANDOM,
    event_date DATE NOT NULL,
    data       JSON,
    PRIMARY KEY (id, event_date)
) PARTITION BY RANGE (YEAR(event_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);

-- TiDB 分区的特殊考量:
--   每个分区对应独立的 TiKV Region 组 → 分区裁剪效果与 Region 分布叠加
--   分区 + AUTO_RANDOM: 分区键必须在主键中（MySQL 继承限制），但 AUTO_RANDOM 仍然有效
--   LIST / LIST COLUMNS 分区: 7.0+ 支持
--   Key 分区: 支持，但 Hash 分区更推荐（Key 分区的 Hash 算法与 MySQL 不同）

-- ============================================================
-- 5. 临时表与 CTAS
-- ============================================================
CREATE TEMPORARY TABLE temp_result (id BIGINT, val INT);
CREATE GLOBAL TEMPORARY TABLE temp_session (
    id BIGINT, val INT
) ON COMMIT DELETE ROWS;

CREATE TABLE active_users AS SELECT id, username, email FROM users WHERE age >= 18;
CREATE TABLE users_backup LIKE users;

-- ============================================================
-- 6. 限制与注意事项
-- ============================================================
-- ENGINE 子句: 解析但忽略（始终使用 TiKV 存储）
-- 外键: 6.6+ 实验性支持，之前仅解析不执行
-- 全文索引: 不支持（建议使用 Elasticsearch 等外部方案）
-- 空间索引: 不支持
-- 触发器: 不支持（这是分布式引擎的常见缺失，触发器的跨节点语义难以定义）
-- 存储过程: 不支持（TiDB 定位为无状态 SQL 层，复杂逻辑放应用层）
-- CHECK 约束: 支持（与 MySQL 8.0.16+ 行为一致）

-- ============================================================
-- 7. 版本演进
-- ============================================================
-- TiDB 3.0: 悲观事务模式
-- TiDB 3.1: AUTO_RANDOM
-- TiDB 4.0: TiFlash 列存，大事务支持（10GB+）
-- TiDB 5.0: Clustered Index 支持，MPP 引擎（TiFlash 并行计算）
-- TiDB 6.0: Placement Rules in SQL, Top SQL
-- TiDB 6.5: 索引加速（DDL 改进），全局内存控制
-- TiDB 6.6: 外键（实验性），多值索引（JSON 数组）
-- TiDB 7.0: 资源管控（Resource Control），LIST COLUMNS 分区
-- TiDB 7.1: TiDB Lightning 集成改进, TiCDC 增强
-- TiDB 7.5: LTS，分布式执行框架改进
-- TiDB 8.0: 全局排序增强，向量搜索（实验性），TTL GA
-- TiDB 8.5: LTS（2025），改进的并行 DDL，增强资源管控

-- ============================================================
-- 8. 横向对比: TiDB vs 其他分布式引擎的 CREATE TABLE
-- ============================================================
-- 1. 存储架构:
--    TiDB:        无状态 SQL 层 + TiKV(行存) + TiFlash(列存)，Raft 共识
--    CockroachDB: 存储和计算紧耦合，每个节点既是 SQL 也是存储，Raft 共识
--    Spanner:     分离的 compute + Colossus 存储，TrueTime 外部一致性
--    OceanBase:   共享无架构，LSM-Tree 存储，Paxos 共识
--
-- 2. MySQL 兼容性:
--    TiDB:      最高（协议级兼容，大多数 MySQL 客户端直接连接）
--    OceanBase: 高（MySQL 模式，但双模式增加了复杂度）
--    其他:       不兼容 MySQL（CockroachDB 兼容 PostgreSQL，Spanner 独立方言）
--
-- 3. 热点规避:
--    TiDB:        AUTO_RANDOM（ID 高位随机化）
--    CockroachDB: UUID + Hash-sharded index
--    Spanner:     bit-reversed sequence / UUID
--    OceanBase:   分区策略分散
