from datetime import datetime, timezone

from flask import Blueprint, g, jsonify, request

import models.db as db
from middleware.auth_middleware import token_required
from utils import jiosaavn

listening_bp = Blueprint("listening", __name__)

_DEFAULT_LIMIT = 20


def _history_to_dict(doc):
    doc = dict(doc)
    doc["_id"] = str(doc["_id"])
    for key, value in doc.items():
        if isinstance(value, datetime):
            doc[key] = value.isoformat()
    return doc


@listening_bp.route("/listen/track", methods=["POST"])
@token_required
def track_listen():
    data = request.get_json(silent=True) or {}
    song_id = (data.get("song_id") or "").strip()
    if not song_id:
        return jsonify({"success": False, "message": "song_id is required"}), 400

    song_meta = data.get("song_metadata") or {}
    listened_seconds = float(data.get("listened_seconds", 0))
    total_duration = float(data.get("total_duration", 0))
    completed = total_duration > 0 and listened_seconds >= total_duration * 0.8

    user_id = g.current_user["_id"]
    now = datetime.now(tz=timezone.utc)

    existing = db.listening_history.find_one({"user_id": user_id, "song_id": song_id})
    if existing:
        new_play_count = existing.get("play_count", 1) + 1
        new_total_time = existing.get("total_listen_time_seconds", 0) + listened_seconds
        db.listening_history.update_one(
            {"_id": existing["_id"]},
            {
                "$set": {
                    "play_count": new_play_count,
                    "total_listen_time_seconds": new_total_time,
                    "last_listened_at": now,
                    "completed": completed,
                }
            },
        )
    else:
        db.listening_history.insert_one(
            {
                "user_id": user_id,
                "song_id": song_id,
                "title": song_meta.get("title"),
                "artist": song_meta.get("artist"),
                "cover_url": song_meta.get("cover_url"),
                "duration": song_meta.get("duration"),
                "play_count": 1,
                "total_listen_time_seconds": listened_seconds,
                "completed": completed,
                "last_listened_at": now,
                "first_listened_at": now,
            }
        )

    return jsonify({"success": True, "message": "Play event recorded"}), 200


@listening_bp.route("/history/recent", methods=["GET"])
@token_required
def recent_history():
    user_id = g.current_user["_id"]
    page = int(request.args.get("page", 1))
    limit = int(request.args.get("limit", _DEFAULT_LIMIT))
    skip = (page - 1) * limit

    cursor = db.listening_history.find({"user_id": user_id}).sort("last_listened_at", -1).skip(skip).limit(limit)
    songs = [_history_to_dict(s) for s in cursor]
    total = db.listening_history.count_documents({"user_id": user_id})

    return jsonify({"success": True, "data": {"songs": songs, "total": total, "page": page, "limit": limit}}), 200


@listening_bp.route("/suggestions", methods=["GET"])
@token_required
def suggestions():
    user_id = g.current_user["_id"]

    # 1. Get user's full listening history
    history = list(db.listening_history.find({"user_id": user_id}))

    # 2. Rank songs by play_count * completion_rate
    for item in history:
        play_count = item.get("play_count", 1)
        total_time = item.get("total_listen_time_seconds", 0)
        duration = item.get("duration") or 0
        if duration and duration > 0:
            completion_rate = min(total_time / (play_count * duration), 1.0)
        else:
            completion_rate = 1.0 if item.get("completed") else 0.5
        item["_score"] = play_count * completion_rate

    history.sort(key=lambda x: x["_score"], reverse=True)

    # 3. Extract top 5 artists
    artist_counts: dict = {}
    for item in history:
        artist = item.get("artist")
        if artist:
            artist_counts[artist] = artist_counts.get(artist, 0) + item.get("_score", 1)
    top_artists = sorted(artist_counts, key=lambda a: artist_counts[a], reverse=True)[:5]

    # Recently listened song IDs to filter out
    recent_ids = {item["song_id"] for item in history[:50]}

    # 4. Fetch top songs for each top artist
    suggested: list = []
    for artist_name in top_artists:
        result = jiosaavn.search_artists(artist_name, limit=1)
        artists_data = (result.get("data") or {}).get("results") or []
        if not artists_data:
            continue
        artist_id = artists_data[0].get("id")
        if not artist_id:
            continue
        artist_detail = jiosaavn.get_artist_by_id(artist_id)
        top_songs = (
            (artist_detail.get("data") or {}).get("topSongs")
            or (artist_detail.get("data") or {}).get("songs")
            or []
        )
        for song in top_songs[:10]:
            sid = song.get("id")
            if sid and sid not in recent_ids:
                suggested.append(song)
                recent_ids.add(sid)

    # 5. Mix with trending if we don't have enough
    if len(suggested) < 20:
        trending = jiosaavn.get_trending()
        trending_songs = (trending.get("data") or [])
        if isinstance(trending_songs, dict):
            trending_songs = trending_songs.get("songs") or trending_songs.get("results") or []
        for song in trending_songs:
            if len(suggested) >= 20:
                break
            sid = song.get("id")
            if sid and sid not in recent_ids:
                suggested.append(song)
                recent_ids.add(sid)

    return jsonify({"success": True, "data": suggested[:20]}), 200
