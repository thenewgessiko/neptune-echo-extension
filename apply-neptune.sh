#!/usr/bin/env bash
set -e
cd "$(git rev-parse --show-toplevel)"
[ "$(git branch --show-current)" = dev ] || { echo 'Switch to dev first'; exit 1; }
p=ext/src/main/java/dev/brahmkshatriya/echo/extension
mv "$p/TestExtension.kt" "$p/NeptuneExtension.kt"
sed -i 's/^extId=.*/extId=neptune/;s/^extClass=.*/extClass=NeptuneExtension/;s/^extName=.*/extName=Neptune/;s/^extDescription=.*/extDescription=Original FLAC audio provider for Echo/;s/^extAuthor=.*/extAuthor=TheNewGessiko/;s|^extRepoUrl=.*|extRepoUrl=https://github.com/thenewgessiko/neptune-echo-extension|' gradle.properties
for f in app/build.gradle.kts ext/build.gradle.kts; do sed -i 's/val verName = "v\$gitHash"/val verName = "0.1.0-DEV.1"/' "$f"; done
sed -i 's/TestExtension()/NeptuneExtension()/;s/"Skrillex"/"Nothing After You"/' ext/src/test/java/dev/brahmkshatriya/echo/extension/ExtensionUnitTest.kt
