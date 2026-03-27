-- MySQL: 字符串类型
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - String Data Types
--       https://dev.mysql.com/doc/refman/8.0/en/string-types.html
--   [2] MySQL 8.0 Reference Manual - Character Sets and Collations
--       https://dev.mysql.com/doc/refman/8.0/en/charset.html
--   [3] MySQL Internals - InnoDB Row Formats
--       https://dev.mysql.com/doc/refman/8.0/en/innodb-row-format.html
--   [4] Unicode Technical Standard #10 - Unicode Collation Algorithm
--       https://unicode.org/reports/tr10/

-- ============================================================
-- 1. 字符串类型一览
-- ============================================================
CREATE TABLE string_examples (
    -- 定长: 右侧补空格到 n 个字符，读取时去除尾部空格（PAD SPACE 语义）
    country_code CHAR(2)         NOT NULL,    -- 'US', 'CN', 'JP'
    -- 变长: 1-2 字节长度前缀 + 实际数据，最大 65535 字节（受行大小限制）
    username     VARCHAR(64)     NOT NULL,
    email        VARCHAR(255)    NOT NULL,
    -- TEXT 族: 存储在溢出页，无法内联到行内
    bio          TEXT,                         -- 最大 64KB
    content      MEDIUMTEXT,                  -- 最大 16MB
    -- 二进制
    avatar_hash  BINARY(32),                  -- 定长二进制（如 SHA-256）
    file_data    VARBINARY(8000)              -- 变长二进制
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- 2. utf8 vs utf8mb4: 字符集设计的历史教训（对引擎开发者）
-- ============================================================

-- 2.1 MySQL 的 "utf8" 只支持 BMP (Basic Multilingual Plane, U+0000 ~ U+FFFF)
-- 真正的 UTF-8 编码使用 1-4 字节，但 MySQL 的 utf8 被硬编码为最多 3 字节。
-- 这意味着 Emoji (U+1F600+)、CJK 扩展 B (U+20000+) 等无法存储。
-- 插入 4 字节字符时: 严格模式报错，宽松模式静默截断 -- 数据丢失！
--
-- 2.2 为什么当初限制为 3 字节？
-- 2003 年 MySQL 4.1 引入字符集时，Unicode 4.0 的补充平面字符还很少使用。
-- 固定最大 3 字节可以简化内存分配: VARCHAR(n) 的内存临时表只需 n*3 字节。
-- 这是一个经典的 "过早优化" 导致长期技术债务的案例。
--
-- 2.3 utf8mb4 的修正（5.5.3+）
-- 真正的 UTF-8 实现，最大 4 字节，覆盖所有 Unicode 平面。
-- 8.0 起 utf8mb4 成为默认字符集。
-- 但 "utf8" 别名仍然指向 3 字节版本！直到 MySQL 9.0 才计划废弃。
--
-- 对引擎开发者的教训:
--   1. 字符编码必须从第一天就完整支持 UTF-8 全范围（1-4 字节）
--   2. 不要用"当前够用"的假设做编码设计 -- Unicode 在持续扩展
--   3. PostgreSQL/SQLite/ClickHouse 的做法: UTF-8 就是 UTF-8，没有 "mb3/mb4" 区分

-- ============================================================
-- 3. CHAR vs VARCHAR vs TEXT 的存储差异（InnoDB 行格式层面）
-- ============================================================

-- 3.1 CHAR(n): 定长存储
-- COMPACT/DYNAMIC 行格式下:
--   变长字符集 (utf8mb4): 实际按变长存储！最少 n 字节，最多 n*4 字节
--   定长字符集 (latin1):  固定 n 字节
-- REDUNDANT 行格式:        总是固定 n*max_bytes_per_char 字节
--
-- 实践意义: utf8mb4 下 CHAR(10) 并不真正 "定长"，与 VARCHAR 差别不大
-- 唯一优势: 高频等长值（如 ISO 国家代码 'US','CN'）避免长度前缀的 1-2 字节开销

-- 3.2 VARCHAR(n): 变长存储
-- 存储 = 实际字节数 + 长度前缀（<=255 字节用 1B，>255 字节用 2B）
-- n 是字符数，但索引长度限制按字节计算:
--   单列索引上限: 3072 字节（innodb_large_prefix=ON，InnoDB 默认）
--   VARCHAR(768) * 4 字节(utf8mb4) = 3072，刚好是上限
--   超过需要前缀索引: INDEX idx (col(191)) -- 191*4 = 764 < 767 (旧上限)
--
-- n 的选择还影响:
--   内存临时表: 按 n * max_bytes_per_char 分配内存，过大的 n 浪费内存
--   排序缓冲区: ORDER BY VARCHAR(10000) 即使实际数据很短也按 40000 字节分配
--   网络传输: 客户端协议按 n * max_bytes_per_char 预分配接收缓冲区

-- 3.3 TEXT 族: 溢出存储
-- 在 InnoDB DYNAMIC 行格式下:
--   行内只存 20 字节指针，数据存在溢出页 (overflow page)
--   COMPACT 格式: 行内存 768 字节前缀 + 20 字节指针
--
-- TEXT 的重要限制:
--   - 8.0.13 之前: 不支持 DEFAULT 值
--   - 不能创建完整索引，只能前缀索引: INDEX idx (col(255))
--   - 不参与内存临时表 (TempTable 引擎除外)，强制磁盘临时表
--     → ORDER BY / GROUP BY / DISTINCT 涉及 TEXT 列时性能显著下降
--   - 每行最多 65535 字节（所有列合计），TEXT 只占行内指针的开销
--
-- 横向对比: TEXT vs VARCHAR 的设计哲学
--   MySQL:      TEXT != VARCHAR，TEXT 有诸多限制，选择需谨慎
--   PostgreSQL: TEXT = VARCHAR（无长度限制的 VARCHAR），完全等价，无任何限制
--               PG 推荐直接用 TEXT，VARCHAR(n) 只在需要长度校验时使用
--   Oracle:     VARCHAR2 最大 4000/32767 字节，超过用 CLOB（类似 MySQL TEXT 的分离存储）
--   SQL Server: VARCHAR(MAX) 最大 2GB，行内存储策略自适应
--   ClickHouse: 只有 String，无长度限制，内部自动处理，无 TEXT/VARCHAR 区分
--   BigQuery:   只有 STRING，最大 10MB，无需选择类型
--
-- 对引擎开发者的启示:
--   PostgreSQL 的统一 TEXT 设计是更优的方向 -- 减少用户认知负担。
--   如果必须区分，应基于存储策略（行内 vs 溢出）自动决策，而非暴露给用户。

-- ============================================================
-- 4. COLLATION: 对索引和比较的引擎层影响
-- ============================================================

-- 4.1 排序规则决定了索引中键的排列方式和相等性判定
-- 同一数据在不同 COLLATION 下的索引行为完全不同:
CREATE TABLE collation_demo (
    val_ci VARCHAR(64) COLLATE utf8mb4_unicode_ci,   -- 大小写不敏感
    val_bin VARCHAR(64) COLLATE utf8mb4_bin           -- 二进制比较
);
CREATE UNIQUE INDEX uk_ci ON collation_demo (val_ci);
CREATE UNIQUE INDEX uk_bin ON collation_demo (val_bin);
-- INSERT ('Hello'), ('hello'):
--   uk_ci: UNIQUE 冲突！因为 'Hello' = 'hello' (case-insensitive)
--   uk_bin: 正常插入，因为 'Hello' != 'hello'

-- 4.2 MySQL 8.0 默认: utf8mb4_0900_ai_ci
-- 基于 Unicode 9.0 的 UCA (Unicode Collation Algorithm)
-- _ai = Accent Insensitive:  'cafe' = 'cafe' (重音不敏感)
-- _ci = Case Insensitive:    'ABC' = 'abc'
-- 对比旧版 utf8mb4_general_ci: 不支持 Unicode 规范化，某些语言排序不准确

-- 4.3 COLLATION 对引擎的深层影响:
-- 索引查找:   B+树比较操作使用 COLLATION 的权重，非简单字节比较
-- JOIN 匹配:  两表的 JOIN 列 COLLATION 不一致时触发隐式转换，导致索引失效
-- WHERE 条件: WHERE name = 'Test' 在 _ci 下走索引，但跨 COLLATION 比较可能全表扫描
-- UNION:      列的 COLLATION 不一致时报错或隐式转换
--
-- 横向对比: 各引擎的 COLLATION 实现
--   MySQL:      4 级继承 (Server→Database→Table→Column)，可逐列设置
--   PostgreSQL: 12+ 支持 ICU collation（基于 ICU 库），之前依赖操作系统 locale
--               PG 的 COLLATE 可以在表达式级别使用: ORDER BY name COLLATE "en_US"
--   SQL Server: 数据库级 collation，_CI_AS/_CS_BIN 等后缀，影响 tempdb 兼容性
--   Oracle:     NLS_SORT/NLS_COMP 参数控制，12c+ 支持列级 COLLATION
--   ClickHouse: 默认二进制比较，排序通过 COLLATE 函数实现（不影响存储）
--   SQLite:     内置 BINARY/NOCASE/RTRIM，可通过 sqlite3_create_collation() 扩展
--
-- 对引擎开发者的启示:
--   COLLATION 是索引子系统最复杂的部分之一。建议:
--   1. 使用 ICU 库（PostgreSQL 12+ 的选择）而非自实现 -- Unicode 规则极其复杂
--   2. 默认使用二进制比较（最快），按需支持语言感知排序
--   3. 避免 MySQL 的 4 级继承设计 -- 调试"为什么 JOIN 不走索引"的噩梦

-- ============================================================
-- 5. ENUM 和 SET: MySQL 独有的字符串约束类型
-- ============================================================
CREATE TABLE enum_set_demo (
    status ENUM('active', 'inactive', 'deleted'),  -- 内部存储为 1-2 字节整数
    tags   SET('vip', 'new', 'premium')             -- 位图存储，最多 64 个成员
);
-- ENUM 的优势: 存储紧凑（1-2 字节 vs VARCHAR 的实际字符串）
-- ENUM 的陷阱:
--   1. ALTER TABLE 添加枚举值需要重建表（非 INSTANT DDL，除非追加到末尾 8.0+）
--   2. 排序按内部整数值（定义顺序），不按字母序
--   3. 插入非法值: 严格模式报错，宽松模式存为空字符串（内部值 0）
--
-- 横向对比:
--   PostgreSQL: CREATE TYPE mood AS ENUM(...)，独立类型对象，可 ALTER TYPE ADD VALUE
--   SQL Server: 无原生 ENUM，用 CHECK 约束模拟
--   Oracle:     无原生 ENUM，用 CHECK 约束模拟
--   ClickHouse: Enum8/Enum16，类似 MySQL 但更严格（不允许未定义值）
--   BigQuery:   无 ENUM，推荐 STRING + CHECK 或应用层校验

-- ============================================================
-- 6. 二进制字符串: BINARY/VARBINARY/BLOB
-- ============================================================
-- BINARY(n):    定长二进制，右侧补 0x00
-- VARBINARY(n): 变长二进制，无字符集/排序规则
-- BLOB 族:      TINYBLOB(255) / BLOB(64K) / MEDIUMBLOB(16M) / LONGBLOB(4G)
--
-- 与字符串的核心区别:
--   - 无 CHARACTER SET / COLLATE，比较按字节值
--   - LENGTH() 返回字节数（与 CHAR_LENGTH 相同）
--   - 适用场景: 哈希值、UUID 二进制存储、加密数据
--
-- 实践: UUID 存储
--   VARCHAR(36): 36 字节（含连字符），可读但占空间
--   BINARY(16):  16 字节，紧凑但不可读
--   MySQL 8.0+:  UUID_TO_BIN() / BIN_TO_UUID() 内置转换函数
--                UUID_TO_BIN(uuid, 1) 重排字节序使 B+树索引友好

-- ============================================================
-- 7. 版本演进与最佳实践
-- ============================================================
-- MySQL 4.1:  引入字符集支持，utf8（3字节）
-- MySQL 5.5:  引入 utf8mb4（4字节真正 UTF-8）
-- MySQL 8.0:  默认 utf8mb4 + utf8mb4_0900_ai_ci
--             表达式默认值 (8.0.13+): TEXT 列可有 DEFAULT
-- MySQL 8.0.28: 废弃 utf8mb3 别名，推进 utf8mb4
--
-- 实践建议:
--   1. 总是使用 utf8mb4，永远不要用 utf8（已是 MySQL 官方立场）
--   2. VARCHAR 优先于 TEXT，除非确实需要超过 16383 字符（65535/4）
--   3. VARCHAR(n) 的 n 不要随意设大 -- 影响内存临时表和排序缓冲
--   4. 需要精确匹配时用 utf8mb4_bin，需要语言感知时用 utf8mb4_0900_ai_ci
