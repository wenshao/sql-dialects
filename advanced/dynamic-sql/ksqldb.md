# ksqlDB: 动态 SQL (Dynamic SQL)

> 参考资料:
> - [ksqlDB Documentation - ksqlDB Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - [ksqlDB Documentation - REST API](https://docs.ksqldb.io/en/latest/developer-guide/api/)
> - [ksqlDB Documentation - Java Client](https://docs.ksqldb.io/en/latest/developer-guide/java-client/)
> - [ksqlDB Documentation - Security](https://docs.ksqldb.io/en/latest/operate-and-deploy/security/)
> - ============================================================
> - 1. ksqlDB 的动态 SQL 模型
> - ============================================================
> - ksqlDB 是基于 Kafka 的流处理 SQL 引擎，不支持服务端动态 SQL:
> - 无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
> - 无存储过程 / 用户自定义函数（UDF 除外）
> - 无会话级变量或控制流
> - ksqlDB 的 SQL 语义:
> - 流（STREAM）和表（TABLE）是核心抽象。
> - 查询分为"推送查询"（push query, EMIT CHANGES）和"拉取查询"（pull query）。
> - 所有 SQL 语句通过 REST API 或客户端发送执行。
> - ============================================================
> - 2. REST API: 动态查询构建
> - ============================================================
> - 通过 HTTP REST API 提交动态构造的 SQL 语句
> - 这是 ksqlDB 中"动态 SQL"的主要实现方式
> - 拉取查询（Pull Query）: 返回当前快照结果
> - curl -X POST http://localhost:8088/query \
> - H "Content-Type: application/vnd.ksql.v1+json" \
> - d '{"ksql": "SELECT * FROM users_table WHERE age > 25;"}'
> - 推送查询（Push Query）: 持续返回流式变更
> - curl -X POST http://localhost:8088/query \
> - H "Content-Type: application/vnd.ksql.v1+json" \
> - d '{"ksql": "SELECT * FROM users_stream WHERE age > 25 EMIT CHANGES;"}'
> - 动态创建流
> - curl -X POST http://localhost:8088/ksql \
> - H "Content-Type: application/vnd.ksql.v1+json" \
> - d '{
> - "ksql": "CREATE STREAM user_events (user_id VARCHAR KEY, event_type VARCHAR, payload VARCHAR) WITH (KAFKA_TOPIC='\''user_events'\'', VALUE_FORMAT='\''JSON'\'');"
> - }'
> - 动态创建物化视图
> - curl -X POST http://localhost:8088/ksql \
> - H "Content-Type: application/vnd.ksql.v1+json" \
> - d '{
> - "ksql": "CREATE TABLE active_users AS SELECT user_id, COUNT(*) AS event_count FROM user_events WINDOW TUMBLING (SIZE 5 MINUTES) GROUP BY user_id HAVING COUNT(*) > 5 EMIT CHANGES;"
> - }'
> - ============================================================
> - 3. Java Client: 类型安全的动态查询
> - ============================================================
> - import io.confluent.ksql.api.client.Client;
> - import io.confluent.ksql.api.client.ClientOptions;
> - ClientOptions options = ClientOptions.create()
> - .setHost("localhost").setPort(8088);
> - Client client = Client.create(options);
> - // 拉取查询: 同步返回结果
> - String pullQuery = "SELECT * FROM users_table WHERE user_id = '" + userId + "';";
> - client.executeQuery(pullQuery).thenAccept(rows -> {
> - // 处理查询结果
> - });
> - // 推送查询: 持续接收变更流
> - String pushQuery = "SELECT * FROM user_events EMIT CHANGES;";
> - client.streamQuery(pushQuery).thenAccept(streamedQueryResult -> {
> - streamedQueryResult.subscribe(row -> {
> - // 处理每一行变更
> - });
> - });
> - 注意: Java Client 中查询语句仍是字符串拼接。
> - ksqlDB 不支持参数化查询（无 PreparedStatement 概念），
> - 需在应用层确保输入安全。
> - ============================================================
> - 4. Python 替代方案: HTTP 请求
> - ============================================================
> - import requests
> - import json
> - KSQL_URL = "http://localhost:8088"
> - headers = {"Content-Type": "application/vnd.ksql.v1+json"}
> - # 动态拉取查询
> - def pull_query(table, conditions):
> - where_clause = " AND ".join(f"{k} = '{v}'" for k, v in conditions.items())
> - sql = f"SELECT * FROM {table} WHERE {where_clause};"
> - resp = requests.post(f"{KSQL_URL}/query", headers=headers,
> - json={"ksql": sql})
> - return resp.json()
> - # 安全性: 需要手动验证 table 和 conditions 中的键名（白名单）
> - VALID_TABLES = {"users_table", "orders_table", "products_table"}
> - def safe_pull_query(table, conditions):
> - if table not in VALID_TABLES:
> - raise ValueError(f"Invalid table: {table}")
> - return pull_query(table, conditions)
> - ============================================================
> - 5. SQL 注入防护
> - ============================================================
> - ksqlDB 没有 PREPARE/EXECUTE 机制，所有动态 SQL 都是字符串拼接。
> - 注入防护完全依赖应用层实现:
> - 策略 1: 白名单验证（推荐）
> - 表名、列名使用固定白名单，不接受用户输入。
> - 有效表名 = {'users_stream', 'orders_stream', 'events_stream'}
> - 策略 2: 输入转义
> - 对字符串值进行单引号转义: value.replace("'", "''")
> - 对数字值进行类型验证: int(value) 或 float(value)
> - 策略 3: 最小权限
> - ksqlDB 服务端配置 ACL，限制写入操作的权限。
> - 使用只读用户执行查询操作。
> - 错误（危险）: 直接拼接用户输入
> - sql = f"SELECT * FROM {user_table} WHERE name = '{user_input}' EMIT CHANGES;"
> - 正确: 验证 + 参数构建
> - if user_table not in ALLOWED_TABLES:
> - raise ValueError("Invalid table")
> - escaped_input = user_input.replace("'", "''")
> - sql = f"SELECT * FROM {user_table} WHERE name = '{escaped_input}' EMIT CHANGES;"
> - ============================================================
> - 6. ksqlDB 特有: 流处理中的"动态"模式
> - ============================================================
> - ksqlDB 的动态性体现在流/表的动态创建与管理:
> - (1) 动态创建流/表（根据 Kafka Topic）
> - CREATE STREAM IF NOT EXISTS new_stream WITH (
> - KAFKA_TOPIC = 'new_topic',
> - VALUE_FORMAT = 'AVRO'
> - );
> - (2) 动态 INSERT INTO（向 Kafka 写入数据）
> - INSERT INTO target_stream (id, name, value)
> - SELECT user_id, action, amount FROM source_stream
> - WHERE action = 'purchase';
> - (3) 动态 CREATE TABLE AS（持续物化聚合）
> - CREATE TABLE running_totals AS
> - SELECT product_id, SUM(quantity) AS total
> - FROM orders_stream
> - GROUP BY product_id
> - EMIT CHANGES;
> - ============================================================
> - 7. 横向对比: 流处理 SQL 引擎
> - ============================================================
> - 1. 服务端动态 SQL 支持:
> - ksqlDB:        无（REST API 代替）
> - Flink SQL:     无（Table API / SQL Client 代替）
> - Materialize:   PREPARE/EXECUTE（PG 兼容）
> - RisingWave:    PREPARE/EXECUTE（PG 兼容）
> - 2. 客户端 API:
> - ksqlDB:        REST API + Java Client
> - Flink SQL:     Table API (Java/Python/SQL Client)
> - Materialize:   psycopg2/pgjdbc（PG 驱动）
> - RisingWave:    psycopg2/pgjdbc（PG 驱动）
> - 3. 流式语义:
> - ksqlDB:        EMIT CHANGES（推送查询）
> - Flink SQL:     动态表 + 时间窗口
> - Materialize:   SUBSCRIBE（增量输出）
> - RisingWave:    基于_mv_ 增量物化视图
> - ============================================================
> - 8. 对引擎开发者的启示
> - ============================================================
> - (1) 流处理引擎的"动态 SQL"与传统数据库完全不同:
> - 传统数据库: 运行时构造 SQL 字符串，在服务端解析执行。
> - 流处理引擎: 动态创建/管理流和表，查询持续运行。
> - ksqlDB 的 REST API 本质上是"远程 SQL 提交"，不是服务端动态 SQL。
> - (2) 缺少参数化查询是一个安全隐患:
> - 所有动态 SQL 都是字符串拼接。
> - 必须在应用层实现白名单验证和输入转义。
> - 未来可考虑支持参数化查询语法。
> - (3) REST API 作为 SQL 接口的设计:
> - 优点: 简单直观，任何语言可通过 HTTP 调用。
> - 缺点: 无连接池、无预处理、安全性依赖 HTTPS + 认证。
> - 适合: 运维管理、数据管道、低频查询。
> - ============================================================
> - 9. 版本与限制
> - ============================================================
> - ksqlDB 0.x (Confluent Community):  REST API + Java Client
> - ksqlDB 7.x (Confluent Platform):   增强的安全特性
> - 限制:                无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
> - 限制:                无存储过程
> - 限制:                无参数化查询语法
> - 限制:                SQL 注入防护完全依赖应用层
> - 限制:                面向 Kafka 流处理，不适用传统 OLTP/OLAP 场景
