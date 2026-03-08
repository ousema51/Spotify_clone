from datetime import datetime, timezone

from bson import ObjectId
from bson.errors import InvalidId
from flask import Blueprint, g, jsonify, request

import models.db as db
from middleware.auth_middleware import token_required

social_bp = Blueprint("social", __name__)


def _user_public(user):
    return {
        "_id": str(user["_id"]),
        "username": user.get("username"),
        "display_name": user.get("display_name"),
        "profile_picture_url": user.get("profile_picture_url"),
    }


def _get_user_or_404(user_id):
    try:
        oid = ObjectId(user_id)
    except InvalidId:
        return None, jsonify({"success": False, "message": "Invalid user ID"}), 400
    user = db.users.find_one({"_id": oid})
    if not user:
        return None, jsonify({"success": False, "message": "User not found"}), 404
    return user, None, None


# ── Follow / unfollow ────────────────────────────────────────────────────────

@social_bp.route("/<user_id>/follow", methods=["POST"])
@token_required
def follow_user(user_id):
    target, err, code = _get_user_or_404(user_id)
    if err:
        return err, code

    me = g.current_user["_id"]
    if me == user_id:
        return jsonify({"success": False, "message": "You cannot follow yourself"}), 400

    if db.followers.find_one({"follower_id": me, "following_id": user_id}):
        return jsonify({"success": False, "message": "Already following this user"}), 400

    db.followers.insert_one({"follower_id": me, "following_id": user_id, "followed_at": datetime.now(tz=timezone.utc)})
    return jsonify({"success": True, "message": "User followed"}), 201


@social_bp.route("/<user_id>/follow", methods=["DELETE"])
@token_required
def unfollow_user(user_id):
    me = g.current_user["_id"]
    result = db.followers.delete_one({"follower_id": me, "following_id": user_id})
    if result.deleted_count == 0:
        return jsonify({"success": False, "message": "You are not following this user"}), 404
    return jsonify({"success": True, "message": "User unfollowed"}), 200


# ── Public profiles ──────────────────────────────────────────────────────────

@social_bp.route("/<user_id>/profile", methods=["GET"])
def get_profile(user_id):
    user, err, code = _get_user_or_404(user_id)
    if err:
        return err, code
    return jsonify({"success": True, "data": _user_public(user)}), 200


@social_bp.route("/<user_id>/playlists", methods=["GET"])
def get_user_playlists(user_id):
    user, err, code = _get_user_or_404(user_id)
    if err:
        return err, code

    cursor = db.playlists.find({"owner_id": user_id, "is_public": True}).sort("created_at", -1)
    result = []
    for pl in cursor:
        pl = dict(pl)
        pl["_id"] = str(pl["_id"])
        for key, value in pl.items():
            if isinstance(value, datetime):
                pl[key] = value.isoformat()
        result.append(pl)
    return jsonify({"success": True, "data": result}), 200


@social_bp.route("/<user_id>/followers", methods=["GET"])
def get_followers(user_id):
    _, err, code = _get_user_or_404(user_id)
    if err:
        return err, code

    docs = list(db.followers.find({"following_id": user_id}))
    follower_oids = []
    for d in docs:
        try:
            follower_oids.append(ObjectId(d["follower_id"]))
        except InvalidId:
            pass
    users = [_user_public(u) for u in db.users.find({"_id": {"$in": follower_oids}})]
    return jsonify({"success": True, "data": users}), 200


@social_bp.route("/<user_id>/following", methods=["GET"])
def get_following(user_id):
    _, err, code = _get_user_or_404(user_id)
    if err:
        return err, code

    docs = list(db.followers.find({"follower_id": user_id}))
    following_oids = []
    for d in docs:
        try:
            following_oids.append(ObjectId(d["following_id"]))
        except InvalidId:
            pass
    users = [_user_public(u) for u in db.users.find({"_id": {"$in": following_oids}})]
    return jsonify({"success": True, "data": users}), 200
