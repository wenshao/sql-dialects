# PostgreSQL: 触发器

> 参考资料:
> - [PostgreSQL Documentation - CREATE TRIGGER](https://www.postgresql.org/docs/current/sql-createtrigger.html)
> - [PostgreSQL Documentation - Trigger Functions](https://www.postgresql.org/docs/current/plpgsql-trigger.html)

## PostgreSQL 触发器的独特设计: 函数分离

PostgreSQL 触发器由两部分组成:
  (1) 触发器函数: CREATE FUNCTION ... RETURNS TRIGGER
  (2) 触发器定义: CREATE TRIGGER ... EXECUTE FUNCTION

设计分析: 函数与触发器分离
  优点: 一个函数可以被多个触发器复用（DRY 原则）
  缺点: 创建触发器需要两步（比 MySQL 的单步定义更冗长）
  对比:
    MySQL:      CREATE TRIGGER 中直接写 BEGIN...END
    Oracle:     CREATE TRIGGER 中直接写 PL/SQL 块
    SQL Server: CREATE TRIGGER 中直接写 T-SQL 块
    PostgreSQL: 必须先创建函数，触发器引用函数

## BEFORE 触发器: 修改/拦截操作

```sql
CREATE OR REPLACE FUNCTION trg_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;  -- BEFORE 触发器必须返回 NEW（或 NULL 取消操作）
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION trg_update_timestamp();
```

设计对比: ON UPDATE CURRENT_TIMESTAMP
  MySQL: 内置 ON UPDATE CURRENT_TIMESTAMP（DDL 级别，零代码）
  PostgreSQL: 需要触发器函数+触发器定义（更多代码但更灵活）
  PostgreSQL 的方式可以在触发器中做更多操作（如条件判断、审计日志）

## AFTER 触发器: 审计日志

```sql
CREATE OR REPLACE FUNCTION trg_audit_log()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, action, record_id, old_data)
        VALUES (TG_TABLE_NAME, TG_OP, OLD.id, to_jsonb(OLD));
        RETURN OLD;
    ELSE
        INSERT INTO audit_log (table_name, action, record_id, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, NEW.id, to_jsonb(NEW));
        RETURN NEW;
    END IF;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_audit
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION trg_audit_log();
```

触发器变量:
  TG_OP:         'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'
  TG_TABLE_NAME: 触发表名
  TG_WHEN:       'BEFORE', 'AFTER', 'INSTEAD OF'
  OLD:           旧行（UPDATE/DELETE 可用）
  NEW:           新行（INSERT/UPDATE 可用）
  TG_ARGV:       触发器参数数组

## 条件触发器: WHEN 子句 (9.0+)

```sql
CREATE TRIGGER trg_email_changed
    AFTER UPDATE ON users
    FOR EACH ROW
    WHEN (OLD.email IS DISTINCT FROM NEW.email)  -- 只在 email 变化时触发
    EXECUTE FUNCTION notify_email_change();
```

WHEN 子句在触发器层面过滤，比在函数体内 IF 判断更高效。
WHEN 条件在触发器执行前评估——不满足条件时不调用函数。

## 语句级触发器 vs 行级触发器

FOR EACH ROW: 每行触发一次
FOR EACH STATEMENT: 整个语句只触发一次（即使影响 0 行也触发）

```sql
CREATE TRIGGER trg_truncate_log
    AFTER TRUNCATE ON users
    FOR EACH STATEMENT EXECUTE FUNCTION log_truncate();
```

语句级触发器的 transition tables (10+): 访问所有受影响的行
```sql
CREATE TRIGGER trg_batch_audit
    AFTER INSERT ON orders
    REFERENCING NEW TABLE AS new_rows
    FOR EACH STATEMENT EXECUTE FUNCTION process_batch();
```

在函数中: SELECT * FROM new_rows; 可以访问所有新插入的行

## INSTEAD OF 触发器: 视图上的 DML

```sql
CREATE TRIGGER trg_view_insert
    INSTEAD OF INSERT ON user_view
    FOR EACH ROW EXECUTE FUNCTION handle_view_insert();
```

INSTEAD OF 只能在视图上使用，不能在表上使用。
用于实现复杂视图（JOIN/聚合视图）的 DML 操作。

## 事件触发器 (9.3+): DDL 事件监控

事件触发器监控 DDL 操作（CREATE/ALTER/DROP）
```sql
CREATE OR REPLACE FUNCTION log_ddl() RETURNS event_trigger AS $$
BEGIN
    INSERT INTO ddl_log (event, tag, object_type, object_name)
    SELECT tg_event, tg_tag, object_type, object_identity
    FROM pg_event_trigger_ddl_commands();
END; $$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER trg_ddl_log ON ddl_command_end
    EXECUTE FUNCTION log_ddl();
```

事件触发器类型:
  ddl_command_start:  DDL 命令开始前
  ddl_command_end:    DDL 命令成功完成后
  table_rewrite:      表重写开始前（ALTER TABLE 导致的）
  sql_drop:           对象被删除后

## 触发器管理

```sql
DROP TRIGGER IF EXISTS trg_users_updated ON users;
ALTER TABLE users DISABLE TRIGGER trg_users_audit;
ALTER TABLE users ENABLE TRIGGER trg_users_audit;
ALTER TABLE users DISABLE TRIGGER ALL;              -- 禁用所有触发器
ALTER TABLE users ENABLE TRIGGER ALL;
```

## 横向对比: 触发器差异

### 触发器与函数的关系

  PostgreSQL: 分离（先创建函数，触发器引用函数）
  MySQL/Oracle/SQL Server: 一体（触发器体内直接写代码）

### 事件触发器 (DDL)

  PostgreSQL: EVENT TRIGGER (9.3+)
  MySQL:      不支持 DDL 触发器
  Oracle:     SCHEMA 级 DDL 触发器
  SQL Server: DDL 触发器 (2005+)

### 分区表触发器

  PostgreSQL 11+: 分区表上的行级触发器自动继承到所有分区
  PostgreSQL 15+: MERGE 操作也会触发触发器

### Transition tables

  PostgreSQL 10+: REFERENCING NEW/OLD TABLE（语句级触发器访问所有行）
  SQL Server: inserted/deleted 伪表（天然支持）
  Oracle:     compound trigger 中的 :OLD / :NEW

## 对引擎开发者的启示

(1) 触发器函数分离设计的优势:
    一个通用的审计函数可以被 100 张表的触发器复用。
    to_jsonb(OLD/NEW) 使得通用审计函数不需要知道表结构。

(2) WHEN 子句的优化价值:
    在触发器框架层面过滤，比在函数体内判断更高效。
    减少了不必要的函数调用开销（特别是高频 UPDATE 场景）。

(3) 事件触发器是 DDL 审计的基础:
    可以记录所有 schema 变更，支持合规审计和变更追踪。
    这在 MySQL 中需要 binlog 解析或第三方工具。

## 版本演进

PostgreSQL 全版本: BEFORE/AFTER 行级触发器
PostgreSQL 9.0:   WHEN 条件子句
PostgreSQL 9.1:   ALTER TABLE ... DISABLE/ENABLE TRIGGER
PostgreSQL 9.3:   事件触发器 (EVENT TRIGGER), INSTEAD OF
PostgreSQL 10:    Transition tables (REFERENCING NEW/OLD TABLE)
PostgreSQL 11:    分区表触发器自动继承
PostgreSQL 15:    MERGE 触发触发器
