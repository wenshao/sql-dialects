# 人大金仓 (KingbaseES): 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [KingbaseES Documentation](https://help.kingbase.com.cn/)


一、多模式兼容: PostgreSQL模式(默认), Oracle模式, MySQL模式
PostgreSQL模式: 高度兼容PostgreSQL语法
Oracle模式: 兼容Oracle SQL/PL语法
二、数据类型: 取决于兼容模式
PG模式: 与PostgreSQL相同
Oracle模式: 支持NUMBER, VARCHAR2, DATE(含时间)等
三、陷阱: 国产数据库, 兼容模式在初始化时选择, 部分高级特性受限,
KWR(类似AWR)性能报告, KCES安全增强
四、自增: SERIAL(PG模式) 或 SEQUENCE
五、日期/字符串: 取决于兼容模式（PostgreSQL或Oracle语法）
PG模式: NOW(); TO_CHAR(ts,'YYYY-MM-DD'); TO_DATE('2024-01-15','YYYY-MM-DD')
Oracle模式: SYSDATE; TO_CHAR(SYSDATE,'YYYY-MM-DD'); TO_DATE(...)
六、字符串: LENGTH, UPPER, LOWER, TRIM, SUBSTR, REPLACE, POSITION/INSTR, ||

## 七、数据类型映射（从 Oracle/PostgreSQL/MySQL 到 KingbaseES）

Oracle → KingbaseES (Oracle 模式): 高度兼容
- NUMBER → NUMBER, VARCHAR2 → VARCHAR2, CLOB → CLOB,
- DATE → DATE, TIMESTAMP → TIMESTAMP, BLOB → BLOB,
- SEQUENCE → SEQUENCE
PostgreSQL → KingbaseES (PG 模式): 高度兼容
- INTEGER → INTEGER, TEXT → TEXT, SERIAL → SERIAL,
- JSONB → JSONB, BOOLEAN → BOOLEAN, ARRAY → ARRAY
MySQL → KingbaseES (MySQL 模式):
- INT → INTEGER, VARCHAR(n) → VARCHAR(n),
- DATETIME → TIMESTAMP, AUTO_INCREMENT → SERIAL,
- TEXT → TEXT, JSON → JSON

### 八、函数等价映射 (取决于兼容模式)

- **Oracle模式**: NVL, DECODE, SYSDATE, ROWNUM, TO_CHAR, TO_DATE
- **PG模式**: COALESCE, CASE WHEN, NOW(), ROW_NUMBER(), TO_CHAR, TO_DATE
- **MySQL模式**: IFNULL, NOW(), DATE_FORMAT, STR_TO_DATE

### 九、常见陷阱补充

国产数据库，兼容模式在初始化时选择，不可更改
部分高级特性受限（如全文索引、GIS 等）
KWR 性能报告（类似 Oracle AWR）
KCES 安全增强（三权分立）
PG 模式下大部分 PostgreSQL 扩展可用
Oracle 模式兼容 PL/SQL（但非 100%）

### 十、NULL 处理

- **PG模式**: COALESCE(a,b,c); NULLIF(a,b); IS DISTINCT FROM
- **Oracle模式**: NVL(a,b); NVL2(a,b,c); DECODE(col,NULL,'null',col)

### 十一、分页语法

- **PG模式**: SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;
- **Oracle模式**: SELECT * FROM t WHERE ROWNUM <= 10;
或 FETCH FIRST 10 ROWS ONLY;
