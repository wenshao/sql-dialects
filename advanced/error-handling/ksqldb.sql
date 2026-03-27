-- ksqlDB: Error Handling
--
-- 参考资料:
--   [1] ksqlDB Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/

-- ============================================================
-- ksqlDB 不支持服务端错误处理
-- ============================================================
-- ksqlDB 是流处理 SQL 引擎，不支持存储过程或异常处理

-- REST API 返回错误信息:
-- {"@type":"currentStatus","statementText":"...","commandStatus":{"status":"ERROR","message":"..."}}

-- Java Client 错误处理:
-- client.executeStatement("CREATE STREAM ...").thenAccept(result -> {
--     if (result.isError()) { ... }
-- }).exceptionally(e -> { ... });

-- 注意：ksqlDB 错误通过 REST API 或 Client 返回
-- 限制：无 SQL 级别的错误处理语法
