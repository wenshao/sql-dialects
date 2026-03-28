# Impala: 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [Impala SQL Reference](https://impala.apache.org/docs/build/html/topics/impala_langref.html)


一、数据类型: 类似Hive但更严格
INT→INT, BIGINT→BIGINT, FLOAT→FLOAT, DOUBLE→DOUBLE,
VARCHAR→STRING/VARCHAR(n), DECIMAL→DECIMAL(p,s),
BOOLEAN→BOOLEAN, DATE→DATE(Impala不支持), TIMESTAMP→TIMESTAMP
二、陷阱: 与Hive共享Metastore但SQL方言不同, 不支持UPDATE/DELETE(非Kudu表),
不支持MERGE(非Kudu表), 不支持递归CTE, 不支持LATERAL VIEW(部分),
Kudu表支持UPSERT/UPDATE/DELETE
三、自增: 无
四、日期: now(); current_timestamp(); date_add(d, 1);
datediff(a,b); from_timestamp(ts,'yyyy-MM-dd HH:mm:ss')
to_timestamp(s, 'yyyy-MM-dd HH:mm:ss'); unix_timestamp(); from_unixtime()
五、字符串: length, upper, lower, trim, substr, regexp_replace, instr, concat

## 六、数据类型映射（从 MySQL/PostgreSQL/Hive 到 Impala）

MySQL → Impala:
- INT → INT, BIGINT → BIGINT, FLOAT → FLOAT, DOUBLE → DOUBLE,
- VARCHAR(n) → STRING/VARCHAR(n), TEXT → STRING,
- DATETIME → TIMESTAMP, DATE → TIMESTAMP (无 DATE 类型),
- DECIMAL(p,s) → DECIMAL(p,s), BOOLEAN → BOOLEAN,
- AUTO_INCREMENT → 不支持, JSON → STRING
PostgreSQL → Impala:
- INTEGER → INT, TEXT → STRING, SERIAL → 不支持,
- BOOLEAN → BOOLEAN, JSONB → STRING, BYTEA → STRING,
- ARRAY → 不支持 (非 Kudu)
Hive → Impala: 基本兼容
- STRING → STRING, MAP → MAP (有限), ARRAY → ARRAY (有限),
- STRUCT → STRUCT (有限)


### 七、函数等价映射

MySQL → Impala:
- IFNULL → IF(a IS NULL, b, a)/COALESCE, NOW() → NOW(),
- DATE_FORMAT → FROM_TIMESTAMP, STR_TO_DATE → TO_TIMESTAMP,
- CONCAT(a,b) → CONCAT(a,b), GROUP_CONCAT → GROUP_CONCAT,
- LIMIT → LIMIT


### 八、常见陷阱补充

与 Hive 共享 Metastore 但 SQL 方言不同
- **非 Kudu 表**: 不支持 UPDATE/DELETE/MERGE
- **Kudu 表**: 支持 UPSERT/UPDATE/DELETE
不支持递归 CTE
无 DATE 数据类型（使用 TIMESTAMP）
COMPUTE STATS 需要定期执行以优化查询
INVALIDATE METADATA 刷新外部表变更


### 九、NULL 处理

COALESCE(a, b, c);
IF(a IS NULL, b, a);                               -- 替代 IFNULL
NULLIF(a, b);
NVL(a, b);                                         -- Impala 支持


### 十、分页语法

SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;


### 十一、日期格式码 (Java SimpleDateFormat)

yyyy=年, MM=月, dd=日, HH=24时, hh=12时, mm=分, ss=秒
> **注意**: 与 MySQL 的 %Y/%m/%d 不同
