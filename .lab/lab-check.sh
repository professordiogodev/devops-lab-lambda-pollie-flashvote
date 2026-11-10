#!/usr/bin/env bash
rc=0
python3 -m py_compile handler.py 2>/dev/null && echo "- ✅ handler.py compiles" || { echo "- ❌ handler.py does not compile"; rc=1; }
grep -q 'NotImplementedError' handler.py && { echo "- ❌ handler.py still contains the starter NotImplementedError"; rc=1; } || echo "- ✅ handler.py is no longer the starter"
grep -q 'update_item' handler.py && echo "- ✅ handler.py updates the counter with update_item" || { echo "- ❌ handler.py must count votes with one atomic update_item call"; rc=1; }
if (python3 -m pip install -q -r tests/requirements.txt >/dev/null 2>&1 && python3 -m pytest -q tests >/dev/null 2>&1); then echo "- ✅ the local tests pass"; else echo "- ❌ the local tests fail (python3 -m pytest -q)"; rc=1; fi
grep -qE '^ALL CHECKS PASSED \(' SUBMISSION.md && echo "- ✅ SUBMISSION.md shows ALL CHECKS PASSED" || { echo "- ❌ paste the verify.sh output ('ALL CHECKS PASSED') into SUBMISSION.md"; rc=1; }
grep -rEq 'AKIA[0-9A-Z]{16}' . --exclude-dir=.git --exclude=verify.sh && { echo "- ❌ an AWS access key is committed"; rc=1; } || echo "- ✅ no AWS access key committed"
exit $rc
