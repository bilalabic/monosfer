"""Cheatcode-consumption scanner.

A Foundry cheatcode such as `vm.prank` or `vm.expectRevert` applies to the next
*call*. If the very next statement evaluates a contract call while building its
own arguments -- in the argument list, or inside a `{value: ...}` expression --
that nested call is the one the cheatcode lands on, and the call under test runs
unpranked or unguarded. The test then passes for the wrong reason, or fails
mysteriously.

The callee itself is fine; only calls nested inside the argument or value
expressions are traps. That distinction is what this scanner draws.

Inside a `{value: ...}` expression the rule is stricter -- *any* call is
reported, not just an obvious instance call -- because a local helper there can
read a contract just as easily and looks pure while doing it.

It keys on *shape*, not on a list of variable names: any `lowercase.member(`
inside the argument or value expression is treated as a call on a contract
instance. An earlier version carried a hardcoded list of names and went blind the
moment a test introduced one it had never heard of -- which is exactly how the
seventh instance of this bug reached CI.

Excluded, because none of them is an external call the EVM would see:
  * `abi.*`, `type(...)`   -- compiler builtins
  * `vm.*`                 -- cheatcodes do not consume other cheatcodes
  * `Capitalised.*`        -- Solidity convention for libraries and types, whose
                              internal functions compile to jumps, not calls
"""

import io
import re
import glob
import sys

CHEAT = re.compile(r'vm[.]expectRevert|vm[.]expectEmit|vm[.]prank')

# A call on a contract instance: a lowercase-initial identifier, then a member.
INSTANCE_CALL = re.compile(r'\b([a-z_]\w*)\.([A-Za-z_]\w*)\s*\(')
BUILTIN = {'abi', 'vm', 'type', 'super', 'this', 'block', 'msg', 'tx'}

# Test helpers that sign, and therefore read a domain separator from a contract.
HELPER_CALL = re.compile(r'\b(sign[A-Z]\w*)\s*\(')

# Any call at all. Used only inside a `{value: ...}` expression, where the rule
# has to be stricter: that expression is evaluated immediately before the call
# the cheatcode was meant for, and a local helper is no safer there than an
# instance call, because the helper may read a contract itself. The eighth
# instance of this bug was exactly that -- `_roundCost(1)`, a pure-looking
# internal helper that reads two config getters.
ANY_CALL = re.compile(r'\b([A-Za-z_]\w*)\s*\(')
VALUE_SAFE = {'value', 'uint256', 'uint128', 'uint96', 'uint64', 'int256'}

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


def offends(text):
    """Whether `text` contains a nested call a cheatcode would land on."""
    if HELPER_CALL.search(text):
        return True
    for obj, _member in INSTANCE_CALL.findall(text):
        if obj not in BUILTIN:
            return True
    return False


def offends_value(text):
    """Stricter rule for a `{value: ...}` expression: any call is a trap."""
    for name in ANY_CALL.findall(text):
        if name not in VALUE_SAFE and name not in BUILTIN:
            return True
    return False


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
            if offends(args) or offends_value(value_expr):
                hits.append((f, i + 1, st))
    return hits


if __name__ == '__main__':
    found = scan(glob.glob('test/**/*.sol', recursive=True))
    for f, n, st in found:
        print("  %s:%d  %s" % (f, n, st[:96]))
    print("  --- cheatcode tuzagi: %d" % len(found))
    sys.exit(1 if found else 0)
