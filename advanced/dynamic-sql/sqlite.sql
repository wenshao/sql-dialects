-- SQLite: 动态 SQL（Dynamic SQL）
--
-- 参考资料:
--   [1] SQLite Documentation - C API Prepared Statements
--       https://www.sqlite.org/c3ref/prepare.html
--   [2] SQLite Documentation - Parameter Binding
--       https://www.sqlite.org/lang_expr.html#varparam

-- ============================================================
-- 1. SQLite 没有服务端动态 SQL
-- ============================================================

-- SQLite 不支持 EXECUTE IMMEDIATE / PREPARE...EXECUTE 等 SQL 语法。
-- 原因: 嵌入式数据库没有独立的 SQL 执行环境。
-- 动态 SQL 在宿主语言中实现（更自然、更安全）。
--
-- 但 SQLite 有精心设计的参数绑定语法（通过 C API 使用）:

-- ============================================================
-- 2. 参数化查询（防 SQL 注入的核心机制）
-- ============================================================

-- SQLite 支持 4 种参数语法（全部通过 API 绑定，不在 SQL 中赋值）:
-- ?         → 位置参数（最常用）
-- ?NNN      → 编号参数（如 ?1, ?2, ?3）
-- :name     → 命名参数（冒号前缀）
-- @name     → 命名参数（at 前缀）
-- $name     → 命名参数（美元前缀）

-- SELECT * FROM users WHERE age > ?1 AND status = ?2;
-- SELECT * FROM users WHERE age > :min_age AND status = :status;
-- SELECT * FROM users WHERE age > @min_age AND status = @status;

-- Python 示例:
-- cursor.execute("SELECT * FROM users WHERE age > ? AND status = ?", (18, 'active'))
-- cursor.execute("SELECT * FROM users WHERE age > :age", {"age": 18})

-- C API 示例:
-- sqlite3_prepare_v2(db, "SELECT * FROM users WHERE id = ?", -1, &stmt, NULL);
-- sqlite3_bind_int(stmt, 1, 42);
-- while (sqlite3_step(stmt) == SQLITE_ROW) { ... }
-- sqlite3_finalize(stmt);

-- ============================================================
-- 3. 宿主语言中的动态 SQL 模式
-- ============================================================

-- 3.1 动态表名（表名不能参数化，必须在应用层验证）
-- table_name = 'users'
-- assert table_name in ALLOWED_TABLES  # 白名单验证!
-- cursor.execute(f"SELECT * FROM [{table_name}] WHERE id = ?", (user_id,))

-- 3.2 动态列选择
-- columns = ['id', 'username', 'email']
-- validated = [c for c in columns if c in KNOWN_COLUMNS]
-- cursor.execute(f"SELECT {','.join(validated)} FROM users")

-- 3.3 动态 DDL（创建归档表）
-- cursor.execute(f"CREATE TABLE IF NOT EXISTS archive_{year} AS "
--                f"SELECT * FROM orders WHERE strftime('%Y', order_date) = ?", (str(year),))

-- 3.4 预编译语句缓存（性能优化）
-- stmt = conn.prepare("INSERT INTO users (name, age) VALUES (?, ?)")
-- for name, age in data:
--     stmt.execute(name, age)   # 复用已编译的语句
-- 性能提升 2-5 倍（避免重复解析 SQL）

-- ============================================================
-- 4. 安全注意事项
-- ============================================================

-- (a) 表名/列名不能参数化:
--     ? 只能用于值（WHERE col = ?），不能用于标识符
--     必须用白名单验证 + 字符串拼接
--
-- (b) SQL 注入防护:
--     始终使用 ? 参数化值，永远不要用字符串拼接
--     错误: f"SELECT * FROM users WHERE name = '{user_input}'"
--     正确: cursor.execute("SELECT * FROM users WHERE name = ?", (user_input,))
--
-- (c) 应用层的动态 SQL 比 SQL 层的 EXECUTE IMMEDIATE 更安全:
--     应用层可以用白名单、ORM、query builder 等多层防护
--     SQL 层的动态 SQL（如 PL/pgSQL 的 EXECUTE）容易写出注入漏洞

-- ============================================================
-- 5. 对比与引擎开发者启示
-- ============================================================
-- SQLite 的动态 SQL 模型:
--   (1) 无服务端动态 SQL → 应用层实现
--   (2) 4 种参数绑定语法 → 灵活且安全
--   (3) 预编译语句 → 性能优化的关键
--
-- 对引擎开发者的启示:
--   参数绑定 API 比服务端 EXECUTE IMMEDIATE 更重要。
--   嵌入式引擎的动态 SQL 由宿主语言自然提供。
--   预编译语句缓存是嵌入式引擎的必备优化。
