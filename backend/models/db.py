import os
from pymongo import MongoClient, ASCENDING

_client = None
_db = None

# Collection references (set after init_db is called)
users = None
sessions = None
liked_songs = None
playlists = None
playlist_follows = None
listening_history = None
followers = None

_initialized = False


def _ensure_initialized():
    """Lazy initialization — called before any DB operation."""
    global _initialized
    if not _initialized or users is None:
        init_db()


def get_db():
    _ensure_initialized()
    return _db


def init_db():
    global _client, _db, _initialized
    global users, sessions, liked_songs, playlists
    global playlist_follows, listening_history, followers

    uri = os.environ.get("MONGODB_URI")
    if not uri:
        raise RuntimeError("MONGODB_URI environment variable is not set")

    _client = MongoClient(uri, serverSelectionTimeoutMS=5000, connectTimeoutMS=5000)
    _db = _client["music_app_db"]

    # Bind collection references
    users = _db["users"]
    sessions = _db["sessions"]
    liked_songs = _db["liked_songs"]
    playlists = _db["playlists"]
    playlist_follows = _db["playlist_follows"]
    listening_history = _db["listening_history"]
    followers = _db["followers"]

    # Create indexes (idempotent)
    try:
        users.create_index([("username", ASCENDING)], unique=True)
        liked_songs.create_index([("user_id", ASCENDING), ("song_id", ASCENDING)], unique=True)
        listening_history.create_index([("user_id", ASCENDING), ("song_id", ASCENDING)])
        playlist_follows.create_index([("user_id", ASCENDING), ("playlist_id", ASCENDING)], unique=True)
        followers.create_index([("follower_id", ASCENDING), ("following_id", ASCENDING)], unique=True)
    except Exception as exc:
        print(f"[WARNING] Could not create indexes: {exc}", flush=True)

    _initialized = True
