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
