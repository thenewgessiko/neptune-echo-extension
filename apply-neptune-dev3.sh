#!/usr/bin/env bash
set -e
cd "$(git rev-parse --show-toplevel)"
[ "$(git branch --show-current)" = dev ] || { echo 'Switch to dev first'; exit 1; }
for f in app/build.gradle.kts ext/build.gradle.kts; do
  sed -i 's/val verName = "0.1.0-DEV.2"/val verName = "0.1.0-DEV.3"/' "$f"
  grep -Fq 'val verName = "0.1.0-DEV.3"' "$f"
done
sed -i 's/^extDescription=.*/extDescription=FLAC and MP3 audio provider for Echo/' gradle.properties
