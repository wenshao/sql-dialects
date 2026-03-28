# TimescaleDB: 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [TimescaleDB Documentation](https://docs.timescale.com/)


一、与 PostgreSQL 兼容性: 100%兼容（TimescaleDB是PostgreSQL扩展）
额外功能: Hypertable(自动分区), 连续聚合, 压缩, 数据保留策略
二、数据类型: 与PostgreSQL完全相同
三、陷阱: CREATE TABLE后需要SELECT create_hypertable()将表转为hypertable,
时间列必须存在, 分区间隔选择影响性能, 压缩可大幅减少存储,
连续聚合类似物化视图但自动刷新
四、自增/日期/字符串: 与 PostgreSQL 完全相同
五、TimescaleDB特有:
SELECT create_hypertable('table', 'time_column');
SELECT time_bucket('1 hour', ts) AS bucket, avg(value) FROM ...;
ALTER TABLE t SET (timescaledb.compress);

## 六、数据类型映射（从 MySQL/InfluxDB 到 TimescaleDB/PostgreSQL）

MySQL → TimescaleDB:
INT → INTEGER, BIGINT → BIGINT, FLOAT → REAL,
DOUBLE → DOUBLE PRECISION, VARCHAR(n) → VARCHAR(n),
TEXT → TEXT, DATETIME → TIMESTAMPTZ (推荐),
DATE → DATE, DECIMAL(p,s) → NUMERIC(p,s),
AUTO_INCREMENT → SERIAL, TINYINT(1) → BOOLEAN,
JSON → JSONB (推荐)
InfluxDB → TimescaleDB:
measurement → hypertable, tag → indexed column,
field (float) → DOUBLE PRECISION, field (int) → BIGINT,
field (string) → TEXT, timestamp → TIMESTAMPTZ
七、函数等价映射
MySQL → TimescaleDB:
IFNULL → COALESCE, NOW() → NOW(),
DATE_FORMAT → TO_CHAR, STR_TO_DATE → TO_DATE,
CONCAT(a,b) → a || b, GROUP_CONCAT → STRING_AGG,
LIMIT → LIMIT
八、常见陷阱补充
CREATE TABLE 后需要 SELECT create_hypertable() 转换
时间列必须存在（TIMESTAMPTZ 推荐）
分区间隔选择影响性能（默认 7 天）
压缩可大幅减少存储（ALTER TABLE ... SET compress）
连续聚合类似物化视图但自动刷新
数据保留策略: SELECT add_retention_policy('t', INTERVAL '30 days');
作业调度: TimescaleDB 内置 job scheduler
九、NULL 处理: 与 PostgreSQL 完全相同
COALESCE(a, b, c); NULLIF(a, b);
IS DISTINCT FROM / IS NOT DISTINCT FROM
十、分页语法
SELECT * FROM t ORDER BY time DESC LIMIT 10 OFFSET 20;
十一、时序特有查询
SELECT time_bucket('1 hour', ts) AS bucket,
avg(value), min(value), max(value)
FROM metrics
WHERE ts > NOW() - INTERVAL '7 days'
GROUP BY bucket ORDER BY bucket DESC;
十二、连续聚合
CREATE MATERIALIZED VIEW hourly_avg
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', ts) AS bucket, avg(value)
FROM metrics GROUP BY bucket;
