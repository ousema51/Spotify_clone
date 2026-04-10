"""
YouTube Music backend search/metadata and stream resolution utilities.
"""

import atexit
import base64
import copy
import logging
import os
import tempfile
import threading
import time
from urllib.parse import urljoin

import requests

logger = logging.getLogger(__name__)

ytmusic = None
try:
    from ytmusicapi import YTMusic

    ytmusic = YTMusic()
except Exception as e:
    logger.error("ytmusicapi failed: %s", e)

YoutubeDL = None
try:
    from yt_dlp import YoutubeDL
except Exception as e:
    logger.warning("yt-dlp not available: %s", e)


DEFAULT_STREAM_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Linux; Android 14; Pixel 7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/123.0.0.0 Mobile Safari/537.36"
    ),
    "Referer": "https://music.youtube.com/",
    "Origin": "https://music.youtube.com",
}


_STREAM_CACHE_LOCK = threading.Lock()
_STREAM_CACHE = {}

_RUNTIME_COOKIEFILE_LOCK = threading.Lock()
_RUNTIME_COOKIEFILE_PATH = None
_RUNTIME_COOKIEFILE_SIGNATURE = None

_BACKEND_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_COOKIE_DIR = os.path.join(_BACKEND_ROOT, "cookies")

_LOCAL_COOKIE_B64_CANDIDATES = (
    "cookie.b64",
    "cookies.b64",
    "cookies.base64",
)

_LOCAL_COOKIE_TEXT_CANDIDATES = (
    "cookie.txt",
    "cookies.txt",
    "youtube.cookies.txt",
)


def _get_int_env(name, default):
    raw = (os.environ.get(name) or "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except Exception:
        return default


_STREAM_CACHE_TTL_SECONDS = max(30, _get_int_env("YTDLP_STREAM_CACHE_TTL_SECONDS", 240))
_STREAM_CACHE_STALE_SECONDS = max(
    _STREAM_CACHE_TTL_SECONDS,
    _get_int_env("YTDLP_STREAM_CACHE_STALE_SECONDS", 1800),
)

_DEFAULT_PIPED_INSTANCES = (
    "https://pipedapi.adminforge.de",
    "https://pipedapi.kavin.rocks",
    "https://api.piped.yt",
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _safe_str(value):
    """Safely convert to string with UTF-8 encoding."""
    if value is None:
        return None
    if isinstance(value, str):
        try:
            value.encode("utf-8")
            return value
        except UnicodeEncodeError:
            return value.encode("utf-8", errors="replace").decode("utf-8")
    return str(value)


def _safe_int(value):
    if value is None:
        return None
    try:
        return int(float(value))
    except Exception:
        return None


def _extract_video_id(raw):
    value = _safe_str(raw)
    if not value:
        return None

    value = value.strip()
    if not value:
        return None

    # Fast path: already a likely video id.
    if len(value) == 11 and all(c.isalnum() or c in "_-" for c in value):
        return value

    # Query-based URL pattern.
    if "v=" in value:
        after = value.split("v=", 1)[1]
        candidate = after.split("&", 1)[0].strip()
        if len(candidate) == 11:
            return candidate

    # youtu.be short URL pattern.
    if "youtu.be/" in value:
        after = value.split("youtu.be/", 1)[1]
        candidate = after.split("?", 1)[0].split("/", 1)[0].strip()
        if len(candidate) == 11:
            return candidate

    # Last chance: scan for a token with valid charset and length.
    for token in value.replace("/", " ").replace("?", " ").replace("&", " ").split():
        token = token.strip()
        if len(token) == 11 and all(c.isalnum() or c in "_-" for c in token):
            return token

    return None


def _merged_stream_headers(raw_headers=None):
    merged = dict(DEFAULT_STREAM_HEADERS)
    if not isinstance(raw_headers, dict):
        return merged

    for key, value in raw_headers.items():
        k = (_safe_str(key) or "").strip()
        v = (_safe_str(value) or "").strip()
        if k and v:
            merged[k] = v
    return merged


def _cleanup_runtime_cookiefile():
    global _RUNTIME_COOKIEFILE_PATH

    path = _RUNTIME_COOKIEFILE_PATH
    if not path:
        return

    try:
        if os.path.exists(path):
            os.remove(path)
    except Exception:
        pass


atexit.register(_cleanup_runtime_cookiefile)


def _read_text_file(path, max_bytes=2_000_000):
    try:
        if not path or not os.path.exists(path) or not os.path.isfile(path):
            return ""
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            data = f.read(max_bytes)
            if not data:
                return ""
            return data.strip()
    except Exception:
        return ""


def _looks_like_cookie_header(text):
    if not text:
        return False
    if "=" not in text or ";" not in text:
        return False
    if "\t" in text:
        return False
    return True


def _cookie_header_to_netscape(text):
    if not text:
        return ""

    lines = ["# Netscape HTTP Cookie File"]
    seen = set()
    domains = (".youtube.com", ".google.com")

    ignored_attrs = {
        "path",
        "domain",
        "expires",
        "max-age",
        "samesite",
        "secure",
        "httponly",
    }

    for part in text.split(";"):
        chunk = part.strip()
        if not chunk or "=" not in chunk:
            continue

        name, value = chunk.split("=", 1)
        name = name.strip()
        value = value.strip()

        if not name or name.lower() in ignored_attrs:
            continue

        secure = "TRUE" if name.startswith("__Secure-") or name.startswith("__Host-") else "FALSE"

        for domain in domains:
            key = (domain, name)
            if key in seen:
                continue
            seen.add(key)
            lines.append(
                "{}\tTRUE\t/\t{}\t2147483647\t{}\t{}".format(
                    domain,
                    secure,
                    name,
                    value,
                )
            )

    if len(lines) == 1:
        return ""

    return "\n".join(lines) + "\n"


def _decode_base64_candidate(raw_blob):
    if not raw_blob:
        return ""

    blob = raw_blob.strip()
    if not blob:
        return ""

    raw_lines = blob.splitlines()
    pem_lines = []
    had_pem_markers = False
    for line in raw_lines:
        ln = line.strip()
        if not ln:
            continue
        if ln.startswith("-----BEGIN") or ln.startswith("-----END"):
            had_pem_markers = True
            continue
        pem_lines.append(ln)

    if pem_lines and had_pem_markers:
        blob = "".join(pem_lines)

    try:
        padded = blob + ("=" * ((4 - len(blob) % 4) % 4))
        decoded = base64.b64decode(padded)
        return decoded.decode("utf-8", errors="replace")
    except Exception:
        return ""


def _discover_local_cookie_source():
    for name in _LOCAL_COOKIE_B64_CANDIDATES:
        path = os.path.join(_COOKIE_DIR, name)
        data = _read_text_file(path)
        if data:
            return {"kind": "local_b64", "path": path, "blob": data}

    for name in _LOCAL_COOKIE_TEXT_CANDIDATES:
        path = os.path.join(_COOKIE_DIR, name)
        data = _read_text_file(path)
        if data:
            return {"kind": "local_text", "path": path, "blob": data}

    return {"kind": None, "path": None, "blob": ""}


def _get_cookie_blob_source():
    env_b64 = (os.environ.get("YTDLP_COOKIES_B64") or os.environ.get("YTDLP_COOKIES_BASE64") or "").strip()
    if env_b64:
        return {"kind": "env_b64", "path": None, "blob": env_b64}

    env_cookiefile = (os.environ.get("YTDLP_COOKIEFILE") or "").strip()
    if env_cookiefile:
        file_blob = _read_text_file(env_cookiefile)
        if file_blob:
            return {"kind": "env_cookiefile", "path": env_cookiefile, "blob": file_blob}

    discovered = _discover_local_cookie_source()
    if discovered.get("blob"):
        return discovered

    return {"kind": None, "path": None, "blob": ""}


def _read_cookie_blob_from_env():
    source = _get_cookie_blob_source()
    return (source.get("blob") or "").strip()


def _normalize_cookie_blob(raw_blob):
    if not raw_blob:
        return ""

    original = raw_blob.replace("\\n", "\n").strip()
    if not original:
        return ""

    decoded_text = _decode_base64_candidate(original)

    candidates = []
    if decoded_text:
        candidates.append(decoded_text)
    candidates.append(original)

    for candidate in candidates:
        text = candidate.replace("\\n", "\n").replace("\r\n", "\n").replace("\r", "\n").strip()
        if not text:
            continue

        if "Netscape HTTP Cookie File" in text:
            return text if text.endswith("\n") else text + "\n"

        if "\t" in text and ("youtube.com" in text or "google.com" in text):
            return "# Netscape HTTP Cookie File\n{}\n".format(text)

        if _looks_like_cookie_header(text):
            normalized = _cookie_header_to_netscape(text)
            if normalized:
                return normalized

    return ""


def _materialize_cookiefile_from_env():
    global _RUNTIME_COOKIEFILE_PATH, _RUNTIME_COOKIEFILE_SIGNATURE

    blob = _read_cookie_blob_from_env()
    if not blob:
        return None

    normalized = _normalize_cookie_blob(blob)
    if not normalized:
        return None

    signature = str(hash(normalized))

    with _RUNTIME_COOKIEFILE_LOCK:
        if (
            _RUNTIME_COOKIEFILE_PATH
            and _RUNTIME_COOKIEFILE_SIGNATURE == signature
            and os.path.exists(_RUNTIME_COOKIEFILE_PATH)
        ):
            return _RUNTIME_COOKIEFILE_PATH

        temp_file = tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            suffix=".cookies.txt",
            delete=False,
            newline="\n",
        )
        try:
            temp_file.write(normalized)
            temp_file.flush()
            temp_path = temp_file.name
        finally:
            temp_file.close()

        old_path = _RUNTIME_COOKIEFILE_PATH
        _RUNTIME_COOKIEFILE_PATH = temp_path
        _RUNTIME_COOKIEFILE_SIGNATURE = signature

        if old_path and old_path != temp_path:
            try:
                if os.path.exists(old_path):
                    os.remove(old_path)
            except Exception:
                pass

        return _RUNTIME_COOKIEFILE_PATH


def _has_cookie_auth_config():
    source = _get_cookie_blob_source()
    if source.get("blob"):
        return True
    if (os.environ.get("YTDLP_COOKIES_FROM_BROWSER") or "").strip():
        return True
    return False


def _is_bot_challenge_message(message):
    normalized = (message or "").lower()
    if not normalized:
        return False

    markers = (
        "sign in to confirm you're not a bot",
        "sign in to confirm that you are not a bot",
        "use --cookies-from-browser or --cookies",
        "this video is unavailable",
        "unable to extract initial player response",
    )
    return any(marker in normalized for marker in markers)


def _stream_cache_get(video_id, allow_stale=False):
    with _STREAM_CACHE_LOCK:
        item = _STREAM_CACHE.get(video_id)
        if not item:
            return None

        now = time.time()
        fresh_until = item.get("fresh_until", 0)
        stale_until = item.get("stale_until", 0)

        if now <= fresh_until:
            return copy.deepcopy(item.get("payload"))

        if allow_stale and now <= stale_until:
            payload = copy.deepcopy(item.get("payload"))
            if isinstance(payload, dict):
                payload["cache_stale"] = True
            return payload

        _STREAM_CACHE.pop(video_id, None)
        return None


def _stream_cache_set(video_id, payload):
    if not video_id or not isinstance(payload, dict):
        return

    now = time.time()
    entry = {
        "payload": copy.deepcopy(payload),
        "fresh_until": now + _STREAM_CACHE_TTL_SECONDS,
        "stale_until": now + _STREAM_CACHE_STALE_SECONDS,
    }

    with _STREAM_CACHE_LOCK:
        _STREAM_CACHE[video_id] = entry


def _load_piped_instances():
    configured = (os.environ.get("PIPED_INSTANCES") or "").strip()
    if configured:
        values = [v.strip().rstrip("/") for v in configured.split(",") if v.strip()]
        if values:
            return values

    return [v.rstrip("/") for v in _DEFAULT_PIPED_INSTANCES]


def _get_rapidapi_key():
    return (
        (os.environ.get("YTDLP_RAPIDAPI_KEY") or "").strip()
        or (os.environ.get("RAPIDAPI_KEY") or "").strip()
        or (os.environ.get("X_RAPIDAPI_KEY") or "").strip()
    )


def _get_rapidapi_host():
    return (os.environ.get("YTDLP_RAPIDAPI_HOST") or "yt-dlp-api.p.rapidapi.com").strip()


def _get_rapidapi_url():
    return (os.environ.get("YTDLP_RAPIDAPI_URL") or "https://yt-dlp-api.p.rapidapi.com/").strip()


def _external_ytdlp_api_enabled():
    provider = (os.environ.get("YTDLP_PROVIDER") or "").strip().lower()
    if provider in ("rapidapi", "external", "remote"):
        return True
    return bool(_get_rapidapi_key())


def _allow_local_ytdlp_fallback():
    raw = (os.environ.get("YTDLP_ALLOW_LOCAL_FALLBACK") or "").strip().lower()
    return raw in ("1", "true", "yes", "on")


def _pick_best_audio_url_from_formats(formats):
    if not isinstance(formats, list):
        return None

    best_url = None
    best_score = -1
    for fmt in formats:
        if not isinstance(fmt, dict):
            continue

        url = _safe_str(fmt.get("url") or fmt.get("download_url") or fmt.get("audio_url"))
        if not url:
            continue

        acodec = (_safe_str(fmt.get("acodec") or fmt.get("audioCodec") or fmt.get("codec")) or "").lower()
        if acodec == "none":
            continue

        vcodec = (_safe_str(fmt.get("vcodec") or fmt.get("videoCodec")) or "").lower()
        bitrate = _safe_int(fmt.get("abr")) or _safe_int(fmt.get("tbr")) or _safe_int(fmt.get("bitrate")) or 0
        ext = (_safe_str(fmt.get("ext") or fmt.get("container")) or "").lower()

        score = bitrate
        if vcodec == "none" or not vcodec:
            score += 20
        if ext in ("m4a", "webm", "mp4", "ogg"):
            score += 10

        if score > best_score:
            best_score = score
            best_url = url

    return best_url


def _extract_audio_url_from_external_payload(payload):
    if not isinstance(payload, dict):
        return None

    candidate_maps = [payload]
    data_map = payload.get("data")
    if isinstance(data_map, dict):
        candidate_maps.insert(0, data_map)
    result_map = payload.get("result")
    if isinstance(result_map, dict):
        candidate_maps.insert(0, result_map)

    for candidate in candidate_maps:
        for key in (
            "audio_url",
            "audio",
            "url",
            "download_url",
            "downloadUrl",
            "stream_url",
            "link",
        ):
            value = _safe_str(candidate.get(key))
            if value:
                return value

    for candidate in candidate_maps:
        for key in ("requested_downloads", "requested_formats", "formats", "audios", "entries"):
            value = candidate.get(key)
            picked = _pick_best_audio_url_from_formats(value)
            if picked:
                return picked

    return None


def _resolve_stream_from_external_api(video_id):
    if not _external_ytdlp_api_enabled():
        return {"success": False, "error_code": "external_disabled", "message": "External yt-dlp API disabled"}

    api_key = _get_rapidapi_key()
    if not api_key:
        return {"success": False, "error_code": "external_missing_key", "message": "Missing RapidAPI key"}

    resolved_id = _extract_video_id(video_id)
    if not resolved_id:
        return {"success": False, "message": "Invalid video_id"}

    endpoint = _get_rapidapi_url()
    host = _get_rapidapi_host()
    target_url = "https://www.youtube.com/watch?v={}".format(resolved_id)

    headers = {
        "x-rapidapi-key": api_key,
        "x-rapidapi-host": host,
        "accept": "application/json",
        "content-type": "application/json",
    }

    timeout_seconds = max(8, _get_int_env("YTDLP_EXTERNAL_TIMEOUT_SECONDS", 20))

    try:
        response = requests.get(
            endpoint,
            params={"url": target_url},
            headers=headers,
            timeout=(8, timeout_seconds),
        )
    except Exception as e:
        return {
            "success": False,
            "error_code": "external_request_failed",
            "message": "RapidAPI yt-dlp request failed: {}".format(str(e)),
        }

    if response.status_code >= 400:
        body = response.text[:220] if response.text else ""
        return {
            "success": False,
            "error_code": "external_http_error",
            "message": "RapidAPI yt-dlp returned status {}: {}".format(response.status_code, body),
        }

    try:
        payload = response.json()
    except Exception as e:
        return {
            "success": False,
            "error_code": "external_invalid_json",
            "message": "RapidAPI yt-dlp returned invalid JSON: {}".format(str(e)),
        }

    audio_url = _extract_audio_url_from_external_payload(payload)
    if not audio_url:
        return {
            "success": False,
            "error_code": "external_no_audio_url",
            "message": "RapidAPI yt-dlp response did not include a usable audio URL",
        }

    data_map = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    title = _safe_str(data_map.get("title") if isinstance(data_map, dict) else None)
    duration = _safe_int(data_map.get("duration") if isinstance(data_map, dict) else None)

    return {
        "success": True,
        "data": {
            "audio_url": audio_url,
            "headers": _merged_stream_headers(),
            "video_id": resolved_id,
            "title": title,
            "duration": duration,
            "source": "rapidapi-yt-dlp",
        },
    }


def _pick_best_piped_audio_stream(streams):
    if not isinstance(streams, list):
        return None

    best = None
    best_score = -1

    for stream in streams:
        if not isinstance(stream, dict):
            continue

        raw_url = _safe_str(stream.get("url") or stream.get("audioProxyUrl"))
        if not raw_url:
            continue

        bitrate = _safe_int(stream.get("bitrate")) or 0
        codec = (_safe_str(stream.get("codec")) or "").lower()

        score = bitrate
        if "opus" in codec or "aac" in codec or "mp4a" in codec:
            score += 10

        if score > best_score:
            best_score = score
            best = dict(stream)

    return best


def _resolve_stream_from_piped(video_id):
    resolved_id = _extract_video_id(video_id)
    if not resolved_id:
        return {"success": False, "message": "Invalid video_id for Piped fallback"}

    instances = _load_piped_instances()
    for instance in instances:
        endpoint = "{}/streams/{}".format(instance, resolved_id)
        try:
            response = requests.get(
                endpoint,
                headers={"Accept": "application/json"},
                timeout=(8, 15),
            )
        except Exception as e:
            logger.warning("Piped request failed for %s: %s", endpoint, e)
            continue

        if response.status_code != 200:
            continue

        try:
            payload = response.json()
        except Exception:
            continue

        if not isinstance(payload, dict):
            continue

        streams = payload.get("audioStreams") or payload.get("audio_streams") or []
        best_stream = _pick_best_piped_audio_stream(streams)
        if not best_stream:
            continue

        stream_url = _safe_str(best_stream.get("url") or best_stream.get("audioProxyUrl"))
        if not stream_url:
            continue

        if stream_url.startswith("/"):
            stream_url = urljoin(instance + "/", stream_url.lstrip("/"))

        stream_payload = {
            "audio_url": stream_url,
            "headers": _merged_stream_headers(),
            "video_id": resolved_id,
            "title": _safe_str(payload.get("title")),
            "duration": _safe_int(payload.get("duration")),
            "source": "piped",
            "piped_instance": instance,
        }

        return {"success": True, "data": stream_payload}

    return {"success": False, "message": "Piped fallback failed to resolve stream"}


def _get_thumbnail(r):
    """Extract thumbnail URL with fallback handling."""
    if r is None:
        return None

    thumbs = r.get("thumbnails")
    if isinstance(thumbs, list) and thumbs:
        url = thumbs[-1].get("url") if thumbs[-1] else None
        if url:
            url = _safe_str(url)
            if url and url.startswith("//"):
                return "https:{}".format(url)
            if url and url.startswith("http"):
                return url
            if url:
                return "https:{}".format(url)

    thumb_obj = r.get("thumbnail")
    if isinstance(thumb_obj, dict):
        inner = thumb_obj.get("thumbnails")
        if isinstance(inner, list) and inner:
            url = inner[-1].get("url") if inner[-1] else None
            if url:
                url = _safe_str(url)
                if url and url.startswith("http"):
                    return url
                if url:
                    return "https:{}".format(url)

    vid = r.get("videoId") or r.get("id")
    if vid:
        vid = _safe_str(vid)
        if vid:
            return "https://img.youtube.com/vi/{}/hqdefault.jpg".format(vid)

    return None


def _normalize(r):
    """Normalize song result from ytmusicapi with UTF-8 encoding."""
    if r is None:
        return None

    artists = r.get("artists") or []
    artist = None
    if artists:
        if isinstance(artists[0], dict):
            artist = artists[0].get("name")
        else:
            artist = artists[0]
    if not artist:
        artist = r.get("artist")

    artist = _safe_str(artist) or "Unknown Artist"

    return {
        "id": _safe_str(r.get("videoId") or r.get("id")),
        "title": _safe_str(r.get("title")) or "Unknown",
        "name": _safe_str(r.get("title")) or "Unknown",
        "artist": artist,
        "duration": r.get("duration"),
        "thumbnail": _get_thumbnail(r),
        "image": _get_thumbnail(r),
        "cover_url": _get_thumbnail(r),
    }


def _build_ytdlp_options():
    opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": True,
        "socket_timeout": 15,
        "extractor_retries": 3,
        "retries": 3,
        "http_headers": dict(DEFAULT_STREAM_HEADERS),
    }

    ytdlp_format = (os.environ.get("YTDLP_FORMAT") or "").strip()
    if ytdlp_format:
        opts["format"] = ytdlp_format

    player_clients = (os.environ.get("YTDLP_PLAYER_CLIENTS") or "").strip()
    if player_clients:
        clients = [c.strip() for c in player_clients.split(",") if c.strip()]
        if clients:
            opts.setdefault("extractor_args", {}).setdefault("youtube", {})["player_client"] = clients

    player_skip = (os.environ.get("YTDLP_PLAYER_SKIP") or "").strip()
    if player_skip:
        skip_items = [c.strip() for c in player_skip.split(",") if c.strip()]
        if skip_items:
            opts.setdefault("extractor_args", {}).setdefault("youtube", {})["player_skip"] = skip_items

    runtime_cookiefile = _materialize_cookiefile_from_env()
    if runtime_cookiefile:
        opts["cookiefile"] = runtime_cookiefile

    # Format: browser[:profile[:keyring[:container]]]
    cookies_from_browser = (os.environ.get("YTDLP_COOKIES_FROM_BROWSER") or "").strip()
    if cookies_from_browser and "cookiefile" not in opts:
        parts = [p.strip() for p in cookies_from_browser.split(":") if p.strip()]
        if parts:
            opts["cookiesfrombrowser"] = tuple(parts)

    po_token = (os.environ.get("YTDLP_PO_TOKEN") or "").strip()
    if po_token:
        opts.setdefault("extractor_args", {}).setdefault("youtube", {})["po_token"] = [po_token]

    visitor_data = (os.environ.get("YTDLP_VISITOR_DATA") or "").strip()
    if visitor_data:
        opts.setdefault("extractor_args", {}).setdefault("youtube", {})["visitor_data"] = [visitor_data]

    return opts


def _pick_best_format(info):
    formats = info.get("formats") or []
    best = None
    best_score = -1

    for fmt in formats:
        if not isinstance(fmt, dict):
            continue

        url = _safe_str(fmt.get("url"))
        if not url:
            continue

        acodec = (_safe_str(fmt.get("acodec")) or "").lower()
        if acodec == "none":
            continue

        vcodec = (_safe_str(fmt.get("vcodec")) or "").lower()
        ext = (_safe_str(fmt.get("ext")) or "").lower()
        bitrate = _safe_int(fmt.get("abr")) or _safe_int(fmt.get("tbr")) or 0

        score = bitrate
        if vcodec == "none":
            score += 40
        if ext in ("m4a", "mp4", "webm", "ogg"):
            score += 20

        if score > best_score:
            best_score = score
            best = fmt

    return best


def _build_stream_payload(info, selected, forced_video_id=None):
    stream_url = None
    extra_headers = None

    if isinstance(selected, dict):
        stream_url = _safe_str(selected.get("url"))
        extra_headers = selected.get("http_headers")

    if not stream_url and isinstance(info, dict):
        stream_url = _safe_str(info.get("url"))
        if not extra_headers:
            extra_headers = info.get("http_headers")

    if not stream_url:
        return None

    title = _safe_str(info.get("title") if isinstance(info, dict) else None)
    duration = _safe_int(info.get("duration") if isinstance(info, dict) else None)
    video_id = _safe_str(info.get("id") if isinstance(info, dict) else None)
    if not video_id:
        video_id = _safe_str(forced_video_id)

    return {
        "audio_url": stream_url,
        "headers": _merged_stream_headers(extra_headers),
        "video_id": video_id,
        "title": title,
        "duration": duration,
        "source": "yt-dlp",
    }


def _resolve_stream_from_yt_dlp(target, from_search=False):
    if not YoutubeDL:
        return {"success": False, "message": "yt-dlp not installed"}

    ydl_opts = _build_ytdlp_options()

    try:
        with YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(target, download=False)
    except Exception as e:
        message = str(e)
        logger.warning("yt-dlp extraction failed for %s: %s", target, message)

        if _is_bot_challenge_message(message):
            if _has_cookie_auth_config():
                hint = (
                    "YouTube bot challenge detected even with cookies configured. "
                    "Refresh account cookies and ensure the account can play this video."
                )
            else:
                hint = (
                    "YouTube bot challenge detected. Configure one of "
                    "YTDLP_COOKIEFILE, YTDLP_COOKIES_B64, or YTDLP_COOKIES_FROM_BROWSER."
                )
            return {
                "success": False,
                "message": "{} (raw: {})".format(hint, message),
                "error_code": "bot_challenge",
            }

        return {"success": False, "message": message}

    if from_search:
        if not isinstance(info, dict):
            return {"success": False, "message": "Invalid yt-dlp search response"}

        entries = info.get("entries") or []
        if not isinstance(entries, list):
            entries = []

        for entry in entries[:8]:
            if not isinstance(entry, dict):
                continue

            selected = _pick_best_format(entry)
            payload = _build_stream_payload(entry, selected)
            if payload:
                return {"success": True, "data": payload}

        return {"success": False, "message": "No playable search stream found"}

    if not isinstance(info, dict):
        return {"success": False, "message": "Invalid yt-dlp response"}

    selected = _pick_best_format(info)
    payload = _build_stream_payload(info, selected)
    if not payload:
        return {"success": False, "message": "No playable audio URL found"}

    return {"success": True, "data": payload}


# ---------------------------------------------------------------------------
# Public API - Search
# ---------------------------------------------------------------------------


def search_songs(query="", page=1, limit=20):
    if not ytmusic:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        query = _safe_str(query)
        start = (page - 1) * limit
        raw = ytmusic.search(query, filter="songs", limit=start + limit) or []
        songs = []
        for r in raw[start : start + limit]:
            if r.get("videoId"):
                normalized = _normalize(r)
                if normalized:
                    songs.append(normalized)
        return {"success": True, "data": songs}
    except Exception as e:
        logger.error("Search error: %s", e)
        return {"success": False, "message": str(e)}


def search_all(query=""):
    return search_songs(query)


def get_stream_url(video_id=""):
    resolved_id = _extract_video_id(video_id)
    if not resolved_id:
        return {"success": False, "message": "Invalid video_id"}

    cached = _stream_cache_get(resolved_id)
    if cached:
        return {"success": True, "data": cached}

    local_result = {"success": False, "message": "local yt-dlp not attempted"}
    external_result = {"success": False, "message": "external yt-dlp not attempted"}

    if _external_ytdlp_api_enabled():
        external_result = _resolve_stream_from_external_api(resolved_id)
        if external_result.get("success"):
            data = external_result.get("data") or {}
            if not data.get("video_id"):
                data["video_id"] = resolved_id
            _stream_cache_set(resolved_id, data)
            external_result["data"] = data
            return external_result

        if _allow_local_ytdlp_fallback():
            target = "https://www.youtube.com/watch?v={}".format(resolved_id)
            local_result = _resolve_stream_from_yt_dlp(target, from_search=False)
    else:
        target = "https://www.youtube.com/watch?v={}".format(resolved_id)
        local_result = _resolve_stream_from_yt_dlp(target, from_search=False)

    if local_result.get("success"):
        data = local_result.get("data") or {}
        if not data.get("video_id"):
            data["video_id"] = resolved_id
        _stream_cache_set(resolved_id, data)
        local_result["data"] = data
        return local_result

    if local_result.get("error_code") == "bot_challenge":
        stale = _stream_cache_get(resolved_id, allow_stale=True)
        if stale:
            return {
                "success": True,
                "data": stale,
                "message": "Using stale cached stream URL due to temporary YouTube challenge",
            }

    piped_result = _resolve_stream_from_piped(resolved_id)
    if piped_result.get("success"):
        data = piped_result.get("data") or {}
        if not data.get("video_id"):
            data["video_id"] = resolved_id
        _stream_cache_set(resolved_id, data)
        piped_result["data"] = data
        return piped_result

    attempted_messages = []
    if _external_ytdlp_api_enabled():
        attempted_messages.append(
            "external api error: {}".format(external_result.get("message", "unknown"))
        )
    if local_result.get("message") and local_result.get("message") != "local yt-dlp not attempted":
        attempted_messages.append("local yt-dlp error: {}".format(local_result.get("message")))
    attempted_messages.append(
        "piped fallback error: {}".format(piped_result.get("message", "unknown"))
    )

    error_code = local_result.get("error_code") or external_result.get("error_code")
    message = "; ".join(attempted_messages)
    if not message:
        message = "Failed to resolve stream URL"

    return {
        "success": False,
        "error_code": error_code,
        "message": message,
    }


def get_stream_from_search(query=""):
    query = (_safe_str(query) or "").strip()
    if not query:
        return {"success": False, "message": "No query provided"}

    # In external mode, avoid local yt-dlp search extraction on serverless hosts.
    if _external_ytdlp_api_enabled() and not _allow_local_ytdlp_fallback():
        search_result = search_songs(query, page=1, limit=1)
        if search_result.get("success"):
            songs = search_result.get("data") or []
            if songs:
                first_id = _extract_video_id((songs[0] or {}).get("id"))
                if first_id:
                    return get_stream_url(first_id)
        return {
            "success": False,
            "message": "Failed to resolve stream from search in external API mode",
        }

    ytdlp_result = _resolve_stream_from_yt_dlp(
        "ytsearch8:{}".format(query),
        from_search=True,
    )
    if ytdlp_result.get("success"):
        return ytdlp_result

    # Fallback: resolve first search hit by id.
    search_result = search_songs(query, page=1, limit=1)
    if search_result.get("success"):
        songs = search_result.get("data") or []
        if songs:
            first_id = _extract_video_id((songs[0] or {}).get("id"))
            if first_id:
                return get_stream_url(first_id)

    return {
        "success": False,
        "message": "Failed to resolve stream from search",
    }


def get_song_by_id(video_id=""):
    """Get song metadata with UTF-8 encoding and thumbnail fallback."""
    resolved_id = _extract_video_id(video_id)
    if not resolved_id:
        return {"success": False, "message": "Invalid video_id"}

    meta = {
        "title": None,
        "artist": "Unknown Artist",
        "duration": None,
        "thumbnail": "https://img.youtube.com/vi/{}/hqdefault.jpg".format(resolved_id),
    }

    if ytmusic:
        try:
            info = ytmusic.get_song(resolved_id)
            vd = info.get("videoDetails") or {}
            thumbs = vd.get("thumbnail", {}).get("thumbnails") or []

            meta["title"] = _safe_str(vd.get("title"))
            meta["artist"] = _safe_str(vd.get("author")) or meta["artist"]
            meta["duration"] = vd.get("lengthSeconds")

            if thumbs:
                turl = thumbs[-1].get("url") if thumbs[-1] else None
                if turl:
                    turl = _safe_str(turl)
                    if turl:
                        if turl.startswith("//"):
                            meta["thumbnail"] = "https:{}".format(turl)
                        else:
                            meta["thumbnail"] = turl
        except Exception as e:
            logger.error("Failed to fetch song metadata: %s", e)

    meta["title"] = meta["title"] or "Unknown Title ({})".format(resolved_id)
    meta["title"] = _safe_str(meta["title"])
    meta["artist"] = _safe_str(meta["artist"])

    return {
        "success": True,
        "data": {
            "id": resolved_id,
            "title": meta["title"],
            "artist": meta["artist"],
            "duration": meta["duration"],
            "thumbnail": meta["thumbnail"],
            "image": meta["thumbnail"],
            "cover_url": meta["thumbnail"],
        },
    }


# ---------------------------------------------------------------------------
# Albums / Artists / Trending
# ---------------------------------------------------------------------------


def search_albums(query="", page=1, limit=20):
    if not ytmusic:
        return {"success": True, "data": []}
    try:
        query = _safe_str(query)
        raw = ytmusic.search(query, filter="albums", limit=limit) or []
        start = (page - 1) * limit
        albums = []
        for r in raw[start : start + limit]:
            artists = r.get("artists") or [{}]
            artist_name = None
            if artists and isinstance(artists[0], dict):
                artist_name = artists[0].get("name")
            elif artists:
                artist_name = artists[0]

            album = {
                "id": _safe_str(r.get("browseId")),
                "title": _safe_str(r.get("title")) or "Unknown",
                "artist": _safe_str(artist_name) or "Unknown",
                "thumbnail": _get_thumbnail(r),
                "cover_url": _get_thumbnail(r),
                "image": _get_thumbnail(r),
            }
            albums.append(album)
        return {"success": True, "data": albums}
    except Exception as e:
        logger.error("Album search error: %s", e)
        return {"success": True, "data": []}


def search_artists(query="", page=1, limit=20):
    if not ytmusic:
        return {"success": True, "data": []}
    try:
        query = _safe_str(query)
        raw = ytmusic.search(query, filter="artists", limit=limit) or []
        start = (page - 1) * limit
        artists = []
        for r in raw[start : start + limit]:
            artist = {
                "id": _safe_str(r.get("browseId")),
                "name": _safe_str(r.get("artist")) or "Unknown",
                "thumbnail": _get_thumbnail(r),
                "image": _get_thumbnail(r),
            }
            artists.append(artist)
        return {"success": True, "data": artists}
    except Exception as e:
        logger.error("Artist search error: %s", e)
        return {"success": True, "data": []}


def get_album_by_id(album_id=""):
    if not ytmusic:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        album_id = _safe_str(album_id)
        album = ytmusic.get_album(album_id)

        artists = album.get("artists") or [{}]
        artist_name = None
        if artists and isinstance(artists[0], dict):
            artist_name = artists[0].get("name")
        elif artists:
            artist_name = artists[0]

        return {
            "success": True,
            "data": {
                "id": album_id,
                "title": _safe_str(album.get("title")) or "Unknown",
                "artist": _safe_str(artist_name) or "Unknown",
                "thumbnail": _get_thumbnail(album),
                "cover_url": _get_thumbnail(album),
                "image": _get_thumbnail(album),
                "tracks": [
                    _normalize(t) for t in (album.get("tracks") or []) if t
                ],
            },
        }
    except Exception as e:
        logger.error("Album get error: %s", e)
        return {"success": False, "message": str(e)}


def get_artist_by_id(artist_id=""):
    if not ytmusic:
        return {"success": False, "message": "ytmusicapi not available"}
    try:
        artist_id = _safe_str(artist_id)
        artist = ytmusic.get_artist(artist_id)

        songs = [
            _normalize(s) for s in (artist.get("songs", {}).get("results") or []) if s
        ]

        return {
            "success": True,
            "data": {
                "id": artist_id,
                "name": _safe_str(artist.get("name")) or "Unknown",
                "thumbnail": _get_thumbnail(artist),
                "image": _get_thumbnail(artist),
                "image_url": _get_thumbnail(artist),
                "songs": songs,
            },
        }
    except Exception as e:
        logger.error("Artist get error: %s", e)
        return {"success": False, "message": str(e)}


def get_trending():
    if not ytmusic:
        return {"success": True, "data": []}
    try:
        raw = ytmusic.search("top hits USA", filter="songs", limit=40) or []
        songs = []
        for r in raw:
            if r.get("videoId"):
                normalized = _normalize(r)
                if normalized:
                    songs.append(normalized)
        return {"success": True, "data": songs[:20]}
    except Exception as e:
        logger.error("Trending error: %s", e)
        return {"success": True, "data": []}


def health_check():
    configured_cookie_file = (os.environ.get("YTDLP_COOKIEFILE") or "").strip()
    cookie_source = _get_cookie_blob_source()
    cookie_blob = (cookie_source.get("blob") or "").strip()
    materialized_cookie_file = _materialize_cookiefile_from_env() if cookie_blob else None
    local_cookie_source = _discover_local_cookie_source()
    piped_instances = _load_piped_instances()
    rapidapi_key = _get_rapidapi_key()
    rapidapi_url = _get_rapidapi_url()
    rapidapi_host = _get_rapidapi_host()

    status = {
        "ytmusic": ytmusic is not None,
        "yt_dlp": YoutubeDL is not None,
        "search": False,
        "stream": YoutubeDL is not None,
        "cookiefile_configured": bool(configured_cookie_file),
        "cookiefile_exists": bool(configured_cookie_file and os.path.exists(configured_cookie_file)),
        "cookies_from_browser_configured": bool(
            (os.environ.get("YTDLP_COOKIES_FROM_BROWSER") or "").strip()
        ),
        "cookies_b64_configured": bool(cookie_blob),
        "cookie_blob_source": cookie_source.get("kind"),
        "cookie_blob_source_path": cookie_source.get("path"),
        "local_cookie_source_found": bool(local_cookie_source.get("blob")),
        "local_cookie_source_path": local_cookie_source.get("path"),
        "runtime_cookiefile_materialized": bool(materialized_cookie_file),
        "po_token_configured": bool((os.environ.get("YTDLP_PO_TOKEN") or "").strip()),
        "visitor_data_configured": bool((os.environ.get("YTDLP_VISITOR_DATA") or "").strip()),
        "stream_cache_size": len(_STREAM_CACHE),
        "stream_cache_ttl_seconds": _STREAM_CACHE_TTL_SECONDS,
        "piped_fallback_enabled": True,
        "piped_instances_count": len(piped_instances),
        "piped_instances": piped_instances,
        "external_ytdlp_enabled": _external_ytdlp_api_enabled(),
        "external_provider": "rapidapi" if _external_ytdlp_api_enabled() else None,
        "rapidapi_key_configured": bool(rapidapi_key),
        "rapidapi_url": rapidapi_url,
        "rapidapi_host": rapidapi_host,
        "allow_local_ytdlp_fallback": _allow_local_ytdlp_fallback(),
    }
    if ytmusic:
        try:
            r = ytmusic.search("test", filter="songs", limit=1)
            status["search"] = bool(r)
            if r:
                thumb = _get_thumbnail(r[0])
                status["thumbnail_test"] = thumb if thumb else "null"
        except Exception as e:
            status["search_error"] = str(e)
    return {"success": True, "data": status}
