# TDengine: 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [TDengine Documentation](https://docs.tdengine.com/)


一、专用时序数据库: 不适用于通用OLTP/OLAP迁移
数据类型: TIMESTAMP(必须), INT, BIGINT, FLOAT, DOUBLE,
BINARY(定长字节串), NCHAR(Unicode字符串), BOOL, TINYINT, SMALLINT,
JSON(仅TAG), 无VARCHAR/TEXT/DATE/DECIMAL
二、数据模型: 超级表(STABLE)→子表(TABLE), TAG标签
每个采集设备一个子表, 必须有时间戳列作为第一列
三、陷阱: 时序数据库(不是通用数据库), 不支持JOIN(3.0有限支持),
不支持事务/回滚, 不支持UPDATE(同时间戳覆盖), 不支持DELETE(部分),
SQL语法是子集, 适合IoT/监控/日志场景
四、自增: 无（时间戳是唯一标识）
五、日期: NOW(); NOW()+1h; TIMEDIFF(a,b); TO_ISO8601(ts)
TO_UNIXTIMESTAMP(s); TIMETRUNCATE(ts, 1h);
TIMEZONE(); ELAPSED(ts) 计算时间间隔
六、字符串: LENGTH, UPPER, LOWER, LTRIM/RTRIM, SUBSTR, CONCAT

## 七、数据类型映射（从 SQL 数据库/InfluxDB 到 TDengine）

MySQL/PostgreSQL → TDengine:
INT → INT, BIGINT → BIGINT, FLOAT → FLOAT,
DOUBLE → DOUBLE, VARCHAR → BINARY/NCHAR,
TEXT → NCHAR(n), BOOLEAN → BOOL,
DATETIME/TIMESTAMP → TIMESTAMP (必须为第一列),
TINYINT → TINYINT, SMALLINT → SMALLINT,
DECIMAL → 不支持, DATE → 不支持, JSON → JSON (仅TAG)
InfluxDB → TDengine:
measurement → 超级表 (STABLE),
tag → TAG 列, field(float) → DOUBLE,
field(int) → BIGINT, field(string) → NCHAR,
timestamp → TIMESTAMP (第一列)
八、函数等价映射
SQL → TDengine:
COUNT/SUM/AVG/MIN/MAX → 支持
IFNULL → 不支持 (用 CASE WHEN),
NOW() → NOW(),
DATE_FORMAT → 不支持 (用 TO_ISO8601),
GROUP BY → GROUP BY (支持),
ORDER BY → ORDER BY (仅按时间列)
九、常见陷阱补充
时序数据库，不是通用数据库
每个采集设备一个子表（子表由超级表模板创建）
第一列必须是 TIMESTAMP 类型
不支持 JOIN (3.0 有限支持)
不支持事务/回滚
同时间戳写入会覆盖旧数据
SQL 语法是标准 SQL 的子集
适合场景: IoT、监控、日志、工业数据采集
数据保留: 通过 KEEP 参数配置自动删除
十、NULL 处理
CASE WHEN col IS NULL THEN default_val ELSE col END;
无 IFNULL/COALESCE/NVL
十一、不支持的 SQL 特性
无 SUBQUERY, 无 HAVING (部分), 无 UNION,
无 DISTINCT (3.0+支持), 无外键/约束,
无 ALTER TABLE ADD COLUMN (超级表除外)
十二、超级表和子表示例
CREATE STABLE meters (ts TIMESTAMP, current FLOAT, voltage INT)
TAGS (location BINARY(64), groupId INT);
CREATE TABLE d1001 USING meters TAGS ('Beijing', 1);
