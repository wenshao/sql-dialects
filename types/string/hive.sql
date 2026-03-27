-- Hive: 字符串类型
--
-- 参考资料:
--   [1] Apache Hive - Data Types (String)
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types
--   [2] Apache Hive - String Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-StringFunctions

-- STRING: 变长字符串，无长度限制（受 Java 内存约束）
-- VARCHAR(n): 变长，1 ~ 65535 字符（0.12+）
-- CHAR(n): 定长，1 ~ 255 字符，尾部补空格（0.13+）

CREATE TABLE examples (
    code       CHAR(10),                  -- 定长（0.13+）
    name       VARCHAR(255),              -- 变长（0.12+）
    content    STRING                     -- 变长无限制（推荐，最常用）
);

-- 注意：早期 Hive 只有 STRING 类型
-- VARCHAR/CHAR 在 0.12/0.13 才引入
-- 实际使用中大多数场景直接用 STRING

-- BINARY: 二进制数据（0.8+）
CREATE TABLE files (data BINARY);

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST(123 AS STRING);

-- 字符串字面量
SELECT 'hello world';                     -- 单引号
SELECT "hello world";                     -- 双引号也可以

-- 注意：STRING 内部采用 UTF-8 编码
-- 注意：没有 ENUM 类型（可用 STRING + 约束模拟）
-- 注意：没有 BLOB/CLOB/TEXT 分级
-- 注意：没有排序规则（COLLATION）设置
-- 注意：字符串比较默认大小写敏感
-- 注意：序列化由 SerDe 决定，如 LazySimpleSerDe、ORC SerDe
