# MySQL: UPSERT

> 参考资料:
> - [MySQL 8.0 Reference Manual - INSERT ... ON DUPLICATE KEY UPDATE](https://dev.mysql.com/doc/refman/8.0/en/insert-on-duplicate.html)
> - [MySQL 8.0 Reference Manual - REPLACE](https://dev.mysql.com/doc/refman/8.0/en/replace.html)
> - [MySQL 8.0 Reference Manual - INSERT ... ON DUPLICATE KEY UPDATE Locking](https://dev.mysql.com/doc/refman/8.0/en/innodb-locks-set.html)

## 基本语法: 三种 UPSERT 方式

方式一: ON DUPLICATE KEY UPDATE (4.1+, 推荐)
命中唯一索引或主键冲突时执行 UPDATE，否则 INSERT
```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON DUPLICATE KEY UPDATE
    email = VALUES(email),
    age = VALUES(age);
```

8.0.20+: VALUES() 在 UPDATE 子句中已废弃，用行/列别名替代
```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25) AS new
ON DUPLICATE KEY UPDATE
    email = new.email,
    age = new.age;
```

列别名语法（更细粒度）
```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25) AS new(u, e, a)
ON DUPLICATE KEY UPDATE
    email = new.e,
    age = new.a;
```

方式二: REPLACE INTO（有隐藏危险，见第 3 节）
```sql
REPLACE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);
```

方式三: INSERT IGNORE（冲突时静默跳过，不更新）
```sql
INSERT IGNORE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);
```

## ON DUPLICATE KEY UPDATE 的锁行为和死锁风险

### 加锁过程（比普通 INSERT 复杂得多）

INSERT ... ON DUPLICATE KEY UPDATE 的锁行为:
  (1) 首先尝试 INSERT: 对聚集索引的插入位置加 insert intention lock
  (2) 检查唯一索引: 如果发现冲突，升级为 Next-Key Lock（排他锁）
  (3) 执行 UPDATE: 持有该行的 X 锁直到事务提交

关键点: 即使最终执行的是 UPDATE，INSERT 阶段已经在索引间隙加了锁。
这意味着 ON DUPLICATE KEY UPDATE 比单独的 UPDATE 加的锁更多。

### 死锁场景（经典案例）

表: t(id PK, uk UNIQUE KEY)
事务 A: INSERT INTO t VALUES(1, 'x') ON DUPLICATE KEY UPDATE ...;
事务 B: INSERT INTO t VALUES(2, 'y') ON DUPLICATE KEY UPDATE ...;

死锁过程:
  (1) 事务 A 对 uk 索引加 Next-Key Lock，覆盖间隙包含 'y'
  (2) 事务 B 对 uk 索引加 Next-Key Lock，覆盖间隙包含 'x'
  (3) 事务 A 的 INSERT 需要对 'x' 位置加 insert intention lock → 被 B 的间隙锁阻塞
  (4) 事务 B 的 INSERT 需要对 'y' 位置加 insert intention lock → 被 A 的间隙锁阻塞
  (5) 死锁检测（innodb_deadlock_detect）发现环路，回滚其中一个事务

解决方案:
  (1) 尽量用主键而非唯一索引作为冲突检测依据（主键精确匹配不加间隙锁）
  (2) 减少唯一索引数量（每个唯一索引都是潜在的死锁点）
  (3) 并发 UPSERT 按固定顺序处理（如按主键排序）
  (4) 降低隔离级别到 READ COMMITTED（不加 Gap Lock，但牺牲可重复读）

### 多唯一索引的歧义问题

如果表有多个唯一索引，ON DUPLICATE KEY UPDATE 只匹配第一个冲突的索引:
```sql
CREATE TABLE t (id INT PK, a INT UNIQUE, b INT UNIQUE);
INSERT INTO t VALUES(1, 10, 100);
INSERT INTO t VALUES(2, 10, 200) ON DUPLICATE KEY UPDATE b = 200;
```

结果: 更新 a=10 那行（第一个冲突的唯一索引），而不是插入新行
如果 (1, 10, 200) 同时冲突 id 和 a，只会更新一行（不可预测哪个先匹配）
最佳实践: 确保 ON DUPLICATE KEY UPDATE 的表只有一个唯一约束（主键或唯一索引）

## REPLACE INTO 的隐藏危险

REPLACE INTO 的实际执行: DELETE + INSERT（不是 UPDATE）
隐藏危险列表:

危险 1: AUTO_INCREMENT 跳跃
REPLACE INTO users(username, email) VALUES('alice', 'new@example.com');
如果 alice 存在（id=5），REPLACE 会: DELETE id=5 → INSERT 新行 id=6
每次 REPLACE 都消耗一个新的自增值，导致 ID 快速增长

危险 2: 触发 DELETE 触发器
REPLACE 会依次触发: BEFORE DELETE → AFTER DELETE → BEFORE INSERT → AFTER INSERT
如果 DELETE 触发器有副作用（如级联删除、审计日志），REPLACE 会意外触发

危险 3: 外键级联删除
如果 users 表被 orders 表外键引用（ON DELETE CASCADE），
REPLACE 的 DELETE 阶段会级联删除 orders 中的关联行！
这是最危险的隐患: 本意是更新用户信息，却删除了用户的所有订单

危险 4: 丢失未指定列的值
```sql
CREATE TABLE t (id INT PK, a INT, b INT, c INT);
INSERT INTO t VALUES (1, 10, 20, 30);
```

REPLACE INTO t (id, a) VALUES (1, 99);
结果: b 和 c 变为 NULL（因为是 DELETE + INSERT，未指定的列用默认值）
ON DUPLICATE KEY UPDATE 则只更新指定列，其他列保持不变

> **结论**: 几乎所有场景都应优先使用 ON DUPLICATE KEY UPDATE 而非 REPLACE INTO。
REPLACE INTO 唯一的优势是语法简单，但带来的隐患远大于便利。

## VALUES() 废弃与新别名语法的设计考量

旧语法（4.1 ~ 8.0.20, 已废弃）:
```sql
INSERT INTO t(a,b) VALUES(1,2) ON DUPLICATE KEY UPDATE b = VALUES(b);
```

废弃原因:
  (1) VALUES() 既是行构造器关键字又是引用待插入值的函数，语义重载
  (2) 在某些上下文中歧义: VALUES(b) 是指 INSERT 的值还是行构造器?
  (3) 与 SQL 标准的 VALUES 行构造器冲突

新语法（8.0.19+）:
```sql
INSERT INTO t(a,b) VALUES(1,2) AS new ON DUPLICATE KEY UPDATE b = new.b;
INSERT INTO t(a,b) VALUES(1,2) AS new(x,y) ON DUPLICATE KEY UPDATE b = new.y;
```

设计优势:
  (1) 别名语义清晰: new.b 明确指向待插入的值
  (2) 列别名（new.x, new.y）允许引用列而不受原表列名限制
  (3) 与标准 SQL 的 INSERT 语义一致，不引入特殊函数

## 横向对比: UPSERT 的设计流派

### MySQL: INSERT ... ON DUPLICATE KEY UPDATE

  触发条件: 主键或任何唯一索引冲突
  实现: 先 INSERT 尝试 → 冲突时转为 UPDATE（同一行，非 DELETE+INSERT）
  affected rows: 1 = 新插入, 2 = 更新了值, 0 = 值相同
  限制: 多唯一索引时行为不直观（见 2.3）

### PostgreSQL: INSERT ... ON CONFLICT (9.5+)

```sql
  INSERT INTO users(username, email, age) VALUES('alice', 'alice@example.com', 25)
```

  ON CONFLICT (username) DO UPDATE SET email = EXCLUDED.email, age = EXCLUDED.age;
  ON CONFLICT (username) DO NOTHING;  -- 等价于 INSERT IGNORE

关键区别:
  (1) ON CONFLICT 必须指定冲突的列或约束名（语义精确）
      MySQL 不需要指定，自动匹配第一个冲突的索引（可能不明确）
  (2) EXCLUDED 关键字引用待插入的行（类似 MySQL 的 VALUES() / 别名）
  (3) 支持 ON CONFLICT ... WHERE ... 条件更新（partial unique index 场景）
  (4) 不加 Gap Lock，死锁风险更低

### SQL 标准 MERGE（SQL:2003）

```sql
MERGE INTO target USING source ON (condition)
```

WHEN MATCHED THEN UPDATE SET ...
WHEN NOT MATCHED THEN INSERT VALUES (...);

支持情况:
  Oracle:     9i+（最早支持，实现最成熟）
  SQL Server: 2008+（有大量已知 Bug，多位 MVP 建议避免）
  PostgreSQL: 15+（终于支持）
  MySQL:      不支持 MERGE（也没有计划支持）
  DB2:        9.7+

MERGE vs ON DUPLICATE KEY vs ON CONFLICT 对比:
  MERGE: 最强大（支持多条件、DELETE 子句），但语法复杂，并发安全性问题
  ON CONFLICT: 最精确（指定冲突列），PG 的并发安全性最好
  ON DUPLICATE KEY: 最简洁，但多索引时语义不明确

### ClickHouse: ReplacingMergeTree

  ClickHouse 没有 UPSERT 语句，通过表引擎实现去重:
```sql
  CREATE TABLE t (...) ENGINE = ReplacingMergeTree(version) ORDER BY id;
```

  INSERT 重复数据 → 后台 merge 时保留最新版本（异步去重）
  在 merge 完成之前，查询可能返回重复数据（需要 FINAL 关键字强制去重）
  这是 AP 引擎的典型方案: 写入不做唯一性检查，查询时或后台合并时去重

### Doris/StarRocks: Unique Key 模型

```sql
  CREATE TABLE t (...) UNIQUE KEY(id) ...;
```

  INSERT 自动覆盖相同 key 的旧数据（类似 REPLACE INTO 但无 DELETE+INSERT 开销）
  实现: 在 Compaction 时合并相同 key 的记录，保留最新版本

## 对引擎开发者: UPSERT 的实现方案选择

方案 A: INSERT 尝试 + 冲突时 UPDATE（MySQL/PG 的做法）
  优点: 语义清晰，行级事务，ACID 保证
  缺点: 需要唯一索引支持，加锁复杂，可能死锁
  适用: OLTP 引擎

方案 B: DELETE + INSERT（MySQL REPLACE INTO 的做法）
  优点: 实现简单
  缺点: 自增跳跃、触发器副作用、外键级联危险
  不推荐: 几乎所有场景都不如方案 A

方案 C: 写入时不检查 + 后台合并去重（ClickHouse/Doris 的做法）
  优点: 写入性能最高（无唯一性检查开销，无锁）
  缺点: 不保证即时唯一性，查询需要额外去重逻辑
  适用: OLAP 引擎，对一致性要求不严格的分析场景

方案 D: 应用层 Read-Modify-Write
  SELECT ... FOR UPDATE → 判断是否存在 → INSERT 或 UPDATE
  优点: 逻辑完全在应用层控制
  缺点: 多次网络往返，性能差，需要应用层处理并发
  适用: 没有原生 UPSERT 支持的引擎

实现建议:
  (1) 必须支持指定冲突检测的列/索引（PG 的 ON CONFLICT 设计更好）
  (2) 提供 DO NOTHING 选项（等价于 INSERT IGNORE）
  (3) 提供引用待插入值的语法（EXCLUDED / 别名 / VALUES()）
  (4) 死锁防范: 减少 Gap Lock 的使用，考虑 PG 的无 Gap Lock 方案
  (5) 如果是分布式引擎: 全局唯一索引的 UPSERT 需要分布式锁或两阶段提交

## 并发安全性深度分析

场景: 两个并发事务同时 UPSERT 同一个 key
```sql
INSERT INTO counters(key, cnt) VALUES('page_views', 1)
```

ON DUPLICATE KEY UPDATE cnt = cnt + 1;

MySQL 的行为:
  两个事务串行化（第二个等待第一个释放 X 锁）
  结果: cnt 正确递增 2，数据一致
  但: 如果并发极高（几千 TPS 对同一 key），锁等待链会导致性能骤降

PostgreSQL 的行为:
  ON CONFLICT 在 READ COMMITTED 下也能正确处理并发（使用 speculative insertion）
  如果 INSERT 失败（冲突），重新检查行并执行 UPDATE
  结果: 同样正确，但实现更轻量（不依赖 Gap Lock）

ClickHouse 的行为:
  两次 INSERT 都成功（不做唯一性检查）
  查询时需要 SELECT ... FINAL 或 GROUP BY 去重
  结果: 可能暂时看到重复数据，Compaction 后合并

> **结论**: 
  OLTP 场景选 ON CONFLICT/ON DUPLICATE KEY（强一致）
  OLAP 场景选 后台去重（最终一致，写入性能最高）

## 版本演进

MySQL 4.1:   INSERT ... ON DUPLICATE KEY UPDATE
MySQL 5.7:   affected_rows 行为明确化（1=插入, 2=更新, 0=无变化）
MySQL 8.0.19: VALUES 行别名语法（替代 VALUES() 函数）
MySQL 8.0.20: VALUES() 在 ON DUPLICATE KEY UPDATE 中正式废弃
