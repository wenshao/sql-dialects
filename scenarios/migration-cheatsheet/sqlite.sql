-- SQLite: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] SQLite Documentation - SQL Syntax
--       https://www.sqlite.org/lang.html

-- ============================================================
-- 从 MySQL/PostgreSQL 迁移到 SQLite 的常见问题
-- ============================================================

-- 1. 数据类型映射
-- MySQL INT/BIGINT       → INTEGER（SQLite 只有 INTEGER 和 REAL）
-- MySQL VARCHAR(255)     → TEXT（SQLite 不限制长度）
-- MySQL DECIMAL(10,2)    → REAL 或 INTEGER（分存储，无真正 DECIMAL）
-- MySQL DATETIME         → TEXT（ISO 8601 格式）或 INTEGER（Unix 时间戳）
-- MySQL BOOLEAN          → INTEGER（0/1）
-- MySQL ENUM             → TEXT + CHECK 约束
-- MySQL JSON             → TEXT（JSON 函数 3.9.0+ 支持）
-- MySQL BLOB             → BLOB
-- PostgreSQL SERIAL      → INTEGER PRIMARY KEY（自动成为 rowid）
-- PostgreSQL UUID        → TEXT（无内置 UUID 类型）
-- PostgreSQL ARRAY       → TEXT（JSON 数组存储）
-- PostgreSQL JSONB       → TEXT（3.45.0+ 有 JSONB）

-- 2. 自增主键
-- MySQL:      id INT AUTO_INCREMENT PRIMARY KEY
-- PostgreSQL: id SERIAL PRIMARY KEY 或 id INT GENERATED ALWAYS AS IDENTITY
-- SQLite:     id INTEGER PRIMARY KEY    -- 必须是 INTEGER（不是 INT!）

-- 3. 字符串拼接
-- MySQL:      CONCAT(a, b, c)
-- PostgreSQL: a || b || c 或 CONCAT(a, b, c)
-- SQLite:     a || b || c   -- 注意: NULL || 'text' = NULL

-- 4. 日期函数
-- MySQL:      NOW(), DATE_ADD(d, INTERVAL 1 DAY), DATEDIFF(a, b)
-- PostgreSQL: NOW(), d + INTERVAL '1 day', a - b
-- SQLite:     datetime('now'), datetime(d, '+1 day'), julianday(a)-julianday(b)

-- 5. UPSERT
-- MySQL:      INSERT ... ON DUPLICATE KEY UPDATE
-- PostgreSQL: INSERT ... ON CONFLICT DO UPDATE
-- SQLite:     INSERT ... ON CONFLICT DO UPDATE（3.24.0+，语法同 PostgreSQL）

-- 6. 不支持的特性
-- 无 ALTER TABLE 修改列类型 → 需要重建表
-- 无 TRUNCATE TABLE → DELETE FROM table
-- 无 GRANT/REVOKE → 文件系统权限
-- 无存储过程/函数 → 应用层实现
-- 外键默认关闭 → PRAGMA foreign_keys = ON
-- 无 RIGHT/FULL JOIN → 3.39.0+ 才支持

-- ============================================================
-- 从 SQLite 迁移到 MySQL/PostgreSQL 的注意事项
-- ============================================================

-- 1. 动态类型陷阱: SQLite 列可能存储了混合类型的数据
-- SELECT typeof(col) FROM t GROUP BY typeof(col);  -- 检查实际存储的类型

-- 2. rowid 依赖: 如果应用依赖隐式 rowid，目标数据库需要显式自增列

-- 3. 日期格式: SQLite 的 TEXT 日期需要转为目标数据库的 DATE/TIMESTAMP

-- 4. 布尔值: SQLite 的 0/1 需要转为 TRUE/FALSE

-- 5. JSON 路径语法:
-- SQLite:     json_extract(data, '$.name')
-- MySQL:      JSON_EXTRACT(data, '$.name') 或 data->'$.name'
-- PostgreSQL: data->>'name' 或 jsonb_extract_path_text(data, 'name')

-- ============================================================
-- 对比与引擎开发者启示
-- ============================================================
-- SQLite 迁移的核心挑战:
--   动态类型 → 数据可能不符合目标 schema
--   无 DECIMAL → 金融数据精度问题
--   日期存储为 TEXT/INTEGER → 需要格式转换
--   外键默认关闭 → 引用完整性可能被破坏
--
-- 对引擎开发者的启示:
--   设计引擎时应考虑迁移路径:
--   提供 IMPORT/EXPORT 工具（如 pg_dump / mysqldump 兼容格式）
--   类型映射文档是用户体验的重要组成部分。
