-- Apache Doris: 字符串类型
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- CHAR(n): 定长，1 ~ 255 字节，尾部补空格
-- VARCHAR(n): 变长，最大 65533 字节
-- STRING: 变长，最大 2147483643 字节（2.0+）
-- TEXT: STRING 的别名

CREATE TABLE examples (
    code       CHAR(10),                  -- 定长
    name       VARCHAR(255),              -- 变长（推荐）
    content    STRING                     -- 大文本（2.0+）
)
DUPLICATE KEY(code)
DISTRIBUTED BY HASH(code);

-- 注意：VARCHAR(n) 中 n 是字节数（UTF-8 下一个中文 3 字节）
-- 注意：STRING 类型不能作为 Key 列、分区列或分桶列
-- 注意：CHAR 类型也不能作为分区列

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST(123 AS VARCHAR);

-- 字符串字面量
SELECT 'hello world';                     -- 单引号
SELECT "hello world";                     -- 双引号也可以（MySQL 兼容）

-- 注意：与 MySQL 类型兼容，但有存储差异
-- 注意：没有 TEXT / MEDIUMTEXT / LONGTEXT 区分（统一用 STRING）
-- 注意：没有 ENUM / SET 类型
-- 注意：VARCHAR 必须指定长度
-- 注意：不支持 COLLATION 设置，默认 UTF-8 字节比较
-- 注意：2.0+ STRING 类型最大支持 2GB
