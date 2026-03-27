-- TDSQL: UPSERT
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
-- 1. ON DUPLICATE KEY UPDATE（推荐方式）
-- ============================================================

-- 基本用法：冲突时更新
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON DUPLICATE KEY UPDATE
    email = VALUES(email),
    age = VALUES(age);

-- 8.0.19+ 推荐用行别名替代 VALUES()（VALUES() 已废弃）
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25) AS new
ON DUPLICATE KEY UPDATE
    email = new.email,
    age = new.age;

-- 条件更新：只在特定条件下才更新
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 30) AS new
ON DUPLICATE KEY UPDATE
    email = new.email,
    age = IF(new.age > users.age, new.age, users.age);

-- ============================================================
-- 2. REPLACE INTO（注意副作用）
-- ============================================================

-- REPLACE INTO = 先 DELETE 再 INSERT（有严重副作用，见下文）
REPLACE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);

-- REPLACE 的隐藏风险:
--   1. AUTO_INCREMENT 值会变（新行获得新 ID，旧 ID 丢失）
--   2. 触发 DELETE + INSERT 触发器（不是 UPDATE 触发器）
--   3. 级联删除的外键会删除子表数据！
--   4. 在分布式环境下，REPLACE 的 DELETE + INSERT 涉及跨分片操作风险
-- 结论: 能用 ON DUPLICATE KEY UPDATE 就不要用 REPLACE INTO

-- ============================================================
-- 3. INSERT IGNORE（静默跳过冲突）
-- ============================================================

-- 冲突时不报错也不更新，静默跳过
INSERT IGNORE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);

-- INSERT IGNORE 的隐藏行为（TDSQL 继承自 MySQL）:
--   - 不仅忽略唯一冲突，还会把类型转换错误降级为警告
--   - 字符串截断: 超长字符串被截断为 VARCHAR(n) 长度（而非报错）
--   - 数值溢出: 超范围的数值被截断为类型最大/最小值
--   - 在 strict mode 下也会被 IGNORE 降级为警告，非常危险
-- 结论: 明确知道自己在做什么时才用 INSERT IGNORE

-- ============================================================
-- 4. 分布式 UPSERT 的 shardkey 要求
-- ============================================================
--
-- TDSQL 是分布式数据库，数据按 shardkey 分布到不同分片。
-- UPSERT 操作涉及冲突检测，对 shardkey 有严格要求:
--
-- (1) 唯一索引必须包含 shardkey 列:
--     CREATE TABLE users (
--         id BIGINT AUTO_INCREMENT PRIMARY KEY,
--         username VARCHAR(50),
--         email VARCHAR(100),
--         UNIQUE KEY uk_username (username)   -- 如果 username 不是 shardkey，此约束不可靠
--     ) SHARDKEY=id;
--     -- 如果 username 列不是 shardkey，两个不同分片可能有相同 username
--     -- ON DUPLICATE KEY UPDATE 在此情况下可能检测不到冲突
--
-- (2) 推荐做法: shardkey 作为主键或作为唯一索引的前缀
--     CREATE TABLE users (
--         id BIGINT AUTO_INCREMENT PRIMARY KEY,
--         username VARCHAR(50) UNIQUE,         -- username 是 shardkey + 唯一索引
--         email VARCHAR(100)
--     ) SHARDKEY=username;
--
-- (3) 不包含 shardkey 的唯一索引:
--     -- 无法保证全局唯一性（每个分片只能保证局部唯一）
--     -- 在 UPSERT 场景下可能导致数据不一致
--     -- 应用层需要额外处理或在中间件层做唯一性校验

-- 单分片 UPSERT（WHERE 条件包含 shardkey）:
INSERT INTO users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 25)
ON DUPLICATE KEY UPDATE
    email = VALUES(email),
    age = VALUES(age);
-- 当 id 是 shardkey 时，此操作只路由到一个分片，性能最优

-- ============================================================
-- 5. 跨分片 UPSERT 与分布式事务
-- ============================================================

-- 批量 UPSERT 中不同 shardkey 值的行会路由到不同分片
INSERT INTO users (id, username, email, age) VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30),
    (3, 'charlie', 'charlie@example.com', 35)
ON DUPLICATE KEY UPDATE
    email = VALUES(email),
    age = VALUES(age);
-- TDSQL 在内部使用分布式事务（两阶段提交）保证跨分片 UPSERT 的原子性
-- 性能影响: 跨 N 个分片 = N 次分布式提交，延迟显著高于单分片

-- 从查询结果批量 UPSERT（可能涉及全分片扫描）:
INSERT INTO users (username, email, age)
SELECT username, email, age FROM staging_users
ON DUPLICATE KEY UPDATE
    email = VALUES(email),
    age = VALUES(age);
-- 如果 staging_users 的数据分布不均匀，部分分片负载会更高

-- ============================================================
-- 6. 广播表的 UPSERT
-- ============================================================
-- 广播表（小表广播）: 数据完整复制到每个分片节点
-- 广播表的 UPSERT 特点:
--   - 写入操作同步到所有节点（保证一致性）
--   - 任何节点的冲突检测都能生效（因为每个节点都有完整数据）
--   - 适合维度表、配置表等小表

-- 示例: 配置表的 UPSERT
INSERT INTO sys_config (config_key, config_value, updated_at)
VALUES ('max_connections', '1000', NOW())
ON DUPLICATE KEY UPDATE
    config_value = VALUES(config_value),
    updated_at = VALUES(updated_at);
-- 广播表的 UPSERT 不存在跨分片问题，但会写入所有节点

-- ============================================================
-- 7. 性能优化建议
-- ============================================================
--
-- (1) 确保 UPSERT 的唯一索引包含 shardkey 列
--     避免跨分片冲突检测的开销
--
-- (2) 批量 UPSERT 时尽量让相同 shardkey 的行聚合
--     减少涉及的分布式事务分支数
--
-- (3) 控制单次批量 UPSERT 的行数
--     推荐 1000-5000 行/批次，避免超大分布式事务
--
-- (4) 避免在高峰期进行大批量 UPSERT
--     分布式事务锁持有时间长，影响并发
--
-- (5) ON DUPLICATE KEY UPDATE 只更新必要的列
--     避免不必要的数据修改（减少 binlog 和 undo log 量）
--
-- (6) 利用 LAST_INSERT_ID() 获取自增 ID
--     TDSQL 的 AUTO_INCREMENT 全局唯一但不保证连续
--     INSERT INTO users (username, email)
--     VALUES ('alice', 'alice@example.com')
--     ON DUPLICATE KEY UPDATE id=LAST_INSERT_ID(id);
--     SELECT LAST_INSERT_ID();  -- 获取已存在行的 ID

-- ============================================================
-- 8. 横向对比: TDSQL vs MySQL vs 其他分布式数据库 UPSERT
-- ============================================================
-- TDSQL:        INSERT ... ON DUPLICATE KEY UPDATE（与 MySQL 兼容）
--               受 shardkey 约束，唯一索引必须包含 shardkey
--               跨分片使用分布式事务（两阶段提交）
-- TiDB:         INSERT ... ON DUPLICATE KEY UPDATE（MySQL 兼容）
--               全局唯一索引天然支持，无 shardkey 限制
--               事务模型为 Percolator（乐观锁 + 两阶段提交）
-- OceanBase:    INSERT ... ON DUPLICATE KEY UPDATE（MySQL 兼容）
--               全局唯一索引支持，分布式事务使用两阶段提交
-- CockroachDB:  INSERT ... ON CONFLICT（PostgreSQL 兼容）
--               分布式 UPSERT 使用 Parallel Commits 协议
-- Spanner:      没有原生 UPSERT，需要用 Read-Modify-Write 模式
--               或用 Mutations API 的 insert_or_update
