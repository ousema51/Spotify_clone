# Spotify Clone — Backend API

A Python Flask REST API designed to be deployed on **Vercel** (serverless). Provides authentication, music search via YouTube Music (ytmusicapi), user libraries, playlists, listening history, and social features.

---

## Project Structure

```
backend/
├── api/
│   └── index.py          # Main Flask app entry point (required by Vercel)
├── routes/
│   ├── auth.py           # Register / login / logout / me
│   ├── music.py          # YouTube Music proxy (search, songs, albums, artists, trending)
│   ├── library.py        # Liked songs
│   ├── playlists.py      # Playlist CRUD + follow/unfollow
│   ├── listening.py      # Listening history + smart suggestions
│   ├── social.py         # Follow/unfollow users, public profiles
│   └── users.py          # User profile management
├── middleware/
│   └── auth_middleware.py # JWT token_required decorator
├── models/
│   └── db.py             # MongoDB connection + collection references
├── utils/
│   └── youtube_music.py  # YouTube Music helper functions (ytmusicapi)
├── requirements.txt
├── vercel.json
├── .env.example
└── README.md
```

---

## Prerequisites

- Python 3.9+
- A [MongoDB Atlas](https://www.mongodb.com/cloud/atlas) cluster
- (Optional) A [Vercel](https://vercel.com) account for deployment

---

## Setup

### 1. Install dependencies

```bash
cd backend
pip install -r requirements.txt
```

### 2. Configure environment variables

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

| Variable            | Description                                              |
|---------------------|----------------------------------------------------------|
| `MONGODB_URI`       | MongoDB Atlas connection string                          |
| `JWT_SECRET`        | Secret key used to sign JWT tokens (keep this secret!)   |
| `YTDLP_COOKIEFILE`  | Absolute path to Netscape-format YouTube cookies file    |
| `YTDLP_COOKIES_B64` | Base64 string of Netscape-format YouTube cookies file    |
| `YTDLP_COOKIES_FROM_BROWSER` | Browser cookie source for yt-dlp (`chrome:Default`, etc.) |
| `YTDLP_PO_TOKEN`    | Optional yt-dlp YouTube PO token for restricted videos   |
| `YTDLP_VISITOR_DATA`| Optional YouTube visitor data used with `YTDLP_PO_TOKEN` |
| `YTDLP_PROVIDER`    | Set to `rapidapi` to prefer external yt-dlp API          |
| `YTDLP_RAPIDAPI_KEY`| RapidAPI key for external yt-dlp API                     |
| `YTDLP_RAPIDAPI_HOST`| RapidAPI host (default `youtube-mp310.p.rapidapi.com`)    |
| `YTDLP_RAPIDAPI_URL`| RapidAPI primary endpoint URL (default `https://youtube-mp310.p.rapidapi.com/download/mp3`) |
| `YTDLP_RAPIDAPI_STATUS_URL`| Optional status endpoint URL for request-id polling (used by status-based providers) |
| `YTDLP_RAPIDAPI_FORMAT`| Requested format for RapidAPI download requests (default `mp3`) |
| `YTDLP_RAPIDAPI_AUDIO_QUALITY`| Legacy option for `ajax/download.php` providers (default `128`) |
| `YTDLP_RAPIDAPI_QUALITY`| Legacy quality fallback used when `YTDLP_RAPIDAPI_AUDIO_QUALITY` is unset |
| `YTDLP_RAPIDAPI_ADD_INFO`| Legacy option for `ajax/download.php` providers (default `0`) |
| `YTDLP_RAPIDAPI_ALLOW_EXTENDED_DURATION`| Legacy option for `ajax/download.php` providers (default `false`) |
| `YTDLP_RAPIDAPI_NO_MERGE`| Legacy option for `ajax/download.php` providers (default `false`) |
| `YTDLP_RAPIDAPI_AUDIO_LANGUAGE`| Legacy option for `ajax/download.php` providers (default `en`) |
| `YTDLP_RAPIDAPI_CALLBACK_URL`| Optional callback URL forwarded to provider |
| `YTDLP_EXTERNAL_TIMEOUT_SECONDS`| External API timeout in seconds (default `60` for this provider) |
| `YTDLP_RAPIDAPI_TRY_ALT_PATHS` | `1` to probe alternate RapidAPI paths if default URL fails |
| `YTDLP_ALLOW_LOCAL_FALLBACK` | Legacy option (ignored in current external-only provider mode) |

Cookie loading priority used by this backend:
1. `YTDLP_COOKIES_B64` / `YTDLP_COOKIES_BASE64`
2. `YTDLP_COOKIEFILE`
3. Local file fallback in `backend/cookies/` (`cookie.b64`, `cookies.b64`, `cookie.txt`, `cookies.txt`)

The backend also auto-converts raw `Cookie:` header strings into Netscape cookie format, so `backend/cookies/cookie.txt` can contain either Netscape cookies or a single cookie header line.

If yt-dlp still fails (for example YouTube bot challenge), backend automatically falls back to Piped stream resolution. You can override instances via `PIPED_INSTANCES` (comma-separated URLs).

When `YTDLP_PROVIDER=rapidapi` (or `YTDLP_RAPIDAPI_KEY` is set), backend resolves streams using only the external provider endpoint. By default it calls `GET /download/mp3` on `youtube-mp310.p.rapidapi.com` with the `url` query parameter set to the YouTube watch URL.

If a provider returns a session-bound intermediate URL (for example links that fail with `Invalid Session` when fetched by backend proxy), backend automatically falls back to Piped stream resolution and then local yt-dlp extraction when available.

### 3. Run locally

```bash
cd backend
flask --app api/index.py run --debug
```

The API will be available at `http://127.0.0.1:5000`.

---

## Deploy to Vercel

```bash
cd backend
vercel deploy
```

Set the environment variables in the Vercel dashboard (Project → Settings → Environment Variables).

---

## API Reference

All responses follow the structure:

```json
{ "success": true | false, "data": ..., "message": "..." }
```

### Authentication (`/api/auth`)

| Method | Path                  | Auth | Description              |
|--------|-----------------------|------|--------------------------|
| POST   | `/api/auth/register`  | —    | Create a new account     |
| POST   | `/api/auth/login`     | —    | Login and get JWT token  |
| POST   | `/api/auth/logout`    | ✓    | Invalidate current token |
| GET    | `/api/auth/me`        | ✓    | Get current user info    |

### Music (`/api/music`)

| Method | Path                        | Auth | Description                     |
|--------|-----------------------------|------|---------------------------------|
| GET    | `/api/music/search`         | —    | Search (`?q=&type=songs|albums|artists|all`) |
| GET    | `/api/music/song/<id>`      | —    | Get song details                |
| GET    | `/api/music/stream/<id>`    | —    | Resolve stream payload (returns proxy-backed `audio_url`) |
| GET    | `/api/music/stream`         | —    | Resolve stream by query (`?q=`) |
| GET    | `/api/music/stream-proxy/<id>` | — | Audio proxy endpoint with range support for web/mobile playback |
| GET    | `/api/music/album/<id>`     | —    | Get album details               |
| GET    | `/api/music/artist/<id>`    | —    | Get artist details              |
| GET    | `/api/music/trending`       | —    | Get trending songs              |

### Library (`/api/library`)

| Method | Path                              | Auth | Description             |
|--------|-----------------------------------|------|-------------------------|
| GET    | `/api/library/liked`              | ✓    | Get liked songs         |
| POST   | `/api/library/like/<song_id>`     | ✓    | Like a song             |
| DELETE | `/api/library/like/<song_id>`     | ✓    | Unlike a song           |
| GET    | `/api/library/liked/check/<id>`   | ✓    | Check if song is liked  |

### Playlists (`/api/playlists`)

| Method | Path                                      | Auth | Description                        |
|--------|-------------------------------------------|------|------------------------------------|
| GET    | `/api/playlists/mine`                     | ✓    | Get own playlists                  |
| POST   | `/api/playlists`                          | ✓    | Create a playlist                  |
| GET    | `/api/playlists/<id>`                     | —*   | Get playlist details               |
| PUT    | `/api/playlists/<id>`                     | ✓    | Update playlist                    |
| DELETE | `/api/playlists/<id>`                     | ✓    | Delete playlist                    |
| POST   | `/api/playlists/<id>/songs`               | ✓    | Add song to playlist               |
| DELETE | `/api/playlists/<id>/songs/<song_id>`     | ✓    | Remove song from playlist          |
| POST   | `/api/playlists/<id>/follow`              | ✓    | Follow a public playlist           |
| DELETE | `/api/playlists/<id>/follow`              | ✓    | Unfollow a playlist                |
| GET    | `/api/playlists/following`                | ✓    | Get followed playlists             |

*Public playlists are accessible without auth; private ones require ownership.

### Listening History & Suggestions

| Method | Path                    | Auth | Description                      |
|--------|-------------------------|------|----------------------------------|
| POST   | `/api/listen/track`     | ✓    | Log a play event                 |
| GET    | `/api/history/recent`   | ✓    | Get recently played songs        |
| GET    | `/api/suggestions`      | ✓    | Get smart song suggestions       |

### Social (`/api/users`)

| Method | Path                              | Auth | Description                    |
|--------|-----------------------------------|------|--------------------------------|
| POST   | `/api/users/<id>/follow`          | ✓    | Follow a user                  |
| DELETE | `/api/users/<id>/follow`          | ✓    | Unfollow a user                |
| GET    | `/api/users/<id>/profile`         | —    | Get public profile             |
| GET    | `/api/users/<id>/playlists`       | —    | Get user's public playlists    |
| GET    | `/api/users/<id>/followers`       | —    | Get user's followers           |
| GET    | `/api/users/<id>/following`       | —    | Get who the user follows       |

### User Profile (`/api/users`)

| Method | Path                    | Auth | Description                    |
|--------|-------------------------|------|--------------------------------|
| PUT    | `/api/users/profile`    | ✓    | Update own profile             |
| GET    | `/api/users/search`     | —    | Search users (`?q=query`)      |

---

## Authentication

Protected endpoints require a JWT bearer token in the `Authorization` header:

```
Authorization: Bearer <token>
```

Tokens are issued on register/login and expire after **30 days**.
