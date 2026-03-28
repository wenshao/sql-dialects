# openGauss: 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [openGauss Documentation](https://docs.opengauss.org/)


一、与 PostgreSQL 兼容性: 基于PostgreSQL 9.2, 扩展了部分功能
差异: 存储引擎不同(MOT内存表), 安全增强, AI特性,
部分PostgreSQL新版本特性不支持(基于较老版本)
二、数据类型: 与PostgreSQL基本相同, 额外支持部分Oracle类型
三、陷阱: 华为开源数据库, 兼容PostgreSQL但不是100%,
MOT(内存优化表)适合OLTP高并发, 分布式版本openGauss需要分片键,
gs_tools系列工具管理集群
四、自增: SERIAL 或 GENERATED ALWAYS AS IDENTITY
五、日期/字符串: 与 PostgreSQL 基本相同
NOW(); CURRENT_TIMESTAMP; CURRENT_DATE;
TO_CHAR(ts, 'YYYY-MM-DD HH24:MI:SS'); TO_DATE('2024-01-15', 'YYYY-MM-DD');
六、字符串: LENGTH, UPPER, LOWER, TRIM, SUBSTRING, REPLACE, POSITION, ||, STRING_AGG

## 七、数据类型映射（从 PostgreSQL/MySQL/Oracle 到 openGauss）

PostgreSQL → openGauss: 大部分兼容 (基于 PG 9.2)
- INT → INT, TEXT → TEXT, JSONB → JSONB (部分),
- SERIAL → SERIAL, BOOLEAN → BOOLEAN
> **注意**: PG 10+ 的声明式分区等新特性可能不支持
MySQL → openGauss:
- INT → INTEGER, VARCHAR(n) → VARCHAR(n),
- DATETIME → TIMESTAMP, TINYINT(1) → BOOLEAN,
- AUTO_INCREMENT → SERIAL, JSON → JSON/JSONB
Oracle → openGauss:
- NUMBER(p,s) → NUMERIC(p,s), VARCHAR2(n) → VARCHAR(n),
- CLOB → TEXT, DATE → TIMESTAMP, SYSDATE → NOW()

### 八、函数等价映射

MySQL → openGauss:
- IFNULL → COALESCE, NOW() → NOW(),
- DATE_FORMAT → TO_CHAR, STR_TO_DATE → TO_DATE,
- CONCAT(a,b) → a || b, GROUP_CONCAT → STRING_AGG,
- LIMIT → LIMIT
Oracle → openGauss:
- NVL → COALESCE/NVL, SYSDATE → NOW(), ROWNUM → ROW_NUMBER(),
- DECODE → CASE WHEN, FROM DUAL → (省略)

### 九、常见陷阱补充

基于 PostgreSQL 9.2，部分新版 PG 特性不支持
MOT 内存优化表适合 OLTP 高并发场景
分布式版本 (openGauss-distributed) 需要指定分片键
gs_tools 系列工具管理集群
- **安全增强**: 数据加密、审计、脱敏
兼容部分 Oracle 语法 (DECODE, NVL, ROWNUM 等)

### 十、NULL 处理

COALESCE(a, b, c); NVL(a, b);
NULLIF(a, b); IS DISTINCT FROM;

### 十一、分页语法

SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;
SELECT * FROM t ORDER BY id FETCH FIRST 10 ROWS ONLY;
