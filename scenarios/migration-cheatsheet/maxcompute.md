# MaxCompute (ODPS): 迁移速查表

> 参考资料:
> - [1] MaxCompute SQL Reference
>   https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview


## 1. 数据类型映射


 MySQL → MaxCompute:
INT → INT(2.0+) / BIGINT(1.0)    | BIGINT → BIGINT
FLOAT → FLOAT(2.0+) / DOUBLE     | DOUBLE → DOUBLE
DECIMAL(p,s) → DECIMAL(p,s)      | VARCHAR(n) → VARCHAR(n)(2.0+) / STRING
TEXT → STRING                     | DATETIME → DATETIME
DATE → DATE(2.0+)                | TIMESTAMP → TIMESTAMP(2.0+)
BOOLEAN → BOOLEAN(2.0+)          | BLOB → BINARY(2.0+)
JSON → JSON(2024+) / STRING      | AUTO_INCREMENT → 不支持
ENUM → STRING                    | SET → STRING

 Hive → MaxCompute: 高度兼容
STRING → STRING                  | INT → INT
ARRAY<T> → ARRAY<T>             | MAP<K,V> → MAP<K,V>
   STRUCT<...> → STRUCT<...>

 Oracle → MaxCompute:
NUMBER(p,s) → DECIMAL(p,s)      | VARCHAR2 → STRING
CLOB → STRING                   | DATE → DATETIME
SYSDATE → GETDATE()             | NVL → NVL（兼容）
DECODE → DECODE（兼容）          | ROWNUM → ROW_NUMBER() OVER(...)

 PostgreSQL → MaxCompute:
INTEGER → INT(2.0+)             | TEXT → STRING
NUMERIC → DECIMAL               | TIMESTAMPTZ → TIMESTAMP（无时区!）
SERIAL → 不支持（用 ROW_NUMBER）| BOOLEAN → BOOLEAN(2.0+)
JSONB → JSON(2024+) / STRING    | ARRAY → ARRAY<T>

## 2. 函数映射


 当前时间:
MySQL NOW() → GETDATE()         | PostgreSQL CURRENT_TIMESTAMP → GETDATE()
   Oracle SYSDATE → GETDATE()

 NULL 处理:
MySQL IFNULL → NVL / COALESCE   | Oracle NVL → NVL（兼容）
   PostgreSQL COALESCE → COALESCE

 字符串:
MySQL CONCAT → CONCAT           | Oracle || → CONCAT（|| 不支持）
MySQL GROUP_CONCAT → WM_CONCAT  | PostgreSQL STRING_AGG → WM_CONCAT（无序!）
MySQL LENGTH → CHAR_LENGTH(2.0+)| Oracle LENGTH → CHAR_LENGTH（注意字节/字符差异!）

 日期:
   MySQL DATE_FORMAT → DATE_FORMAT（格式码相似但有差异）
   MySQL DATE_ADD → DATEADD（参数顺序不同!）
   MySQL DATEDIFF → DATEDIFF（多一个 unit 参数）
   Oracle TO_CHAR → TO_CHAR（格式码有差异）
   Oracle ADD_MONTHS → ADD_MONTHS（兼容）

 类型转换:
MySQL CAST → CAST              | PostgreSQL ::type → CAST（不支持::）
MySQL CONVERT → 不支持         | Oracle TO_NUMBER → CAST(... AS DECIMAL)

## 3. 常见迁移陷阱


 陷阱 1: SELECT 1; 不合法
   MySQL/PostgreSQL: SELECT 1; 合法
   MaxCompute: 需要 FROM 子句: SELECT 1 FROM (SELECT 1) t;

 陷阱 2: 字符串比较大小写敏感
   MySQL: 默认不敏感（utf8mb4_general_ci）
   MaxCompute: 默认敏感 → WHERE name = 'Alice' 不匹配 'alice'
   解决: WHERE LOWER(name) = 'alice'

 陷阱 3: LENGTH 返回字节数
   MySQL LENGTH('你好') = 2（字符数）
   MaxCompute LENGTH('你好') = 6（字节数!）
   解决: 使用 CHAR_LENGTH（2.0+）

 陷阱 4: DATEADD 参数顺序
   MySQL: DATE_ADD(date, INTERVAL 7 DAY)
   MaxCompute: DATEADD(date, 7, 'dd')

 陷阱 5: 普通表不支持 UPDATE/DELETE
   迁移 MySQL 的 UPDATE/DELETE → INSERT OVERWRITE 模式

 陷阱 6: 没有 AUTO_INCREMENT
   迁移自增列 → ROW_NUMBER() OVER(...) 或 UUID()

 陷阱 7: 分区列不是普通列
   MySQL: 分区列是表中的普通列
   MaxCompute: 分区列在 PARTITIONED BY 中单独定义

 陷阱 8: 两套格式码
   TO_CHAR: mm = 月, mi = 分钟
   DATE_FORMAT: MM = 月, mm = 分钟

## 4. 核心架构差异


 MaxCompute 不是传统数据库:
   每个 SQL 是一个分布式作业（秒级启动延迟）
   没有"连接"/"会话"概念
   计费按扫描数据量或预留 CU
   主要数据写入方式: INSERT OVERWRITE（分区级替换）
   数据导入: Tunnel SDK（非 INSERT VALUES）

 命名层级:
   MySQL: database.table → MaxCompute: project.schema.table（3.0+）
   权限: MySQL GRANT → MaxCompute ACL + Label Security

## 5. 分页语法


 MaxCompute 2.0+: LIMIT n OFFSET m
 旧版: 只有 LIMIT n（无 OFFSET）
 不支持: MySQL LIMIT m, n 简写 / SQL 标准 FETCH FIRST

## 6. NULL 处理


```sql
SELECT NVL(a, b);                           -- a 为 NULL 则返回 b
SELECT COALESCE(a, b, c);                   -- 返回第一个非 NULL
SELECT NULLIF(a, b);                        -- a = b 则返回 NULL
SELECT NVL2(a, b, c);                       -- a 非 NULL 返回 b，否则 c

```

## 7. 日期格式码速查


 Java SimpleDateFormat（DATE_FORMAT 使用）:
   yyyy=年 MM=月 dd=日 HH=24时 mm=分 ss=秒
 Oracle 风格（TO_CHAR/TO_DATE 使用）:
   yyyy=年 mm=月 dd=日 hh=时 mi=分 ss=秒

## 8. 迁移决策树


 从 MySQL 迁移:
### 1. 开启 2.0 类型系统: SET odps.sql.type.system.odps2 = true;

### 2. UPDATE/DELETE → MERGE(事务表) 或 INSERT OVERWRITE

### 3. AUTO_INCREMENT → ROW_NUMBER/UUID

### 4. 触发器 → DataWorks 调度

### 5. 存储过程 → Script Mode + UDF


从 Hive 迁移:
高度兼容（语法90%+兼容）
注意: 部分 Hive UDF 需要重新注册
注意: Hive SerDe 可能不完全支持

从 Oracle 迁移:
NVL/DECODE/TO_CHAR 大部分兼容
PL/SQL → Script Mode + DataWorks
CONNECT BY → 路径枚举/闭包表
MERGE → MERGE(事务表)

