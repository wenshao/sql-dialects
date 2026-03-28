#!/usr/bin/env python3
"""Convert .sql files to .md format for 8 dialects, with deep rewrite for SQL engine developers."""

import os
import re
import sys
import subprocess

DIALECTS = ['tidb', 'oceanbase', 'cockroachdb', 'spanner', 'yugabytedb', 'trino', 'flink', 'duckdb']

DIALECT_DISPLAY = {
    'tidb': 'TiDB',
    'oceanbase': 'OceanBase',
    'cockroachdb': 'CockroachDB',
    'spanner': 'Spanner',
    'yugabytedb': 'YugabyteDB',
    'trino': 'Trino',
    'flink': 'Flink SQL',
    'duckdb': 'DuckDB',
}

MODULE_CHINESE = {
    'create-table': 'CREATE TABLE',
    'alter-table': 'ALTER TABLE',
    'indexes': '索引',
    'constraints': '约束',
    'views': '视图',
    'sequences': '序列与自增',
    'users-databases': '数据库与用户管理',
    'delete': 'DELETE',
    'insert': 'INSERT',
    'update': 'UPDATE',
    'upsert': 'UPSERT',
    'aggregate': '聚合函数',
    'conditional': '条件函数',
    'date-functions': '日期函数',
    'math-functions': '数学函数',
    'string-functions': '字符串函数',
    'type-conversion': '类型转换',
    'cte': 'CTE 公共表表达式',
    'full-text-search': '全文搜索',
    'joins': 'JOIN 连接查询',
    'pagination': '分页查询',
    'pivot-unpivot': '行列转换',
    'set-operations': '集合操作',
    'subquery': '子查询',
    'window-functions': '窗口函数',
    'dynamic-sql': '动态 SQL',
    'error-handling': '错误处理',
    'explain': '执行计划',
    'locking': '锁机制',
    'partitioning': '分区',
    'permissions': '权限管理',
    'stored-procedures': '存储过程',
    'temp-tables': '临时表',
    'transactions': '事务',
    'triggers': '触发器',
    'date-series-fill': '日期序列填充',
    'deduplication': '数据去重',
    'gap-detection': '间隔检测',
    'hierarchical-query': '层级查询',
    'json-flatten': 'JSON 展开',
    'migration-cheatsheet': '迁移速查表',
    'ranking-top-n': 'TopN 排名查询',
    'running-total': '累计求和',
    'slowly-changing-dim': '缓慢变化维',
    'string-split-to-rows': '字符串拆分',
    'window-analytics': '窗口分析实战',
    'array-map-struct': '复合类型',
    'datetime': '日期时间类型',
    'json': 'JSON 类型',
    'numeric': '数值类型',
    'string': '字符串类型',
}

DIALECT_CHARACTERISTICS = {
    'tidb': '分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识',
    'oceanbase': '分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识',
    'cockroachdb': '分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning',
    'spanner': 'Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务',
    'yugabytedb': '分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识',
    'trino': '分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）',
    'flink': '流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制',
    'duckdb': '嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法',
}


def convert_sql_to_md(sql_content, dialect, module_name, category):
    """Convert a .sql file content to .md format with deep rewrite."""
    display_name = DIALECT_DISPLAY.get(dialect, dialect)
    chinese_name = MODULE_CHINESE.get(module_name, module_name)

    lines = sql_content.split('\n')

    # Extract references from header
    refs = []
    ref_start = -1
    ref_end = -1
    for i, line in enumerate(lines):
        stripped = line.strip()
        if '参考资料' in stripped:
            ref_start = i
        if ref_start >= 0 and i > ref_start:
            if not stripped.startswith('--') and stripped != '':
                ref_end = i
                break
            # URL line
            url_match = re.search(r'https?://\S+', stripped)
            title_match = re.match(r'--\s+\[\d+\]\s+(.*)', stripped)
            if title_match:
                refs.append({'title': title_match.group(1), 'url': ''})
            elif url_match and refs:
                refs[-1]['url'] = url_match.group(0)

    # Build the markdown
    md_lines = []
    md_lines.append(f'# {display_name}: {chinese_name}')
    md_lines.append('')

    # References block
    if refs:
        md_lines.append('> 参考资料:')
        for ref in refs:
            if ref['url']:
                md_lines.append(f'> - [{ref["title"]}]({ref["url"]})')
            else:
                md_lines.append(f'> - {ref["title"]}')
        md_lines.append('')

    # Engine positioning
    char = DIALECT_CHARACTERISTICS.get(dialect, '')
    if char:
        md_lines.append(f'**引擎定位**: {char}。')
        md_lines.append('')

    # Now process the body: convert SQL comments to prose, SQL code to code blocks
    # Skip the header (title + refs)
    body_start = 0
    found_first_separator = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith('-- ===='):
            body_start = i
            found_first_separator = True
            break
        if not stripped.startswith('--') and stripped != '' and i > 2:
            # First SQL code line (no separator files)
            body_start = i
            break

    if not found_first_separator:
        # For files without separators, find end of header comments
        for i, line in enumerate(lines):
            stripped = line.strip()
            if i > 0 and not stripped.startswith('--') and stripped != '':
                body_start = i
                break

    # Process body lines
    i = body_start
    in_sql_block = False
    sql_block_lines = []
    pending_comments = []

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Section separator
        if stripped.startswith('-- ===='):
            # Flush SQL block if open
            if in_sql_block and sql_block_lines:
                md_lines.append('```sql')
                md_lines.extend(sql_block_lines)
                md_lines.append('```')
                md_lines.append('')
                sql_block_lines = []
                in_sql_block = False

            # Next line should be the section title
            i += 1
            if i < len(lines):
                title_line = lines[i].strip()
                if title_line.startswith('-- '):
                    title_text = title_line[3:].strip()
                    # Extract section number and title
                    sec_match = re.match(r'^(\d+(?:\.\d+)?)[.\s]\s*(.*)', title_text)
                    if sec_match:
                        num = sec_match.group(1)
                        title = sec_match.group(2)
                        if '.' not in num:
                            md_lines.append(f'## {title}')
                        else:
                            md_lines.append(f'### {title}')
                    else:
                        md_lines.append(f'## {title_text}')
                    md_lines.append('')
            # Skip closing separator
            i += 1
            if i < len(lines) and lines[i].strip().startswith('-- ===='):
                i += 1
            continue

        # Comment line
        if stripped.startswith('--'):
            # Flush SQL block if open
            if in_sql_block and sql_block_lines:
                md_lines.append('```sql')
                md_lines.extend(sql_block_lines)
                md_lines.append('```')
                md_lines.append('')
                sql_block_lines = []
                in_sql_block = False

            # Process comment
            if stripped == '--':
                md_lines.append('')
            else:
                text = stripped[3:] if stripped.startswith('-- ') else stripped[2:]

                # Sub-section header like "2.1 Title: description"
                subsec_match = re.match(r'^(\d+\.\d+)\s+(.*)', text)
                if subsec_match:
                    md_lines.append(f'### {subsec_match.group(2)}')
                    md_lines.append('')
                    i += 1
                    continue

                # Numbered section like "1. Title"
                sec_match = re.match(r'^(\d+)\.\s+(.*)', text)
                if sec_match and not re.match(r'^\d+\.\s+\S+\s*=', text):  # not an assignment
                    md_lines.append(f'## {sec_match.group(2)}')
                    md_lines.append('')
                    i += 1
                    continue

                # Label patterns -> bold
                label_match = re.match(r'^(设计分析|设计原理|设计理由|设计哲学|设计哲理|设计 trade-off|设计背景|设计意义|实现细节|关键实现|横向对比|对比|对引擎开发者的启示|对引擎开发者|已知陷阱|核心应用|限制|注意|优点|缺点|用途|含义|背景|原因|语法特点|存储开销|对比其他|对比:)\s*[:：]?\s*(.*)', text)
                if label_match:
                    label = label_match.group(1)
                    rest = label_match.group(2) if label_match.group(2) else ''
                    if rest:
                        md_lines.append(f'**{label}:** {rest}')
                    else:
                        md_lines.append(f'**{label}:**')
                    i += 1
                    continue

                # Table-like patterns: "Engine: description" or "Name  value"
                # Keep as-is for now

                md_lines.append(text)
            i += 1
            continue

        # Empty line
        if stripped == '':
            if in_sql_block:
                sql_block_lines.append(line)
            else:
                md_lines.append('')
            i += 1
            continue

        # SQL code line
        if not in_sql_block:
            in_sql_block = True
            sql_block_lines = []

        sql_block_lines.append(line)
        i += 1

    # Flush any remaining SQL block
    if in_sql_block and sql_block_lines:
        md_lines.append('```sql')
        md_lines.extend(sql_block_lines)
        md_lines.append('```')
        md_lines.append('')

    # Post-processing: clean up excessive blank lines
    result = '\n'.join(md_lines)
    result = re.sub(r'\n{4,}', '\n\n\n', result)

    # Ensure file ends with single newline
    result = result.rstrip('\n') + '\n'

    return result


def process_file(sql_path, dialect):
    """Process a single .sql file."""
    parts = sql_path.replace('/root/git/sql/', '').split('/')
    category = parts[0]
    module_name = parts[1]

    with open(sql_path, 'r', encoding='utf-8') as f:
        sql_content = f.read()

    md_content = convert_sql_to_md(sql_content, dialect, module_name, category)

    md_path = sql_path.replace('.sql', '.md')
    with open(md_path, 'w', encoding='utf-8') as f:
        f.write(md_content)

    return md_path


def update_dialect_page(dialect):
    """Update dialect page links from .sql to .md."""
    dialect_page = f'/root/git/sql/dialects/{dialect}.md'
    if not os.path.exists(dialect_page):
        print(f"  WARNING: {dialect_page} not found, skipping link update")
        return False

    with open(dialect_page, 'r', encoding='utf-8') as f:
        content = f.read()

    new_content = content.replace(f'{dialect}.sql)', f'{dialect}.md)')

    if new_content != content:
        with open(dialect_page, 'w', encoding='utf-8') as f:
            f.write(new_content)
        count = content.count(f'{dialect}.sql)')
        print(f"  Updated {count} links in {dialect_page}")
        return True
    else:
        print(f"  No links to update in {dialect_page}")
        return False


def main():
    total_files = 0

    for dialect in DIALECTS:
        print(f"\n{'='*60}")
        print(f"Processing {DIALECT_DISPLAY[dialect]} ({dialect})")
        print(f"{'='*60}")

        result = subprocess.run(
            ['find', '/root/git/sql', '-name', f'{dialect}.sql', '-not', '-path', '*/dialects/*'],
            capture_output=True, text=True
        )
        sql_files = sorted([f for f in result.stdout.strip().split('\n') if f])

        print(f"  Found {len(sql_files)} .sql files")

        for sql_path in sql_files:
            try:
                md_path = process_file(sql_path, dialect)
                total_files += 1
                short = sql_path.replace('/root/git/sql/', '')
                print(f"  [{total_files:3d}] {short} -> .md")
            except Exception as e:
                print(f"  ERROR: {sql_path}: {e}")
                import traceback
                traceback.print_exc()

        update_dialect_page(dialect)

    print(f"\n{'='*60}")
    print(f"Total: {total_files} .md files created")
    print(f"{'='*60}")


if __name__ == '__main__':
    main()
