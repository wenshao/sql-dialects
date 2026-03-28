# Redshift: 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [Amazon Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/)
> - [Amazon Redshift Migration Guide](https://docs.aws.amazon.com/SchemaConversionTool/)


一、数据类型（到 Redshift）
INT→INTEGER, BIGINT→BIGINT, FLOAT→REAL, DOUBLE→DOUBLE PRECISION,
VARCHAR→VARCHAR(max 65535), TEXT→VARCHAR(MAX), DECIMAL→DECIMAL(p,s),
BOOLEAN→BOOLEAN, DATE→DATE, TIMESTAMP→TIMESTAMP/TIMESTAMPTZ,
BLOB→不支持(用S3), JSON→SUPER(推荐)或VARCHAR, AUTO_INCREMENT→IDENTITY
二、函数: IFNULL/NVL→NVL/COALESCE, NOW()→GETDATE()/SYSDATE,
CONCAT→||或CONCAT, GROUP_CONCAT→LISTAGG, DATEDIFF→DATEDIFF,
DATE_ADD→DATEADD
三、陷阱: 无主键强制(信息性), 列式存储(选择合适的DISTKEY/SORTKEY很重要),
无LATERAL JOIN, 有限的UPDATE/DELETE性能, 无窗口帧ROWS BETWEEN(部分支持),
VARCHAR最大65535字节
四、自增: IDENTITY(seed, step)
五、日期: GETDATE(); CURRENT_DATE; DATEADD('day',1,d); DATEDIFF('day',a,b);
TO_CHAR(ts,'YYYY-MM-DD HH24:MI:SS')
TO_DATE(s,'YYYY-MM-DD'); TO_TIMESTAMP(s,'YYYY-MM-DD HH24:MI:SS')
EXTRACT(YEAR FROM d); DATE_TRUNC('month', d); SYSDATE
六、字符串: LEN, UPPER, LOWER, TRIM, SUBSTRING, REPLACE, CHARINDEX, ||, LISTAGG

## 七、数据类型映射（从 PostgreSQL/MySQL/Oracle 到 Redshift）

PostgreSQL → Redshift: 部分兼容
- INTEGER → INTEGER, TEXT → VARCHAR(MAX),
- SERIAL → IDENTITY, BOOLEAN → BOOLEAN,
- JSONB → SUPER (推荐), BYTEA → 不支持 (用S3),
- ARRAY → 不支持, TIMESTAMPTZ → TIMESTAMPTZ
MySQL → Redshift:
- INT → INTEGER, BIGINT → BIGINT, FLOAT → REAL,
- DOUBLE → DOUBLE PRECISION, VARCHAR(n) → VARCHAR(n) (max 65535),
- TEXT → VARCHAR(MAX), DATETIME → TIMESTAMP,
- DATE → DATE, DECIMAL(p,s) → DECIMAL(p,s),
- BOOLEAN → BOOLEAN, AUTO_INCREMENT → IDENTITY,
- JSON → SUPER, BLOB → 不支持 (用S3)
Oracle → Redshift:
- NUMBER → DECIMAL, VARCHAR2 → VARCHAR,
- CLOB → VARCHAR(MAX), DATE → TIMESTAMP,
- SYSDATE → GETDATE(), SEQUENCE → IDENTITY


### 八、函数等价映射

MySQL → Redshift:
- IFNULL → NVL/COALESCE, NOW() → GETDATE(),
- DATE_FORMAT → TO_CHAR, CONCAT(a,b) → a || b,
- GROUP_CONCAT → LISTAGG, LIMIT → LIMIT,
- DATE_ADD → DATEADD


### 九、常见陷阱补充

列式存储（DISTKEY/SORTKEY 选择关键）
主键不强制唯一（仅用于优化器提示）
无 LATERAL JOIN
有限的 UPDATE/DELETE 性能
VARCHAR 最大 65535 字节
SUPER 类型替代 JSON（推荐）
COPY 命令从 S3 加载数据（最高效）
Spectrum 可查询 S3 外部表


### 十、NULL 处理

NVL(a, b); NVL2(a, b, c);
COALESCE(a, b, c); NULLIF(a, b);
DECODE(a, NULL, b, a);                             -- 类似 NVL


### 十一、分页语法

SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;


### 十二、日期格式码 (PostgreSQL/Oracle 风格)

YYYY=年, MM=月, DD=日, HH24=24时, MI=分, SS=秒
