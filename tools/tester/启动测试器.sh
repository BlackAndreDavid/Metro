#!/usr/bin/env sh
cd "$(dirname "$0")/../.." || exit 1
if [ -x .venv-editor/bin/python ]; then exec .venv-editor/bin/python tools/tester/desktop.py; fi
if [ -x .venv/bin/python ]; then exec .venv/bin/python tools/tester/desktop.py; fi
exec python3 tools/tester/desktop.py
