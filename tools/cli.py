#!/usr/bin/env python3
"""Unified CLI tool for sql-dialects repository management.

Subcommands:
    check              Validate repository structure (modules, dialect count)
    check-headers      Validate SQL file headers (title, references)
    check-comparisons  Validate _comparison.md presence and format
    check-quality      Check for empty/short files
    report             Generate coverage report
    convert            Convert .sql files to .md format
    expand             Expand dialect module tables with enriched descriptions

Usage:
    python tools/cli.py check
    python tools/cli.py check-headers [--min-refs 1]
    python tools/cli.py check-comparisons
    python tools/cli.py check-quality [--min-lines 10]
    python tools/cli.py report
    python tools/cli.py convert [--dialects mysql,postgres]
    python tools/cli.py expand [--dialect postgres]
"""

import argparse
import os
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
if not (REPO_ROOT / ".git").is_dir():
    # Fallback: try current working directory
    if (Path.cwd() / ".git").is_dir():
        REPO_ROOT = Path.cwd()
    else:
        print(f"WARNING: Cannot find repository root (no .git in {REPO_ROOT} or {Path.cwd()})", file=sys.stderr)

EXPECTED_DIALECTS = sorted([
    "bigquery", "clickhouse", "cockroachdb", "dameng", "databricks",
    "db2", "derby", "doris", "duckdb", "firebird", "flink", "greenplum",
    "h2", "hive", "hologres", "impala", "kingbase", "ksqldb", "mariadb",
    "materialize", "maxcompute", "mysql", "oceanbase", "opengauss",
    "oracle", "polardb", "postgres", "redshift", "saphana", "snowflake",
    "spanner", "spark", "sqlite", "sql-standard", "sqlserver", "starrocks",
    "synapse", "tdengine", "tdsql", "teradata", "tidb", "timescaledb",
    "trino", "vertica", "yugabytedb",
])

MODULE_DIRS = [
    "ddl/alter-table", "ddl/constraints", "ddl/create-table", "ddl/indexes",
    "ddl/sequences", "ddl/users-databases", "ddl/views",
    "dml/delete", "dml/insert", "dml/update", "dml/upsert",
    "query/cte", "query/full-text-search", "query/joins", "query/pagination",
    "query/pivot-unpivot", "query/set-operations", "query/subquery",
    "query/window-functions",
    "types/array-map-struct", "types/datetime", "types/json", "types/numeric",
    "types/string",
    "functions/aggregate", "functions/conditional", "functions/date-functions",
    "functions/math-functions", "functions/string-functions",
    "functions/type-conversion",
    "advanced/dynamic-sql", "advanced/error-handling", "advanced/explain",
    "advanced/locking", "advanced/partitioning", "advanced/permissions",
    "advanced/stored-procedures", "advanced/temp-tables",
    "advanced/transactions", "advanced/triggers",
    "scenarios/date-series-fill", "scenarios/deduplication",
    "scenarios/gap-detection", "scenarios/hierarchical-query",
    "scenarios/json-flatten", "scenarios/migration-cheatsheet",
    "scenarios/ranking-top-n", "scenarios/running-total",
    "scenarios/slowly-changing-dim", "scenarios/string-split-to-rows",
    "scenarios/window-analytics",
]

EXPECTED_DIALECT_COUNT = len(EXPECTED_DIALECTS)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def module_path(module: str) -> Path:
    return REPO_ROOT / module


def sql_files_in_module(module: str) -> list[Path]:
    """Return all .sql files in a module directory."""
    mp = module_path(module)
    if not mp.is_dir():
        return []
    return sorted(p for p in mp.iterdir() if p.suffix == ".sql")


def dialects_in_module(module: str) -> set[str]:
    """Return dialect names present in a module."""
    return {p.stem for p in sql_files_in_module(module)}


def error(msg: str):
    print(f"  ❌ {msg}", file=sys.stderr)


def ok(msg: str):
    print(f"  ✅ {msg}")


def warn(msg: str):
    print(f"  ⚠️  {msg}", file=sys.stderr)


# ---------------------------------------------------------------------------
# Subcommand: check
# ---------------------------------------------------------------------------

def cmd_check(_args):
    """Validate that every module has the expected 45 dialect SQL files."""
    print("Checking repository structure...\n")
    failures = 0

    for module in MODULE_DIRS:
        mp = module_path(module)
        if not mp.is_dir():
            error(f"{module}/ — directory missing")
            failures += 1
            continue

        present = dialects_in_module(module)
        missing = set(EXPECTED_DIALECTS) - present
        extra = present - set(EXPECTED_DIALECTS)

        if missing:
            error(f"{module}/ — missing {len(missing)} dialects: {', '.join(sorted(missing))}")
            failures += 1
        elif extra:
            warn(f"{module}/ — extra files: {', '.join(sorted(extra))}")
        else:
            ok(f"{module}/ — {len(present)} dialects")

    total_modules = len(MODULE_DIRS)
    print(f"\nResult: {total_modules - failures}/{total_modules} modules OK")
    return 0 if failures == 0 else 1


# ---------------------------------------------------------------------------
# Subcommand: check-headers
# ---------------------------------------------------------------------------

def cmd_check_headers(args):
    """Validate SQL file headers (title line + references)."""
    min_refs = args.min_refs
    print(f"Checking SQL file headers (min {min_refs} reference(s))...\n")
    failures = 0
    total = 0

    for module in MODULE_DIRS:
        for sql_path in sql_files_in_module(module):
            total += 1
            dialect = sql_path.stem
            content = sql_path.read_text(encoding="utf-8")
            lines = content.split("\n")

            # Check title line: -- Dialect: Topic
            if not lines or not lines[0].strip().startswith("--"):
                error(f"{module}/{dialect}.sql — missing title comment")
                failures += 1
                continue

            title_text = lines[0].strip().lstrip("- ").strip()
            if not title_text:
                error(f"{module}/{dialect}.sql — empty title line")
                failures += 1
                continue

            # Check references
            ref_count = len(re.findall(r'\[\d+\]', content))
            url_count = len(re.findall(r'https?://[^\s)]+', content))

            if ref_count < min_refs:
                error(f"{module}/{dialect}.sql — only {ref_count} reference(s) (min {min_refs})")
                failures += 1
            elif url_count < min_refs:
                error(f"{module}/{dialect}.sql — only {url_count} URL(s) in references")
                failures += 1

    print(f"\nResult: {total - failures}/{total} files OK")
    return 0 if failures == 0 else 1


# ---------------------------------------------------------------------------
# Subcommand: check-comparisons
# ---------------------------------------------------------------------------

def cmd_check_comparisons(_args):
    """Validate _comparison.md presence and basic format."""
    print("Checking _comparison.md files...\n")
    failures = 0

    for module in MODULE_DIRS:
        comp = module_path(module) / "_comparison.md"
        if not comp.exists():
            error(f"{module}/_comparison.md — missing")
            failures += 1
            continue

        content = comp.read_text(encoding="utf-8")
        lines = content.strip().split("\n")

        if len(lines) < 20:
            error(f"{module}/_comparison.md — too short ({len(lines)} lines)")
            failures += 1
            continue

        # Check for required sections
        has_table = "|" in content and "---" in content
        if not has_table:
            error(f"{module}/_comparison.md — no markdown table found")
            failures += 1
            continue

        ok(f"{module}/_comparison.md — {len(lines)} lines")

    total = len(MODULE_DIRS)
    print(f"\nResult: {total - failures}/{total} comparison tables OK")
    return 0 if failures == 0 else 1


# ---------------------------------------------------------------------------
# Subcommand: check-quality
# ---------------------------------------------------------------------------

def cmd_check_quality(args):
    """Check for empty or suspiciously short files."""
    min_lines = args.min_lines
    print(f"Checking file quality (min {min_lines} lines)...\n")
    failures = 0
    total = 0

    for module in MODULE_DIRS:
        for sql_path in sql_files_in_module(module):
            total += 1
            dialect = sql_path.stem
            lines = sql_path.read_text(encoding="utf-8").strip().split("\n")
            line_count = len(lines)

            if line_count < min_lines:
                error(f"{module}/{dialect}.sql — only {line_count} lines (min {min_lines})")
                failures += 1

        # Also check .md files in the module
        for md_path in sorted(module_path(module).glob("*.md")):
            if md_path.name == "_comparison.md":
                continue
            total += 1
            lines = md_path.read_text(encoding="utf-8").strip().split("\n")
            if len(lines) < min_lines:
                error(f"{module}/{md_path.name} — only {len(lines)} lines (min {min_lines})")
                failures += 1

    print(f"\nResult: {total - failures}/{total} files OK")
    return 0 if failures == 0 else 1


# ---------------------------------------------------------------------------
# Subcommand: report
# ---------------------------------------------------------------------------

def cmd_report(_args):
    """Generate a coverage report."""
    print("Repository Coverage Report\n")
    print("=" * 60)

    total_sql = 0
    total_md = 0
    total_comp = 0
    total_lines = 0

    for module in MODULE_DIRS:
        mp = module_path(module)
        sqls = sql_files_in_module(module)
        mds = sorted(mp.glob("*.md")) if mp.is_dir() else []
        comp = mp / "_comparison.md"

        sql_count = len(sqls)
        md_count = len(mds)
        has_comp = comp.exists()
        lines = sum(
            len(s.read_text(encoding="utf-8").split("\n"))
            for s in sqls
        )

        total_sql += sql_count
        total_md += md_count
        total_comp += int(has_comp)
        total_lines += lines

    print(f"\n  Modules:            {len(MODULE_DIRS)}")
    print(f"  Dialects:           {EXPECTED_DIALECT_COUNT}")
    print(f"  SQL files:          {total_sql} (expected {len(MODULE_DIRS) * EXPECTED_DIALECT_COUNT})")
    print(f"  Markdown files:     {total_md}")
    print(f"  Comparison tables:  {total_comp}/{len(MODULE_DIRS)}")
    print(f"  Total SQL lines:    {total_lines:,}")
    print(f"  Expected matrix:    {len(MODULE_DIRS)} × {EXPECTED_DIALECT_COUNT} = {len(MODULE_DIRS) * EXPECTED_DIALECT_COUNT}")
    print()

    # Per-category breakdown
    categories = {}
    for module in MODULE_DIRS:
        cat = module.split("/")[0]
        categories.setdefault(cat, []).append(module)

    print("  Category Breakdown:")
    for cat, modules in sorted(categories.items()):
        sqls = sum(len(sql_files_in_module(m)) for m in modules)
        comps = sum(1 for m in modules if (module_path(m) / "_comparison.md").exists())
        print(f"    {cat:15s}  {len(modules):2d} modules  {sqls:3d} SQL files  {comps}/{len(modules)} comparisons")

    print("\n" + "=" * 60)
    return 0


# ---------------------------------------------------------------------------
# Subcommand: convert
# ---------------------------------------------------------------------------

# The convert functionality is imported from the existing convert.py
# to avoid code duplication.

def _convert_sql_to_md(content: str) -> str:
    """Convert .sql content to .md format. (Simplified version)"""
    # Reuse the full implementation from convert.py
    sys.path.insert(0, str(REPO_ROOT))
    from convert import convert_sql_to_md
    return convert_sql_to_md(content)


def cmd_convert(args):
    """Convert .sql files to .md for specified dialects."""
    if args.dialects:
        dialects = [d.strip() for d in args.dialects.split(",")]
    else:
        from convert import DIALECTS
        dialects = DIALECTS

    print(f"Converting .sql → .md for {len(dialects)} dialect(s): {', '.join(dialects[:5])}...\n")

    sys.path.insert(0, str(REPO_ROOT))
    from convert import convert_sql_to_md, find_sql_files, update_dialect_page

    total_created = 0
    total_skipped = 0
    total_updated = 0

    for dialect in dialects:
        sql_files = find_sql_files(dialect)
        for sql_path in sql_files:
            md_path = sql_path.replace(".sql", ".md")
            if os.path.exists(md_path):
                # Protect manually-written .md files from overwrite
                md_size = os.path.getsize(md_path)
                if md_size > 2000 and not args.force:
                    print(f"  SKIP (exists, {md_size}B, use --force): {md_path}")
                    total_skipped += 1
                    continue
                elif not args.force:
                    continue

            with open(sql_path, "r") as f:
                sql_content = f.read()

            md_content = convert_sql_to_md(sql_content)

            with open(md_path, "w") as f:
                f.write(md_content)

            total_created += 1
            print(f"  Created: {md_path}")

        if update_dialect_page(dialect):
            total_updated += 1

    print(f"\nSummary: Created {total_created} .md files, skipped {total_skipped}, updated {total_updated} dialect pages")
    return 0


# ---------------------------------------------------------------------------
# Subcommand: expand
# ---------------------------------------------------------------------------

def cmd_expand(args):
    """Expand dialect module tables with enriched descriptions."""
    sys.path.insert(0, str(REPO_ROOT))
    from expand_tables import EXPANSIONS

    if args.dialect:
        dialects = [args.dialect]
    else:
        dialects = list(EXPANSIONS.keys())

    print(f"Expanding module tables for {len(dialects)} dialect(s)\n")

    for dialect in dialects:
        if dialect not in EXPANSIONS:
            warn(f"No expansions defined for '{dialect}', skipping")
            continue

        page_path = REPO_ROOT / "dialects" / f"{dialect}.md"
        if not page_path.exists():
            error(f"Dialect page not found: {page_path}")
            continue

        content = page_path.read_text(encoding="utf-8")
        expansions = EXPANSIONS[dialect]
        updated = 0

        for link_fragment, description in expansions.items():
            # Find the row in the table and update description
            pattern = rf'(\|[^|]*\[[^\]]*\]\([^)]*{re.escape(link_fragment)}[^)]*\)[^|]*\|)([^|]*)(\|)'
            match = re.search(pattern, content)
            if match:
                new_row = f"{match.group(1)} {description} {match.group(3)}"
                content = content[:match.start()] + new_row + content[match.end():]
                updated += 1

        if updated > 0:
            page_path.write_text(content, encoding="utf-8")
            ok(f"{dialect}.md — updated {updated} entries")
        else:
            warn(f"{dialect}.md — no matching entries found")

    return 0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Unified CLI tool for sql-dialects repository",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # check
    subparsers.add_parser("check", help="Validate repository structure")

    # check-headers
    p_headers = subparsers.add_parser("check-headers", help="Validate SQL file headers")
    p_headers.add_argument("--min-refs", type=int, default=1, help="Minimum number of references (default: 1)")

    # check-comparisons
    subparsers.add_parser("check-comparisons", help="Validate _comparison.md presence and format")

    # check-quality
    p_quality = subparsers.add_parser("check-quality", help="Check for empty/short files")
    p_quality.add_argument("--min-lines", type=int, default=10, help="Minimum lines per file (default: 10)")

    # report
    subparsers.add_parser("report", help="Generate coverage report")

    # convert
    p_convert = subparsers.add_parser("convert", help="Convert .sql files to .md")
    p_convert.add_argument("--dialects", type=str, default=None, help="Comma-separated dialect list (default: all from convert.py)")
    p_convert.add_argument("--force", action="store_true", help="Overwrite existing .md files (protects manual content by default)")

    # expand
    p_expand = subparsers.add_parser("expand", help="Expand dialect module tables")
    p_expand.add_argument("--dialect", type=str, default=None, help="Single dialect to expand (default: all)")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 1

    commands = {
        "check": cmd_check,
        "check-headers": cmd_check_headers,
        "check-comparisons": cmd_check_comparisons,
        "check-quality": cmd_check_quality,
        "report": cmd_report,
        "convert": cmd_convert,
        "expand": cmd_expand,
    }

    return commands[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
