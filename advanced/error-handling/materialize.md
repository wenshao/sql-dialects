# Materialize: Error Handling

> 参考资料:
> - [Materialize Documentation](https://materialize.com/docs/sql/)


## Materialize 不支持服务端错误处理

## Materialize 没有存储过程或异常处理语法

错误处理必须在应用层完成

## 应用层替代方案 (Python/psycopg2)

import psycopg2
from psycopg2 import errors
try:
cursor.execute('CREATE SOURCE ...')
except psycopg2.errors.DuplicateTable:
print('Object already exists')
except psycopg2.errors.UndefinedTable:
print('Object does not exist')
except psycopg2.Error as e:
print(f'Materialize error: {e.pgcode} - {e.pgerror}')

## SQL 层面的错误避免

## IF NOT EXISTS 防止重复创建

```sql
CREATE TABLE IF NOT EXISTS users (id INT, name TEXT);
```

## DROP IF EXISTS 防止删除不存在对象

```sql
DROP TABLE IF EXISTS temp_data;
```

## CREATE OR REPLACE 覆盖已有视图

```sql
CREATE OR REPLACE MATERIALIZED VIEW user_summary AS
SELECT COUNT(*) AS total_users FROM users;
```

## Materialize 特有的错误源和排查

查看 Source 的错误状态
SELECT * FROM mz_internal.mz_source_statuses;
查看物化视图的错误状态
SELECT * FROM mz_internal.mz_materialization_statuses;
查看 Sink 的错误状态
SELECT * FROM mz_internal.mz_sink_statuses;
查看系统日志中的错误
SELECT * FROM mz_internal.mz_recent_activity_log
WHERE severity = 'error';

## 常见错误场景

## Source 连接失败（Kafka broker 不可达）

## Schema Registry 解析失败

## 物化视图依赖的 Source 被删除

## 资源不足导致物化失败


注意：Materialize 兼容 PostgreSQL 协议和错误码（SQLSTATE）
注意：使用 mz_internal schema 查看系统状态和错误
限制：无存储过程或异常处理语法
限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER
