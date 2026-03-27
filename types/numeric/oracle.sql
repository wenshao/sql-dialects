-- Oracle: 数值类型
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - NUMBER Data Type
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Data-Types.html
--   [2] Oracle SQL Language Reference - Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Single-Row-Functions.html

-- NUMBER(p,s): Oracle 最主要的数值类型
-- p: 精度（总位数），1~38
-- s: 小数位数，-84~127
-- NUMBER 不指定参数：任意精度

CREATE TABLE examples (
    int_val    NUMBER(10),             -- 整数（10 位）
    big_val    NUMBER(19),             -- 大整数
    price      NUMBER(10,2),           -- 精确到分
    any_num    NUMBER                  -- 任意精度
);

-- 整数快捷方式（21c+）
-- 之前版本没有 INT 的原生类型，INT/INTEGER/SMALLINT 都是 NUMBER(38) 的别名

-- BINARY_FLOAT:  4 字节 IEEE 浮点数（10g+）
-- BINARY_DOUBLE: 8 字节 IEEE 浮点数（10g+）
-- 比 NUMBER 计算更快，但有精度损失
CREATE TABLE t (
    fast_val BINARY_DOUBLE
);

-- FLOAT(b): b 是二进制精度（1~126），映射到 NUMBER
-- FLOAT 默认 = FLOAT(126)

-- 没有 BOOLEAN 类型！
-- PL/SQL 有 BOOLEAN，但 SQL 没有
-- 常用替代：NUMBER(1) CHECK (val IN (0, 1))
-- 23c+: SQL 层面支持 BOOLEAN

-- NUMBER(p,s) 中 s 可以为负数:
-- NUMBER(5, -2): 四舍五入到百位，如 12345 → 12300

-- 自增
-- 传统方式：SEQUENCE
CREATE SEQUENCE users_seq START WITH 1 INCREMENT BY 1;
-- 12c+: IDENTITY 列
CREATE TABLE t (id NUMBER GENERATED ALWAYS AS IDENTITY);

-- 特殊值
SELECT BINARY_DOUBLE_NAN FROM dual;          -- NaN
SELECT BINARY_DOUBLE_INFINITY FROM dual;     -- 正无穷

-- 注意：NUMBER 没有 UNSIGNED
-- 注意：空字符串 '' = NULL，但数值 0 ≠ NULL
