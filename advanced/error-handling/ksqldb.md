# ksqlDB: Error Handling

> 参考资料:
> - [ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)


## ksqlDB 不支持服务端错误处理

## ksqlDB 是流处理 SQL 引擎，不支持存储过程或异常处理

## REST API 错误响应示例

成功响应:
{"@type":"currentStatus","statementText":"CREATE STREAM ...","commandStatus":{"status":"SUCCESS"}}
错误响应:
{"@type":"currentStatus","statementText":"...","commandStatus":{"status":"ERROR","message":"..."}}
语法错误:
{"@type":"statement_error","error_code":40001,"message":"line 1:8: mismatched input..."}

## Java Client 错误处理

import io.confluent.ksql.api.client.Client;
import io.confluent.ksql.api.client.ClientOptions;
ClientOptions options = ClientOptions.create()
.setHost("localhost").setPort(8088);
Client client = Client.create(options);
client.executeStatement("CREATE STREAM ...")
.thenAccept(result -> {
System.out.println("Success");
})
.exceptionally(e -> {
System.err.println("ksqlDB error: " + e.getMessage());
return null;
});

## SQL 层面的错误避免

CREATE STREAM IF NOT EXISTS 避免重复创建
CREATE STREAM IF NOT EXISTS my_stream (
id VARCHAR KEY,
name VARCHAR
) WITH (KAFKA_TOPIC='my_topic', VALUE_FORMAT='JSON');
CREATE TABLE IF NOT EXISTS 避免重复创建
CREATE TABLE IF NOT EXISTS my_table (
id VARCHAR PRIMARY KEY,
count BIGINT
) WITH (KAFKA_TOPIC='my_topic', VALUE_FORMAT='JSON');
DROP STREAM IF EXISTS / DROP TABLE IF EXISTS 避免删除不存在的对象
DROP STREAM IF EXISTS my_stream;
DROP TABLE IF EXISTS my_table;

## 常见错误码

40001: 语句解析错误（语法错误）
40002: 执行错误（表/流不存在等）
50000: 服务器内部错误
注意：ksqlDB 错误通过 REST API 或 Client SDK 返回
注意：使用 IF NOT EXISTS / IF EXISTS 避免常见 DDL 错误
限制：无 SQL 级别的错误处理语法（无 TRY/CATCH）
限制：无存储过程或异常处理
限制：错误处理必须在应用层实现
