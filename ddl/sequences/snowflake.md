# Snowflake: 序列与自增 (Sequences & Identity)

> 参考资料:
> - [1] Snowflake SQL Reference - CREATE SEQUENCE
>   https://docs.snowflake.com/en/sql-reference/sql/create-sequence
> - [2] Snowflake SQL Reference - AUTOINCREMENT / IDENTITY
>   https://docs.snowflake.com/en/sql-reference/sql/create-table


## 1. 基本语法: AUTOINCREMENT / IDENTITY


方式 1: AUTOINCREMENT（Snowflake 推荐写法）

```sql
CREATE TABLE users (
    id   NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    name VARCHAR(100)
);

```

方式 2: IDENTITY（SQL 标准兼容写法）

```sql
CREATE TABLE orders (
    id   NUMBER IDENTITY(1, 1),   -- IDENTITY(start, increment)
    name VARCHAR(100)
);
```

 两种语法完全等价，生成相同的内部实现

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 分布式自增的实现挑战

 Snowflake 的自增列值 不保证连续、不保证单调递增。
 只保证唯一性（在同一表内不重复）。

 实现推测:
   多 Virtual Warehouse 并发写入时，每个 Warehouse 预分配一段 ID（段分配）
   Warehouse A 分配 [1-1000], Warehouse B 分配 [1001-2000]
   A 实际只用了 1-5，B 实际用了 1001-1003
   最终序列: 1,2,3,4,5,1001,1002,1003（不连续但唯一）

 对比各引擎的自增策略:
   MySQL:      AUTO_INCREMENT，单机连续，8.0+ 持久化
   PostgreSQL: SERIAL/IDENTITY 基于 SEQUENCE，事务回滚消耗序列值
   Oracle:     SEQUENCE 对象，CACHE 参数控制预分配段大小
   BigQuery:   无自增（设计哲学: 分布式系统不应依赖全局序列）
   Redshift:   IDENTITY(seed, step)，不保证连续
   TiDB:       AUTO_INCREMENT 段分配 + AUTO_RANDOM（分布式推荐）
   Databricks: GENERATED ALWAYS AS IDENTITY（Delta Lake 3.0+）

 对引擎开发者的启示:
   分布式自增的核心矛盾: 全局唯一性 vs 高吞吐
   方案 A: 中心化序列服务（保证连续但成为瓶颈）
   方案 B: 段预分配（高吞吐但有间隙），Snowflake/TiDB 的选择
   方案 C: 不支持自增，推荐 UUID（BigQuery/Spanner 的选择）

### 2.2 IDENTITY vs SEQUENCE: 两种 ID 生成范式

 IDENTITY: 绑定到列，声明在 CREATE TABLE 中，生命周期与表一致
 SEQUENCE: 独立数据库对象，可跨表共享，需要显式引用

## 3. SEQUENCE 对象


```sql
CREATE SEQUENCE user_seq START 1 INCREMENT 1;
CREATE SEQUENCE order_seq START 1000 INCREMENT 10;

```

使用:

```sql
INSERT INTO users (id, name) VALUES (user_seq.NEXTVAL, 'Alice');
SELECT user_seq.NEXTVAL;     -- 获取下一个值

```

跨表共享序列:

```sql
INSERT INTO orders (id, name) VALUES (order_seq.NEXTVAL, 'Order-A');
INSERT INTO invoices (id, name) VALUES (order_seq.NEXTVAL, 'Invoice-A');

```

## 4. SEQUENCE 行为细节


ORDER / NOORDER

```sql
CREATE SEQUENCE strict_seq START 1 INCREMENT 1 ORDER;
```

ORDER: 保证值严格递增（可能影响并发性能）
NOORDER (默认): 只保证唯一，不保证顺序

对比: Oracle SEQUENCE 也有 ORDER/NOORDER（RAC 多实例场景）

CYCLE / NOCYCLE

```sql
CREATE SEQUENCE cyclic_seq START 1 INCREMENT 1 CYCLE;
```

CYCLE: 达到最大值后重新开始 | NOCYCLE (默认): 达到最大值报错

管理

```sql
SHOW SEQUENCES IN SCHEMA PUBLIC;
DESCRIBE SEQUENCE user_seq;
ALTER SEQUENCE user_seq SET INCREMENT 5;
DROP SEQUENCE IF EXISTS user_seq;

```

## 5. 自增列的限制

 (a) 不保证连续: INSERT 失败、事务回滚导致间隙
 (b) 不保证单调递增: 多 Warehouse 并发的段分配
 (c) COPY INTO 批量加载: 同一文件内连续，文件间可能不连续
 (d) INSERT OVERWRITE 后自增不重置

## 6. UUID 替代方案


```sql
CREATE TABLE events (
    id   VARCHAR(36) DEFAULT UUID_STRING(),
    data VARIANT
);
```

 UUID_STRING() 生成 v4 UUID，无需全局协调
优点: 天然适合分布式 | 缺点: 36 字节、聚簇效果差

 对比:
   PostgreSQL: gen_random_uuid()（14+）
   BigQuery:   GENERATE_UUID()（推荐方案）
   Spanner:    UUID 是推荐的主键策略

## 7. 选择指南

场景                     | 推荐方案
单表代理键               | AUTOINCREMENT / IDENTITY
跨表统一 ID 空间         | SEQUENCE 对象
分布式高并发写入         | UUID_STRING()
事实表（分析场景）       | 不需要自增（业务键 + 时间戳即可）

横向对比:
Snowflake: AUTOINCREMENT + SEQUENCE + UUID 三种方案
BigQuery:  只有 GENERATE_UUID()（明确拒绝自增）
Redshift:  IDENTITY + UUID（无 SEQUENCE 对象）
Databricks: GENERATED ALWAYS AS IDENTITY + UUID
MaxCompute: 无自增，无 SEQUENCE

