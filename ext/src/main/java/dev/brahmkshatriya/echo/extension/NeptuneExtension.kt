package dev.brahmkshatriya.echo.extension

import dev.brahmkshatriya.echo.common.clients.*
import dev.brahmkshatriya.echo.common.helpers.ContinuationCallback.Companion.await
import dev.brahmkshatriya.echo.common.models.*
import dev.brahmkshatriya.echo.common.models.Feed.Companion.toFeedData
import dev.brahmkshatriya.echo.common.models.Streamable.Companion.server
import dev.brahmkshatriya.echo.common.models.Streamable.Media.Companion.toServerMedia
import dev.brahmkshatriya.echo.common.settings.Setting
import dev.brahmkshatriya.echo.common.settings.Settings
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.Request
import java.text.Normalizer
import java.util.Locale

class NeptuneExtension : ExtensionClient, SearchFeedClient, TrackClient {
    private val http = OkHttpClient()
    private val base = "https://thenewgessiko.duckdns.org/flac/"
    override fun setSettings(settings: Settings) {}
    override suspend fun getSettingItems(): List<Setting> = emptyList()
    override suspend fun onInitialize() {}

    private fun normalize(s: String) = Normalizer.normalize(s, Normalizer.Form.NFKD)
        .lowercase(Locale.ROOT).replace(Regex("\\p{M}+"), "")
        .replace(Regex("['’]"), "").replace(Regex("[^\\p{L}\\p{N}]+"), " ").trim()

    private suspend fun catalog(): List<Track> {
        val request = Request.Builder().url(base + "catalog.json").header("Cache-Control", "no-cache").build()
        val body = http.newCall(request).await().use { response ->
            check(response.isSuccessful) { "Neptune catalog HTTP ${response.code}" }
            response.body?.string() ?: error("Empty catalog")
        }
        return Json.parseToJsonElement(body).jsonArray.mapNotNull { item ->
            val obj = item.jsonObject
            fun field(key: String) = obj[key]?.jsonPrimitive?.contentOrNull.orEmpty()
            val id = field("isrc")
            val title = field("title")
            val artist = field("artist")
            val url = field("url")
            if (!id.matches(Regex("[A-Z]{2}[A-Z0-9]{3}[0-9]{7}")) || title.isBlank() || artist.isBlank() || !url.equals(base + id + ".flac", ignoreCase = false)) return@mapNotNull null
            val rate = field("sampleRate").toIntOrNull() ?: return@mapNotNull null
            val bits = field("bitDepth").toIntOrNull() ?: return@mapNotNull null
            val channels = field("channels").toIntOrNull() ?: return@mapNotNull null
            val artists = listOf(Artist(id = artist, name = artist))
            val label = "FLAC $bits-bit / ${rate / 1000.0} kHz"
            Track(id = id, title = title, artists = artists,
                album = field("album").takeIf { it.isNotBlank() }?.let { Album(id = "$artist:$it", title = it, artists = artists) },
                duration = field("duration").toLongOrNull(), isrc = id,
                isPlayable = Track.Playable.Yes, isRadioSupported = false,
                streamables = listOf(server(id, (rate.toLong() * bits * channels / 1000).toInt(), label, mapOf("url" to url))))
        }
    }

    override suspend fun loadSearchFeed(query: String): Feed<Shelf> = Feed(listOf(Tab("TRACKS", "Tracks"))) {
        val terms = normalize(query).split(' ').filter { it.isNotBlank() }
        val tracks = if (terms.isEmpty()) emptyList() else catalog().filter { track ->
            val haystack = normalize(track.title + " " + track.artists.joinToString(" ") { it.name } + " " + track.album?.title.orEmpty() + " " + track.id)
            terms.all { it in haystack }
        }
        val shelves: List<Shelf> = if (tracks.isEmpty()) emptyList() else listOf(Shelf.Lists.Tracks(id = "tracks", title = "Tracks", list = tracks))
        shelves.toFeedData()
    }

    override suspend fun loadTrack(track: Track, isDownload: Boolean): Track =
        catalog().firstOrNull { it.id == track.id } ?: error("Track unavailable on Neptune")

    override suspend fun loadStreamableMedia(streamable: Streamable, isDownload: Boolean): Streamable.Media {
        val url = streamable.extras["url"] ?: error("Missing Neptune URL")
        check(url.startsWith(base))
        http.newCall(Request.Builder().url(url).head().build()).await().use {
            check(it.isSuccessful) { "Neptune audio HTTP ${it.code}" }
        }
        return url.toServerMedia()
    }

    override suspend fun loadFeed(track: Track): Feed<Shelf>? = null
}
