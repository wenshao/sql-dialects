-- Redshift: 字符串类型
--
-- 参考资料:
--   [1] Redshift SQL Reference
--       https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html
--   [2] Redshift SQL Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html
--   [3] Redshift Data Types
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html

-- CHAR(n): 定长，最大 4096 字节，尾部空格填充
-- VARCHAR(n): 变长，最大 65535 字节
-- TEXT: VARCHAR(256) 的别名
-- BPCHAR: CHAR 的别名（blank-padded character）

CREATE TABLE examples (
    code       CHAR(10),                     -- 定长，尾部填充空格
    name       VARCHAR(255),                 -- 变长
    content    VARCHAR(65535),               -- 最大长度
    short_text TEXT,                         -- VARCHAR(256) 的别名
    data       VARBYTE(1024)                 -- 二进制数据（VARBYTE 最大 1024000）
);

-- 注意：VARCHAR(n) 中的 n 是字节数，不是字符数
-- 对于多字节字符（如中文 UTF-8），一个字符可能占 3-4 字节
-- 示例：VARCHAR(100) 最多存约 33 个中文字符

-- 不指定长度时的默认值
-- CHAR: CHAR(1)
-- VARCHAR: VARCHAR(256)

-- 字符串字面量
SELECT 'hello world';                        -- 单引号
SELECT 'it''s escaped';                      -- 单引号转义

-- 编码（列压缩）
CREATE TABLE compressed (
    code       CHAR(10) ENCODE BYTEDICT,     -- 字典编码（低基数）
    name       VARCHAR(255) ENCODE ZSTD,     -- ZSTD 压缩
    content    VARCHAR(65535) ENCODE LZO,    -- LZO 压缩
    short_code VARCHAR(10) ENCODE TEXT255    -- 短文本编码
);

-- NCHAR / NVARCHAR 不支持
-- Redshift 使用 UTF-8 编码，VARCHAR 原生支持多字节字符

-- SUPER 类型中的字符串
SELECT json_data.name FROM events WHERE IS_VARCHAR(json_data.name);

-- 注意：没有 ENUM 类型
-- 注意：没有 TINYTEXT / MEDIUMTEXT / LONGTEXT
-- 注意：没有 NCHAR / NVARCHAR（所有字符串都是 UTF-8）
-- 注意：VARCHAR 最大 65535 字节（不是字符）
-- 注意：CHAR 会做尾部空格填充，VARCHAR 不会
-- 注意：TEXT 只是 VARCHAR(256) 的别名，不是无限长度
-- 注意：选择合适的 ENCODE 可以显著减少存储和提升查询性能
