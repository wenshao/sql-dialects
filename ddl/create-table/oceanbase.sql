-- OceanBase: CREATE TABLE
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase Architecture
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [3] OceanBase - LSM-Tree Storage Engine
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- 1. 基本语法 — MySQL 模式
-- ============================================================
CREATE TABLE users (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        TEXT,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_username (username),
    UNIQUE KEY uk_email (email)
);

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 双模式架构: MySQL 模式 vs Oracle 模式
-- OceanBase 最独特的设计是同一引擎支持两种 SQL 方言。
-- 每个"租户"(tenant) 在创建时选择模式，模式决定了:
--   - SQL 语法（CREATE TABLE 语法差异巨大）
--   - 数据类型（INT vs NUMBER, VARCHAR vs VARCHAR2）
--   - 内置函数（NOW() vs SYSDATE, CONCAT vs ||）
--   - 事务语义（自动提交 vs 显式提交）
--
-- 设计 trade-off:
--   优点: 降低 MySQL 和 Oracle 用户的迁移成本，一个引擎覆盖两个生态
--   缺点: 引擎复杂度倍增（解析器、优化器、执行器都要双路径），
--         两种模式的交集功能最稳定，各自的边缘特性兼容性可能不完整
--
-- 对比:
--   TiDB:        只兼容 MySQL（专注单一方言，兼容性更高）
--   CockroachDB: 只兼容 PostgreSQL
--   Spanner:     独立方言 GoogleSQL（不兼容任何传统数据库）
--   Aurora:      MySQL 和 PostgreSQL 是两个独立产品（不是双模式）
--
-- 对引擎开发者的启示:
--   双模式是商业上的差异化策略，但工程成本极高。
--   如果选择双模式，建议在存储层统一，只在 SQL 层分叉。
--   OceanBase 的实践证明这条路可行但需要巨大投入。

-- 2.2 Tablegroup: 表组共置（OceanBase 独有）
-- 将相关表的数据放在同一组 OBServer 节点上，优化 JOIN 性能。
-- 核心原理: 共置的表在同一节点上执行 JOIN 可避免网络传输。
CREATE TABLEGROUP tg_order;
CREATE TABLE orders (
    id      BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    amount  DECIMAL(10,2),
    PRIMARY KEY (id)
) TABLEGROUP = tg_order;

-- 设计分析:
--   优点: 显式控制数据共置，DBA 可以优化关键 JOIN 路径
--   缺点: 需要 DBA 手动规划，增加运维复杂度；表组内的表不能随意重分布
--
-- 对比其他引擎的共置策略:
--   Spanner:     INTERLEAVE IN PARENT（物理共置父子表，更自动化）
--   CockroachDB: Column families + Locality 控制（不同粒度）
--   Citus:       co-location groups（按分布列共置）
--   TiDB:        无显式共置机制（依赖 TiKV 的 Region 调度）

-- 2.3 Primary Zone 和 Locality: 副本放置控制
-- OceanBase 通过 Paxos 共识协议维护多副本，这两个参数控制副本分布。
CREATE TABLE hot_data (
    id   BIGINT NOT NULL AUTO_INCREMENT,
    data VARCHAR(256),
    PRIMARY KEY (id)
) PRIMARY_ZONE = 'zone1';

-- PRIMARY_ZONE: 控制 Leader 副本所在的 Zone（决定写入路由和读延迟）
-- LOCALITY:     控制副本类型和分布（F=Full, R=ReadOnly, L=LogOnly）
ALTER TABLE users LOCALITY = 'F@zone1, F@zone2, R@zone3';

-- 对比:
--   TiDB:        Placement Rules（SQL 层指定 Region/Zone 放置策略）
--   CockroachDB: LOCALITY REGIONAL BY ROW/TABLE（行级或表级区域控制）
--   Spanner:     Instance 配置时选择区域（创建后不可更改实例级别的区域配置）

-- ============================================================
-- 3. LSM-Tree 存储引擎对 DDL 的影响
-- ============================================================
-- OceanBase 使用 LSM-Tree 存储，与 B+Tree (InnoDB) 的关键差异:
--   写入: 先写 MemTable（内存），后台 Compact 到 SSTable（磁盘）
--         写放大低于 B+Tree，但读放大可能更高（需要合并多层查找）
--   DDL:  ALTER TABLE 添加列在 LSM-Tree 中更高效（只需修改 Schema，
--         不需要重写数据文件，新数据按新 Schema 写入，旧数据读取时适配）
--
-- 对引擎开发者的启示:
--   LSM-Tree 的 Schema Evolution 天然友好（append-only 特性），
--   但 Compaction 的资源消耗需要精细控制，避免影响在线业务。

-- ============================================================
-- 4. 分区表（核心功能）
-- ============================================================
-- OceanBase 中分区是数据分布的核心单位（不同于 MySQL 的可选优化）。
-- 每个分区是一个独立的 Paxos 组，有自己的 Leader 副本。

-- KEY 分区（支持非整数列，OceanBase 扩展）
CREATE TABLE big_table (
    id   BIGINT NOT NULL,
    name VARCHAR(64),
    PRIMARY KEY (id)
) PARTITION BY KEY(id) PARTITIONS 16;

-- RANGE 分区
CREATE TABLE logs (
    id       BIGINT NOT NULL AUTO_INCREMENT,
    log_date DATE NOT NULL,
    message  TEXT,
    PRIMARY KEY (id, log_date)
) PARTITION BY RANGE(YEAR(log_date)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);

-- RANGE COLUMNS + 二级分区（4.0+）
CREATE TABLE sales (
    id        BIGINT NOT NULL,
    region    VARCHAR(32) NOT NULL,
    sale_date DATE NOT NULL,
    amount    DECIMAL(10,2),
    PRIMARY KEY (id, region, sale_date)
) PARTITION BY RANGE COLUMNS(sale_date)
  SUBPARTITION BY KEY(region) SUBPARTITIONS 4 (
    PARTITION p2023 VALUES LESS THAN ('2024-01-01'),
    PARTITION p2024 VALUES LESS THAN ('2025-01-01')
);

-- 分区设计对比:
--   OceanBase: 分区 = 数据分布单位（每个分区独立 Paxos 组）
--   TiDB:      Region = 数据分布单位（分区只是逻辑概念，Region 自动分裂/合并）
--   CockroachDB: Range = 数据分布单位（基于主键范围自动分裂）
--   Spanner:    Split = 数据分布单位（自动管理，用户不直接控制）

-- ============================================================
-- 5. Oracle 模式
-- ============================================================
-- Oracle 模式使用完全不同的语法和类型系统。

-- CREATE TABLE users_ora (
--     id         NUMBER       NOT NULL,
--     username   VARCHAR2(64) NOT NULL,
--     email      VARCHAR2(255) NOT NULL,
--     age        NUMBER(3),
--     balance    NUMBER(10,2) DEFAULT 0.00,
--     bio        CLOB,
--     created_at TIMESTAMP    DEFAULT SYSTIMESTAMP NOT NULL,
--     CONSTRAINT pk_users PRIMARY KEY (id),
--     CONSTRAINT uk_username UNIQUE (username)
-- );
-- CREATE SEQUENCE seq_users START WITH 1 INCREMENT BY 1;

-- ============================================================
-- 6. 限制与注意事项
-- ============================================================
-- 全文索引: 4.0+ 支持（MySQL 模式）
-- 空间索引: 4.0+ 支持（MySQL 模式）
-- 外键: 完全支持且强制执行（优于 TiDB 的实验性支持）
-- CHECK 约束: 4.0+ 支持
-- 触发器: MySQL 模式有限支持，Oracle 模式较完整
-- 存储过程: MySQL 模式有限支持，Oracle 模式完整支持 PL/SQL

-- ============================================================
-- 7. 版本演进
-- ============================================================
-- OceanBase 1.x: 内部孵化（阿里巴巴/蚂蚁集团内部使用）
-- OceanBase 2.x: 支持 MySQL 协议兼容
-- OceanBase 3.x: 开源版本，Oracle 模式增强，分布式事务优化
-- OceanBase 4.0: 单机分布式一体化架构，大幅降低小规模部署成本
--                全文索引、空间索引、JSON 增强，LSM-Tree Compaction 优化
-- OceanBase 4.1: 备份恢复增强，物化视图，SQL 审计增强
-- OceanBase 4.2: 列存引擎（HTAP），Online DDL 增强，资源隔离
-- OceanBase 4.3: 列存增强，AP 性能大幅提升，向量化执行引擎优化

-- ============================================================
-- 8. 横向对比: OceanBase vs 其他引擎
-- ============================================================
-- 1. 共识协议:
--    OceanBase: Paxos（自研实现，日志级同步）
--    TiDB:      Raft（etcd 实现，Region 级同步）
--    CockroachDB: Raft（Range 级同步）
--    Spanner:   Paxos（Google 实现 + TrueTime）
--
-- 2. 存储引擎:
--    OceanBase: LSM-Tree（写优化，Compaction 管理是关键）
--    TiDB:      RocksDB（也是 LSM-Tree，但由 TiKV 管理）
--    CockroachDB: Pebble（Go 实现的 LSM-Tree，替代了早期的 RocksDB）
--    MySQL:     B+Tree（InnoDB，读优化）
--
-- 3. 多租户:
--    OceanBase: 原生多租户（资源隔离到 CPU/内存/IO 级别），业界领先
--    TiDB:      资源管控（7.0+），非原生多租户
--    CockroachDB: 多租户（Serverless 版本），基于虚拟集群
--    Spanner:   Instance 级隔离
