-- MySQL: CREATE TABLE
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - CREATE TABLE
--       https://dev.mysql.com/doc/refman/8.0/en/create-table.html
--   [2] MySQL 8.0 Reference Manual - Data Types
--       https://dev.mysql.com/doc/refman/8.0/en/data-types.html
--   [3] MySQL 8.0 Reference Manual - AUTO_INCREMENT
--       https://dev.mysql.com/doc/refman/8.0/en/example-auto-increment.html

-- ============================================================
-- 基本建表
-- ============================================================
-- 一个典型的业务表，包含了 MySQL 建表中最常用的特性
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

-- 设计要点:
--   1. 主键用 BIGINT 而非 INT: INT 最大约 21 亿，大表容易溢出
--   2. AUTO_INCREMENT: MySQL 特有的自增语法，简单但在分布式场景下有问题（见下文）
--   3. ON UPDATE CURRENT_TIMESTAMP: MySQL 特有，自动更新修改时间，其他数据库需要触发器
--   4. ENGINE=InnoDB: 5.5+ 默认引擎，支持事务、行级锁、外键。MyISAM 已不推荐
--   5. utf8mb4: 真正的 UTF-8（支持 emoji），不要用 utf8（只支持 3 字节，BMP 子集）
--   6. COLLATE utf8mb4_unicode_ci: 大小写不敏感比较，生产环境推荐
--      8.0 默认是 utf8mb4_0900_ai_ci（Unicode 9.0，重音不敏感）

-- ============================================================
-- DATETIME vs TIMESTAMP 选择
-- ============================================================
-- 这是 MySQL 中最容易踩坑的类型选择之一
CREATE TABLE events (
    id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,

    -- DATETIME: 存什么就是什么，不做时区转换
    --   存储: 5 字节（5.6.4+），之前 8 字节
    --   范围: '1000-01-01 00:00:00' ~ '9999-12-31 23:59:59'
    --   适用: 业务时间（订单时间、出生日期等，不随时区变化的数据）
    event_time DATETIME NOT NULL,

    -- TIMESTAMP: 存储为 UTC，读取时按 session time_zone 转换
    --   存储: 4 字节
    --   范围: '1970-01-01 00:00:01' UTC ~ '2038-01-19 03:14:07' UTC (2038 年问题!)
    --   适用: 系统时间（created_at、updated_at）
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP

    -- 建议: 如果不确定，用 DATETIME。TIMESTAMP 的 2038 年问题在长生命周期系统中是真实风险
);

-- ============================================================
-- VARCHAR 长度设计
-- ============================================================
-- VARCHAR(n) 中 n 是字符数，不是字节数
-- utf8mb4 下一个字符最多占 4 字节，但 VARCHAR(255) 不会比 VARCHAR(64) 多占空间
-- 实际占用 = 实际字符数 × 字节/字符 + 1 或 2 字节长度前缀
--
-- 但 n 的选择影响:
--   1. 内存分配: 临时表和排序时按 n × 4 字节分配（InnoDB internal temp table 除外）
--   2. 索引限制: InnoDB 单列索引最大 767 字节（innodb_large_prefix=OFF）或 3072 字节
--      VARCHAR(255) × 4 字节 = 1020 字节，超过 767，需要前缀索引或开启 large_prefix
--   3. 行大小限制: InnoDB 行最大 65535 字节（所有 VARCHAR 列长度之和）
--
-- 最佳实践: 按业务含义选择合理的长度，不要无脑 VARCHAR(255)

-- ============================================================
-- 自增主键的坑
-- ============================================================
-- AUTO_INCREMENT 在单机场景简单好用，但有几个陷阱:
--
-- 1. 重启后可能回退 (5.7 及之前):
--    MySQL 5.7 中 AUTO_INCREMENT 值存在内存，重启后取 MAX(id)+1
--    如果最大 id 的行被删除了，重启后 id 会被复用
--    8.0 修复: AUTO_INCREMENT 值持久化到 redo log
--
-- 2. INSERT ... ON DUPLICATE KEY UPDATE 会消耗 AUTO_INCREMENT 值:
--    即使实际执行的是 UPDATE（没有新行），自增值也会 +1，造成 id 跳跃
--
-- 3. 批量插入的自增分配:
--    InnoDB 默认 innodb_autoinc_lock_mode=2（8.0+）
--    并发批量插入时 id 可能不连续，但性能更好
--    如果业务要求 id 连续，需要设为 1（不推荐，影响并发性能）
--
-- 4. 分布式场景不适用:
--    AUTO_INCREMENT 是单机概念，分库分表后会冲突
--    替代方案: UUID, 雪花算法, TiDB 的 AUTO_RANDOM

-- ============================================================
-- CHECK 约束的历史
-- ============================================================
-- MySQL 对 CHECK 约束的支持是一个著名的"坑":
--   5.7 及之前: 语法上接受 CHECK，但解析后直接忽略！不报错也不执行
--   8.0.16+: CHECK 约束真正被执行
CREATE TABLE products (
    id    BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name  VARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    stock INT NOT NULL DEFAULT 0,
    CHECK (price >= 0),                   -- 8.0.16+ 才真正生效
    CHECK (stock >= 0)
) ENGINE=InnoDB;

-- 如果需要兼容 5.7，用触发器代替 CHECK

-- ============================================================
-- 索引设计
-- ============================================================
CREATE TABLE orders (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id     BIGINT       NOT NULL,
    status      TINYINT      NOT NULL DEFAULT 0 COMMENT '0:待支付 1:已支付 2:已发货 3:已完成 4:已取消',
    amount      DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    order_no    VARCHAR(32)  NOT NULL COMMENT '订单号',
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- 索引设计原则:
    -- 1. 高选择性列放前面（user_id 比 status 选择性高）
    -- 2. 覆盖索引: 把查询需要的列都放进索引，避免回表
    -- 3. 最左前缀原则: (a, b, c) 的索引可以用于 WHERE a=? / WHERE a=? AND b=? / 但不能用于 WHERE b=?

    UNIQUE KEY uk_order_no (order_no),
    INDEX idx_user_status (user_id, status),         -- 复合索引: 查某用户的某状态订单
    INDEX idx_created (created_at),                   -- 按时间范围查询

    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='订单表';

-- COMMENT: 给表和列加注释是好习惯，很多团队强制要求
-- TINYINT vs ENUM: 状态字段用 TINYINT + 注释比 ENUM 更灵活（ENUM 加值需要 ALTER TABLE）

-- ============================================================
-- 8.0+ 新特性
-- ============================================================

-- 8.0+: 表达式默认值（5.7 只允许常量）
CREATE TABLE logs (
    id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    log_uuid   BINARY(16) NOT NULL DEFAULT (UUID_TO_BIN(UUID())),  -- 8.0+
    data       JSON,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),  -- 毫秒精度

    -- 8.0+: 函数索引（表达式索引）
    -- 可以对 JSON 字段的提取值建索引
    INDEX idx_data_name ((CAST(data->>'$.name' AS CHAR(64)) COLLATE utf8mb4_bin))
) ENGINE=InnoDB;

-- 8.0+: 不可见索引（优化器忽略，但仍维护）
-- 用途: 想删索引但不确定影响，先设为 INVISIBLE 观察
ALTER TABLE orders ALTER INDEX idx_created INVISIBLE;
-- 观察一段时间无影响后再真正删除
-- ALTER TABLE orders DROP INDEX idx_created;
-- 确认有影响，恢复可见
ALTER TABLE orders ALTER INDEX idx_created VISIBLE;

-- ============================================================
-- CREATE TABLE ... SELECT / LIKE
-- ============================================================
-- CTAS: 从查询结果建表（不复制索引和约束，只复制数据和列类型）
CREATE TABLE active_users AS
SELECT id, username, email, created_at FROM users WHERE age >= 18;
-- 注意: 新表没有主键、没有索引、没有 AUTO_INCREMENT，需要手动添加

-- LIKE: 复制表结构（包括索引和约束，但不复制数据）
CREATE TABLE users_backup LIKE users;
-- 然后: INSERT INTO users_backup SELECT * FROM users;

-- IF NOT EXISTS: 条件建表
CREATE TABLE IF NOT EXISTS audit_log (
    id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    action     VARCHAR(50) NOT NULL,
    details    JSON,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ============================================================
-- 分区表
-- ============================================================
-- 适用场景: 大表按时间或范围分区，加速查询和数据管理（按分区删除历史数据）
CREATE TABLE access_logs (
    id         BIGINT NOT NULL AUTO_INCREMENT,
    user_id    BIGINT NOT NULL,
    action     VARCHAR(50) NOT NULL,
    created_at DATETIME NOT NULL,
    PRIMARY KEY (id, created_at)           -- 分区键必须是主键的一部分
) ENGINE=InnoDB
PARTITION BY RANGE (YEAR(created_at)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);
-- 注意: 分区键必须包含在主键和所有唯一索引中，这是 MySQL 分区表最大的限制

-- ============================================================
-- 临时表
-- ============================================================
CREATE TEMPORARY TABLE tmp_results (
    id    BIGINT PRIMARY KEY,
    score DECIMAL(5,2)
) ENGINE=MEMORY;  -- MEMORY 引擎: 全内存，会话结束自动销毁，断电丢失
-- 也可以用 ENGINE=InnoDB（支持事务，但比 MEMORY 慢）

-- ============================================================
-- 版本演进总结
-- ============================================================
-- MySQL 5.6:  InnoDB 全文索引, DATETIME 微秒精度
-- MySQL 5.7:  JSON 类型, 虚拟生成列, sys schema
-- MySQL 8.0:  窗口函数, CTE, CHECK 约束(8.0.16+), 不可见索引,
--             表达式默认值, 函数索引, 原子 DDL, 降序索引,
--             AUTO_INCREMENT 持久化, utf8mb4 为默认字符集
-- MySQL 8.0.13: DEFAULT 支持表达式
-- MySQL 8.0.16: CHECK 约束真正执行
-- MySQL 8.0.17: UNSIGNED/ZEROFILL/显示宽度 废弃
-- MySQL 8.0.19: VALUES ROW() 语法, ON DUPLICATE KEY UPDATE 别名
-- MySQL 8.0.31: INTERSECT / EXCEPT 支持
