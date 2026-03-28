# Synapse: 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [Azure Synapse Analytics Documentation](https://learn.microsoft.com/en-us/azure/synapse-analytics/)


一、与 SQL Server 兼容性: 大部分T-SQL语法兼容
差异: MPP架构, 分布式表(HASH/ROUND_ROBIN/REPLICATE),
不支持部分T-SQL(如游标/临时存储过程/全文搜索)
二、数据类型: 与SQL Server基本相同
差异: 无TIMESTAMP(rowversion), 无HIERARCHYID, GEOMETRY/GEOGRAPHY有限支持
三、陷阱: DISTRIBUTION选择很关键(HASH vs ROUND_ROBIN vs REPLICATE),
CTAS模式替代INSERT/UPDATE(推荐), 不支持MERGE(部分池),
Serverless SQL Pool vs Dedicated SQL Pool功能不同,
统计信息需要手动创建/更新
四、自增: IDENTITY(1,1)
五、日期/字符串: 与 SQL Server 基本相同
GETDATE(); CURRENT_TIMESTAMP; DATEADD(DAY,1,d);
DATEDIFF(DAY,a,b); CONVERT(VARCHAR,d,120); FORMAT(d,'yyyy-MM-dd')
六、字符串: LEN, UPPER, LOWER, TRIM, SUBSTRING, REPLACE, CHARINDEX, +, STRING_AGG

## 七、数据类型映射（从 SQL Server/PostgreSQL/MySQL 到 Synapse）

SQL Server → Synapse: 大部分兼容
- INT → INT, BIGINT → BIGINT, FLOAT → FLOAT,
- VARCHAR(n) → VARCHAR(n), NVARCHAR(n) → NVARCHAR(n),
- DATETIME → DATETIME/DATETIME2, DATE → DATE,
- DECIMAL(p,s) → DECIMAL(p,s), BIT → BIT,
- XML → 不支持, TIMESTAMP(rowversion) → 不支持,
- HIERARCHYID → 不支持, FILESTREAM → 不支持
MySQL → Synapse:
- INT → INT, VARCHAR(n) → VARCHAR(n),
- DATETIME → DATETIME2, TEXT → VARCHAR(MAX),
- AUTO_INCREMENT → IDENTITY(1,1), TINYINT(1) → BIT,
- JSON → NVARCHAR(MAX) (用JSON函数)


### 八、函数等价映射

MySQL → Synapse:
- IFNULL → ISNULL/COALESCE, NOW() → GETDATE(),
- DATE_FORMAT → FORMAT/CONVERT, CONCAT → CONCAT/+,
- GROUP_CONCAT → STRING_AGG, LIMIT → TOP/OFFSET FETCH


### 九、常见陷阱补充

- **DISTRIBUTION 选择关键**: HASH(均匀分布)/ROUND_ROBIN(默认)/REPLICATE(小表)
CTAS 模式替代 INSERT/UPDATE（推荐的数据加载方式）
不支持 MERGE（Dedicated SQL Pool 部分版本支持）
Serverless SQL Pool vs Dedicated SQL Pool 功能不同
统计信息需要手动创建/更新
不支持游标/临时存储过程/全文搜索
PolyBase 可查询外部数据源


### 十、NULL 处理

ISNULL(a, b);                                      -- SQL Server 风格
COALESCE(a, b, c);                                 -- 标准 SQL
NULLIF(a, b);


### 十一、分页语法

SELECT * FROM t ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
SELECT TOP 10 * FROM t ORDER BY id;                -- 只取前 N 行
