# StarRocks: 错误处理

> 参考资料:
> - [1] StarRocks Documentation
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


## 1. 错误处理: 与 Doris 同源的设计

 StarRocks 同样不支持过程式错误处理(无 TRY/CATCH)。
 错误处理依赖: 应用层 MySQL 驱动 + SQL 防御性写法 + 导入容错。

## 2. 错误码 (MySQL 兼容)

 MySQL 兼容错误码(与 Doris 相同):
   1045 = 访问被拒绝     1049 = 数据库不存在
   1050 = 表已存在        1064 = 语法错误
   1105 = 内部错误

## 3. 应用层错误捕获

 Python (pymysql): 与 Doris 完全相同
 try:
     cursor.execute("INSERT INTO users VALUES(1, 'test')")
 except pymysql.Error as e:
     print(f'Error [{e.args[0]}]: {e.args[1]}')

## 4. SQL 防御性写法

```sql
CREATE TABLE IF NOT EXISTS users (
    id INT, name VARCHAR(100)
) DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES ("replication_num" = "1");

DROP TABLE IF EXISTS temp_data;

```

## 5. 导入错误处理

Stream Load 容错(与 Doris 相同):
curl -H "max_filter_ratio:0.1" -T data.csv \
http://fe:8040/api/db/table/_stream_load

Pipe 持续加载(3.2+，StarRocks 独有):
CREATE PIPE my_pipe AS INSERT INTO target
SELECT * FROM FILES('path'='s3://bucket/data/', 'format'='parquet');
Pipe 自动处理新文件，失败自动重试。


```sql
SHOW LOAD WHERE LABEL = 'my_label';

```

## 6. 诊断查询

```sql
SHOW PROCESSLIST;
SHOW BACKENDS;
SHOW TABLET FROM users;
SHOW CREATE TABLE users;

SET exec_mem_limit = 8589934592;
SET query_timeout = 600;

```

 StarRocks 特有诊断:
 SHOW RUNNING QUERIES;
 EXPLAIN ANALYZE SELECT ...;  -- 实际执行并收集统计

## 7. StarRocks vs Doris 错误处理差异

 核心相同: 都是 MySQL 协议兼容，错误码一致。
 StarRocks 独有: Pipe 持续加载(3.2+)提供自动重试机制。
 Doris 独有: ADMIN REPAIR TABLE(手动修复副本)。

 对引擎开发者的启示:
   OLAP 引擎的错误处理重点不是 SQL 层面，而是:
1. 导入容错(max_filter_ratio): 允许部分数据错误

2. 副本修复(自动/手动): 保证数据一致性

3. 查询超时控制: 避免 unbounded query 耗尽资源

