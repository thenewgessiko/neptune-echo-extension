package dev.brahmkshatriya.echo.extension

import dev.brahmkshatriya.echo.common.clients.*
import dev.brahmkshatriya.echo.common.helpers.ContinuationCallback.Companion.await
import dev.brahmkshatriya.echo.common.models.*
import dev.brahmkshatriya.echo.common.models.Feed.Companion.toFeedData
import dev.brahmkshatriya.echo.common.models.Streamable.Companion.server
import dev.brahmkshatriya.echo.common.models.Streamable.Media.Companion.toServerMedia
import dev.brahmkshatriya.echo.common.settings.Setting
import dev.brahmkshatriya.echo.common.settings.Settings
import dev.brahmkshatriya.echo.common.settings.SettingSwitch
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.*
import dev.brahmkshatriya.echo.common.models.ImageHolder.Companion.toImageHolder
import okhttp3.OkHttpClient
import okhttp3.Request
import java.text.Normalizer
import java.util.Locale

class NeptuneExtension : ExtensionClient, SearchFeedClient, TrackClient, HomeFeedClient, ArtistClient, AlbumClient {
    private val http = OkHttpClient()
    private val root = "https://thenewgessiko.duckdns.org/"
    private val base = root + "flac/"
    private fun validUrl(url: String) = Regex("https://thenewgessiko\\.duckdns\\.org/(flac/[A-Z]{2}[A-Z0-9]{3}[0-9]{7}\\.flac|mpeg(320|128)/[A-Z]{2}[A-Z0-9]{3}[0-9]{7}\\.mp3)").matches(url)
    private var preferences: Settings? = null
    private fun previewsEnabled() = preferences?.getBoolean("show_previews") == true
    override fun setSettings(settings: Settings) { preferences = settings }
    override suspend fun getSettingItems(): List<Setting> = listOf(
        SettingSwitch(title = "Attiva Prossime Release / Spoiler", key = "show_previews",
            summary = "Mostra e riproduci Upcoming Releases e Spoilers", defaultValue = false)
    )
    private fun previewUrl(url: String) = Regex(root.replace(".", "\\.") +
        "(upcoming|spoilers)/([a-z0-9-]+\\.flac|mpeg(320|128)/[a-z0-9-]+\\.mp3)").matches(url)
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
    }
    override suspend fun onInitialize() {}

    private fun normalize(s: String) = Normalizer.normalize(s, Normalizer.Form.NFKD)
        .lowercase(Locale.ROOT).replace(Regex("\\p{M}+"), "")
        .replace(Regex("['’]"), "").replace(Regex("[^\\p{L}\\p{N}]+"), " ").trim()

    private fun artistList(value: String) = value.split(',').map { it.trim() }
        .filter { it.isNotBlank() }.map {
            val name = when (it.lowercase(Locale.ROOT)) {
                "thenewgessiko" -> "TheNewGessiko"
                "nayelina" -> "Nayelina"
                "the profh3t" -> "The Profh3t"
                else -> it
            }
            Artist(id = normalize(name), name = name,
                cover = when (normalize(name)) {
                    "thenewgessiko", "nayelina" -> (root + "artists/" + normalize(name) + ".jpg").toImageHolder(crop = true)
                    else -> null
                }, isRadioSupported = false)
        }.distinctBy { it.id }
    private val mainArtists = artistList("TheNewGessiko,Nayelina")
    private fun ordered(tracks: List<Track>) = tracks.sortedWith(compareBy<Track>(
        { it.albumDiscNumber ?: 1L }, { it.albumOrderNumber ?: Long.MAX_VALUE }, { it.title }))
    private fun albums(tracks: List<Track>) = tracks.filter { it.album != null }
        .groupBy { it.album!!.id }.values.map { group ->
            ordered(group).first().album!!.copy(trackCount = group.size.toLong(),
                type = when (group.size) {
                    1 -> Album.Type.Single
                    in 2..5 -> Album.Type.EP
                    else -> Album.Type.LP
                },
                duration = group.sumOf { it.duration ?: 0L })
        }.sortedBy { normalize(it.title) }
    private fun shelves(tracks: List<Track>, artists: List<Artist>, releases: List<Album>): List<Shelf> = buildList {
        if (artists.isNotEmpty()) add(Shelf.Lists.Items("artists", "Artists", artists))
        for ((type, title) in listOf(Album.Type.Single to "Singles", Album.Type.EP to "EPs", Album.Type.LP to "Albums")) {
            val items = releases.filter { it.type == type }
            if (items.isNotEmpty()) add(Shelf.Lists.Items(title.lowercase(Locale.ROOT), title, items))
        }
        if (tracks.isNotEmpty()) add(Shelf.Lists.Tracks("tracks", "Tracks", tracks))
    }
    override suspend fun loadHomeFeed(): Feed<Shelf> = Feed(emptyList()) {
        val tracks = catalog()
        (shelves(tracks, mainArtists, albums(tracks)) + previewShelves()).toFeedData()
    }
    override suspend fun loadArtist(artist: Artist): Artist =
        (mainArtists + catalog().flatMap { it.artists }).firstOrNull { it.id == artist.id } ?: artist
    override suspend fun loadFeed(artist: Artist): Feed<Shelf> = Feed(emptyList()) {
        val all = catalog()
        val tracks = all.filter { t -> t.artists.any { it.id == artist.id } ||
            t.album?.artists?.any { it.id == artist.id } == true }
        val ids = tracks.mapNotNull { it.album?.id }.toSet()
        (shelves(tracks, emptyList(), albums(all).filter { it.id in ids }) + previewShelves(artist.id)).toFeedData()
    }
    override suspend fun loadAlbum(album: Album): Album = albums(if (previewId(album.id)) allTracks() else catalog()).firstOrNull { it.id == album.id }
        ?: error("Album unavailable on Neptune")
    override suspend fun loadTracks(album: Album): Feed<Track> = Feed(emptyList()) {
        ordered((if (previewId(album.id)) allTracks() else catalog()).filter { it.album?.id == album.id }).toFeedData()
    }
    override suspend fun loadFeed(album: Album): Feed<Shelf>? = null

    private suspend fun catalog(category: String = "flac"): List<Track> {
        val official = category == "flac"
        val base = root + category + "/"
        val request = Request.Builder().url(base + "catalog.json").header("Cache-Control", "no-cache").build()
        val body = http.newCall(request).await().use { response ->
            check(response.isSuccessful) { "Neptune catalog HTTP ${response.code}" }
            response.body?.string() ?: error("Empty catalog")
        }
        val tracks = Json.parseToJsonElement(body).jsonArray.mapNotNull { item ->
            val obj = item.jsonObject
            fun field(key: String) = obj[key]?.jsonPrimitive?.contentOrNull.orEmpty()
            val id = field(if (official) "isrc" else "id")
            val title = field("title")
            val artist = field("artist")
            val url = field("url")
            if (title.isBlank() || artist.isBlank()) return@mapNotNull null
            if (official) {
                if (!id.matches(Regex("[A-Z]{2}[A-Z0-9]{3}[0-9]{7}")) || url != base + id + ".flac") return@mapNotNull null
            } else {
                if (!id.matches(Regex("$category-[a-f0-9]{64}")) ||
                    !field("releaseId").matches(Regex("$category-[a-f0-9]{64}")) ||
                    field("category") != category || field("playable") != "true" ||
                    !previewUrl(url) || !url.startsWith(base) || !url.endsWith(".flac")) return@mapNotNull null
            }
            val rate = field("sampleRate").toIntOrNull() ?: return@mapNotNull null
            val bits = field("bitDepth").toIntOrNull() ?: return@mapNotNull null
            val channels = field("channels").toIntOrNull() ?: return@mapNotNull null
            val artists = artistList(artist)
            val albumArtists = artistList(field("albumArtist").ifBlank { artist })
            val artwork = field("artwork").takeIf { value ->
                listOf("jpg", "png", "webp").any { value == base + "artwork/$id.$it" }
            }?.toImageHolder()
            if (artists.isEmpty()) return@mapNotNull null
            val streams = obj["streams"] as? JsonObject
            val sources = mutableListOf(server("$id-flac", (rate.toLong() * bits * channels / 1000).toInt().coerceAtLeast(321), "FLAC", mapOf("url" to url)))
            for (bitrate in listOf(320, 128)) {
                val mp3 = (streams?.get(bitrate.toString()) as? JsonPrimitive)?.contentOrNull
                if (mp3 == (if (official) root + "mpeg$bitrate/$id.mp3" else
                    base + "mpeg$bitrate/" + url.substringAfterLast('/').removeSuffix(".flac") + ".mp3")) {
                    sources.add(server("$id-$bitrate", bitrate, "${bitrate}kbps", mapOf("url" to mp3)))
                }
            }
            Track(id = id, title = title, artists = artists,
                cover = artwork,
                album = field("album").takeIf { it.isNotBlank() }?.let {
                    Album(id = if (official) albumArtists.map { a -> a.id }.sorted().joinToString(",") + ":" + normalize(it) else field("releaseId"),
                        title = it, artists = albumArtists, cover = artwork, isRadioSupported = false)
                },
                albumOrderNumber = field("trackNumber").toLongOrNull()?.takeIf { it > 0 },
                albumDiscNumber = field("discNumber").toLongOrNull()?.takeIf { it > 0 },
                duration = field("duration").toLongOrNull(), isrc = if (official) id else null,
                isPlayable = Track.Playable.Yes, isRadioSupported = false,
                streamables = sources)
        }
        val releases = albums(tracks).associateBy { it.id }
        return tracks.map { it.copy(album = it.album?.let { a -> releases[a.id] ?: a }) }
    }

    override suspend fun loadSearchFeed(query: String): Feed<Shelf> = Feed(listOf(
        Tab("TRACKS", "Tracks"), Tab("ALL", "All"), Tab("SINGLES", "Singles"), Tab("EPS", "EPs"), Tab("ALBUMS", "Albums"), Tab("ARTISTS", "Artists")
    )) { tab ->
        val terms = normalize(query).split(' ').filter { it.isNotBlank() }
        fun matches(value: String) = terms.isNotEmpty() && terms.all { it in normalize(value) }
        val all = catalog()
        val tracks = all.filter { t -> matches(t.title + " " + t.artists.joinToString(" ") { it.name } + " " + t.album?.title.orEmpty() + " " + t.id) }
        val releases = albums(all).filter { a -> matches(a.title + " " + a.artists.joinToString(" ") { it.name }) }
        val artists = mainArtists.filter { matches(it.name) }
        when (tab?.id) {
            "ALL" -> shelves(tracks, artists, releases)
            "SINGLES" -> shelves(emptyList(), emptyList(), releases.filter { it.type == Album.Type.Single })
            "EPS" -> shelves(emptyList(), emptyList(), releases.filter { it.type == Album.Type.EP })
            "ALBUMS" -> shelves(emptyList(), emptyList(), releases.filter { it.type == Album.Type.LP })
            "ARTISTS" -> shelves(emptyList(), artists, emptyList())
            else -> shelves(tracks, emptyList(), emptyList())
        }.toFeedData()
    }

    override suspend fun loadTrack(track: Track, isDownload: Boolean): Track =
        (if (previewId(track.id)) allTracks() else catalog()).firstOrNull { it.id == track.id } ?: error("Track unavailable on Neptune")

    override suspend fun loadStreamableMedia(streamable: Streamable, isDownload: Boolean): Streamable.Media {
        val url = streamable.extras["url"] ?: error("Missing Neptune URL")
        check(validUrl(url) || (previewsEnabled() && previewUrl(url)))
        http.newCall(Request.Builder().url(url).head().build()).await().use {
            check(it.isSuccessful) { "Neptune audio HTTP ${it.code}" }
        }
        return url.toServerMedia()
    }

    override suspend fun loadFeed(track: Track): Feed<Shelf>? = null
}
