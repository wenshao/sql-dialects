# Vertica: 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)


一、数据类型（到 Vertica）
INT→INTEGER/INT, BIGINT→BIGINT/INT8, FLOAT→FLOAT/FLOAT8,
VARCHAR→VARCHAR(n)(默认80), TEXT→LONG VARCHAR(max 32MB),
DECIMAL→NUMERIC(p,s), BOOLEAN→BOOLEAN, DATE→DATE,
TIMESTAMP→TIMESTAMP/TIMESTAMPTZ, BLOB→LONG VARBINARY,
JSON→VARCHAR(用JSON函数), AUTO_INCREMENT→AUTO_INCREMENT或IDENTITY
二、函数: IFNULL/NVL→NVL/COALESCE, NOW()→NOW()/CURRENT_TIMESTAMP,
CONCAT→||或CONCAT, GROUP_CONCAT→不支持(用子查询)
三、陷阱: 列式存储MPP(选择合适的投影Projection很重要),
分段segmentation和排序sort order影响性能, 无MERGE(11.x+支持),
DELETE标记行而非物理删除(需PURGE)
四、自增: CREATE TABLE t (id AUTO_INCREMENT PRIMARY KEY);
五、日期: NOW(); CURRENT_DATE; d + INTERVAL '1 day'; DATEDIFF('day',a,b);
TO_CHAR(ts,'YYYY-MM-DD HH24:MI:SS')
TO_DATE(s,'YYYY-MM-DD'); TO_TIMESTAMP(s,'YYYY-MM-DD HH24:MI:SS')
EXTRACT(YEAR FROM d); DATE_TRUNC('month', d)
六、字符串: LENGTH, UPPER, LOWER, TRIM, SUBSTR, REPLACE, POSITION, ||

## 七、数据类型映射（从 PostgreSQL/MySQL/Oracle 到 Vertica）

PostgreSQL → Vertica: 基本兼容
INTEGER → INTEGER/INT, TEXT → LONG VARCHAR (max 32MB),
SERIAL → AUTO_INCREMENT/IDENTITY,
BOOLEAN → BOOLEAN, JSONB → VARCHAR (用JSON函数),
BYTEA → LONG VARBINARY, ARRAY → 不直接支持
MySQL → Vertica:
INT → INTEGER, BIGINT → BIGINT/INT8,
VARCHAR(n) → VARCHAR(n) (默认80), TEXT → LONG VARCHAR,
DATETIME → TIMESTAMP, DATE → DATE,
DECIMAL(p,s) → NUMERIC(p,s), BOOLEAN → BOOLEAN,
AUTO_INCREMENT → AUTO_INCREMENT/IDENTITY,
JSON → VARCHAR (用JSON函数)
Oracle → Vertica:
NUMBER(p,s) → NUMERIC(p,s), VARCHAR2(n) → VARCHAR(n),
CLOB → LONG VARCHAR, DATE → TIMESTAMP,
SYSDATE → NOW(), SEQUENCE → SEQUENCE

八、函数等价映射
MySQL → Vertica:
IFNULL → NVL/COALESCE, NOW() → NOW(),
DATE_FORMAT → TO_CHAR, CONCAT(a,b) → a || b,
GROUP_CONCAT → 不直接支持 (用子查询),
LIMIT → LIMIT

九、常见陷阱补充
列式存储 MPP（Projection 投影很重要）
Segmentation 和 Sort Order 影响性能
DELETE 标记行而非物理删除（需 PURGE）
无 MERGE (11.x+ 支持)
VARCHAR 默认最大长度 80（需显式指定长度）
COPY 命令批量加载数据
Flex Table 可加载半结构化数据

十、NULL 处理
NVL(a, b); COALESCE(a, b, c);
NULLIF(a, b); NVL2(a, b, c);
ZEROIFNULL(a);                                     -- NULL→0

十一、分页语法
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

十二、日期格式码 (PostgreSQL/Oracle 风格)
YYYY=年, MM=月, DD=日, HH24=24时, MI=分, SS=秒
