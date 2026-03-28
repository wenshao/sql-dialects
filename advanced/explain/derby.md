# Apache Derby: 执行计划与查询分析

> 参考资料:
> - [Derby Documentation - Statement execution plan](https://db.apache.org/derby/docs/10.16/tuning/ctuntransform13966.html)
> - [Derby Documentation - RUNTIMESTATISTICS](https://db.apache.org/derby/docs/10.16/ref/rrefsqlj32268.html)


## RUNTIMESTATISTICS（运行时统计）


## 启用运行时统计

```sql
CALL SYSCS_UTIL.SYSCS_SET_RUNTIMESTATISTICS(1);
CALL SYSCS_UTIL.SYSCS_SET_STATISTICS_TIMING(1);
```

## 执行查询

```sql
SELECT * FROM users WHERE age > 25;
```

## 获取执行计划

```sql
VALUES SYSCS_UTIL.SYSCS_GET_RUNTIMESTATISTICS();
```

## 关闭

```sql
CALL SYSCS_UTIL.SYSCS_SET_RUNTIMESTATISTICS(0);
CALL SYSCS_UTIL.SYSCS_SET_STATISTICS_TIMING(0);
```

## 执行计划输出内容


输出包含：
Statement Name / Text
Parse Time / Bind Time / Optimize Time / Generate Time
Execute Time
Begin/End Compilation Timestamp
Statement Execution Plan Text:
扫描方式
索引使用
连接方式
排序信息
行数估算和实际

## 执行计划关键操作


Table Scan          全表扫描
Index Scan          索引扫描
Index Row to Base Row  通过索引回表
Hash Join           哈希连接
Nested Loop Join    嵌套循环连接
Sort                排序
Group By            分组
Distinct            去重
Scroll Insensitive  滚动游标

## XPLAIN 风格（10.5+）


## 启用 XPLAIN 模式将统计信息存入系统表

```sql
CALL SYSCS_UTIL.SYSCS_SET_XPLAIN_SCHEMA('MYSCHEMA');
CALL SYSCS_UTIL.SYSCS_SET_XPLAIN_MODE(1);
```

## 执行查询

```sql
SELECT * FROM users WHERE age > 25;
```

## 关闭 XPLAIN

```sql
CALL SYSCS_UTIL.SYSCS_SET_XPLAIN_MODE(0);
CALL SYSCS_UTIL.SYSCS_SET_XPLAIN_SCHEMA(NULL);
```

## 查看收集的信息

```sql
SELECT * FROM MYSCHEMA.SYSXPLAIN_STATEMENTS;
SELECT * FROM MYSCHEMA.SYSXPLAIN_RESULTSETS;
SELECT * FROM MYSCHEMA.SYSXPLAIN_SCAN_PROPS;
```

## 统计信息


## 更新统计信息

```sql
CALL SYSCS_UTIL.SYSCS_UPDATE_STATISTICS('APP', 'USERS', NULL);
```

## 删除统计信息

```sql
CALL SYSCS_UTIL.SYSCS_DROP_STATISTICS('APP', 'USERS', NULL);
```

注意：Derby 没有 EXPLAIN 语句
注意：使用 SYSCS_UTIL.SYSCS_SET_RUNTIMESTATISTICS 收集执行信息
注意：XPLAIN 模式（10.5+）将统计信息存入可查询的表
注意：Derby 作为嵌入式数据库，查询优化器相对简单
注意：SYSCS_UTIL.SYSCS_UPDATE_STATISTICS 手动更新统计信息
