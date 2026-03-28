# StarRocks: 序列与自增

> 参考资料:
> - [1] StarRocks Documentation - AUTO_INCREMENT
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


## 1. AUTO_INCREMENT (3.0+)

StarRocks 3.0+ 支持 AUTO_INCREMENT，实现方案与 Doris 类似(段分配)。

对比 Doris:
StarRocks 3.0+: AUTO_INCREMENT，段分配方案
Doris 2.1+:     AUTO_INCREMENT，段分配方案
两者实现独立(分叉后各自开发)，但方案一致。


```sql
CREATE TABLE users (
    id       BIGINT       NOT NULL AUTO_INCREMENT,
    username VARCHAR(64)  NOT NULL,
    email    VARCHAR(255) NOT NULL
) PRIMARY KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES ("replication_num" = "3");

INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');

```

 特点:
1. 唯一但不连续(跨 BE 有间隙)

2. 段分配: 每个 BE 预分配一批 ID

3. 仅 Primary Key / Unique Key 模型支持


 对比:
   MySQL:     AUTO_INCREMENT，单机连续
   ClickHouse: 无自增
   BigQuery:  无自增(推荐 GENERATE_UUID)
   TiDB:     AUTO_RANDOM(推荐，避免写入热点)

## 2. UUID 生成

```sql
SELECT uuid();
```

结果: '7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b'


```sql
SELECT uuid_numeric();
```

 返回 LARGEINT 类型

## 3. StarRocks vs Doris 自增差异

 AUTO_INCREMENT 版本:
   StarRocks: 3.0+
   Doris:     2.1+

 SEQUENCE 列(版本控制):
   StarRocks: 不支持 function_column.sequence_col
   Doris:     支持(确定相同 Key 的哪条记录最新)
   StarRocks Primary Key 按写入顺序覆盖(后写入的为准)

 适用模型:
   StarRocks: Primary Key / Unique Key 模型
   Doris:     Unique Key(MoW) 模型

 对引擎开发者的启示:
   段分配方案的关键参数:
     段大小: 太大 → ID 间隙大，太小 → BE 频繁向 FE 请求新段
     默认 100000 是合理的折中(适合批量写入场景)。
   SEQUENCE 列(Doris 独有)解决了多源写入的"哪条更新"问题——
   StarRocks 没有等价功能，用户需要保证写入顺序。

## 4. 自增策略选择

AUTO_INCREMENT(3.0+):  简单，分布式唯一，适合主键
uuid():               全局唯一，128 位
Snowflake ID:          应用层生成，时间有序，可拆解

限制:
不支持 CREATE SEQUENCE
不支持 IDENTITY / SERIAL
不支持 Doris 的 SEQUENCE 列(版本控制机制)

