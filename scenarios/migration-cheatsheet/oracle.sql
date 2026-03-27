-- Oracle: 迁移速查表 (Migration Cheatsheet)
--
-- 参考资料:
--   [1] Oracle Documentation - SQL Language Reference
--       https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/
--   [2] Oracle Database Migration Guide
--       https://docs.oracle.com/en/database/oracle/oracle-database/19/spmig/

-- ============================================================
-- 一、从 MySQL 迁移到 Oracle
-- ============================================================
-- 数据类型: INT→NUMBER(10), BIGINT→NUMBER(19), VARCHAR→VARCHAR2,
--           TEXT→CLOB, BLOB→BLOB, DATETIME→TIMESTAMP,
--           BOOLEAN→NUMBER(1)或CHAR(1), AUTO_INCREMENT→IDENTITY或SEQUENCE,
--           JSON→JSON(21c+)或CLOB+约束
-- 函数: IFNULL→NVL, IF()→DECODE/CASE, NOW()→SYSDATE/SYSTIMESTAMP,
--        CONCAT(a,b,c)→a||b||c(Oracle CONCAT只接受2参数),
--        GROUP_CONCAT→LISTAGG, DATE_FORMAT→TO_CHAR,
--        LIMIT→ROWNUM/FETCH FIRST(12c+)
-- 陷阱: Oracle空串=NULL, 无AUTO_INCREMENT(12c+有IDENTITY),
--        SELECT必须FROM(用DUAL), 默认大小写为大写

-- ============================================================
-- 二、从 SQL Server 迁移到 Oracle
-- ============================================================
-- 数据类型: NVARCHAR→NVARCHAR2或VARCHAR2, BIT→NUMBER(1),
--           DATETIME2→TIMESTAMP, IDENTITY→IDENTITY(12c+)或SEQUENCE,
--           UNIQUEIDENTIFIER→RAW(16)或VARCHAR2(36)
-- 函数: ISNULL→NVL, GETDATE()→SYSDATE, IIF→CASE/DECODE,
--        TOP→ROWNUM/FETCH FIRST, CROSS APPLY→LATERAL(12c+)
-- 陷阱: T-SQL→PL/SQL完全重写, 临时表语法不同(GTT),
--        Oracle事务需显式COMMIT

-- ============================================================
-- 三、自增/序列
-- ============================================================
-- Oracle 12c+:
CREATE TABLE t (id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY);
-- 传统方式:
CREATE SEQUENCE my_seq START WITH 1 INCREMENT BY 1;
-- 使用: INSERT INTO t (id, name) VALUES (my_seq.NEXTVAL, 'test');

-- ============================================================
-- 四、日期/时间函数
-- ============================================================
SELECT SYSDATE FROM DUAL;                     -- 当前日期时间
SELECT SYSTIMESTAMP FROM DUAL;                -- 高精度时间戳
SELECT TRUNC(SYSDATE) FROM DUAL;              -- 当前日期（去时间）
SELECT SYSDATE + 1 FROM DUAL;                 -- 加一天
SELECT SYSDATE - DATE '2024-01-01' FROM DUAL; -- 日期差（天数）
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
-- 格式: YYYY=年, MM=月, DD=日, HH24=24小时, MI=分, SS=秒
SELECT ADD_MONTHS(SYSDATE, 1) FROM DUAL;      -- 加一月

-- ============================================================
-- 五、字符串函数
-- ============================================================
SELECT LENGTH('hello') FROM DUAL;        -- 字符长度
SELECT UPPER('hello') FROM DUAL;         -- 大写
SELECT LOWER('HELLO') FROM DUAL;         -- 小写
SELECT TRIM('  hello  ') FROM DUAL;      -- 去空格
SELECT SUBSTR('hello', 2, 3) FROM DUAL;  -- 子串 → 'ell'
SELECT REPLACE('hello','l','r') FROM DUAL;-- 替换
SELECT INSTR('hello','lo') FROM DUAL;    -- 位置 → 4
SELECT 'hello' || ' world' FROM DUAL;    -- 连接
SELECT LISTAGG(name, ', ') WITHIN GROUP (ORDER BY name) -- 聚合连接
FROM   users;
SELECT REGEXP_SUBSTR('a,b,c', '[^,]+', 1, 2) FROM DUAL; -- → 'b'
