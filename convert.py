#!/usr/bin/env python3
"""Convert .sql files to .md format for specified dialects."""

import os
import re
import sys

DIALECTS = [
    "polardb", "opengauss", "tdsql", "dameng", "kingbase",
    "hologres", "timescaledb", "tdengine", "ksqldb", "materialize",
    "h2", "derby", "firebird", "db2", "saphana"
]

BASE = "/root/git/sql"

def find_sql_files(dialect):
    """Find all .sql files for a dialect, excluding dialects/ directory."""
    results = []
    for root, dirs, files in os.walk(BASE):
        if "/dialects/" in root or root.endswith("/dialects"):
            continue
        for f in files:
            if f == f"{dialect}.sql":
                results.append(os.path.join(root, f))
    return sorted(results)

def is_sql_line(line):
    """Check if a line looks like SQL code (not a comment)."""
    stripped = line.strip()
    if not stripped:
        return False
    if stripped.startswith("--"):
        return False
    return True

def convert_sql_to_md(content):
    """Convert .sql content to .md format."""
    lines = content.split("\n")
    output = []
    i = 0

    # Track if we're in a SQL block
    in_sql_block = False
    # Track if we've output the title
    title_done = False
    # Track if we've output references
    refs_done = False

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Skip empty lines at the very start
        if not title_done and not stripped:
            i += 1
            continue

        # Handle the title line (first comment line like "-- PolarDB: CREATE TABLE")
        if not title_done and stripped.startswith("--"):
            title_text = stripped.lstrip("- ").strip()
            if title_text:
                output.append(f"# {title_text}")
                output.append("")
                title_done = True
                i += 1

                # Collect subsequent comment lines that are part of the header
                # (sub-description lines before references)
                header_comments = []
                while i < len(lines):
                    s = lines[i].strip()
                    if not s:
                        i += 1
                        continue
                    if s.startswith("--"):
                        text = s.lstrip("- ").strip()
                        if not text:
                            i += 1
                            continue
                        # Check if this is the start of references
                        if "参考资料" in text or "Reference" in text:
                            break
                        # Check if it looks like a reference link
                        if text.startswith("[") and "]" in text:
                            break
                        if text.startswith("http"):
                            break
                        header_comments.append(text)
                        i += 1
                    else:
                        break

                if header_comments:
                    for hc in header_comments:
                        output.append(hc)
                    output.append("")

                continue
            i += 1
            continue

        # Handle reference block
        if not refs_done and stripped.startswith("--") and ("参考资料" in stripped or "Reference" in stripped):
            output.append("> 参考资料:")
            i += 1
            while i < len(lines):
                s = lines[i].strip()
                # Empty line or bare comment signals end of reference block
                if not s or s == "--":
                    # But first check if next non-empty line is still a reference
                    peek = i + 1
                    while peek < len(lines) and not lines[peek].strip():
                        peek += 1
                    if peek < len(lines):
                        peek_text = lines[peek].strip().lstrip("- ").strip()
                        if re.match(r'\[\d+\]', peek_text) or peek_text.startswith("http"):
                            i += 1
                            continue
                    break
                if not s.startswith("--"):
                    break
                text = s.lstrip("- ").strip()
                if not text:
                    i += 1
                    continue
                # Reference entry like [1] Name \n URL
                if re.match(r'\[\d+\]', text):
                    # Extract name part
                    ref_match = re.match(r'\[(\d+)\]\s*(.*)', text)
                    if ref_match:
                        ref_name = ref_match.group(2)
                        # Look ahead for URL
                        if i + 1 < len(lines):
                            next_s = lines[i+1].strip().lstrip("- ").strip()
                            if next_s.startswith("http"):
                                output.append(f"> - [{ref_name}]({next_s})")
                                i += 2
                                continue
                        output.append(f"> - {ref_name}")
                elif text.startswith("http"):
                    # URL on its own (shouldn't happen often with the lookahead above)
                    pass
                else:
                    # Not a reference - this is content after the references
                    break
                i += 1
            output.append("")
            refs_done = True
            continue

        # Handle separator lines like -- ============
        if stripped.startswith("--") and re.match(r'^--\s*[=\-\*]{4,}', stripped):
            i += 1
            continue

        # Handle section headers: -- N. Title or -- Title
        if stripped.startswith("--") and not in_sql_block:
            text = stripped.lstrip("- ").strip()

            if not text:
                if in_sql_block:
                    pass
                else:
                    output.append("")
                i += 1
                continue

            # Check if this is a numbered section header like "1. Title" or "N. Title"
            section_match = re.match(r'^(\d+)\.\s+(.*)', text)
            if section_match:
                if in_sql_block:
                    output.append("```")
                    output.append("")
                    in_sql_block = False
                output.append(f"## {section_match.group(2)}")
                output.append("")
                i += 1
                continue

            # Check if this looks like a heading (short, possibly descriptive)
            # Heuristics: lines that are section-like comments become ## headings
            # Multi-line comments that are explanatory become prose

            # Collect consecutive comment lines
            comment_lines = [text]
            j = i + 1
            while j < len(lines):
                ns = lines[j].strip()
                if ns.startswith("--") and not re.match(r'^--\s*[=\-\*]{4,}', ns):
                    ct = ns.lstrip("- ").strip()
                    if ct:
                        comment_lines.append(ct)
                    j += 1
                elif not ns:
                    j += 1
                    # Check if next non-empty line is still a comment
                    peek = j
                    while peek < len(lines) and not lines[peek].strip():
                        peek += 1
                    if peek < len(lines) and lines[peek].strip().startswith("--"):
                        continue
                    break
                else:
                    break

            # Determine if this is a heading or prose
            # Short single-line comments before SQL code are headings
            # Multi-line explanatory comments are prose

            # Check what follows: SQL code or more comments?
            next_code_idx = j
            while next_code_idx < len(lines) and not lines[next_code_idx].strip():
                next_code_idx += 1

            if len(comment_lines) == 1 and len(text) < 120:
                # Check if it looks like a heading (contains colon, or is short)
                # Also check if next line is SQL
                has_sql_after = (next_code_idx < len(lines) and
                                is_sql_line(lines[next_code_idx]))

                if has_sql_after or "：" in text or ":" in text or len(text) < 60:
                    if in_sql_block:
                        output.append("```")
                        output.append("")
                        in_sql_block = False
                    output.append(f"## {text}")
                    output.append("")
                    i = j
                    continue

            if len(comment_lines) <= 2 and all(len(cl) < 80 for cl in comment_lines):
                # Short comment block -> heading + subtitle or just heading
                if in_sql_block:
                    output.append("```")
                    output.append("")
                    in_sql_block = False
                if len(comment_lines) == 2:
                    output.append(f"## {comment_lines[0]}")
                    output.append("")
                    output.append(comment_lines[1])
                    output.append("")
                else:
                    output.append(f"## {comment_lines[0]}")
                    output.append("")
                i = j
                continue

            # Multi-line comment block -> prose
            if in_sql_block:
                output.append("```")
                output.append("")
                in_sql_block = False

            for cl in comment_lines:
                output.append(cl)
            output.append("")
            i = j
            continue

        # Handle SQL code lines
        if stripped and not stripped.startswith("--"):
            if not in_sql_block:
                output.append("```sql")
                in_sql_block = True
            output.append(line.rstrip())
            i += 1
            continue

        # Handle inline comments within SQL blocks (-- at end of SQL)
        if in_sql_block and stripped.startswith("--"):
            # This is a comment inside a SQL context - keep it in the SQL block
            # Actually, let's close the block and treat as prose
            pass

        # Empty line
        if not stripped:
            if in_sql_block:
                # Check if next non-empty line is SQL
                peek = i + 1
                while peek < len(lines) and not lines[peek].strip():
                    peek += 1
                if peek < len(lines) and is_sql_line(lines[peek]):
                    output.append("")
                    i += 1
                    continue
                else:
                    output.append("```")
                    output.append("")
                    in_sql_block = False
                    i += 1
                    continue
            else:
                output.append("")
                i += 1
                continue

        i += 1

    # Close any open SQL block
    if in_sql_block:
        output.append("```")

    # Clean up: remove excessive blank lines (max 2 consecutive)
    result = []
    blank_count = 0
    for line in output:
        if not line.strip():
            blank_count += 1
            if blank_count <= 2:
                result.append("")
        else:
            blank_count = 0
            result.append(line)

    # Remove trailing blank lines
    while result and not result[-1].strip():
        result.pop()

    return "\n".join(result) + "\n"


def update_dialect_page(dialect):
    """Update dialect page to replace .sql) with .md) in module links."""
    page_path = os.path.join(BASE, "dialects", f"{dialect}.md")
    if not os.path.exists(page_path):
        print(f"  WARNING: dialect page not found: {page_path}")
        return False

    with open(page_path, "r") as f:
        content = f.read()

    # Replace .sql) with .md) in links like (../ddl/create-table/polardb.sql)
    new_content = re.sub(
        rf'(\.\./[^)]*/{re.escape(dialect)})\.sql\)',
        r'\1.md)',
        content
    )

    if new_content != content:
        with open(page_path, "w") as f:
            f.write(new_content)
        count = content.count(f"{dialect}.sql)") - new_content.count(f"{dialect}.sql)")
        print(f"  Updated {count} links in {page_path}")
        return True
    else:
        print(f"  No links to update in {page_path}")
        return False


def main():
    total_created = 0
    total_links_updated = 0

    for dialect in DIALECTS:
        print(f"\n{'='*60}")
        print(f"Processing dialect: {dialect}")
        print(f"{'='*60}")

        sql_files = find_sql_files(dialect)
        print(f"  Found {len(sql_files)} .sql files")

        for sql_path in sql_files:
            md_path = sql_path.replace(".sql", ".md")

            if os.path.exists(md_path):
                print(f"  SKIP (exists): {md_path}")
                continue

            with open(sql_path, "r") as f:
                sql_content = f.read()

            md_content = convert_sql_to_md(sql_content)

            with open(md_path, "w") as f:
                f.write(md_content)

            total_created += 1
            print(f"  Created: {md_path}")

        # Update dialect page links
        if update_dialect_page(dialect):
            total_links_updated += 1

    print(f"\n{'='*60}")
    print(f"SUMMARY: Created {total_created} .md files, updated {total_links_updated} dialect pages")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
