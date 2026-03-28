# 达梦 (Dameng): 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [达梦数据库 SQL 参考手册](https://eco.dameng.com/document/dm/zh-cn/sql-dev/)


一、与 Oracle 兼容性: 高度兼容Oracle SQL和PL/SQL
数据类型: NUMBER→NUMBER, VARCHAR2→VARCHAR2/VARCHAR, CLOB→CLOB,
DATE→DATE(含时间), TIMESTAMP→TIMESTAMP, BLOB→BLOB
二、函数: NVL, DECODE, TO_CHAR, TO_DATE, SYSDATE, ROWNUM 等Oracle函数均支持
三、陷阱: 国产数据库, 需要适配特定认证要求, 部分Oracle高级特性不支持,
PL/SQL兼容但不是100%, 数据迁移工具DTS可用,
字符集选择影响存储(推荐UTF-8)
四、自增: IDENTITY(1,1) 或 SEQUENCE
五、日期: SYSDATE; CURRENT_DATE; SYSDATE+1; TO_CHAR(SYSDATE,'YYYY-MM-DD')
ADD_MONTHS(SYSDATE, 1); MONTHS_BETWEEN(a, b);
EXTRACT(YEAR FROM SYSDATE); TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS')
六、字符串: LENGTH, UPPER, LOWER, TRIM, SUBSTR, REPLACE, INSTR, ||, LISTAGG

## 七、数据类型映射（从 Oracle/MySQL/PostgreSQL 到 达梦）

Oracle → 达梦: 高度兼容
NUMBER → NUMBER, VARCHAR2 → VARCHAR2, CLOB → CLOB,
DATE → DATE, TIMESTAMP → TIMESTAMP, BLOB → BLOB,
SEQUENCE → SEQUENCE, ROWID → ROWID
MySQL → 达梦:
INT → INTEGER, VARCHAR(n) → VARCHAR(n),
DATETIME → TIMESTAMP, TEXT → CLOB,
AUTO_INCREMENT → IDENTITY(1,1),
TINYINT(1) → BIT/BOOLEAN, ENUM → VARCHAR + CHECK
PostgreSQL → 达梦:
INTEGER → INTEGER, TEXT → CLOB, SERIAL → IDENTITY,
BOOLEAN → BIT, JSONB → CLOB (用JSON函数)
八、函数等价映射
MySQL → 达梦:
IFNULL → NVL, NOW() → SYSDATE,
DATE_FORMAT → TO_CHAR, STR_TO_DATE → TO_DATE,
CONCAT(a,b) → a || b, GROUP_CONCAT → LISTAGG,
LIMIT n → ROWNUM <= n 或 FETCH FIRST n ROWS ONLY
九、常见陷阱补充
国产数据库，需要适配特定信创认证要求
高度兼容 Oracle，但 PL/SQL 不是 100% 兼容
字符集选择影响存储（推荐 UTF-8）
DTS 数据迁移工具可用于 Oracle/MySQL 迁移
IDENTITY 列和 SEQUENCE 都支持自增
ROWNUM 支持（与 Oracle 兼容）
十、NULL 处理
NVL(a, b);                                         -- 第一个非 NULL
NVL2(a, b, c);                                     -- a 非 NULL 返回 b，否则返回 c
COALESCE(a, b, c);                                 -- 标准 SQL
NULLIF(a, b);                                      -- a=b 时返回 NULL
DECODE(col, NULL, 'null', col);                    -- 处理 NULL
十一、分页语法
Oracle 风格: SELECT * FROM t WHERE ROWNUM <= 10;
标准 SQL: SELECT * FROM t FETCH FIRST 10 ROWS ONLY;
偏移: SELECT * FROM t ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
