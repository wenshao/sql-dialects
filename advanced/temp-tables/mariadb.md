# MariaDB: 临时表

与 MySQL 基本一致, Aria 引擎用于内部临时表

参考资料:
[1] MariaDB Knowledge Base - CREATE TEMPORARY TABLE
https://mariadb.com/kb/en/create-temporary-table/

## 1. 基本临时表

```sql
CREATE TEMPORARY TABLE tmp_results (
    id    BIGINT,
    score DECIMAL(5,2)
);

CREATE TEMPORARY TABLE tmp_users AS
SELECT id, username FROM users WHERE age > 25;
```


## 2. 会话隔离

临时表只在当前会话可见, 会话结束自动销毁
不同会话可以创建同名临时表, 互不影响
临时表可以与永久表同名 (临时表优先)

## 3. 内部临时表引擎 (MariaDB 独有)

MariaDB 使用 Aria 引擎处理内部临时表 (GROUP BY, ORDER BY 等)
MySQL 使用 InnoDB 或 TempTable 引擎
Aria 的优势:
1. 崩溃安全 (比 MyISAM 更好)
2. 更高效的临时表操作 (专门优化)
3. 支持压缩 (减少磁盘临时表的空间)
aria_used_for_temp_tables = ON (默认)

## 4. 对引擎开发者的启示

内部临时表的引擎选择直接影响复杂查询性能:
内存优先: 小结果集用内存临时表 (MEMORY/TempTable)
磁盘 fallback: 超过阈值切换到磁盘临时表
MariaDB Aria: 为临时表场景专门优化的引擎
MySQL TempTable: 8.0 引入的专用内存临时表引擎
关键指标: 内存到磁盘的切换阈值 (tmp_table_size, max_heap_table_size)
