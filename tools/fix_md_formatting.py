#!/usr/bin/env python3
"""Fix Markdown formatting issues. CONSERVATIVE: only does safe text replacements,
never adds/removes code block fences (```).

Fixes:
1. ### N. text → N. text (headings misused as numbered list items)
2. YYYY: text → - **YYYY**: text (bare year lines)
"""

import re
import os
import sys


def fix_file(path, dry_run=False):
    with open(path) as f:
        content = f.read()

    original = content
    lines = content.split('\n')
    result = []
    in_code = False

    for line in lines:
        stripped = line.strip()

        # Track code block state
        if stripped.startswith('```'):
            in_code = not in_code
            result.append(line)
            continue

        if in_code:
            result.append(line)
            continue

        # Fix 1: ### N. text → N. text (but NOT ### N.N patterns like ### 3.1)
        m = re.match(r'^### (\d+)\.\s+(.*)', line)
        if m:
            num = m.group(1)
            text = m.group(2)
            # Keep legitimate sub-section headings like "### 3.1 Title"
            if re.match(r'^\d+\.\d+', text):
                result.append(line)
            else:
                result.append(f'{num}. {text}')
            continue

        # Fix 2: Year lines at start: "2016: text" → "- **2016**: text"
        m = re.match(r'^((?:19|20)\d{2}):\s+(.*)', line)
        if m:
            year = m.group(1)
            text = m.group(2)
            result.append(f'- **{year}**: {text}')
            continue

        result.append(line)

    new_content = '\n'.join(result)

    if new_content != original:
        if not dry_run:
            with open(path, 'w') as f:
                f.write(new_content)
        return True
    return False


def main():
    dry_run = '--dry-run' in sys.argv
    verbose = '--verbose' in sys.argv or '-v' in sys.argv

    changed = 0
    total = 0

    for root, dirs, files in os.walk('.'):
        if '.git' in root:
            continue
        for f in files:
            if not f.endswith('.md'):
                continue
            path = os.path.join(root, f)
            total += 1
            if fix_file(path, dry_run):
                changed += 1
                if verbose:
                    print(f'  {"[DRY] " if dry_run else ""}Fixed: {path}')

    print(f'\n{"[DRY RUN] " if dry_run else ""}Fixed {changed}/{total} files')


if __name__ == '__main__':
    main()
