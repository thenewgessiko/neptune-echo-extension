#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
python3 - <<'PATCH'
from pathlib import Path
p=Path('ext/src/main/java/dev/brahmkshatriya/echo/extension/NeptuneExtension.kt')
changes={p:[('Attiva Prossime Release / Spoiler','Enable Upcoming Releases / Spoilers'),('Mostra e riproduci Upcoming Releases e Spoilers','Show and play upcoming releases and spoilers')]}
for name in ('app/build.gradle.kts','ext/build.gradle.kts'):
    changes[Path(name)]=[('val verName = "0.1.0-DEV.6"','val verName = "0.1.0-DEV.7"')]
outputs={}
for path,replacements in changes.items():
    s=path.read_text()
    for old,new in replacements:
        if s.count(old)==1 and new not in s:
            s=s.replace(old,new,1)
        elif old not in s and s.count(new)==1:
            pass
        else:
            raise SystemExit(f'Unexpected source: {path}: {old}')
    outputs[path]=s
for path,s in outputs.items():
    path.write_text(s)
print('Neptune DEV.7 localization applied.')
PATCH
