#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
[ "$(git branch --show-current)" = dev ] || { echo 'Switch to dev first'; exit 1; }
python3 - <<'PY'
from pathlib import Path
p=Path('ext/src/main/java/dev/brahmkshatriya/echo/extension/NeptuneExtension.kt')
s=p.read_text()
def rep(a,b):
 global s
 assert s.count(a)==1, 'Unexpected source: '+a
 s=s.replace(a,b,1)
rep('Artist(id = normalize(name), name = name, isRadioSupported = false)', '''Artist(id = normalize(name), name = name,
                cover = when (normalize(name)) {
                    "thenewgessiko", "nayelina" -> (root + "artists/" + normalize(name) + ".jpg").toImageHolder(crop = true)
                    else -> null
                }, isRadioSupported = false)''')
rep('ordered(group).first().album!!.copy(trackCount = group.size.toLong(),','''ordered(group).first().album!!.copy(trackCount = group.size.toLong(),
                type = when (group.size) {
                    1 -> Album.Type.Single
                    in 2..5 -> Album.Type.EP
                    else -> Album.Type.LP
                },''')
rep('        if (releases.isNotEmpty()) add(Shelf.Lists.Items("albums", "Albums", releases))','''        for ((type, title) in listOf(Album.Type.Single to "Singles", Album.Type.EP to "EPs", Album.Type.LP to "Albums")) {
            val items = releases.filter { it.type == type }
            if (items.isNotEmpty()) add(Shelf.Lists.Items(title.lowercase(Locale.ROOT), title, items))
        }''')
rep('        val tracks = catalog().filter { t -> t.artists.any { it.id == artist.id } ||\n            t.album?.artists?.any { it.id == artist.id } == true }\n        shelves(tracks, emptyList(), albums(tracks)).toFeedData()', '''        val all = catalog()
        val tracks = all.filter { t -> t.artists.any { it.id == artist.id } ||
            t.album?.artists?.any { it.id == artist.id } == true }
        val ids = tracks.mapNotNull { it.album?.id }.toSet()
        shelves(tracks, emptyList(), albums(all).filter { it.id in ids }).toFeedData()''')
rep('        return Json.parseToJsonElement(body).jsonArray.mapNotNull { item ->','        val tracks = Json.parseToJsonElement(body).jsonArray.mapNotNull { item ->')
rep('        }\n    }\n\n    override suspend fun loadSearchFeed','''        }
        val releases = albums(tracks).associateBy { it.id }
        return tracks.map { it.copy(album = it.album?.let { a -> releases[a.id] ?: a }) }
    }

    override suspend fun loadSearchFeed''')
rep('Tab("TRACKS", "Tracks"), Tab("ALL", "All"), Tab("ALBUMS", "Albums"), Tab("ARTISTS", "Artists")','Tab("TRACKS", "Tracks"), Tab("ALL", "All"), Tab("SINGLES", "Singles"), Tab("EPS", "EPs"), Tab("ALBUMS", "Albums"), Tab("ARTISTS", "Artists")')
rep('"ALBUMS" -> shelves(emptyList(), emptyList(), releases)','''"SINGLES" -> shelves(emptyList(), emptyList(), releases.filter { it.type == Album.Type.Single })
            "EPS" -> shelves(emptyList(), emptyList(), releases.filter { it.type == Album.Type.EP })
            "ALBUMS" -> shelves(emptyList(), emptyList(), releases.filter { it.type == Album.Type.LP })''')
updates={p:s}
for f in ['app/build.gradle.kts','ext/build.gradle.kts']:
 q=Path(f); v=q.read_text(); assert v.count('val verName = "0.1.0-DEV.4"')==1; updates[q]=v.replace('val verName = "0.1.0-DEV.4"','val verName = "0.1.0-DEV.5"')
q=Path('.github/workflows/neptune-dev.yml'); v=q.read_text(); assert v.count('0.1.0-DEV.3')==3
v=v.replace('      - run: |\n          mkdir -p artifacts','''      - name: Resolve version
        id: version
        run: |
          VERSION=$(sed -n 's/^val verName = "\\([^"]*\\)"$/\\1/p' ext/build.gradle.kts)
          APP_VERSION=$(sed -n 's/^val verName = "\\([^"]*\\)"$/\\1/p' app/build.gradle.kts)
          test -n "$VERSION" && test "$VERSION" = "$APP_VERSION"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
      - run: |
          mkdir -p artifacts''')
v=v.replace('0.1.0-DEV.3','${{ steps.version.outputs.version }}'); updates[q]=v
for q,v in updates.items(): q.write_text(v)
print('Neptune DEV.5 patch applied')
PY
