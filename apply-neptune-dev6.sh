#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
p=Path('ext/src/main/java/dev/brahmkshatriya/echo/extension/NeptuneExtension.kt')
s=p.read_text()
def replace(a,b):
 global s
 if s.count(a)!=1: raise SystemExit('Unexpected DEV.5 source: '+a[:90])
 s=s.replace(a,b,1)
replace('import dev.brahmkshatriya.echo.common.settings.Settings','import dev.brahmkshatriya.echo.common.settings.Settings\nimport dev.brahmkshatriya.echo.common.settings.SettingSwitch\nimport kotlinx.coroutines.CancellationException')
replace('override fun setSettings(settings: Settings) {}\n    override suspend fun getSettingItems(): List<Setting> = emptyList()', '''private var preferences: Settings? = null
    private fun previewsEnabled() = preferences?.getBoolean("show_previews") == true
    override fun setSettings(settings: Settings) { preferences = settings }
    override suspend fun getSettingItems(): List<Setting> = listOf(
        SettingSwitch(title = "Attiva Prossime Release / Spoiler", key = "show_previews",
            summary = "Mostra e riproduci Upcoming Releases e Spoilers", defaultValue = false)
    )
    private fun previewUrl(url: String) = Regex(root.replace(".", "\\\\.") +
        "(upcoming|spoilers)/([a-z0-9-]+\\\\.flac|mpeg(320|128)/[a-z0-9-]+\\\\.mp3)").matches(url)
    private fun previewId(id: String) = id.startsWith("upcoming-") || id.startsWith("spoilers-")
    private suspend fun previewTracks(category: String): List<Track> {
        if (!previewsEnabled()) return emptyList()
        return try { catalog(category) } catch (e: CancellationException) { throw e }
        catch (e: Exception) { emptyList() }
    }
    private suspend fun allTracks() = catalog() + previewTracks("upcoming") + previewTracks("spoilers")
    private suspend fun previewShelves(artistId: String? = null): List<Shelf> = buildList {
        for ((category, prefix) in listOf("upcoming" to "Upcoming", "spoilers" to "Spoiler")) {
            val all = previewTracks(category)
            val ids = all.filter { t -> artistId == null || t.artists.any { it.id == artistId } ||
                t.album?.artists?.any { it.id == artistId } == true }.mapNotNull { it.album?.id }.toSet()
            val releases = albums(all).filter { it.id in ids }
            for ((type, label) in listOf(Album.Type.Single to "Singles", Album.Type.EP to "EPs", Album.Type.LP to "Albums")) {
                val items = releases.filter { it.type == type }
                if (items.isNotEmpty()) add(Shelf.Lists.Items("$category-$label", "$prefix $label", items))
            }
        }
    }''')
replace('shelves(tracks, mainArtists, albums(tracks)).toFeedData()', '(shelves(tracks, mainArtists, albums(tracks)) + previewShelves()).toFeedData()')
replace('shelves(tracks, emptyList(), albums(all).filter { it.id in ids }).toFeedData()', '(shelves(tracks, emptyList(), albums(all).filter { it.id in ids }) + previewShelves(artist.id)).toFeedData()')
replace('albums(catalog()).firstOrNull { it.id == album.id }','albums(if (previewId(album.id)) allTracks() else catalog()).firstOrNull { it.id == album.id }')
replace('ordered(catalog().filter { it.album?.id == album.id })','ordered((if (previewId(album.id)) allTracks() else catalog()).filter { it.album?.id == album.id })')
replace('private suspend fun catalog(): List<Track> {\n        val request = Request.Builder().url(base + "catalog.json")','private suspend fun catalog(category: String = "flac"): List<Track> {\n        val official = category == "flac"\n        val base = root + category + "/"\n        val request = Request.Builder().url(base + "catalog.json")')
replace('val id = field("isrc")','val id = field(if (official) "isrc" else "id")')
start=s.index('            if (!id.matches('); end=s.index('\n',start)
s=s[:start]+'''            if (title.isBlank() || artist.isBlank()) return@mapNotNull null
            if (official) {
                if (!id.matches(Regex("[A-Z]{2}[A-Z0-9]{3}[0-9]{7}")) || url != base + id + ".flac") return@mapNotNull null
            } else {
                if (!id.matches(Regex("$category-[a-f0-9]{64}")) ||
                    !field("releaseId").matches(Regex("$category-[a-f0-9]{64}")) ||
                    field("category") != category || field("playable") != "true" ||
                    !previewUrl(url) || !url.startsWith(base) || !url.endsWith(".flac")) return@mapNotNull null
            }'''+s[end:]
replace('if (mp3 == root + "mpeg$bitrate/$id.mp3") {','if (mp3 == (if (official) root + "mpeg$bitrate/$id.mp3" else\n                    base + "mpeg$bitrate/" + url.substringAfterLast(\'/\').removeSuffix(".flac") + ".mp3")) {')
replace('Album(id = albumArtists.map { a -> a.id }.sorted().joinToString(",") + ":" + normalize(it),','Album(id = if (official) albumArtists.map { a -> a.id }.sorted().joinToString(",") + ":" + normalize(it) else field("releaseId"),')
replace('isrc = id,','isrc = if (official) id else null,')
replace('catalog().firstOrNull { it.id == track.id }','(if (previewId(track.id)) allTracks() else catalog()).firstOrNull { it.id == track.id }')
replace('check(validUrl(url))','check(validUrl(url) || (previewsEnabled() && previewUrl(url)))')
paths=[Path('app/build.gradle.kts'),Path('ext/build.gradle.kts')]
versions=[]
for f in paths:
 v=f.read_text()
 if v.count('0.1.0-DEV.5')!=1: raise SystemExit('Unexpected version: '+str(f))
 versions.append(v.replace('0.1.0-DEV.5','0.1.0-DEV.6'))
p.write_text(s)
for f,v in zip(paths,versions): f.write_text(v)
print('Neptune DEV.6 patch applied')
PY
