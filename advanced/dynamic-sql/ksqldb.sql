-- ksqlDB: Dynamic SQL
--
-- 参考资料:
--   [1] ksqlDB Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/

-- ============================================================
-- ksqlDB 不支持动态 SQL
-- ============================================================
-- ksqlDB 是流处理 SQL 引擎（基于 Kafka），不支持动态 SQL 或存储过程

-- ============================================================
-- REST API 替代方案
-- ============================================================
-- # 通过 REST API 执行动态查询
-- curl -X POST http://localhost:8088/ksql \
--   -H "Content-Type: application/vnd.ksql.v1+json" \
--   -d '{"ksql": "SELECT * FROM users_stream EMIT CHANGES LIMIT 10;"}'
--
-- # 动态创建流
-- curl -X POST http://localhost:8088/ksql \
--   -H "Content-Type: application/vnd.ksql.v1+json" \
--   -d '{"ksql": "CREATE STREAM my_stream (id VARCHAR KEY, data VARCHAR) WITH (KAFKA_TOPIC='\''my_topic'\'', VALUE_FORMAT='\''JSON'\'');"}'

-- ============================================================
-- Java Client 替代方案
-- ============================================================
-- Client client = Client.create(options);
-- // 动态查询
-- String sql = "SELECT * FROM users_stream WHERE age > " + minAge + " EMIT CHANGES;";
-- client.streamQuery(sql).thenAccept(streamedQueryResult -> { ... });

-- 注意：ksqlDB 面向 Kafka 流处理
-- 注意：通过 REST API 或 Java Client 实现动态查询
-- 限制：无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
-- 限制：无存储过程
-- 限制：不支持参数化查询语法
