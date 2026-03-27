-- Hologres: UPSERT
--
-- 参考资料:
--   [1] Hologres SQL - INSERT ON CONFLICT
--       https://help.aliyun.com/zh/hologres/user-guide/insert-on-conflict
--   [2] Hologres SQL Reference
--       https://help.aliyun.com/zh/hologres/user-guide/overview-27

-- 注意: Hologres 支持 PostgreSQL 兼容的 ON CONFLICT 语法
-- 同时支持 Hologres 特有的整行替换语义

-- 方式一: INSERT ON CONFLICT（推荐，PostgreSQL 兼容语法）
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;

-- 冲突时什么都不做
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username) DO NOTHING;

-- 带 WHERE 条件的 UPSERT（只在满足条件时才更新）
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age
WHERE users.age < EXCLUDED.age;

-- 批量 UPSERT
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;

-- 方式二: INSERT 主键冲突自动替换（Hologres 特有）
-- 建表时设置 mutate_type:
-- CREATE TABLE users (...) WITH (mutate_type = 'insertorreplace');
-- INSERT 时相同主键的行自动整行替换
INSERT INTO users (username, email, age)
VALUES ('alice', 'new@example.com', 26);
-- 如果 username 是主键且已存在，整行替换

-- 方式三: INSERT 主键冲突自动忽略（Hologres 特有）
-- CREATE TABLE users (...) WITH (mutate_type = 'insertorignore');
-- INSERT 时相同主键的行自动忽略
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);
-- 如果已存在，静默跳过

-- 方式四: 部分列更新
-- CREATE TABLE users (...) WITH (mutate_type = 'insertorreplace');
-- 只更新指定列，其他列保持不变（需设置 partial_update）
-- SET hg_experimental_enable_partial_update = on;
INSERT INTO users (username, email)
VALUES ('alice', 'new@example.com')
ON CONFLICT (username)
DO UPDATE SET email = EXCLUDED.email;

-- 性能提示:
-- ON CONFLICT 写入性能极高，适合高 QPS 场景
-- 建议使用 JDBC PreparedStatement + 批量提交
-- mutate_type 设置在建表时确定，不可修改
