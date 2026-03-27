-- TDSQL: 字符串类型
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557
--   [3] MySQL 8.0 Reference Manual - String Data Types
--       https://dev.mysql.com/doc/refman/8.0/en/string-types.html

-- ============================================================
-- 1. 字符串类型一览
-- ============================================================
CREATE TABLE string_examples (
    -- 定长: 右侧补空格到 n 个字符，最大 255 字符
    country_code  CHAR(2)           NOT NULL,    -- 'US', 'CN', 'JP'
    -- 变长: 1-2 字节长度前缀 + 实际数据，最大 65535 字节（受行大小限制）
    username      VARCHAR(64)       NOT NULL,
    email         VARCHAR(255)      NOT NULL,
    -- TEXT 族: 存储在溢出页，无法内联到行内
    bio           TEXT,                          -- 最大 64KB
    content       MEDIUMTEXT,                   -- 最大 16MB
    big_data      LONGTEXT,                     -- 最大 4GB
    -- 二进制
    avatar_hash   BINARY(32),                   -- 定长二进制（如 SHA-256）
    file_data     VARBINARY(8000)               -- 变长二进制
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- 2. 分布式环境下的字符串类型考量
-- ============================================================

-- 2.1 shardkey 选择对字符串类型的约束
-- TDSQL 使用分片键（shardkey）将数据分布到不同物理节点
-- shardkey 列推荐使用 INT / BIGINT / VARCHAR 类型
-- 以下类型不能作为 shardkey:
--   TEXT / MEDIUMTEXT / LONGTEXT: 数据量不确定，hash 分布不均
--   BLOB / MEDIUMBLOB / LONGBLOB: 同上
--   BINARY / VARBINARY: 部分版本支持但性能不佳
--
-- 最佳实践: shardkey 使用定长或短变长字符串
CREATE TABLE distributed_users (
    id       BIGINT NOT NULL AUTO_INCREMENT,
    tenant_id VARCHAR(32) NOT NULL,       -- 推荐作为 shardkey
    name     VARCHAR(100),
    bio      TEXT,
    PRIMARY KEY (id),
    SHARDKEY (tenant_id)                  -- 使用短字符串作为分片键
);

-- 2.2 字符串在分布式 JOIN 中的行为
-- 跨分片 JOIN 时，TDSQL 需要在协调节点（CN）汇总数据
-- 字符串列的 JOIN 性能低于整数列:
--   - 字符串 hash 比较开销大于整数
--   - TEXT 类型可能触发磁盘临时表
-- 建议: JOIN 关联列优先使用 INT/BIGINT

-- ============================================================
-- 3. 字符集与排序规则
-- ============================================================

-- TDSQL 默认字符集 utf8mb4（与 MySQL 8.0 一致）
-- utf8mb4 支持完整的 Unicode（包括 Emoji、CJK 扩展字符）

-- 列级字符集设置
CREATE TABLE t (
    name VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
    code VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_bin      -- 精确匹配
);

-- 分布式环境下的字符集注意事项:
--   1. 所有分片的字符集必须一致，否则跨分片查询可能产生乱码
--   2. COLLATION 影响 JOIN 匹配: 不同 COLLATION 的列 JOIN 时隐式转换，索引失效
--   3. 推荐全局统一使用 utf8mb4 + utf8mb4_unicode_ci
--   4. 需要大小写敏感精确匹配时使用 utf8mb4_bin

-- utf8 vs utf8mb4 (与 MySQL 相同的历史问题):
--   utf8（utf8mb3）: 最多 3 字节，不支持 Emoji 和 CJK 扩展 B+
--   utf8mb4:         最多 4 字节，完整 UTF-8
--   TDSQL 新建表必须使用 utf8mb4

-- ============================================================
-- 4. CHAR / VARCHAR / TEXT 的选择
-- ============================================================

-- CHAR(n):  定长，适合固定长度编码（如国家代码、手机号）
-- VARCHAR(n): 变长，日常首选，n 不要随意设大
-- TEXT:     大文本，有索引限制（只能前缀索引）

-- VARCHAR(n) 中 n 的选择影响:
--   内存临时表: 按 n × max_bytes_per_char 分配，过大的 n 浪费内存
--   排序缓冲区: ORDER BY VARCHAR(10000) 即使实际数据短也按 40000 字节分配
--   分布式场景下影响更大: 数据需在分片间传输，过大的 n 增加网络开销

-- TEXT 类型的分布式注意事项:
--   1. TEXT 列不能作为 shardkey
--   2. TEXT 列的 ORDER BY / GROUP BY 可能触发跨分片排序
--   3. 分布式查询中 TEXT 列的网络传输开销显著
--   4. 如果可能，使用 VARCHAR(有效最大长度) 替代 TEXT

-- ============================================================
-- 5. ENUM 和 SET
-- ============================================================

CREATE TABLE enum_set_demo (
    status ENUM('active', 'inactive', 'deleted'),  -- 内部存储为 1-2 字节整数
    tags   SET('vip', 'new', 'premium')             -- 位图存储，最多 64 个成员
);

-- ENUM 的分布式注意事项:
--   1. ENUM 值可以作为 shardkey（内部为整数）
--   2. ALTER TABLE 添加枚举值: 非 INSTANT DDL 会触发表重建，需评估分片影响
--   3. 分布式 DDL 需要在所有分片上执行，大表的 ENUM 变更可能很慢

-- ============================================================
-- 6. 二进制字符串
-- ============================================================

-- BINARY(n):    定长二进制，右侧补 0x00
-- VARBINARY(n): 变长二进制，无字符集/排序规则
-- BLOB 族:      TINYBLOB(255) / BLOB(64K) / MEDIUMBLOB(16M) / LONGBLOB(4G)

-- UUID 在 TDSQL 中的存储:
--   VARCHAR(36):  36 字节，可读但占空间
--   BINARY(16):   16 字节，紧凑但不可读
--   如果使用 UUID 作为 shardkey，建议使用 BINARY(16) 以减少分布式传输开销

-- ============================================================
-- 7. 字符串函数（分布式场景常用）
-- ============================================================

-- 长度
SELECT LENGTH('你好');                  -- 6（字节数，utf8mb4 下每中文字 3 字节）
SELECT CHAR_LENGTH('你好');             -- 2（字符数）

-- 拼接
SELECT CONCAT(name, '@', domain);       -- 字符串拼接
SELECT CONCAT_WS(',', tags);            -- 带分隔符拼接

-- 模式匹配
SELECT * FROM t WHERE name LIKE '%测试%';
SELECT * FROM t WHERE name REGEXP '^[A-Z]+';

-- 分布式中常用: hash 相关
SELECT MD5('hello');                    -- 5d41402abc4b2a76b9719d911017c592
SELECT SHA2('hello', 256);              -- SHA-256 哈希

-- ============================================================
-- 8. 注意事项与最佳实践
-- ============================================================

-- 1. 字符串类型与 MySQL 完全兼容，所有 MySQL 字符串函数均可用
-- 2. shardkey 列建议使用 VARCHAR 或 INT 类型，避免 TEXT/BLOB
-- 3. 所有分片的字符集和 COLLATION 必须统一配置
-- 4. TEXT/BLOB 列不能作为 shardkey，需通过其他列路由
-- 5. 默认字符集 utf8mb4，永远不要使用 utf8（3 字节版本）
-- 6. VARCHAR(n) 的 n 应根据实际需求设定，过大的 n 影响分布式性能
-- 7. 跨分片字符串 JOIN 注意 COLLATION 一致性
-- 8. ENUM 值的 DDL 变更在分布式环境下需评估影响范围
