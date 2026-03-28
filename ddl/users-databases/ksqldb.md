# ksqlDB: 数据库、模式与用户管理

> 参考资料:
> - [ksqlDB Documentation](https://docs.ksqldb.io/en/latest/)
> - [Confluent Platform Security](https://docs.confluent.io/platform/current/security/index.html)


ksqlDB 特性：
基于 Kafka 的流处理引擎
没有传统意义上的数据库/模式
所有数据存储在 Kafka topic 中
没有 CREATE DATABASE / CREATE SCHEMA
没有 SQL 层面的用户管理


## 数据库与模式


ksqlDB 没有数据库和模式的概念
所有 STREAM 和 TABLE 都在同一个命名空间下
通过 ksqlDB 集群隔离实现逻辑分离

## 用户与权限


ksqlDB 本身不管理用户
安全性通过以下方式实现：
1. Kafka ACL（底层权限控制）
$ kafka-acls --authorizer-properties zookeeper.connect=zk:2181 \
add --allow-principal User:alice \
operation Read --topic my_topic
2. Confluent RBAC（企业版）
通过 Confluent Control Center 管理角色
3. HTTP Basic Auth（ksqlDB Server）
配置: ksql.authentication.plugin.class
4. TLS/SSL 加密

## 配置管理（通过 SET 命令）


```sql
SET 'auto.offset.reset' = 'earliest';
SET 'ksql.streams.num.stream.threads' = '4';
SET 'ksql.output.topic.name.prefix' = 'myapp_';
```

## 查看配置

```sql
SHOW PROPERTIES;
```

## 查询元数据


```sql
SHOW STREAMS;
SHOW TABLES;
SHOW TOPICS;
SHOW QUERIES;
SHOW CONNECTORS;

LIST STREAMS;
LIST TABLES;
LIST TOPICS;

DESCRIBE my_stream;
DESCRIBE EXTENDED my_stream;
```

注意：ksqlDB 的概念与传统数据库完全不同
没有数据库、模式、用户
一个 ksqlDB 集群 = 一个命名空间
权限通过 Kafka ACL 或 Confluent RBAC 管理
