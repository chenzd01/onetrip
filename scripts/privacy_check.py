#!/usr/bin/env python3
"""Scan the repository for secrets and private data before making it public.

Checks every file git would publish (tracked + untracked, not ignored) and, with
--history, every blob in every commit. Two kinds of rules:
  * built-in patterns: private keys, common API tokens, absolute home paths,
    public IPv4 addresses, e-mail addresses, oversized files (1 MB; 3 MB under docs/assets/);
  * your own denylist: one regex per line in .privacy-denylist (git-ignored, since
    it contains the very strings you want to keep out: names, domains, IDs…).
Exit code 1 if anything is found. Standard library only.
"""
import argparse, ipaddress, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILTIN = {
    'private key': re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
    'GitHub token': re.compile(r'\bgh[pousr]_[A-Za-z0-9]{30,}\b'),
    'AWS key': re.compile(r'\bAKIA[0-9A-Z]{16}\b'),
    'Slack/OpenAI/Anthropic-style key': re.compile(r'\b(xox[abprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{20,})\b'),
    'home path': re.compile(r'(/Users/|/home/)(?!runner/|example/|you/|<)[A-Za-z0-9._-]+/'),
    'email': re.compile(r'\b[A-Za-z0-9._%+-]+@(?!example\.(com|org)\b)(?!users\.noreply\.github\.com\b)(?!anthropic\.com\b)[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'),
}
IPV4 = re.compile(r'\b(?:\d{1,3}\.){3}\d{1,3}\b')
MAX_BYTES = 1_000_000
MEDIA_MAX_BYTES = 3_000_000  # README screenshots and the demo animation (docs/assets/)


def denylist(path):
    if not path.exists(): return []
    rules = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#'): rules.append(re.compile(line, re.I))
    return rules


def public_ip(text):
    for match in IPV4.findall(text):
        try:
            ip = ipaddress.ip_address(match)
        except ValueError:
            continue
        if ip.is_global and not match.startswith(('0.', '1.0.', '2.0.')): yield match


def scan_text(label, text, rules):
    hits = []
    for name, pattern in BUILTIN.items():
        for m in pattern.finditer(text):
            # Reserved example domains (RFC 2606) are used by tests and docs on purpose.
            if name == 'email' and re.search(r'\.(example|test|invalid)$', m.group(0), re.I): continue
            hits.append((label, name, m.group(0)))
    for ip in public_ip(text): hits.append((label, 'public IPv4', ip))
    for rule in rules:
        for m in rule.finditer(text): hits.append((label, 'denylist', m.group(0)))
    return hits


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, check=True, capture_output=True).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--history', action='store_true', help='also scan every blob in git history')
    parser.add_argument('--denylist', type=Path, default=ROOT / '.privacy-denylist')
    args = parser.parse_args()
    rules = denylist(args.denylist)
    if not rules: print('note: no .privacy-denylist found; only built-in patterns are checked')
    hits = []
    files = git('ls-files', '-z', '--cached', '--others', '--exclude-standard').decode().split('\0')
    for name in filter(None, files):
        path = ROOT / name
        if not path.is_file(): continue
        hits += scan_text(name, name, rules)  # file names can leak too
        limit = MEDIA_MAX_BYTES if name.startswith('docs/assets/') else MAX_BYTES
        if path.stat().st_size > limit: hits.append((name, 'large file', f'{path.stat().st_size} bytes'))
        data = path.read_bytes()
        if b'\0' in data[:4096]: continue
        hits += scan_text(name, data.decode('utf-8', 'replace'), rules)
    if args.history:
        seen = set()
        for line in git('rev-list', '--objects', '--all').decode().splitlines():
            sha, _, name = line.partition(' ')
            if not name or sha in seen: continue
            seen.add(sha)
            if git('cat-file', '-t', sha).strip() != b'blob': continue
            data = git('cat-file', '-p', sha)
            if b'\0' in data[:4096]: continue
            hits += scan_text(f'history:{name}@{sha[:8]}', data.decode('utf-8', 'replace'), rules)
        # Author and committer can differ (rebases, amends); both end up public.
        for message in git('log', '--all', '--format=%H %an <%ae> %cn <%ce>%n%B').decode().split('\n'):
            hits += scan_text('commit message/author/committer', message, rules)
    for label, kind, value in sorted(set(hits)):
        print(f'{kind:>12}  {label}: {value[:120]}')
    print(('FAIL' if hits else 'PASS') + f': {len(set(hits))} finding(s)')
    return 1 if hits else 0


if __name__ == '__main__':
    sys.exit(main())
