-- ClickHouse: UPDATE
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - ALTER UPDATE
--       https://clickhouse.com/docs/en/sql-reference/statements/alter/update
--   [2] ClickHouse - Mutations
--       https://clickhouse.com/docs/en/sql-reference/statements/alter#mutations

-- 注意: ClickHouse 没有标准 UPDATE 语句
-- 使用 ALTER TABLE ... UPDATE（异步 mutation，后台执行）
-- mutation 是重量级操作，不适合频繁小批量更新
-- 18.12.14+ 支持

-- === ALTER TABLE UPDATE（异步 mutation） ===

-- 基本更新
ALTER TABLE users UPDATE age = 26 WHERE username = 'alice';

-- 多列更新
ALTER TABLE users UPDATE email = 'new@example.com', age = 26 WHERE username = 'alice';

-- CASE 表达式
ALTER TABLE users UPDATE status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END
WHERE 1 = 1;

-- 自引用更新
ALTER TABLE users UPDATE age = age + 1 WHERE 1 = 1;

-- 条件更新
ALTER TABLE users UPDATE status = 0 WHERE last_login < '2023-01-01';

-- 查看 mutation 执行状态
-- SELECT * FROM system.mutations WHERE table = 'users' AND is_done = 0;

-- 同步等待 mutation 完成
-- SET mutations_sync = 1;
-- ALTER TABLE users UPDATE age = 26 WHERE username = 'alice';

-- === 轻量级更新（23.3+，实验性） ===
-- 仅适用于 *MergeTree 引擎，修改内存中的数据，性能更好
-- SET apply_mutations_on_fly = 1;
-- ALTER TABLE users UPDATE age = 26 WHERE username = 'alice';

-- === CollapsingMergeTree / ReplacingMergeTree 替代方案 ===

-- ReplacingMergeTree: 插入新版本行，后台合并时去重
INSERT INTO users (username, email, age, _version)
VALUES ('alice', 'new@example.com', 26, 2);
-- 合并后只保留最新版本

-- CollapsingMergeTree: 插入取消行 + 新行
INSERT INTO users (username, email, age, sign)
VALUES ('alice', 'alice@example.com', 25, -1);  -- 取消旧行
INSERT INTO users (username, email, age, sign)
VALUES ('alice', 'new@example.com', 26, 1);     -- 插入新行

-- 限制:
-- mutation 是异步的，不保证立即生效
-- 不支持多表 JOIN 更新
-- WHERE 子句必须存在
-- mutation 会重写整个 data part，影响性能
