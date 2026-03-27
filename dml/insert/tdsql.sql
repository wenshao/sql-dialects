-- TDSQL: INSERT
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557
--   [3] TDSQL Distributed Transaction Guide
--       https://cloud.tencent.com/document/product/557/10575

-- ============================================================
-- 1. 基本 INSERT
-- ============================================================

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入（批量 VALUES）
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 插入并忽略重复（匹配唯一索引/主键冲突时静默跳过）
INSERT IGNORE INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- VALUES 行别名（8.0.19+ 兼容语法）
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25) AS new
ON DUPLICATE KEY UPDATE email = new.email;

-- 获取自增 ID
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
SELECT LAST_INSERT_ID();

-- 指定列默认值
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);

-- SET 语法（MySQL 特有）
INSERT INTO users SET username = 'alice', email = 'alice@example.com', age = 25;

-- ============================================================
-- 2. shardkey 与 INSERT 路由
-- ============================================================
-- TDSQL 中数据按 shardkey 分布到不同分片。INSERT 的路由行为:
--
-- (1) shardkey 列必须出现在 INSERT 语句中:
--     如果 shardkey 是 id（AUTO_INCREMENT 列），系统自动分配路由
--     如果 shardkey 是显式列（如 user_id），INSERT 时必须提供值
--
-- (2) 单行 INSERT 路由:
INSERT INTO users (id, username, email, age)
VALUES (42, 'alice', 'alice@example.com', 25);
--     当 id 是 shardkey 时，此 INSERT 路由到 id=42 所在的分片
--     只需一次 RPC，延迟最低

-- (3) 批量 INSERT 路由:
INSERT INTO users (id, username, email, age) VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30),
    (3, 'charlie', 'charlie@example.com', 35);
--     三行可能路由到 1-3 个不同分片
--     TDSQL 自动将行按 shardkey 分组，分别发送到对应分片
--     涉及 N 个分片时使用分布式事务（2PC）保证原子性

-- ============================================================
-- 3. AUTO_INCREMENT 在分布式环境下的行为
-- ============================================================
--
-- TDSQL 的 AUTO_INCREMENT 保证全局唯一但不保证连续:
--   - 使用中心化的 ID 分配器（或雪花算法）生成全局唯一 ID
--   - ID 可能不连续（跨分片分配时有间隔）
--   - 性能优化: 每个分片预分配一段 ID 范围，减少中心化协调
--
-- LAST_INSERT_ID() 的行为:
--   - 单行 INSERT: 返回当前行的自增 ID
--   - 多行 INSERT: 返回第一行的自增 ID（与 MySQL 一致）
--   - 批量 INSERT 涉及多分片时: 返回第一个成功插入行的 ID

-- ============================================================
-- 4. 跨分片 INSERT ... SELECT
-- ============================================================

-- 当 SELECT 的源表和 INSERT 的目标表在不同分片时:
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;
-- TDSQL 生成分布式执行计划:
--   (1) 向 users 所在分片下发 SELECT 请求
--   (2) 收集结果数据到协调节点
--   (3) 按 shardkey 重新分发到目标表的分片
--   (4) 各分片并行执行 INSERT
--   (5) 使用分布式事务保证整体原子性

-- 性能建议:
--   避免大结果集的 INSERT ... SELECT（可能导致分布式事务超时）
--   分批执行: 先 SELECT INTO 临时表，再分批 INSERT

-- ============================================================
-- 5. 广播表的 INSERT
-- ============================================================
-- 广播表（小表广播）: 数据完整复制到每个分片节点
--
-- 广播表的 INSERT 特点:
--   - INSERT 同步写入所有节点
--   - 使用分布式事务保证所有节点的一致性
--   - 适合维度表、配置表等小表
--   - 不存在 shardkey 路由问题（每个节点都有完整数据）
--
-- 示例:
-- INSERT INTO sys_config (config_key, config_value) VALUES ('timeout', '30');
-- 所有分片同时执行此 INSERT

-- ============================================================
-- 6. INSERT 性能优化
-- ============================================================
--
-- (1) 确保 INSERT 包含 shardkey 列值:
--     避免 TDSQL 无法路由而广播到所有分片
--
-- (2) 批量 INSERT 时按 shardkey 排序:
--     相同分片的行聚合在一起，减少分布式事务分支数
--     例如: INSERT INTO t VALUES (1,...),(2,...),(3,...)
--     如果 1,2 在分片A，3 在分片B，只需 2 个分支（而非 3 个）
--
-- (3) 控制单次批量 INSERT 的行数:
--     推荐 1000-5000 行/批次
--     过多行导致分布式事务持有锁时间长
--
-- (4) 避免在事务中混合不同 shardkey 的操作:
--     跨分片事务的性能远低于单分片事务
--     尽量让一个事务内的操作在同一个分片
--
-- (5) 使用 LOAD DATA 替代大批量 INSERT:
--     LOAD DATA INFILE '/tmp/users.csv' INTO TABLE users
--     FIELDS TERMINATED BY ',' ENCLOSED BY '"'
--     LINES TERMINATED BY '\n' IGNORE 1 LINES;
--     TDSQL 对 LOAD DATA 有专门的分布式优化

-- ============================================================
-- 7. 横向对比: TDSQL vs 单机 MySQL INSERT
-- ============================================================
-- 语法兼容性: TDSQL INSERT 语法与 MySQL 完全兼容
-- 主要差异在执行层面:
--
-- 单机 MySQL:
--   INSERT 直接写入本地 InnoDB
--   AUTO_INCREMENT 连续
--   LOAD DATA 绕过 SQL 层
--
-- TDSQL:
--   INSERT 按 shardkey 路由到分片
--   AUTO_INCREMENT 全局唯一但不连续
--   跨分片操作使用分布式事务
--   LOAD DATA 自动按 shardkey 分发
--
-- 迁移注意:
--   (1) 检查 INSERT 是否包含 shardkey 列
--   (2) 检查唯一索引是否包含 shardkey 列
--   (3) 应用中依赖 LAST_INSERT_ID() 连续的逻辑需要调整
--   (4) 大事务需要拆分为小事务以适配分布式环境
