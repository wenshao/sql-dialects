-- H2: 数值类型
--
-- 参考资料:
--   [1] H2 SQL Reference - Commands
--       https://h2database.com/html/commands.html
--   [2] H2 - Data Types
--       https://h2database.com/html/datatypes.html
--   [3] H2 - Functions
--       https://h2database.com/html/functions.html

-- 整数
-- TINYINT: 1 字节，-128 ~ 127
-- SMALLINT: 2 字节，-32768 ~ 32767
-- INTEGER / INT: 4 字节
-- BIGINT: 8 字节

-- 浮点数
-- REAL / FLOAT4: 4 字节
-- DOUBLE PRECISION / FLOAT / FLOAT8: 8 字节

-- 定点数
-- NUMERIC(p,s) / DECIMAL(p,s) / DEC(p,s): 精确数值

-- 布尔
-- BOOLEAN / BOOL / BIT

CREATE TABLE products (
    id       INT PRIMARY KEY AUTO_INCREMENT,
    code     TINYINT,
    quantity SMALLINT,
    stock    INTEGER,
    total_id BIGINT,
    price    DECIMAL(10,2),
    weight   REAL,
    score    DOUBLE,
    active   BOOLEAN DEFAULT TRUE
);

-- IDENTITY（自增简写）
CREATE TABLE events (
    id IDENTITY,                              -- BIGINT AUTO_INCREMENT PRIMARY KEY
    name VARCHAR(100)
);

-- GENERATED ALWAYS AS IDENTITY
CREATE TABLE logs (
    id INT GENERATED ALWAYS AS IDENTITY,
    msg VARCHAR(1000)
);

-- 类型转换
SELECT CAST('123' AS INT);
SELECT CAST(3.14 AS DECIMAL(10,2));
SELECT CONVERT('123', INT);                   -- H2 兼容语法

-- 数学函数
SELECT ABS(-5), MOD(10, 3), ROUND(3.14159, 2);
SELECT CEIL(3.14), FLOOR(3.14), TRUNCATE(3.14159, 2);
SELECT POWER(2, 10), SQRT(144), LOG(100), LOG10(1000);
SELECT PI(), RAND(), RANDOM_UUID();
SELECT SIGN(-5);                              -- -1
SELECT BITAND(15, 9);                         -- 9
SELECT BITOR(9, 6);                           -- 15
SELECT BITXOR(15, 9);                         -- 6

-- 序列
CREATE SEQUENCE user_seq START WITH 1 INCREMENT BY 1;
SELECT NEXT VALUE FOR user_seq;
SELECT CURRENT VALUE FOR user_seq;

-- 注意：H2 支持完整的 SQL 标准数值类型
-- 注意：IDENTITY 是自增主键的简写
-- 注意：支持 TINYINT 到 BIGINT 全部整数类型
-- 注意：兼容模式下可能支持 UNSIGNED 类型
-- 注意：支持序列（SEQUENCE）
