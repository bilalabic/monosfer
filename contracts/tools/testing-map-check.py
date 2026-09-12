"""Check that docs/testing.md names tests that actually exist.

The map is only worth reading if every name in it resolves. A renamed or deleted
test leaves a line that still *reads* like coverage, which is the exact failure
this repository keeps finding in its own work: a claim that looks verified and
is not. So the claim is checked mechanically rather than trusted.

Run from `contracts/`. Exits non-zero on the first name that does not resolve.
"""

import glob
import io
import re
import sys

CITED = re.compile(r'`((?:test|testFuzz|invariant)_\w+)`')
DEFINED = re.compile(r'function ((?:test|testFuzz|invariant)_\w+)')


def main():
    doc_path = 'docs/testing.md'
    try:
        doc = io.open(doc_path, encoding='utf-8').read()
    except OSError:
        print("  %s okunamadi -- contracts/ icinden calistirin" % doc_path)
        return 1

    cited = set(CITED.findall(doc))
    if not cited:
        print("  haritada hic test adi yok; dosya bozulmus olabilir")
        return 1

    defined = set()
    for path in glob.glob('test/**/*.sol', recursive=True):
        defined |= set(DEFINED.findall(io.open(path, encoding='utf-8').read()))

    missing = sorted(cited - defined)
    for name in missing:
        print("  haritada var, suite'te yok: %s" % name)
    print("  --- testing.md: %d ad, %d cozulmeyen" % (len(cited), len(missing)))
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
