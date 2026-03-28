# Apache Impala: Error Handling

> 参考资料:
> - [Apache Impala SQL Reference](https://impala.apache.org/docs/build/html/topics/impala_langref.html)


## Impala 不支持服务端错误处理

Impala 不支持存储过程或异常处理

## 应用层替代方案 (Python/impyla)

from impala.dbapi import connect
from impala.error import HiveServer2Error, OperationalError

conn = connect(host='localhost', port=21050)
cursor = conn.cursor()

try:
cursor.execute('SELECT * FROM nonexistent_table')
results = cursor.fetchall()
except HiveServer2Error as e:
print(f'Impala error: {e}')
except OperationalError as e:
print(f'Operational error: {e}')
finally:
cursor.close()
conn.close()

## 应用层替代方案 (Java/JDBC)

try {
Statement stmt = conn.createStatement();
ResultSet rs = stmt.executeQuery("SELECT * FROM users");
} catch (SQLException e) {
System.err.println("SQLState: " + e.getSQLState());
System.err.println("Message: " + e.getMessage());
}

## SQL 层面的错误避免

IF NOT EXISTS / IF EXISTS 防止常见 DDL 错误
```sql
CREATE TABLE IF NOT EXISTS users (id INT, name STRING);
DROP TABLE IF EXISTS temp_table;
CREATE DATABASE IF NOT EXISTS analytics;
DROP DATABASE IF EXISTS temp_db;
```


## Impala 查询选项控制错误行为

设置查询超时（毫秒）
SET QUERY_TIMEOUT_S=300;

内存限制（避免 OOM）
SET MEM_LIMIT=4g;

失败后的重试策略
SET MAX_RETRIES=3;

## 常见错误场景

1. 表不存在: AnalysisException: Could not resolve table reference
2. 列不存在: AnalysisException: Could not resolve column/field reference
3. 内存不足: Memory limit exceeded
4. 权限不足: AuthorizationException
5. 元数据过期: TableLoadingException（需要 INVALIDATE METADATA）

刷新元数据（解决元数据过期问题）
INVALIDATE METADATA users;
REFRESH users;

> **注意**: Impala 面向交互式 OLAP，不支持服务端错误处理
> **注意**: 兼容 HiveServer2 协议
> **注意**: 使用 INVALIDATE METADATA / REFRESH 解决元数据同步问题
> **限制**: 无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER
> **限制**: 无存储过程或 PL/SQL 块
