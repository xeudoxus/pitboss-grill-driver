#!/usr/bin/env python3
"""
Small markdown link and anchor checker.
Scans the workspace for .md files, computes simple GitHub-style anchors from headers,
and validates all non-image links of the form [text](path/to/file.md#anchor).

Outputs a short report to stdout.
"""
import os, re, sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]

md_files = list(root.rglob('*.md'))

header_re = re.compile(r'^(#{1,6})\s*(.+)$')
link_re = re.compile(r'(?<!\!)\[[^\]]+\]\(([^)]+)\)')

def slugify(header: str) -> str:
    s = header.strip().lower()
    # remove markdown formatting like `code`
    s = re.sub(r'`+', '', s)
    # remove punctuation except spaces and hyphens
    s = re.sub(r"[^a-z0-9 \-]", '', s)
    s = re.sub(r'\s+', '-', s)
    s = re.sub(r'-+', '-', s)
    s = s.strip('-')
    return s

# Collect anchors per file
anchors = {}
for md in md_files:
    rel = md.relative_to(root)
    anchors[str(rel).replace('\\','/')] = set()
    try:
        text = md.read_text(encoding='utf-8')
    except Exception:
        continue
    for line in text.splitlines():
        m = header_re.match(line)
        if m:
            hdr = m.group(2).strip()
            anchors[str(rel).replace('\\','/')].add(slugify(hdr))

# Check links
problems = []
checked = []
for md in md_files:
    rel = md.relative_to(root)
    rel_str = str(rel).replace('\\','/')
    try:
        text = md.read_text(encoding='utf-8')
    except Exception:
        continue
    for m in link_re.finditer(text):
        target = m.group(1).strip()
        # skip mailto or http(s) links
        if target.startswith('http://') or target.startswith('https://') or target.startswith('mailto:'):
            continue
        # split anchor
        if '#' in target:
            path_part, frag = target.split('#',1)
            frag = frag.strip()
        else:
            path_part, frag = target, None
        # resolve relative path
        src_dir = md.parent
        path_resolved = (src_dir / path_part).resolve() if path_part else (src_dir / '')
        try:
            path_resolved.relative_to(root)
            rel_target = str(path_resolved.relative_to(root)).replace('\\','/')
        except Exception:
            # outside workspace or bad path
            rel_target = None
        status = 'OK'
        notes = []
        if path_part and (not path_resolved.exists()):
            status = 'MISSING_FILE'
            notes.append(f'File not found: {path_part}')
        else:
            if frag:
                # normalize frag to slug
                frag_slug = slugify(frag)
                # if path_part empty, it's same file
                tgt = rel_target if rel_target else rel_str
                anchors_set = anchors.get(tgt, set())
                if frag_slug not in anchors_set:
                    status = 'MISSING_ANCHOR'
                    notes.append(f'Anchor not found: {frag} -> slug {frag_slug}')
        checked.append((rel_str, m.group(0), target, status, notes))

# Print report
print('\nMarkdown Link Check Report')
print('Workspace root:', root)
print('Files scanned:', len(md_files))
print('Links checked:', len(checked))
print('')

failures = [c for c in checked if c[3] != 'OK']
if not failures:
    print('All checked non-image links and anchors are OK.')
    sys.exit(0)

print('Problems found:')
for src, markup, target, status, notes in failures:
    print(f'- Source: {src}')
    print(f'  Link: {markup}')
    print(f'  Target: {target}')
    print(f'  Status: {status}')
    for n in notes:
        print(f'    - {n}')
    print('')

sys.exit(2)
