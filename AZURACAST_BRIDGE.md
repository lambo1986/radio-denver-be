# Human Frequency AzuraCast Bridge

Human Frequency should treat AzuraCast as the broadcast engine, not the place where hosts build shows.

## Current Flow

1. Hosts upload audio and build shows in Human Frequency.
2. Admins review submitted shows.
3. Admins schedule approved shows.
4. Admins queue a stream package with the `azuracast` delivery target.
5. Rails stores a `delivery_manifest` with show metadata, ordered assets, playout order, and AzuraCast handoff details.

This is currently a manual-export bridge. It prepares the package cleanly, but it does not upload files into AzuraCast yet.

## Stage 3A: Read-Only Discovery

Rails now has an admin-only discovery check at:

```text
GET /api/v1/station/azuracast_discovery
```

It uses the configured `AZURACAST_API_KEY` to inspect AzuraCast without changing the station. It reports:

- API key configured as true/false only.
- station id, shortcode, public player URL, and stream URL.
- playlist names and ids.
- media folder names and ids when the host exposes a compatible endpoint.
- recent media examples with safe metadata only.
- recommended playlist/folder matching from the Human Frequency stream manifest.
- per-endpoint warnings when AzuraCast returns an unsupported shape or error.

This endpoint must stay admin-only. It must not upload media, modify playlists, restart the station, or expose signed S3 URLs.

## Recommended First AzuraCast Setup

1. Install AzuraCast on a small VPS using the official Docker install.
2. Create one station named `Human Frequency`.
3. Create an AutoDJ playlist named `Human Frequency Shows`.
4. Create an API key from the AzuraCast user menu.
5. Add the public stream URL to the frontend as `NEXT_PUBLIC_STREAM_URL`.
6. Configure Rails with the public player, stream, and now-playing endpoints so Human Frequency can display live metadata.

## Backend Environment Variables

Set these when an AzuraCast instance exists:

```bash
STREAM_STATION_NAME="Human Frequency"
AZURACAST_BASE_URL="https://a5.asurahosting.com"
AZURACAST_STATION_ID="720"
AZURACAST_STATION_SHORTCODE="human_frequency"
AZURACAST_PUBLIC_PLAYER_URL="https://a5.asurahosting.com/public/human_frequency"
AZURACAST_STREAM_URL="https://a5.asurahosting.com:7390/radio.mp3"
AZURACAST_NOW_PLAYING_URL="https://a5.asurahosting.com/api/nowplaying_static/human_frequency.json"
AZURACAST_API_KEY="replace-with-azuracast-api-key"
AZURACAST_PLAYLIST_NAME="Human Frequency Shows"
```

`AZURACAST_API_KEY` is server-only. Do not prefix it with `NEXT_PUBLIC_`, do not expose it in frontend code, and do not commit a real value.

## Frontend Environment Variable

```bash
NEXT_PUBLIC_STREAM_URL="https://a5.asurahosting.com:7390/radio.mp3"
```

The frontend should get now-playing metadata from Rails at `/api/v1/station/now_playing`, not directly from authenticated AzuraCast APIs.

## Manual Test Path

Use this before automating API uploads:

1. Create and submit a short show in Human Frequency.
2. Mark it ready in Station Review.
3. Schedule it.
4. Select `AzuraCast AutoDJ` as the stream target.
5. Click `Queue Stream Package`.
6. Open the stream export manifest.
7. Upload the full-show file or ordered assets into AzuraCast media.
8. Assign the media to the recommended playlist.
9. Confirm the stream URL plays on the Human Frequency listener page.

## Automation Path

Stage 3B should begin only after the discovery panel confirms the right station, playlist, and media path. The next backend service should:

1. Render one broadcast master in Human Frequency.
2. Upload that master to AzuraCast through its authenticated media API.
3. Assign the uploaded media to the configured playlist.
4. Save AzuraCast media id, playlist id, remote path, upload timestamp, and assignment timestamp back into `delivery_manifest`.
5. Add delivery fields such as `azuracast_media_id`, `azuracast_playlist_id`, `azuracast_remote_path`, `azuracast_uploaded_at`, and `azuracast_assigned_at` once the API response shape is verified.
6. Mark `delivery_status` as `sent` only after AzuraCast confirms both upload and playlist assignment.

Keep `queued` for packages that are exported but not yet accepted by AzuraCast.

Stage 3C can add station control, but only behind explicit admin confirmation and only after the upload and playlist assignment path is stable.
