-- MariaDB: INSERT
-- 核心差异: RETURNING 子句和与 SEQUENCE 的集成
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - INSERT
--       https://mariadb.com/kb/en/insert/

-- ============================================================
-- 1. 基本语法 (与 MySQL 相同)
-- ============================================================
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

INSERT IGNORE INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

INSERT INTO users_archive SELECT * FROM users WHERE age > 60;

-- SET 语法 (同 MySQL)
INSERT INTO users SET username = 'alice', email = 'alice@example.com', age = 25;

-- ============================================================
-- 2. RETURNING 子句 (10.5+) -- MariaDB 独有, MySQL 不支持
-- ============================================================
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25)
RETURNING id, username, created_at;
-- 一次操作完成插入并返回生成值 (自增ID, 默认值等)
-- 等价于 INSERT + SELECT LAST_INSERT_ID() 但原子性更好

-- RETURNING 支持表达式
INSERT INTO users (username, email, age) VALUES ('bob', 'bob@example.com', 30)
RETURNING id, UPPER(username) AS upper_name, created_at;

-- 对比其他数据库的 RETURNING:
--   PostgreSQL: INSERT ... RETURNING 是最早的实现 (8.2+)
--   Oracle: INSERT ... RETURNING INTO (PL/SQL 中使用)
--   SQLite: INSERT ... RETURNING (3.35.0+)
--   Firebird: INSERT ... RETURNING (2.0+)
--   MySQL: 不支持! 必须 INSERT + LAST_INSERT_ID() 两步操作

-- ============================================================
-- 3. 与 SEQUENCE 集成 (10.3+)
-- ============================================================
INSERT INTO orders (id, customer, amount)
VALUES (NEXT VALUE FOR seq_orders, 'alice', 100.00);

-- 批量插入使用序列
INSERT INTO orders (id, customer, amount)
VALUES (NEXT VALUE FOR seq_orders, 'alice', 100.00),
       (NEXT VALUE FOR seq_orders, 'bob', 200.00);

-- ============================================================
-- 4. 批量加载
-- ============================================================
LOAD DATA INFILE '/tmp/users.csv'
INTO TABLE users
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(username, email, age);

-- LOAD DATA 也支持 RETURNING (MariaDB 独有特性组合)
-- 但实际中大批量加载通常不需要 RETURNING

-- ============================================================
-- 5. 对引擎开发者的启示
-- ============================================================
-- RETURNING 的实现要点:
--   1. 在 INSERT 执行完毕后, 从已插入的行中读取指定列
--   2. 需要处理: 自增值已分配, DEFAULT 已求值, 触发器已执行
--   3. 多行 INSERT 的 RETURNING 返回多行结果集
--   4. 实现成本低 (复用 SELECT 的列计算逻辑), 价值高
--   5. 与事务的交互: RETURNING 在同一事务中执行, 无并发可见性问题
