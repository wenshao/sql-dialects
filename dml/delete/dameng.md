# DamengDB (达梦): DELETE

Oracle compatible syntax.

> 参考资料:
> - [DamengDB SQL Reference](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)
> - [DamengDB dmfldr User Guide](https://eco.dameng.com/document/dm/zh-cn/pm/zh-cn/pm2-appendix-dmfldr.html)
> - ============================================================
> - 1. 基本 DELETE
> - ============================================================
> - 单行删除

```sql
DELETE FROM users WHERE username = 'alice';
```

## 多条件删除

```sql
DELETE FROM users WHERE status = 0 AND last_login < DATE '2023-01-01';
```

## 删除所有行（逐行删除，产生 undo log，可回滚）

```sql
DELETE FROM users;
```

## 快速清空表（DDL 操作，不可回滚，不触发触发器）

```sql
TRUNCATE TABLE users;
```

## 子查询与关联删除


## IN 子查询删除

```sql
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);
```

## EXISTS 关联删除

```sql
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = u.email);
```

## 复杂关联删除（使用子查询）

```sql
DELETE FROM users
WHERE id IN (
    SELECT u.id FROM users u
    JOIN blacklist b ON u.email = b.email
);
```

## NOT EXISTS 删除（删除没有订单的用户）

```sql
DELETE FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

## 分区表上的 DELETE


## 指定分区删除（减少扫描范围）

```sql
DELETE FROM users PARTITION (p2023) WHERE status = 0;
```

## 按时间范围清理过期分区数据

```sql
DELETE FROM logs PARTITION (p202301) WHERE created_at < DATE '2023-01-15';
```

交换分区后 TRUNCATE（高效清理整分区数据）
ALTER TABLE users EXCHANGE PARTITION p2020 WITH TABLE users_archive_p2020;
TRUNCATE TABLE users_archive_p2020;
分区裁剪优化:
当 WHERE 条件包含分区键时，达梦会自动进行分区裁剪
只扫描符合条件的分区，大幅减少 I/O
例如: DELETE FROM range_users WHERE create_time BETWEEN '2023-01-01' AND '2023-03-01'
只扫描 2023-Q1 分区

## RETURNING 子句（PL/SQL 中使用）


DELETE ... RETURNING INTO（在 PL/SQL 匿名块中使用）
DECLARE
v_id INTEGER;
v_name VARCHAR(50);
BEGIN
DELETE FROM users WHERE username = 'alice'
RETURNING id, username INTO v_id, v_name;
DBMS_OUTPUT.PUT_LINE('Deleted: id=' || v_id || ', name=' || v_name);
END;
/
BULK COLLECT INTO（批量删除并收集结果）
DECLARE
TYPE id_array IS TABLE OF INTEGER;
v_ids id_array;
BEGIN
DELETE FROM users WHERE status = 0
RETURNING id BULK COLLECT INTO v_ids;
DBMS_OUTPUT.PUT_LINE('Deleted ' || v_ids.COUNT || ' rows');
END;
/

## 批量删除策略


策略 1: 分批删除（避免长事务锁表）
DECLARE
v_rows INTEGER := 1;
BEGIN
WHILE v_rows > 0 LOOP
DELETE FROM logs WHERE created_at < DATE '2023-01-01' AND ROWNUM <= 10000;
v_rows := SQL%ROWCOUNT;
COMMIT;
END LOOP;
END;
/
策略 2: 使用 TRUNCATE 清空整表（最快）

```sql
TRUNCATE TABLE logs;
```

策略 3: DROP + 重建（比 DELETE 更快，适用于完全重建场景）
DROP TABLE logs;
CREATE TABLE logs (...);
策略 4: 分区交换（DROP PARTITION 最高效）
ALTER TABLE logs DROP PARTITION p2020;
或使用 TRUNCATE PARTITION
ALTER TABLE logs TRUNCATE PARTITION p2020;
批量删除的性能考量:
DELETE 产生大量 undo log 和 redo log
大批量删除时 undo 表空间可能膨胀
建议: 单次 DELETE 控制在 10000 行以内，分批提交
高水位不降: DELETE 后表的 HWM 不会降低，全表扫描性能不变
解决: DELETE 后使用 ALTER TABLE ... SHRINK SPACE 回收空间

## dmfldr 数据卸载与清理

dmfldr 是达梦的快速数据装载/卸载工具（类似 Oracle SQL*Loader）:
导出数据: dmfldr SYSDBA/password SERVER=localhost:5236 \
"LOAD DATA OUTFILE '/tmp/users.dat' FROM users"
导入数据: dmfldr SYSDBA/password SERVER=localhost:5236 \
"LOAD DATA INFILE '/tmp/new_users.dat' INTO TABLE users"
dmfldr 在 DELETE 场景的应用:
(1) 导出需要保留的数据，TRUNCATE 表，再导入（等效于大范围删除）
(2) 数据迁移场景: 先用 dmfldr 导出归档数据，再清理源表
(3) 适合处理千万级以上的数据清理，比 SQL DELETE 快 10-100 倍
注意: dmfldr 导入时 DIRECT=TRUE 模式绕过 redo log，不可回滚

## 事务与并发控制


达梦 DELETE 的事务特性:
DELETE 默认在当前事务中执行，需要 COMMIT 才生效
DELETE 会对扫描到的行加行锁（SELECT ... FOR UPDATE 风格）
大批量 DELETE 可能阻塞其他事务的 DML 操作
并发删除注意事项:
不同行可以并发删除（行级锁）
DELETE + WHERE 条件不冲突时可以并发执行
避免在事务中先 SELECT 再 DELETE（应使用 WHERE 条件直接 DELETE）
死锁风险:
两个事务交叉删除对方的行可能导致死锁
达梦会自动检测死锁并回滚其中一个事务

## 横向对比: 达梦 vs Oracle DELETE

语法兼容性:  达梦 DELETE 语法与 Oracle 高度兼容
共同特性:
RETURNING ... INTO 变量
BULK COLLECT INTO 批量收集
PARTITION 分区指定
ROWNUM 分页删除
没有 MySQL 风格的 JOIN DELETE / LIMIT DELETE
差异:
达梦没有 Oracle 的 FLASHBACK QUERY（无法查询 DELETE 前的数据）
达梦的 undo 保留策略与 Oracle 不同（UNDO_RETENTION 参数）
达梦不支持 Oracle 的 DBMS_PARALLEL_EXECUTE 并行删除包
