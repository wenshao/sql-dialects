-- SQLite: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] SQLite Documentation - ATTACH DATABASE
--       https://www.sqlite.org/lang_attach.html
--   [2] SQLite Documentation - PRAGMA
--       https://www.sqlite.org/pragma.html
--   [3] SQLite Architecture - File Locking
--       https://www.sqlite.org/lockingv3.html

-- ============================================================
-- 1. SQLite 的"数据库" = 一个文件
-- ============================================================

-- SQLite 没有 CREATE DATABASE / DROP DATABASE 语句。
-- 数据库是操作系统层面的文件，通过打开文件来"创建"数据库:
--   $ sqlite3 myapp.db        -- 打开或创建数据库文件
--   $ sqlite3 :memory:        -- 内存数据库（进程退出即丢失）
--   conn = sqlite3.connect('myapp.db')   -- Python 示例
--
-- 为什么没有 CREATE DATABASE?
-- (a) 嵌入式定位: 数据库文件是应用的一部分，不是独立服务
-- (b) 零配置: 不需要指定表空间、字符集、存储引擎等参数
-- (c) 文件即数据库: 复制文件 = 备份，删除文件 = 删库
--
-- 对比:
--   MySQL:      CREATE DATABASE myapp CHARACTER SET utf8mb4;
--   PostgreSQL: CREATE DATABASE myapp OWNER myuser;
--   SQL Server: CREATE DATABASE myapp ON (NAME='myapp', FILENAME='...');
--   ClickHouse: CREATE DATABASE myapp ENGINE = Atomic;

-- ============================================================
-- 2. ATTACH DATABASE: 多数据库协同
-- ============================================================

-- SQLite 允许在同一连接中附加多个数据库文件
ATTACH DATABASE 'analytics.db' AS analytics;
ATTACH DATABASE 'archive.db' AS archive;
ATTACH DATABASE ':memory:' AS memdb;

-- 跨数据库查询（这是 SQLite 独特的多数据库能力）
SELECT u.username, o.amount
FROM main.users u
JOIN analytics.user_metrics m ON m.user_id = u.id
JOIN archive.old_orders o ON o.user_id = u.id;

-- 查看所有附加的数据库
PRAGMA database_list;
-- 输出: seq=0, name='main', file='/path/to/myapp.db'
--       seq=1, name='analytics', file='/path/to/analytics.db'
--       seq=2, name='temp', file=''（临时数据库，始终存在）

-- 分离数据库
DETACH DATABASE analytics;
-- 注意: main 和 temp 不能分离

-- 设计分析:
--   ATTACH 是 SQLite 版本的"联邦查询":
--   不同数据文件可以有不同的 schema、不同的 page_size、不同的 WAL 模式。
--   但所有 ATTACH 的数据库共享同一个锁（写入一个会锁住所有）。
--   这限制了 ATTACH 在高并发场景的使用。
--
-- 跨数据库事务:
--   SQLite 支持跨 ATTACH 数据库的事务!
--   BEGIN; INSERT INTO main.t1 ...; INSERT INTO analytics.t2 ...; COMMIT;
--   内部使用多文件原子提交协议（类似 2PC）保证原子性。

-- ============================================================
-- 3. 数据库配置（PRAGMA）
-- ============================================================

-- PRAGMA 是 SQLite 独有的配置机制，替代了传统数据库的 SET/ALTER DATABASE

-- 3.1 WAL 模式: SQLite 最重要的性能开关
PRAGMA journal_mode = WAL;
-- WAL (Write-Ahead Logging) vs DELETE (默认):
--   DELETE:  写入前备份原始页到 rollback journal → 串行读写
--   WAL:     写入追加到 WAL 文件 → 并发多读单写
--   WAL 模式下读写可以并发，是 SQLite 并发性能的关键。
--   但 WAL 不支持网络文件系统（NFS），因为依赖共享内存（-shm 文件）

-- 3.2 同步模式
PRAGMA synchronous = NORMAL;     -- WAL 模式推荐（性能与安全平衡）
PRAGMA synchronous = FULL;       -- 最安全（默认，每次提交 fsync）
PRAGMA synchronous = OFF;        -- 最快但不安全（崩溃可能损坏数据库）

-- 3.3 页面大小（影响 I/O 效率）
PRAGMA page_size = 4096;         -- 默认 4096，建库时设置
-- 对 SSD: 4096 通常最优
-- 对大 BLOB: 可以增大到 8192/16384/32768/65536

-- 3.4 缓存大小
PRAGMA cache_size = -64000;      -- 负数 = KB（64MB），正数 = 页数

-- 3.5 外键（默认关闭！见 constraints/sqlite.sql）
PRAGMA foreign_keys = ON;

-- 3.6 自动清理
PRAGMA auto_vacuum = INCREMENTAL;  -- 0=NONE, 1=FULL, 2=INCREMENTAL

-- ============================================================
-- 4. 为什么 SQLite 没有用户/角色/权限
-- ============================================================

-- SQLite 没有 CREATE USER / CREATE ROLE / GRANT / REVOKE。
-- 原因:
-- (a) 嵌入式: 数据库运行在应用进程内，没有独立的"服务器"来验证身份
-- (b) 单用户: 通常只有一个应用访问数据库文件
-- (c) 文件系统权限: 安全性依赖操作系统的文件权限（chmod/chown）
-- (d) 应用层控制: 访问控制由应用代码实现
--
-- 安全替代方案:
-- (a) 文件权限: chmod 640 myapp.db（只有 owner 和 group 可访问）
-- (b) SQLite Authorizer API: C 函数回调，在每次 SQL 操作前检查权限
--     sqlite3_set_authorizer(db, callback, user_data);
--     回调函数可以返回 SQLITE_OK / SQLITE_DENY / SQLITE_IGNORE
-- (c) SQLCipher: 开源加密扩展，AES-256 加密整个数据库文件
-- (d) SEE (SQLite Encryption Extension): 官方商业加密扩展

-- ============================================================
-- 5. 元数据查询
-- ============================================================

-- sqlite_master: 所有表/索引/视图/触发器的 schema
SELECT name, type, sql FROM sqlite_master;
SELECT name FROM sqlite_master WHERE type = 'table';
SELECT name FROM sqlite_master WHERE type = 'index';

-- 表结构
PRAGMA table_info(users);
PRAGMA table_xinfo(users);        -- 3.26.0+，包含隐藏列

-- 外键和索引
PRAGMA foreign_key_list(orders);
PRAGMA index_list(users);

-- 数据库信息
PRAGMA database_list;
PRAGMA compile_options;            -- 编译时选项

-- 维护
VACUUM;                            -- 重建数据库文件，回收空间
PRAGMA integrity_check;            -- 完整性检查
ANALYZE;                           -- 收集统计信息

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- SQLite 的"零管理"设计:
--   无 CREATE DATABASE → 文件即数据库
--   无 CREATE USER → 安全性交给操作系统和应用层
--   PRAGMA 替代 ALTER DATABASE → 简单但非标准 SQL
--   ATTACH 替代跨库查询 → 灵活但共享锁
--
-- 对引擎开发者的启示:
--   (1) 嵌入式数据库不需要用户管理（应用层更合适）
--   (2) PRAGMA 是一种实用的配置机制，但增加了方言差异
--   (3) WAL 模式是嵌入式数据库并发的关键设计
--   (4) ATTACH 机制是简洁的多数据源方案，但锁模型需要仔细设计
--   (5) 文件 = 数据库 的设计使得备份/迁移极其简单（cp myapp.db backup.db）
