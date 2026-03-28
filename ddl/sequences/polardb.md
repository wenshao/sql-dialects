# PolarDB: Sequences & Auto-Increment

> 参考资料:
> - [PolarDB for MySQL Documentation - AUTO_INCREMENT](https://www.alibabacloud.com/help/en/polardb/polardb-for-mysql/auto-increment)
> - [PolarDB for PostgreSQL Documentation - CREATE SEQUENCE](https://www.alibabacloud.com/help/en/polardb/polardb-for-postgresql/create-sequence)
> - [PolarDB Documentation - Distributed ID](https://www.alibabacloud.com/help/en/polardb/polardb-for-mysql/sequence)


## AUTO_INCREMENT（MySQL 兼容模式）

```sql
CREATE TABLE users (
    id       BIGINT NOT NULL AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB;

SELECT LAST_INSERT_ID();
```

PolarDB-X（分布式版）的全局自增序列
CREATE SEQUENCE auto_seq START WITH 1 INCREMENT BY 1;
分布式环境下保证全局唯一

## SEQUENCE（PolarDB for PostgreSQL 模式）

CREATE SEQUENCE user_id_seq START WITH 1 INCREMENT BY 1 CACHE 20;
SELECT nextval('user_id_seq');
SELECT currval('user_id_seq');
SERIAL / BIGSERIAL（PostgreSQL 模式）
CREATE TABLE users (
id       BIGSERIAL PRIMARY KEY,
username VARCHAR(64) NOT NULL
);

## PolarDB-X 分布式序列

GROUP SEQUENCE（默认，分段缓存，性能最佳）
CREATE SEQUENCE group_seq START WITH 1;
SIMPLE SEQUENCE（单点生成，全局有序）
CREATE SIMPLE SEQUENCE simple_seq START WITH 1;
TIME-BASED SEQUENCE（基于时间戳的分布式 ID）
CREATE TIME SEQUENCE time_seq;

## UUID 生成

## MySQL 模式

```sql
SELECT UUID();
```

## PostgreSQL 模式

SELECT uuid_generate_v4();

## 序列 vs 自增 权衡

## AUTO_INCREMENT（MySQL 模式）：简单，单节点

## GROUP SEQUENCE（PolarDB-X）：分布式最佳性能

## SIMPLE SEQUENCE：全局有序但有性能瓶颈

## TIME SEQUENCE：类 Snowflake ID，分布式有序

## UUID：全局唯一，无中心化依赖

## PolarDB 根据模式（MySQL/PG）支持对应的语法
