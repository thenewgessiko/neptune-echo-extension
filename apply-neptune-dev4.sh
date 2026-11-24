#!/usr/bin/env bash
set -e
cd "$(git rev-parse --show-toplevel)"
[ "$(git branch --show-current)" = dev ] || { echo 'Switch to dev first'; exit 1; }
python3 - <<'PY'
from pathlib import Path
p=Path('ext/src/main/java/dev/brahmkshatriya/echo/extension/NeptuneExtension.kt')
s=p.read_text()
def rep(a,b):
 global s
 assert s.count(a)==1,a
 s=s.replace(a,b,1)
rep('import kotlinx.serialization.json.*','import kotlinx.serialization.json.*\nimport dev.brahmkshatriya.echo.common.models.ImageHolder.Companion.toImageHolder')
rep('ExtensionClient, SearchFeedClient, TrackClient {','ExtensionClient, SearchFeedClient, TrackClient, HomeFeedClient, ArtistClient, AlbumClient {')
rep('    private suspend fun catalog(): List<Track> {','''    private fun artistList(value: String) = value.split(',').map { it.trim() }
        .filter { it.isNotBlank() }.map {
            val name = when (it.lowercase(Locale.ROOT)) {
                "thenewgessiko" -> "TheNewGessiko"
                "nayelina" -> "Nayelina"
                "the profh3t" -> "The Profh3t"
                else -> it
            }
            Artist(id = normalize(name), name = name, isRadioSupported = false)
        }.distinctBy { it.id }
    private val mainArtists = artistList("TheNewGessiko,Nayelina")
    private fun ordered(tracks: List<Track>) = tracks.sortedWith(compareBy<Track>(
        { it.albumDiscNumber ?: 1L }, { it.albumOrderNumber ?: Long.MAX_VALUE }, { it.title }))
    private fun albums(tracks: List<Track>) = tracks.filter { it.album != null }
        .groupBy { it.album!!.id }.values.map { group ->
            ordered(group).first().album!!.copy(trackCount = group.size.toLong(),
                duration = group.sumOf { it.duration ?: 0L })
        }.sortedBy { normalize(it.title) }
    private fun shelves(tracks: List<Track>, artists: List<Artist>, releases: List<Album>): List<Shelf> = buildList {
        if (artists.isNotEmpty()) add(Shelf.Lists.Items("artists", "Artists", artists))
        if (releases.isNotEmpty()) add(Shelf.Lists.Items("albums", "Albums", releases))
        if (tracks.isNotEmpty()) add(Shelf.Lists.Tracks("tracks", "Tracks", tracks))
    }
    override suspend fun loadHomeFeed(): Feed<Shelf> = Feed(emptyList()) {
        val tracks = catalog()
        shelves(tracks, mainArtists, albums(tracks)).toFeedData()
    }
    override suspend fun loadArtist(artist: Artist): Artist =
        (mainArtists + catalog().flatMap { it.artists }).firstOrNull { it.id == artist.id } ?: artist
    override suspend fun loadFeed(artist: Artist): Feed<Shelf> = Feed(emptyList()) {
        val tracks = catalog().filter { t -> t.artists.any { it.id == artist.id } ||
            t.album?.artists?.any { it.id == artist.id } == true }
        shelves(tracks, emptyList(), albums(tracks)).toFeedData()
    }
    override suspend fun loadAlbum(album: Album): Album = albums(catalog()).firstOrNull { it.id == album.id }
        ?: error("Album unavailable on Neptune")
    override suspend fun loadTracks(album: Album): Feed<Track> = Feed(emptyList()) {
        ordered(catalog().filter { it.album?.id == album.id }).toFeedData()
    }
    override suspend fun loadFeed(album: Album): Feed<Shelf>? = null

    private suspend fun catalog(): List<Track> {''')
a=s.index("            val artists = artist.split(',')"); b=s.index('            if (artists.isEmpty())',a)
s=s[:a]+'''            val artists = artistList(artist)
            val albumArtists = artistList(field("albumArtist").ifBlank { artist })
            val artwork = field("artwork").takeIf { value ->
                listOf("jpg", "png", "webp").any { value == base + "artwork/$id.$it" }
            }?.toImageHolder()
'''+s[b:]
rep('                album = field("album").takeIf { it.isNotBlank() }?.let { Album(id = "$artist:$it", title = it, artists = artists) },','''                cover = artwork,
                album = field("album").takeIf { it.isNotBlank() }?.let {
                    Album(id = albumArtists.map { a -> a.id }.sorted().joinToString(",") + ":" + normalize(it),
                        title = it, artists = albumArtists, cover = artwork, isRadioSupported = false)
                },
                albumOrderNumber = field("trackNumber").toLongOrNull()?.takeIf { it > 0 },
                albumDiscNumber = field("discNumber").toLongOrNull()?.takeIf { it > 0 },''')
a=s.index('    override suspend fun loadSearchFeed('); b=s.index('    override suspend fun loadTrack(',a)
s=s[:a]+'''    override suspend fun loadSearchFeed(query: String): Feed<Shelf> = Feed(listOf(
        Tab("TRACKS", "Tracks"), Tab("ALL", "All"), Tab("ALBUMS", "Albums"), Tab("ARTISTS", "Artists")
    )) { tab ->
        val terms = normalize(query).split(' ').filter { it.isNotBlank() }
        fun matches(value: String) = terms.isNotEmpty() && terms.all { it in normalize(value) }
        val all = catalog()
        val tracks = all.filter { t -> matches(t.title + " " + t.artists.joinToString(" ") { it.name } + " " + t.album?.title.orEmpty() + " " + t.id) }
        val releases = albums(all).filter { a -> matches(a.title + " " + a.artists.joinToString(" ") { it.name }) }
        val artists = mainArtists.filter { matches(it.name) }
        when (tab?.id) {
            "ALL" -> shelves(tracks, artists, releases)
            "ALBUMS" -> shelves(emptyList(), emptyList(), releases)
            "ARTISTS" -> shelves(emptyList(), artists, emptyList())
            else -> shelves(tracks, emptyList(), emptyList())
        }.toFeedData()
    }

'''+s[b:]
versions={}
for name in ['app/build.gradle.kts','ext/build.gradle.kts']:
 f=Path(name); t=f.read_text(); assert 'val verName = "0.1.0-DEV.3"' in t
 versions[f]=t.replace('val verName = "0.1.0-DEV.3"','val verName = "0.1.0-DEV.4"')
p.write_text(s)
for f,t in versions.items(): f.write_text(t)
print('Neptune DEV.4 patch applied')
PY
