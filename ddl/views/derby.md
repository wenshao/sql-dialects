# Apache Derby: 视图 (Views)

Apache Derby is a lightweight Java embedded relational database.

> 参考资料:
> - [Apache Derby 10.16 Reference - CREATE VIEW](https://db.apache.org/derby/docs/10.16/ref/rrefsqlj15446.html)
> - [Apache Derby 10.16 Developer Guide - Views](https://db.apache.org/derby/docs/10.16/devguide/cdevspecial41021.html)
> - [Apache Derby 10.16 Reference - System Tables](https://db.apache.org/derby/docs/10.16/ref/rrefsistabs38369.html)
> - [Apache Derby 10.16 Tools Guide - sysinfo](https://db.apache.org/derby/docs/10.16/tools/ctoolsdblook.html)


## 基本视图

```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

## 视图中使用列别名

```sql
CREATE VIEW user_summary (uid, name, mail)
AS SELECT id, username, email FROM users;
```

## 可更新视图 + WITH CHECK OPTION

## Derby 支持可更新的单表视图（简单视图）

```sql
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;
```

## 通过可更新视图插入（WITH CHECK OPTION 保证 age >= 18）

```sql
INSERT INTO adult_users (id, username, email, age) VALUES (1, 'alice', 'alice@example.com', 25);
```

## 通过可更新视图更新（WITH CHECK OPTION 防止将 age 改为 < 18）

```sql
UPDATE adult_users SET email = 'new@example.com' WHERE id = 1;
```

以下操作会被 WITH CHECK OPTION 拒绝:
UPDATE adult_users SET age = 15 WHERE id = 1;  -- 违反 age >= 18 条件
INSERT INTO adult_users VALUES (2, 'bob', 'b@b.com', 10);  -- 违反 age >= 18 条件
可更新视图的条件:
基于 single table（单表）
不含 GROUP BY, HAVING, DISTINCT
不含 subquery（子查询）
包含基表的所有 NOT NULL 列（用于 INSERT）
不含聚合函数或表达式列

## 物化视图

## Derby 不支持物化视图（Materialized View）

替代方案: 手动创建汇总表 + 触发器维护

```sql
CREATE TABLE mv_order_summary (
    user_id      BIGINT PRIMARY KEY,
    order_count  INTEGER NOT NULL DEFAULT 0,
    total_amount DECIMAL(18,2) NOT NULL DEFAULT 0
);
```

## 通过触发器维护汇总表

```sql
CREATE TRIGGER trg_order_insert
AFTER INSERT ON orders
REFERENCING NEW AS new_row
FOR EACH ROW
UPDATE mv_order_summary
SET order_count = order_count + 1,
    total_amount = total_amount + new_row.amount
WHERE user_id = new_row.user_id;
```

## 删除视图

```sql
DROP VIEW active_users;
```

## 系统目录查询（System Catalog Queries）

Derby 通过 SYS 模式下的系统表管理元数据。
查询视图信息是 Derby DDL 管理的核心能力。
5.1 查询所有视图

```sql
SELECT v.TABLENAME, v.VIEWDEFINITION, v.SCHEMAID
FROM SYS.SYSVIEWS v
JOIN SYS.SYSTABLES t ON v.TABLEID = t.TABLEID
JOIN SYS.SYSSCHEMAS s ON t.SCHEMAID = s.SCHEMAID
WHERE s.SCHEMANAME = 'APP';  -- APP 是默认 schema
```

## 5.2 查询视图的定义文本

```sql
SELECT TABLENAME, VIEWDEFINITION
FROM SYS.SYSVIEWS
WHERE TABLENAME = 'ACTIVE_USERS';
```

## 5.3 查询视图的列信息

```sql
SELECT c.COLUMNNAME, c.COLUMNNUMBER, c.TYPENAME,
       c.COLUMNDATATYPE, c."DEFAULT", c.COLUMNDEFAULT
FROM SYS.SYSCOLUMNS c
JOIN SYS.SYSTABLES t ON c.REFERENCEID = t.TABLEID
JOIN SYS.SYSSCHEMAS s ON t.SCHEMAID = s.SCHEMAID
WHERE s.SCHEMANAME = 'APP' AND t.TABLENAME = 'ACTIVE_USERS'
ORDER BY c.COLUMNNUMBER;
```

## 5.4 查询视图依赖关系（视图依赖哪些表/视图）

```sql
SELECT d.PROVIDERID, d.DEPENDENTID,
       pt.TABLENAME AS PROVIDER_NAME,
       dt.TABLENAME AS DEPENDENT_NAME
FROM SYS.SYSDEPENDS d
JOIN SYS.SYSTABLES pt ON d.PROVIDERID = pt.TABLEID
JOIN SYS.SYSTABLES dt ON d.DEPENDENTID = dt.TABLEID;
```

## 5.5 查询所有表和视图（区分表和视图）

```sql
SELECT s.SCHEMANAME, t.TABLENAME,
       CASE WHEN t.TABLETYPE = 'V' THEN 'VIEW'
            WHEN t.TABLETYPE = 'T' THEN 'TABLE'
            WHEN t.TABLETYPE = 'S' THEN 'SYSTEM TABLE'
            ELSE t.TABLETYPE END AS OBJECT_TYPE
FROM SYS.SYSTABLES t
JOIN SYS.SYSSCHEMAS s ON t.SCHEMAID = s.SCHEMAID
WHERE s.SCHEMANAME NOT IN ('SYS', 'SYSCAT', 'SYSFUN', 'SYSPROC', 'SYSIBM')
ORDER BY s.SCHEMANAME, t.TABLENAME;
```

5.6 使用 DATABASE METADATA（JDBC 方式）
在 Java 中通过 JDBC DatabaseMetaData 获取视图信息:
ResultSet views = meta.getTables(null, "APP", "%", new String[]{"VIEW"});
while (views.next()) {
String viewName = views.getString("TABLE_NAME");
}

## Derby 视图的限制

不支持 CREATE OR REPLACE VIEW（需 DROP + CREATE）
不支持 IF NOT EXISTS / IF EXISTS
不支持物化视图
不支持 DROP VIEW CASCADE
可更新视图仅限于简单单表查询
不支持在视图上创建触发器
视图定义不可包含 FOR UPDATE 子句
视图不存储查询计划（每次查询重新优化）

## 设计分析（对 SQL 引擎开发者）

Derby 的视图实现是嵌入式数据库的典型代表:
7.1 嵌入式数据库的视图设计哲学:
视图只是 "stored query"（保存的查询），不存储数据
每次访问视图都重新执行底层查询（无缓存）
简单、可靠、无一致性问题
适合嵌入式场景（数据量小、查询频率低）
- **对比 PostgreSQL**: 视图查询计划可缓存，且支持物化视图
- **对比 Oracle**: 视图可使用 NO_MERGE / PUSH_PRED 等优化提示
7.2 WITH CHECK OPTION 的实现:
Derby 的 WITH CHECK_OPTION 是 ANSI SQL 标准
在 INSERT/UPDATE 时，Derby 通过视图的 WHERE 条件验证数据
如果违反条件则抛出 SQLException
- **对比 MySQL**: 同样支持 WITH CHECK OPTION（CASCADED / LOCAL）
- **对比 SQLite**: 不支持 WITH CHECK OPTION
7.3 跨方言对比:
- **Derby**: 简单视图支持，可更新视图，WITH CHECK OPTION
- **H2**: 更丰富（CREATE OR REPLACE, 可更新 Join 视图）

```
HSQLDB:       最完整（物化视图、CREATE OR REPLACE）
```
- **SQLite**: 只读视图，不支持 WITH CHECK OPTION
- **PostgreSQL**: 物化视图、可更新视图（简单）、WITH CHECK OPTION
- **Oracle**: 最完整（物化视图、可更新 Join 视图、超多选项）
7.4 版本演进:
- **Derby 10.x**: 基于 IBM Cloudscape 的成熟版本
- **Derby 10.16 (2023)**: 最新稳定版，Java 11+ 要求
Apache Derby 是 JDK 自带的 JavaDB 基础
