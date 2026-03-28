-- MariaDB: CREATE TABLE
-- MySQL fork with diverging features since MariaDB 10.x
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - CREATE TABLE
--       https://mariadb.com/kb/en/create-table/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/
--   [3] MariaDB System-Versioned Tables
--       https://mariadb.com/kb/en/system-versioned-tables/

-- ============================================================
-- 1. 基本语法
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- 2. MariaDB 独有特性: INVISIBLE 列 (10.3.3+)
-- ============================================================
-- INVISIBLE 列不出现在 SELECT * 中, 必须显式引用
-- 设计动机: 向表添加内部字段而不影响已有应用代码
CREATE TABLE audit_events (
    id            BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event         VARCHAR(255) NOT NULL,
    detail        TEXT,
    internal_flag TINYINT INVISIBLE DEFAULT 0,
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP
);
-- SELECT * FROM audit_events 不返回 internal_flag
-- SELECT internal_flag FROM audit_events 才可见
--
-- 对比 MySQL 8.0: MySQL 有 INVISIBLE INDEX 但没有 INVISIBLE COLUMN
-- 对比 Oracle 12c: 也有 INVISIBLE COLUMN, 语法相似
-- 设计启示: INVISIBLE 列是 schema 演进的低成本方案, 比 ALTER + 应用改造轻量

-- ============================================================
-- 3. SEQUENCE 对象 (10.3+)
-- ============================================================
-- MariaDB 引入 Oracle 风格的 SEQUENCE, MySQL 至今不支持
CREATE SEQUENCE seq_orders START WITH 1 INCREMENT BY 1
    MINVALUE 1 MAXVALUE 9999999999 CACHE 1000 CYCLE;
SELECT NEXT VALUE FOR seq_orders;
SELECT PREVIOUS VALUE FOR seq_orders;
-- 设计动机: AUTO_INCREMENT 绑定到单表, SEQUENCE 可跨表共享
-- 对比 MySQL: 只有 AUTO_INCREMENT, 无 SEQUENCE
-- 对比 PostgreSQL: SERIAL (语法糖) → IDENTITY (10+), 也有独立 SEQUENCE
-- 对比 Oracle: SEQUENCE 是最早的实现 (8i+), MariaDB 语法最接近 Oracle

-- ============================================================
-- 4. 系统版本表 (System-Versioned Tables, 10.3.4+)
-- ============================================================
-- SQL:2011 标准的 temporal table 实现, MySQL 完全不支持
CREATE TABLE products (
    id    BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name  VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL
) WITH SYSTEM VERSIONING;

-- 带显式历史列的版本表
CREATE TABLE contracts (
    id        BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    client    VARCHAR(255),
    amount    DECIMAL(10,2),
    row_start TIMESTAMP(6) GENERATED ALWAYS AS ROW START INVISIBLE,
    row_end   TIMESTAMP(6) GENERATED ALWAYS AS ROW END INVISIBLE,
    PERIOD FOR SYSTEM_TIME (row_start, row_end)
) WITH SYSTEM VERSIONING;

-- 查询历史数据 (时间旅行查询)
SELECT * FROM products FOR SYSTEM_TIME AS OF '2024-01-01';
SELECT * FROM products FOR SYSTEM_TIME BETWEEN '2024-01-01' AND '2024-06-01';
SELECT * FROM products FOR SYSTEM_TIME ALL;

-- 设计分析:
--   MariaDB 是首个实现 SQL:2011 temporal table 的主流开源数据库
--   内部实现: 历史行存储在隐藏的历史分区中, 当前行在主分区
--   优点: 审计追踪零代码, 数据恢复简单, 合规需求天然满足
--   缺点: 历史数据膨胀快, 需要定期归档 (DELETE HISTORY 语句)
--   对比 SQL Server: Temporal Table (2016+), 需要显式历史表
--   对比 Oracle: Flashback Query 基于 undo, 不是持久化历史

-- ============================================================
-- 5. WITHOUT OVERLAPS 约束 (10.5.3+)
-- ============================================================
-- 时间段不重叠约束, 解决预订冲突问题
CREATE TABLE bookings (
    room_id    INT NOT NULL,
    start_date DATE NOT NULL,
    end_date   DATE NOT NULL,
    PERIOD FOR booking_period (start_date, end_date),
    UNIQUE (room_id, booking_period WITHOUT OVERLAPS)
);
-- 数据库层面保证同一房间的预订时间不重叠
-- 对比: 其他数据库需要触发器或应用层逻辑实现

-- ============================================================
-- 6. CREATE OR REPLACE TABLE
-- ============================================================
-- MariaDB 独有扩展, MySQL 不支持
CREATE OR REPLACE TABLE temp_data (id INT, val VARCHAR(100));
-- 等价于 DROP TABLE IF EXISTS + CREATE TABLE, 但原子性更好

-- ============================================================
-- 7. Spider 存储引擎: 内置分片 (10.0+)
-- ============================================================
CREATE TABLE sharded_orders (
    id     BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    amount DECIMAL(10,2)
) ENGINE=Spider
  COMMENT='wrapper "mysql", table "orders"'
  PARTITION BY HASH(id) (
    PARTITION p1 COMMENT = 'srv "shard1"',
    PARTITION p2 COMMENT = 'srv "shard2"'
);
-- Spider 引擎透明地将数据分布到多个后端 MariaDB 实例
-- 对比 MySQL: 需要 MySQL Cluster (NDB) 或中间件 (ProxySQL/Vitess)
-- 对比 MySQL: Spider 是 MariaDB 独有的, 基于 PARTITION 语法路由

-- ============================================================
-- 8. CONNECT 存储引擎: 外部数据访问
-- ============================================================
CREATE TABLE csv_data (
    id   INT NOT NULL,
    name VARCHAR(100),
    val  DOUBLE
) ENGINE=CONNECT TABLE_TYPE=CSV FILE_NAME='/data/input.csv' HEADER=1;
-- 可直接查询 CSV/JSON/XML/ODBC 数据源, 无需 ETL
-- 对比 MySQL: 无等价功能; PostgreSQL 有 FDW (Foreign Data Wrapper)

-- ============================================================
-- 9. 与 MySQL 8.0 的关键分歧
-- ============================================================
-- 1. 数据字典: MariaDB 保留 .frm 文件, MySQL 8.0 迁移到 InnoDB 数据字典
-- 2. 认证插件: MariaDB 默认 mysql_native_password, MySQL 8.0+ 默认 caching_sha2
-- 3. 索引可见性: MariaDB 用 IGNORED/NOT IGNORED, MySQL 用 INVISIBLE/VISIBLE
-- 4. CLONE 插件: MySQL 8.0 独有, MariaDB 无等价功能
-- 5. 窗口函数: 两者都支持 (MariaDB 10.2+), 但实现和优化路径不同
-- 6. JSON: MySQL 用二进制存储, MariaDB 用 LONGTEXT + 验证
-- 7. CHECK 约束: MariaDB 从 10.2.1 开始真正执行, MySQL 从 8.0.16
--
-- 对引擎开发者的启示:
--   MariaDB 的 fork 策略展示了: 兼容性 vs 创新的平衡
--   SEQUENCE/系统版本表/INVISIBLE 列等都是 MariaDB 领先于 MySQL 的特性
--   但 MySQL 8.0 的数据字典重构、CLONE 插件等架构级改进 MariaDB 未跟进
--   分叉后的引擎需要选择: 跟随上游(兼容) vs 独立创新(差异化)
