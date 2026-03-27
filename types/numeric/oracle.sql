-- Oracle: 数值类型
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - NUMBER Data Type
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Data-Types.html

-- ============================================================
-- 1. NUMBER: Oracle 的"万能"数值类型
-- ============================================================

-- NUMBER(p,s): Oracle 最核心的数值类型
-- p: 精度（总有效位数），1~38
-- s: 小数位数（标度），-84~127
-- NUMBER 不指定参数: 任意精度（最灵活）

CREATE TABLE examples (
    int_val    NUMBER(10),            -- 整数（10 位）
    big_val    NUMBER(19),            -- 大整数
    price      NUMBER(10,2),          -- 精确到分
    any_num    NUMBER                 -- 任意精度
);

-- 设计分析: NUMBER 万能类型的哲学
--   Oracle 没有 INT、BIGINT、DECIMAL、FLOAT 等独立类型。
--   INT/INTEGER/SMALLINT 都只是 NUMBER(38) 的别名!
--   这与其他数据库形成鲜明对比:
--
-- 横向对比:
--   Oracle:     NUMBER(p,s) 是唯一的精确数值类型
--               INT = NUMBER(38), DECIMAL(p,s) = NUMBER(p,s)
--   PostgreSQL: smallint(2B) / integer(4B) / bigint(8B) / numeric(p,s)
--   MySQL:      tinyint(1B) / smallint(2B) / int(4B) / bigint(8B) / decimal(p,s)
--   SQL Server: tinyint(1B) / smallint(2B) / int(4B) / bigint(8B) / decimal(p,s)
--
-- Oracle 设计的优缺点:
--   优点: 简单，不需要选择"够不够大"（NUMBER(38) 足够任何整数）
--   缺点: 存储效率低（NUMBER 是变长的，最多 22 字节，而 INT 固定 4 字节）
--         查询性能: 定长整数的 CPU 运算比变长 NUMBER 快
--         从 Oracle 迁移到其他数据库: 需要手动映射 NUMBER → INT/BIGINT/DECIMAL
--
-- 对引擎开发者的启示:
--   推荐提供独立的整数类型（INT/BIGINT）+ 精确小数类型（DECIMAL/NUMERIC）。
--   固定长度整数在存储和 CPU 运算上都优于变长精确数值。
--   Oracle 的 NUMBER 设计是"简化用户选择"，但牺牲了性能。

-- ============================================================
-- 2. NUMBER(p,s) 中 s 的特殊行为
-- ============================================================

-- s 可以为负数（四舍五入到指定位数）
-- NUMBER(5, -2): 四舍五入到百位
INSERT INTO examples (int_val) VALUES (12345);
-- 存储为 12300（如果类型是 NUMBER(5,-2)）

-- s 可以大于 p（存储小于 1 的小数）
-- NUMBER(2, 5): 存储形如 0.000XX 的小数

-- ============================================================
-- 3. BINARY_FLOAT / BINARY_DOUBLE（10g+，IEEE 754）
-- ============================================================

CREATE TABLE fast_math (
    val_f BINARY_FLOAT,              -- 4 字节 IEEE 浮点
    val_d BINARY_DOUBLE              -- 8 字节 IEEE 浮点
);

-- 比 NUMBER 计算更快，但有精度损失（浮点固有问题）
-- 支持特殊值:
SELECT BINARY_FLOAT_NAN FROM DUAL;             -- NaN
SELECT BINARY_DOUBLE_INFINITY FROM DUAL;       -- 正无穷
SELECT BINARY_FLOAT_MAX_NORMAL FROM DUAL;      -- 最大正常值

-- 设计分析:
--   Oracle 10g 才引入 IEEE 浮点类型，之前只有 NUMBER。
--   BINARY_DOUBLE 适合科学计算（速度是 NUMBER 的 3-5 倍）。
--   但金融应用必须用 NUMBER（浮点精度问题）。

-- ============================================================
-- 4. BOOLEAN 类型的缺失与补救
-- ============================================================

-- 23c 之前: SQL 层面没有 BOOLEAN 类型!
-- PL/SQL 有 BOOLEAN，但 SQL 没有（不能作为表列类型）
-- 常用替代:
--   NUMBER(1) CHECK (val IN (0, 1))
--   CHAR(1) CHECK (val IN ('Y', 'N'))

-- 23c+: SQL 层面支持 BOOLEAN
-- CREATE TABLE t (id NUMBER, is_active BOOLEAN);

-- 横向对比:
--   Oracle <23c: 无 SQL BOOLEAN（最大遗漏之一）
--   PostgreSQL:  BOOLEAN（一直有）
--   MySQL:       BOOLEAN = TINYINT(1)（语法糖）
--   SQL Server:  BIT（0/1）

-- ============================================================
-- 5. 自增（SEQUENCE + IDENTITY）
-- ============================================================

-- 传统方式: SEQUENCE
CREATE SEQUENCE users_seq START WITH 1 INCREMENT BY 1;

-- 12c+: IDENTITY 列
CREATE TABLE t (id NUMBER GENERATED ALWAYS AS IDENTITY);

-- ============================================================
-- 6. NUMBER 没有 UNSIGNED
-- ============================================================

-- Oracle NUMBER 没有无符号版本
-- 需要 CHECK 约束模拟: CHECK (val >= 0)

-- ============================================================
-- 7. '' = NULL vs 数值 0
-- ============================================================

-- 空字符串 '' = NULL（Oracle 独有行为）
-- 但数值 0 ≠ NULL（这是正常的）
-- 注意区分: '' = NULL 只影响字符类型

-- TO_NUMBER('') 的行为:
-- SELECT TO_NUMBER('') FROM DUAL;  -- ORA-01722: invalid number
-- 看似应该返回 NULL，但实际报错（Oracle 内部不一致性）

-- ============================================================
-- 8. 对引擎开发者的总结
-- ============================================================
-- 1. NUMBER 万能类型简化了用户选择但牺牲了存储和性能效率。
-- 2. 新引擎应提供独立的 INT/BIGINT + DECIMAL/NUMERIC 类型体系。
-- 3. BOOLEAN 的缺失是 Oracle 长达 40+ 年的遗憾，23c 才修复。
-- 4. IEEE 浮点类型（FLOAT/DOUBLE）对科学计算必要，但不应是默认数值类型。
-- 5. NUMBER(p,s) 中 s 为负数的行为是 Oracle 独特的设计，实际使用率低。
