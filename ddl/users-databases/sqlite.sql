-- SQLite: 数据库、模式与用户管理
--
-- 参考资料:
--   [1] SQLite Documentation - ATTACH DATABASE
--       https://www.sqlite.org/lang_attach.html
--   [2] SQLite Documentation - PRAGMA
--       https://www.sqlite.org/pragma.html

-- ============================================================
-- SQLite 特性：
-- - 数据库就是一个文件（或 :memory:）
-- - 没有 CREATE DATABASE / DROP DATABASE
-- - 没有 CREATE SCHEMA
-- - 没有用户、角色、权限（应用层控制）
-- - 使用 ATTACH 管理多个数据库文件
-- ============================================================

-- ============================================================
-- 1. 创建数据库（命令行方式，非 SQL）
-- ============================================================

-- 方式一：sqlite3 命令行
-- $ sqlite3 myapp.db
-- 打开或创建数据库文件

-- 方式二：内存数据库
-- $ sqlite3 :memory:

-- 方式三：在应用代码中
-- conn = sqlite3.connect('myapp.db')
-- conn = sqlite3.connect(':memory:')

-- ============================================================
-- 2. ATTACH / DETACH（多数据库管理）
-- ============================================================

-- 附加另一个数据库文件
ATTACH DATABASE 'other.db' AS other;
ATTACH DATABASE ':memory:' AS memdb;

-- 现在可以跨数据库查询
SELECT * FROM main.users u
JOIN other.orders o ON o.user_id = u.id;

-- 查看已附加的数据库
PRAGMA database_list;

-- 分离数据库
DETACH DATABASE other;

-- 注意：main 是默认数据库的别名，不能分离
-- temp 是临时数据库，用于临时表

-- ============================================================
-- 3. 数据库级别设置（PRAGMA）
-- ============================================================

-- 日志模式（WAL 推荐用于并发）
PRAGMA journal_mode = WAL;                      -- WAL 模式，提高并发读写
PRAGMA journal_mode = DELETE;                   -- 默认模式

-- 同步模式
PRAGMA synchronous = NORMAL;                    -- WAL 模式推荐
PRAGMA synchronous = FULL;                      -- 默认，最安全

-- 外键约束（默认关闭！）
PRAGMA foreign_keys = ON;

-- 页面大小（建库时设置）
PRAGMA page_size = 4096;                        -- 默认 4096

-- 缓存大小
PRAGMA cache_size = -64000;                     -- 负数表示 KB（64MB）

-- 自动清理
PRAGMA auto_vacuum = FULL;                      -- 0=NONE, 1=FULL, 2=INCREMENTAL

-- 编码
PRAGMA encoding = 'UTF-8';                      -- 建库时设置

-- ============================================================
-- 4. 安全与权限
-- ============================================================

-- SQLite 没有内建的用户管理和权限系统
-- 安全性依赖：
-- 1. 文件系统权限（chmod / chown）
-- 2. 应用层的访问控制
-- 3. SQLite Encryption Extension（SEE，商业扩展）
-- 4. SQLCipher（开源加密扩展）

-- 使用 SQLCipher 加密（非标准 SQLite）
-- PRAGMA key = 'encryption_password';
-- PRAGMA rekey = 'new_password';

-- ============================================================
-- 5. 查询元数据
-- ============================================================

-- 所有表
SELECT name FROM sqlite_master WHERE type = 'table';

-- 所有索引
SELECT name FROM sqlite_master WHERE type = 'index';

-- 表结构
PRAGMA table_info(users);

-- 外键信息
PRAGMA foreign_key_list(orders);

-- 数据库信息
PRAGMA database_list;
PRAGMA compile_options;                         -- 编译选项

-- ============================================================
-- 6. 数据库维护
-- ============================================================

-- 重建数据库文件（回收空间）
VACUUM;

-- 完整性检查
PRAGMA integrity_check;
PRAGMA quick_check;

-- 分析统计信息（优化查询计划）
ANALYZE;

-- ============================================================
-- 总结
-- ============================================================
-- SQLite 是嵌入式数据库，没有服务器概念
-- 一个数据库 = 一个文件
-- 通过 ATTACH 可以同时操作多个数据库文件
-- 没有用户/角色/权限管理
-- PRAGMA 是 SQLite 特有的配置机制
