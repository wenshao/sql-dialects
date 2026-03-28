-- StarRocks: 字符串类型
--
-- 参考资料:
--   [1] StarRocks Documentation - String Types
--       https://docs.starrocks.io/docs/sql-reference/data-types/

-- ============================================================
-- 与 Doris 类似的类型体系
-- ============================================================
-- CHAR(n):    定长, 1~255 字节
-- VARCHAR(n): 变长, 最大 1048576 字节(1MB, 比 Doris 的 65533 大)
-- STRING:     变长, 最大 65535 字节(3.0+, 比 Doris 的 2GB 小)

CREATE TABLE examples (
    code CHAR(10), name VARCHAR(255), content STRING
) DUPLICATE KEY(code) DISTRIBUTED BY HASH(code);

-- ============================================================
-- StarRocks vs Doris 字符串差异
-- ============================================================
-- VARCHAR 最大值:
--   StarRocks: 1048576 字节(1MB)
--   Doris:     65533 字节
--
-- STRING 最大值:
--   StarRocks: 65535 字节(较小)
--   Doris:     2147483643 字节(2GB, 更大)
--
-- 其他限制相同:
--   STRING 不能作为 Key/分区/分桶列
--   不支持 COLLATION
--   VARCHAR(n) 的 n 是字节数
--   不支持 ENUM / SET

-- 字符串字面量
SELECT 'hello world';
SELECT "hello world";    -- MySQL 兼容
