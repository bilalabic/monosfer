"""Cheatcode-consumption scanner.

A Foundry cheatcode such as `vm.prank` or `vm.expectRevert` applies to the next
*call*. If the very next statement evaluates a view call while building its own
arguments -- in the argument list, or inside a `{value: ...}` expression -- that
view call is the one the cheatcode lands on, and the call under test runs
unpranked or unguarded. The test then passes for the wrong reason, or fails
mysteriously.

The callee itself is fine; only calls nested inside the argument or value
expressions are traps. That distinction is what this scanner draws.
"""

import io
import re
import glob
import sys

# `startPrank` is persistent: a view call cannot consume it, so it is not a
# trap. Only the single-shot cheatcodes are.
CHEAT = re.compile(r'vm[.]expectRevert|vm[.]expectEmit|vm[.]prank')
TARGET = re.compile(r'\b(hub|config|registry|vault|manager|rep|reputation)\.[A-Za-z_]\w*\(')
SIGN = re.compile(r'\b(signQuote|signQuoteAs|signAttestation|signAttestationAs|signAcceptance)\(')

# Assignment / return / try prefixes that sit in front of the actual call.
PREFIX = re.compile(
    r'^(?:'
    r'(?:[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\s+(?:memory|storage|calldata)?\s*)?[A-Za-z_]\w*\s*=\s*'
    r'|return\s+'
    r'|try\s+'
    r'|\(\s*[^)]*\)\s*=\s*'
    r')'
)
CALLEE = re.compile(r'^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\s*(\{[^}]*\})?\s*\(')


def split_call(stmt):
    """Return (value_expression, argument_text) for the statement's outer call."""
    body = stmt
    for _ in range(3):
        m = PREFIX.match(body)
        if not m:
            break
        body = body[m.end():]
    m = CALLEE.match(body)
    if not m:
        return '', ''
    return (m.group(1) or ''), body[m.end() - 1:]


def scan(paths):
    hits = []
    for f in sorted(paths):
        lines = io.open(f, encoding='utf-8').read().split('\n')
        armed = False
        for i, raw in enumerate(lines):
            st = raw.strip()
            if CHEAT.search(st):
                armed = True
                continue
            if not armed:
                continue
            if st == '' or st.startswith(('//', '*', '/*')):
                continue
            armed = False
            value_expr, args = split_call(st)
            if not args and not value_expr:
                continue
            if TARGET.search(args) or SIGN.search(args) or TARGET.search(value_expr):
                hits.append((f, i + 1, st))
    return hits


if __name__ == '__main__':
    found = scan(glob.glob('test/**/*.sol', recursive=True))
    for f, n, st in found:
        print("  %s:%d  %s" % (f, n, st[:96]))
    print("  --- cheatcode tuzagi: %d" % len(found))
    sys.exit(1 if found else 0)
