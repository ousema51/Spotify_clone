import os
import sys
import unittest
from unittest.mock import patch


BACKEND_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if BACKEND_ROOT not in sys.path:
    sys.path.insert(0, BACKEND_ROOT)

from utils import youtube_music


class YoutubeMusicFallbackTests(unittest.TestCase):
    def setUp(self):
        youtube_music._STREAM_CACHE.clear()
        self._env_patcher = patch.dict(
            os.environ,
            {
                "YTDLP_PROVIDER": "",
                "YTDLP_RAPIDAPI_KEY": "",
                "RAPIDAPI_KEY": "",
                "YTDLP_ALLOW_LOCAL_FALLBACK": "",
                "YTDLP_DISABLE_EMBEDDED_RAPIDAPI_KEY": "1",
            },
            clear=False,
        )
        self._env_patcher.start()

    def tearDown(self):
        self._env_patcher.stop()

    def test_get_stream_url_returns_error_when_external_provider_disabled(self):
        with patch.dict(
            os.environ,
            {
                "YTDLP_PROVIDER": "",
                "YTDLP_RAPIDAPI_KEY": "",
                "RAPIDAPI_KEY": "",
                "YTDLP_DISABLE_EMBEDDED_RAPIDAPI_KEY": "1",
            },
            clear=False,
        ):
            result = youtube_music.get_stream_url("GwrLUr01NOY")

        self.assertFalse(result["success"])
        self.assertEqual(result.get("error_code"), "external_disabled")
        self.assertIn("external provider", result.get("message", "").lower())

    def test_get_stream_url_uses_external_api_when_enabled(self):
        external_success = {
            "success": True,
            "data": {
                "audio_url": "https://rapidapi.example/stream.webm",
                "headers": {},
                "video_id": "GwrLUr01NOY",
                "source": "rapidapi-yt-dlp",
            },
        }

        with patch.dict(os.environ, {"YTDLP_PROVIDER": "rapidapi", "YTDLP_RAPIDAPI_KEY": "key"}, clear=False):
            with patch.object(youtube_music, "_resolve_stream_from_external_api", return_value=external_success):
                with patch.object(youtube_music, "_resolve_stream_from_yt_dlp") as mocked_local:
                    with patch.object(youtube_music, "_resolve_stream_from_piped") as mocked_piped:
                        result = youtube_music.get_stream_url("GwrLUr01NOY")

        self.assertTrue(result["success"])
        self.assertEqual(result["data"]["source"], "rapidapi-yt-dlp")
        mocked_local.assert_not_called()
        mocked_piped.assert_not_called()

    def test_get_stream_url_reports_external_failure_without_local_or_piped_fallback(self):
        external_failure = {
            "success": False,
            "error_code": "external_http_error",
            "message": "RapidAPI yt-dlp returned status 500",
        }

        with patch.dict(os.environ, {"YTDLP_PROVIDER": "rapidapi", "YTDLP_RAPIDAPI_KEY": "key"}, clear=False):
            with patch.object(youtube_music, "_resolve_stream_from_external_api", return_value=external_failure):
                with patch.object(youtube_music, "_resolve_stream_from_yt_dlp") as mocked_local:
                    with patch.object(youtube_music, "_resolve_stream_from_piped") as mocked_piped:
                        result = youtube_music.get_stream_url("GwrLUr01NOY")

        self.assertFalse(result["success"])
        self.assertEqual(result.get("error_code"), "external_http_error")
        self.assertIn("status 500", result.get("message", ""))
        mocked_local.assert_not_called()
        mocked_piped.assert_not_called()

    def test_get_stream_url_uses_piped_fallback_on_region_restriction(self):
        external_failure = {
            "success": False,
            "error_code": "external_http_error",
            "status_code": 406,
            "message": "Unable to download video due to regional restrictions",
        }
        piped_success = {
            "success": True,
            "data": {
                "audio_url": "https://piped.example/audio.webm",
                "headers": {},
                "video_id": "GwrLUr01NOY",
                "source": "piped",
            },
        }

        with patch.dict(os.environ, {"YTDLP_PROVIDER": "rapidapi", "YTDLP_RAPIDAPI_KEY": "key"}, clear=False):
            with patch.object(youtube_music, "_resolve_stream_from_external_api", return_value=external_failure):
                with patch.object(youtube_music, "_resolve_stream_from_piped", return_value=piped_success) as mocked_piped:
                    with patch.object(youtube_music, "_resolve_stream_from_yt_dlp") as mocked_local:
                        result = youtube_music.get_stream_url("GwrLUr01NOY")

        self.assertTrue(result["success"])
        self.assertEqual(result["data"]["audio_url"], "https://piped.example/audio.webm")
        self.assertEqual(result["data"].get("fallback_reason"), "regional_restriction")
        self.assertEqual(result["data"].get("fallback_source"), "piped")
        mocked_piped.assert_called_once()
        mocked_local.assert_not_called()

    def test_get_stream_from_search_skips_region_restricted_candidate(self):
        with patch.object(
            youtube_music,
            "search_songs",
            return_value={
                "success": True,
                "data": [
                    {"id": "GwrLUr01NOY", "title": "Blocked Candidate"},
                    {"id": "Ckom3gf57Yw", "title": "Playable Candidate"},
                ],
            },
        ):
            with patch.object(
                youtube_music,
                "get_stream_url",
                side_effect=[
                    {
                        "success": False,
                        "error_code": "external_http_error",
                        "status_code": 406,
                        "message": "Unable to download video due to regional restrictions",
                    },
                    {
                        "success": True,
                        "data": {
                            "audio_url": "https://cdn.example.com/ok.mp3",
                            "video_id": "Ckom3gf57Yw",
                            "source": "rapidapi-yt-dlp",
                        },
                    },
                ],
            ) as mocked_get_stream:
                result = youtube_music.get_stream_from_search("query")

        self.assertTrue(result["success"])
        self.assertEqual(result["data"]["video_id"], "Ckom3gf57Yw")
        self.assertEqual(mocked_get_stream.call_count, 2)

    def test_get_stream_from_search_uses_search_then_external_by_id(self):
        with patch.object(
            youtube_music,
            "search_songs",
            return_value={
                "success": True,
                "data": [{"id": "GwrLUr01NOY", "title": "Any Song"}],
            },
        ):
            with patch.object(
                youtube_music,
                "get_stream_url",
                return_value={
                    "success": True,
                    "data": {
                        "audio_url": "https://rapidapi.example/out.mp3",
                        "video_id": "GwrLUr01NOY",
                        "source": "rapidapi-yt-dlp",
                    },
                },
            ) as mocked_get_stream:
                result = youtube_music.get_stream_from_search("some query")

        self.assertTrue(result["success"])
        mocked_get_stream.assert_called_once_with("GwrLUr01NOY")

    def test_resolve_stream_from_external_api_download_post_flow(self):
        class FakeResponse:
            def __init__(self, status_code, payload):
                self.status_code = status_code
                self._payload = payload
                self.text = str(payload)

            def json(self):
                return self._payload

        post_payload = {
            "id": "req-123",
            "downloadUrl": "https://cdn.example.com/audio.mp3",
            "status": "CONVERTING",
            "format": "MP3",
        }
        poll_payload = {
            "id": "req-123",
            "downloadUrl": "https://cdn.example.com/audio.mp3",
            "status": "COMPLETED",
            "format": "MP3",
        }

        with patch.dict(
            os.environ,
            {
                "YTDLP_PROVIDER": "rapidapi",
                "YTDLP_RAPIDAPI_KEY": "key",
                "YTDLP_RAPIDAPI_HOST": "youtube-to-mp315.p.rapidapi.com",
                "YTDLP_RAPIDAPI_URL": "https://youtube-to-mp315.p.rapidapi.com/download",
                "YTDLP_RAPIDAPI_STATUS_POLL_ATTEMPTS": "1",
            },
            clear=False,
        ):
            with patch.object(youtube_music.requests, "post", return_value=FakeResponse(200, post_payload)) as mocked_post:
                with patch.object(youtube_music.requests, "get", return_value=FakeResponse(200, poll_payload)) as mocked_get:
                    result = youtube_music._resolve_stream_from_external_api("GwrLUr01NOY")

        self.assertTrue(result["success"])
        self.assertEqual(result["data"]["audio_url"], "https://cdn.example.com/audio.mp3")
        self.assertEqual(result["data"]["external_method"], "POST")

        _, kwargs = mocked_post.call_args
        self.assertIn("youtube.com/watch?v=GwrLUr01NOY", kwargs.get("params", {}).get("url", ""))
        self.assertEqual(kwargs.get("json", {}).get("format"), "mp3")
        self.assertEqual(kwargs.get("json", {}).get("quality"), 0)

        self.assertTrue(mocked_get.called)
        status_url = mocked_get.call_args[0][0]
        self.assertIn("/status/req-123", status_url)

    def test_resolve_stream_from_external_api_get_mp3_download_link_flow(self):
        class FakeResponse:
            def __init__(self, status_code, payload):
                self.status_code = status_code
                self._payload = payload
                self.text = str(payload)

            def json(self):
                return self._payload

        payload = {
            "comment": "The file will soon be ready",
            "file": "https://cdn.example.com/out.mp3",
            "reserved_file": "https://cdn.example.com/reserved-out.mp3",
        }

        with patch.dict(
            os.environ,
            {
                "YTDLP_PROVIDER": "rapidapi",
                "YTDLP_RAPIDAPI_KEY": "key",
                "YTDLP_RAPIDAPI_HOST": "youtube-mp3-audio-video-downloader.p.rapidapi.com",
                "YTDLP_RAPIDAPI_URL": "https://youtube-mp3-audio-video-downloader.p.rapidapi.com/get_mp3_download_link/{id}?quality=low&wait_until_the_file_is_ready=false",
            },
            clear=False,
        ):
            with patch.object(youtube_music.requests, "get", return_value=FakeResponse(200, payload)) as mocked_get:
                result = youtube_music._resolve_stream_from_external_api("https://www.youtube.com/watch?v=Ckom3gf57Yw")

        self.assertTrue(result["success"])
        self.assertEqual(result["data"]["audio_url"], "https://cdn.example.com/out.mp3")
        self.assertEqual(result["data"]["external_method"], "GET")

        called_url = mocked_get.call_args[0][0]
        self.assertIn("/get_mp3_download_link/Ckom3gf57Yw", called_url)
        self.assertIn("quality=low", called_url)


if __name__ == "__main__":
    unittest.main()
