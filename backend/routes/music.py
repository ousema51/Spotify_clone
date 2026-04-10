from flask import Blueprint, jsonify, request
import traceback

from utils import youtube_music

music_bp = Blueprint("music", __name__)


def _normalize_stream_payload(payload, fallback_video_id=None):
    if not isinstance(payload, dict):
        return None

    audio_url = payload.get("audio_url") or payload.get("stream_url") or payload.get("url")
    if audio_url is None:
        return None

    audio_url = str(audio_url).strip()
    if not audio_url:
        return None

    raw_headers = payload.get("headers") or {}
    headers = {}
    if isinstance(raw_headers, dict):
        for key, value in raw_headers.items():
            k = str(key).strip()
            v = str(value).strip()
            if k and v:
                headers[k] = v

    duration_raw = payload.get("duration")
    duration = None
    if duration_raw is not None:
        try:
            duration = int(float(duration_raw))
        except Exception:
            duration = None

    video_id = (
        payload.get("video_id")
        or payload.get("videoId")
        or payload.get("id")
        or fallback_video_id
    )
    if video_id is not None:
        video_id = str(video_id).strip() or None

    title = payload.get("title")
    if title is not None:
        title = str(title).strip() or None

    source = payload.get("source")
    if source is not None:
        source = str(source).strip() or None

    return {
        "audio_url": audio_url,
        "headers": headers,
        "video_id": video_id,
        "title": title,
        "duration": duration,
        "source": source or "yt-dlp",
    }


@music_bp.route("/search", methods=["GET"])
def search():
    query = (request.args.get("q") or "").strip()
    search_type = (request.args.get("type") or "all").lower()
    try:
        page = int(request.args.get("page", 1))
    except Exception:
        return jsonify({"success": False, "message": "Invalid 'page' parameter"}), 400
    try:
        limit = int(request.args.get("limit", 20))
    except Exception:
        return jsonify({"success": False, "message": "Invalid 'limit' parameter"}), 400

    if not query:
        return jsonify({"success": False, "message": "Query parameter 'q' is required"}), 400

    try:
        print("[search] q={} type={} page={} limit={}".format(repr(query), search_type, page, limit), flush=True)
        if search_type == "songs":
            result = youtube_music.search_songs(query, page=page, limit=limit)
        elif search_type == "albums":
            result = youtube_music.search_albums(query, page=page, limit=limit)
        elif search_type == "artists":
            result = youtube_music.search_artists(query, page=page, limit=limit)
        else:
            result = youtube_music.search_all(query)

        if isinstance(result, list):
            data = result
        elif isinstance(result, dict):
            if result.get("success") is False:
                print("[search] error: {}".format(result.get("message")), flush=True)
                return jsonify({"success": False, "message": result.get("message", "Search failed")}), 502
            data = result.get("data", None)
        else:
            data = result

        try:
            count = len(data) if data is not None else 0
        except Exception:
            count = 1
        print("[search] returned {} result(s)".format(count), flush=True)

        return jsonify({"success": True, "data": data}), 200
    except Exception as e:
        print("[search] exception:", flush=True)
        traceback.print_exc()
        return jsonify({"success": False, "message": str(e)}), 500


@music_bp.route("/song/<song_id>", methods=["GET"])
def get_song(song_id):
    result = youtube_music.get_song_by_id(song_id)
    if result.get("success") is False and "message" in result:
        return jsonify({"success": False, "message": result["message"]}), 502
    return jsonify({"success": True, "data": result.get("data", result)}), 200


@music_bp.route("/stream/<video_id>", methods=["GET"])
def get_stream(video_id):
    try:
        result = youtube_music.get_stream_url(video_id)
    except Exception as e:
        print("[stream] exception while resolving stream:", flush=True)
        traceback.print_exc()
        return jsonify({"success": False, "message": str(e)}), 500

    if not isinstance(result, dict):
        return jsonify({"success": False, "message": "Invalid stream resolver response"}), 502

    if result.get("success") is False:
        return jsonify({"success": False, "message": result.get("message", "Stream resolution failed")}), 502

    normalized = _normalize_stream_payload(result.get("data", result), fallback_video_id=video_id)
    if not normalized:
        return jsonify({"success": False, "message": "Invalid stream payload"}), 502

    return jsonify({"success": True, "data": normalized}), 200


@music_bp.route("/stream", methods=["GET"])
def get_stream_from_query():
    query = (request.args.get("q") or "").strip()
    if not query:
        return jsonify({"success": False, "message": "Query parameter 'q' is required"}), 400

    try:
        result = youtube_music.get_stream_from_search(query)
    except Exception as e:
        print("[stream-search] exception while resolving stream:", flush=True)
        traceback.print_exc()
        return jsonify({"success": False, "message": str(e)}), 500

    if not isinstance(result, dict):
        return jsonify({"success": False, "message": "Invalid stream resolver response"}), 502

    if result.get("success") is False:
        return jsonify({"success": False, "message": result.get("message", "Stream search resolution failed")}), 502

    normalized = _normalize_stream_payload(result.get("data", result))
    if not normalized:
        return jsonify({"success": False, "message": "Invalid stream payload"}), 502

    return jsonify({"success": True, "data": normalized}), 200


@music_bp.route("/album/<album_id>", methods=["GET"])
def get_album(album_id):
    result = youtube_music.get_album_by_id(album_id)
    if result.get("success") is False and "message" in result:
        return jsonify({"success": False, "message": result["message"]}), 502
    return jsonify({"success": True, "data": result.get("data", result)}), 200


@music_bp.route("/artist/<artist_id>", methods=["GET"])
def get_artist(artist_id):
    result = youtube_music.get_artist_by_id(artist_id)
    if result.get("success") is False and "message" in result:
        return jsonify({"success": False, "message": result["message"]}), 502
    return jsonify({"success": True, "data": result.get("data", result)}), 200


@music_bp.route("/trending", methods=["GET"])
def trending():
    result = youtube_music.get_trending()
    if result.get("success") is False and "message" in result:
        return jsonify({"success": False, "message": result["message"]}), 502
    return jsonify({"success": True, "data": result.get("data", result)}), 200


@music_bp.route("/health", methods=["GET"])
def music_health():
    result = youtube_music.health_check()
    return jsonify(result), 200