# TDengine: 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [TDengine Documentation - SQL Reference](https://docs.tdengine.com/taos-sql/)
> - [TDengine Documentation - String Functions](https://docs.tdengine.com/taos-sql/function/#string-functions)
> - [TDengine Documentation - UDF（用户自定义函数）](https://docs.tdengine.com/taos-sql/udf/)


## TDengine 字符串拆分概述


TDengine 是专用时序数据库，对字符串拆分的原生支持有限:
(a) 无内置的 SPLIT 或字符串拆分函数
(b) 不支持 UNNEST 或数组展开
(c) 不支持递归 CTE（WITH RECURSIVE）
(d) 可通过 UDF（用户自定义函数）扩展功能

## 推荐数据模型: 预拆分为多行


## 时序数据库的最佳实践是数据写入时即完成拆分

将标签字符串拆分为多行存储（每个标签一条记录）

```sql
CREATE STABLE IF NOT EXISTS sensor_tags (
    ts      TIMESTAMP,
    value   DOUBLE
) TAGS (
    device_id INT,
    tag       NCHAR(50)
);
```

## 预拆分写入: 每个标签单独创建子表或写入不同行

```sql
CREATE TABLE IF NOT EXISTS sensor_1_python USING sensor_tags TAGS (1, 'python');
CREATE TABLE IF NOT EXISTS sensor_1_java   USING sensor_tags TAGS (1, 'java');
CREATE TABLE IF NOT EXISTS sensor_1_sql    USING sensor_tags TAGS (1, 'sql');
CREATE TABLE IF NOT EXISTS sensor_2_go     USING sensor_tags TAGS (2, 'go');
CREATE TABLE IF NOT EXISTS sensor_2_rust   USING sensor_tags TAGS (2, 'rust');

INSERT INTO sensor_1_python VALUES ('2024-01-01 08:00:00', 22.5);
INSERT INTO sensor_1_java   VALUES ('2024-01-01 08:00:00', 22.5);
INSERT INTO sensor_1_sql    VALUES ('2024-01-01 08:00:00', 22.5);
INSERT INTO sensor_2_go     VALUES ('2024-01-01 08:00:00', 19.8);
INSERT INTO sensor_2_rust   VALUES ('2024-01-01 08:00:00', 19.8);
```

## 查询标签数据


## 查询某设备的所有标签

```sql
SELECT DISTINCT tag FROM sensor_tags WHERE device_id = 1;
```

## 按标签聚合

```sql
SELECT tag, COUNT(*) AS device_count, AVG(value) AS avg_value
FROM   sensor_tags
WHERE  ts >= '2024-01-01 00:00:00'
GROUP  BY tag
ORDER  BY device_count DESC;
```

## 使用 UDF 实现字符串拆分（TDengine 3.x）


TDengine 3.x 支持自定义 UDF（C/Python）
可以创建 split_str UDF 来拆分字符串
C UDF 示例（需编译为 .so 文件）:
CREATE FUNCTION split_str AS '/path/to/libsplit_str.so' OUTPUTTYPE NCHAR(50);
SELECT split_str('python,java,sql', ',', 0);  -- 返回 'python'
SELECT split_str('python,java,sql', ',', 1);  -- 返回 'java'
Python UDF 示例:
CREATE FUNCTION py_split AS '/path/to/split.py' OUTPUTTYPE NCHAR(50);

## 使用 TaosShell 脚本拆分


在应用层使用 TDengine 客户端连接器处理拆分:
Python 示例:
import taos
conn = taos.connect()
cursor = conn.cursor()
cursor.execute("SELECT id, tags FROM devices")
for row in cursor:
for tag in row[1].split(','):
cursor.execute(f"INSERT INTO ... TAGS ({row[0]}, '{tag.strip()}')")
这种方式利用 TDengine 的高性能写入能力
在数据摄入管道中完成拆分

## 多标签列方案（替代拆分）


## 如果标签数量固定且已知，可使用多列存储

```sql
CREATE STABLE IF NOT EXISTS sensor_multi_tags (
    ts    TIMESTAMP,
    value DOUBLE
) TAGS (
    device_id INT,
    tag1 NCHAR(50),
    tag2 NCHAR(50),
    tag3 NCHAR(50),
    tag4 NCHAR(50)
);

CREATE TABLE IF NOT EXISTS sensor_m1 USING sensor_multi_tags
    TAGS (1, 'python', 'java', 'sql', NULL);
```

## 查询所有标签（UNION ALL 合并多列）

```sql
SELECT device_id, tag1 AS tag FROM sensor_multi_tags WHERE tag1 IS NOT NULL
UNION ALL
SELECT device_id, tag2 AS tag FROM sensor_multi_tags WHERE tag2 IS NOT NULL
UNION ALL
SELECT device_id, tag3 AS tag FROM sensor_multi_tags WHERE tag3 IS NOT NULL
UNION ALL
SELECT device_id, tag4 AS tag FROM sensor_multi_tags WHERE tag4 IS NOT NULL;
```

## 横向对比与对引擎开发者的启示


## TDengine 字符串拆分策略:

- **最佳方案**: 数据写入时预拆分为多行
- **备选方案 A**: UDF 自定义拆分函数
- **备选方案 B**: 应用层拆分 + 批量写入
- **备选方案 C**: 多标签列 + UNION ALL
2. 与其他数据库对比:
- **PostgreSQL**: STRING_TO_ARRAY + UNNEST（一行搞定）
- **ClickHouse**: splitByChar + arrayJoin
- **BigQuery**: SPLIT + UNNEST（最简洁）
- **TDengine**: 无内置支持，需 ETL 拆分
对引擎开发者:
时序数据库的设计目标是高性能时间序列操作
字符串拆分是 OLTP/分析型操作，不是时序数据库的核心场景
提供 UDF 机制让用户扩展比内置所有功能更合理
数据摄入管道中的预处理是时序场景的最佳实践
