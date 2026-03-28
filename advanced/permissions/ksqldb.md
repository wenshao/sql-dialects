# ksqlDB: 权限管理

ksqlDB 的权限管理依赖 Kafka 的 ACL 和 RBAC
============================================================
Kafka ACL（开源版）
============================================================
通过 Kafka 的 kafka-acls 工具管理
kafka-acls --add --allow-principal User:alice \
operation READ --topic pageviews_topic
kafka-acls --add --allow-principal User:alice \
operation WRITE --topic output_topic
kafka-acls --add --allow-principal User:alice \
operation ALL --consumer-group ksql-group
============================================================
Confluent RBAC（企业版）
============================================================
预定义角色：
ResourceOwner: 完全控制
DeveloperRead: 只读
DeveloperWrite: 读写
DeveloperManage: 管理
通过 Confluent CLI 授权
confluent iam rbac role-binding create \
principal User:alice --role DeveloperRead \
resource Topic:pageviews_topic \
kafka-cluster-id <cluster-id>
============================================================
ksqlDB 安全配置
============================================================
认证（在 ksqlDB server 配置文件中）
ksql.authentication.plugin.class=...
authentication.method=BASIC
authentication.roles=admin,developer
配置 SSL/TLS
ssl.truststore.location=/path/to/truststore
ssl.keystore.location=/path/to/keystore
============================================================
ksqlDB 内置命令
============================================================
查看当前用户信息
通过 REST API 或 CLI 认证
列出可访问的对象

```sql
SHOW STREAMS;
SHOW TABLES;
SHOW TOPICS;
SHOW QUERIES;
```

注意：ksqlDB 依赖 Kafka 的权限系统
注意：开源版使用 Kafka ACL
注意：企业版使用 Confluent RBAC
注意：ksqlDB 本身不管理用户和权限
