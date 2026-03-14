import os
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from bson import ObjectId
from flask import Blueprint, g, jsonify, request

import models.db as db
from middleware.auth_middleware import token_required

auth_bp = Blueprint("auth", __name__)


def _make_token(user_id, username):
    secret = os.environ.get("JWT_SECRET", "changeme")
    payload = {
        "user_id": str(user_id),
        "username": username,
        "exp": datetime.now(tz=timezone.utc) + timedelta(days=30),
        "iat": datetime.now(tz=timezone.utc),
    }
    return jwt.encode(payload, secret, algorithm="HS256")


def _user_to_dict(user):
    user = dict(user)
    user["_id"] = str(user["_id"])
    user.pop("password_hash", None)
    return user


@auth_bp.route("/register", methods=["POST"])
def register():
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""
    display_name = (data.get("display_name") or username).strip()

    if not username:
        return jsonify({"success": False, "message": "Username is required"}), 400
    if len(password) < 6:
        return jsonify({"success": False, "message": "Password must be at least 6 characters"}), 400

    if db.users.find_one({"username": username}):
        return jsonify({"success": False, "message": "Username already taken"}), 400

    password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    now = datetime.now(tz=timezone.utc)
    result = db.users.insert_one(
        {
            "username": username,
            "password_hash": password_hash,
            "display_name": display_name,
            "profile_picture_url": None,
            "created_at": now,
            "last_login": now,
        }
    )
    user_id = result.inserted_id
    token = _make_token(user_id, username)

    db.sessions.insert_one({"user_id": str(user_id), "token": token, "is_active": True, "created_at": now})

    user = db.users.find_one({"_id": user_id})
    return jsonify({"success": True, "data": {"token": token, "user": _user_to_dict(user)}}), 201


@auth_bp.route("/login", methods=["POST"])
def login():
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""

    if not username or not password:
        return jsonify({"success": False, "message": "Username and password are required"}), 400

    user = db.users.find_one({"username": username})
    if not user:
        return jsonify({"success": False, "message": "Invalid credentials"}), 401

    if not bcrypt.checkpw(password.encode(), user["password_hash"].encode()):
        return jsonify({"success": False, "message": "Invalid credentials"}), 401

    now = datetime.now(tz=timezone.utc)
    db.users.update_one({"_id": user["_id"]}, {"$set": {"last_login": now}})

    token = _make_token(user["_id"], username)
    db.sessions.insert_one({"user_id": str(user["_id"]), "token": token, "is_active": True, "created_at": now})

    user["last_login"] = now
    return jsonify({"success": True, "data": {"token": token, "user": _user_to_dict(user)}}), 200


@auth_bp.route("/logout", methods=["POST"])
@token_required
def logout():
    db.sessions.update_one({"token": g.token}, {"$set": {"is_active": False}})
    return jsonify({"success": True, "message": "Logged out successfully"}), 200


@auth_bp.route("/me", methods=["GET"])
@token_required
def me():
    return jsonify({"success": True, "data": g.current_user}), 200
