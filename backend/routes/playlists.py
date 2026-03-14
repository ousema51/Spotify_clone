import os
from datetime import datetime, timezone

import jwt as _jwt
from bson import ObjectId
from bson.errors import InvalidId
from flask import Blueprint, g, jsonify, request

import models.db as db
from middleware.auth_middleware import token_required

playlists_bp = Blueprint("playlists", __name__)


def _pl_to_dict(pl):
    pl = dict(pl)
    pl["_id"] = str(pl["_id"])
    return pl


def _get_playlist_or_404(playlist_id):
    try:
        oid = ObjectId(playlist_id)
    except InvalidId:
        return None, jsonify({"success": False, "message": "Invalid playlist ID"}), 400
    pl = db.playlists.find_one({"_id": oid})
    if not pl:
        return None, jsonify({"success": False, "message": "Playlist not found"}), 404
    return pl, None, None


# ── Owner's playlists ────────────────────────────────────────────────────────

@playlists_bp.route("/mine", methods=["GET"])
@token_required
def get_mine():
    user_id = g.current_user["_id"]
    cursor = db.playlists.find({"owner_id": user_id}).sort("created_at", -1)
    return jsonify({"success": True, "data": [_pl_to_dict(p) for p in cursor]}), 200


@playlists_bp.route("", methods=["POST"])
@token_required
def create_playlist():
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    if not name:
        return jsonify({"success": False, "message": "Playlist name is required"}), 400

    now = datetime.now(tz=timezone.utc)
    doc = {
        "owner_id": g.current_user["_id"],
        "name": name,
        "description": data.get("description", ""),
        "is_public": bool(data.get("is_public", True)),
        "songs": [],
        "created_at": now,
        "updated_at": now,
    }
    result = db.playlists.insert_one(doc)
    doc["_id"] = str(result.inserted_id)
    return jsonify({"success": True, "data": doc}), 201


# ── Single playlist ──────────────────────────────────────────────────────────

@playlists_bp.route("/<playlist_id>", methods=["GET"])
def get_playlist(playlist_id):
    pl, err, code = _get_playlist_or_404(playlist_id)
    if err:
        return err, code

    requesting_user_id = None
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header.split(" ", 1)[1].strip()
        try:
            payload = _jwt.decode(token, os.environ.get("JWT_SECRET", "changeme"), algorithms=["HS256"])
            requesting_user_id = payload.get("user_id")
        except Exception:
            pass

    if not pl["is_public"] and pl["owner_id"] != requesting_user_id:
        return jsonify({"success": False, "message": "Access denied"}), 403

    return jsonify({"success": True, "data": _pl_to_dict(pl)}), 200


@playlists_bp.route("/<playlist_id>", methods=["PUT"])
@token_required
def update_playlist(playlist_id):
    pl, err, code = _get_playlist_or_404(playlist_id)
    if err:
        return err, code
    if pl["owner_id"] != g.current_user["_id"]:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    data = request.get_json(silent=True) or {}
    updates = {}
    if "name" in data:
        name = data["name"].strip()
        if not name:
            return jsonify({"success": False, "message": "Playlist name cannot be empty"}), 400
        updates["name"] = name
    if "description" in data:
        updates["description"] = data["description"]
    if "is_public" in data:
        updates["is_public"] = bool(data["is_public"])
    updates["updated_at"] = datetime.now(tz=timezone.utc)

    db.playlists.update_one({"_id": pl["_id"]}, {"$set": updates})
    updated = db.playlists.find_one({"_id": pl["_id"]})
    return jsonify({"success": True, "data": _pl_to_dict(updated)}), 200


@playlists_bp.route("/<playlist_id>", methods=["DELETE"])
@token_required
def delete_playlist(playlist_id):
    pl, err, code = _get_playlist_or_404(playlist_id)
    if err:
        return err, code
    if pl["owner_id"] != g.current_user["_id"]:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    db.playlists.delete_one({"_id": pl["_id"]})
    db.playlist_follows.delete_many({"playlist_id": playlist_id})
    return jsonify({"success": True, "message": "Playlist deleted"}), 200


# ── Playlist songs ───────────────────────────────────────────────────────────

@playlists_bp.route("/<playlist_id>/songs", methods=["POST"])
@token_required
def add_song(playlist_id):
    pl, err, code = _get_playlist_or_404(playlist_id)
    if err:
        return err, code
    if pl["owner_id"] != g.current_user["_id"]:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    data = request.get_json(silent=True) or {}
    song_id = (data.get("song_id") or "").strip()
    if not song_id:
        return jsonify({"success": False, "message": "song_id is required"}), 400

    # Prevent duplicates
    if any(s.get("song_id") == song_id for s in pl.get("songs", [])):
        return jsonify({"success": False, "message": "Song already in playlist"}), 400

    song_entry = {
        "song_id": song_id,
        "title": data.get("title"),
        "artist": data.get("artist"),
        "cover_url": data.get("cover_url"),
        "duration": data.get("duration"),
        "added_at": datetime.now(tz=timezone.utc).isoformat(),
    }
    db.playlists.update_one(
        {"_id": pl["_id"]},
        {"$push": {"songs": song_entry}, "$set": {"updated_at": datetime.now(tz=timezone.utc)}},
    )
    return jsonify({"success": True, "message": "Song added to playlist"}), 201


@playlists_bp.route("/<playlist_id>/songs/<song_id>", methods=["DELETE"])
@token_required
def remove_song(playlist_id, song_id):
    pl, err, code = _get_playlist_or_404(playlist_id)
    if err:
        return err, code
    if pl["owner_id"] != g.current_user["_id"]:
        return jsonify({"success": False, "message": "Forbidden"}), 403

    db.playlists.update_one(
        {"_id": pl["_id"]},
        {"$pull": {"songs": {"song_id": song_id}}, "$set": {"updated_at": datetime.now(tz=timezone.utc)}},
    )
    return jsonify({"success": True, "message": "Song removed from playlist"}), 200


# ── Follow / unfollow ────────────────────────────────────────────────────────

@playlists_bp.route("/<playlist_id>/follow", methods=["POST"])
@token_required
def follow_playlist(playlist_id):
    pl, err, code = _get_playlist_or_404(playlist_id)
    if err:
        return err, code
    if not pl["is_public"]:
        return jsonify({"success": False, "message": "Cannot follow a private playlist"}), 403

    user_id = g.current_user["_id"]
    if db.playlist_follows.find_one({"user_id": user_id, "playlist_id": playlist_id}):
        return jsonify({"success": False, "message": "Already following this playlist"}), 400

    db.playlist_follows.insert_one({"user_id": user_id, "playlist_id": playlist_id, "followed_at": datetime.now(tz=timezone.utc)})
    return jsonify({"success": True, "message": "Playlist followed"}), 201


@playlists_bp.route("/<playlist_id>/follow", methods=["DELETE"])
@token_required
def unfollow_playlist(playlist_id):
    user_id = g.current_user["_id"]
    result = db.playlist_follows.delete_one({"user_id": user_id, "playlist_id": playlist_id})
    if result.deleted_count == 0:
        return jsonify({"success": False, "message": "You are not following this playlist"}), 404
    return jsonify({"success": True, "message": "Playlist unfollowed"}), 200


@playlists_bp.route("/following", methods=["GET"])
@token_required
def get_following():
    user_id = g.current_user["_id"]
    follows = list(db.playlist_follows.find({"user_id": user_id}))
    playlist_ids = []
    for f in follows:
        try:
            playlist_ids.append(ObjectId(f["playlist_id"]))
        except InvalidId:
            pass

    result = []
    for pl in db.playlists.find({"_id": {"$in": playlist_ids}}):
        result.append(_pl_to_dict(pl))

    return jsonify({"success": True, "data": result}), 200
