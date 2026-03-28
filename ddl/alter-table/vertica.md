# Vertica: ALTER TABLE

> 参考资料:
> - [Vertica SQL Reference](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm)
> - [Vertica Functions](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm)


添加列
```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN phone VARCHAR(20) DEFAULT 'N/A' NOT NULL;
```


删除列
```sql
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN phone CASCADE;
```


修改列类型
```sql
ALTER TABLE users ALTER COLUMN phone SET DATA TYPE VARCHAR(32);
ALTER TABLE users ALTER COLUMN age SET DATA TYPE BIGINT;
```


重命名列
```sql
ALTER TABLE users RENAME COLUMN phone TO mobile;
```


设置/删除默认值
```sql
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
```


设置/删除 NOT NULL
```sql
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
```


修改编码
```sql
ALTER TABLE users ALTER COLUMN email ENCODING RLE;
ALTER TABLE users ALTER COLUMN age ENCODING DELTAVAL;
```


重命名表
```sql
ALTER TABLE users RENAME TO members;
```


添加/删除约束
```sql
ALTER TABLE users ADD CONSTRAINT uq_email UNIQUE (email);
ALTER TABLE users DROP CONSTRAINT uq_email;
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0);
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);
ALTER TABLE orders ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users(id);
```


启用/禁用约束
```sql
ALTER TABLE users ALTER CONSTRAINT uq_email ENABLED;
ALTER TABLE users ALTER CONSTRAINT uq_email DISABLED;
```


分区操作
```sql
ALTER TABLE events PARTITION BY event_time::DATE;
ALTER TABLE events REORGANIZE;
```


修改分段
```sql
ALTER TABLE users SEGMENTED BY HASH(id) ALL NODES;
ALTER TABLE users UNSEGMENTED ALL NODES;
```


修改排序键
```sql
ALTER TABLE users ALTER COLUMN username SET USING username;
```


Schema
```sql
ALTER TABLE users SET SCHEMA archive;
```


Owner
```sql
ALTER TABLE users OWNER TO admin;
```


修改 Projection
```sql
SELECT MARK_DESIGN_KSAFE(1);  -- K-safety level
```


强制重组织
```sql
ALTER TABLE users REORGANIZE;
```


清除删除标记（提高查询性能）
```sql
SELECT PURGE_TABLE('users');
```


访问策略
```sql
ALTER TABLE users ADD ROW ACCESS POLICY my_policy;
```


注意：Vertica 使用 Projections 代替传统索引
注意：ALTER TABLE 后可能需要重新创建 Projections
注意：修改列类型后运行 SELECT MAKE_AHM_NOW() 可加速清理
