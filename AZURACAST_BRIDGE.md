# Human Frequency AzuraCast Bridge

Human Frequency should treat AzuraCast as the broadcast engine, not the place where hosts build shows.

## Current Flow

1. Hosts upload audio and build shows in Human Frequency.
2. Admins review submitted shows.
3. Admins schedule approved shows.
4. Admins queue a stream package with the `azuracast` delivery target.
5. Rails stores a `delivery_manifest` with show metadata, ordered assets, playout order, and AzuraCast handoff details.
6. Admins render one broadcast master, upload it to AzuraCast, and verify playlist assignment from Station Review.

This bridge now supports guarded upload of a rendered broadcast master. It still avoids risky station-control actions such as starting, stopping, or restarting AzuraCast.

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
AZURACAST_MEDIA_FOLDER="human-frequency-shows"
```

`AZURACAST_API_KEY` is server-only. Do not prefix it with `NEXT_PUBLIC_`, do not expose it in frontend code, and do not commit a real value.

## Frontend Environment Variable

```bash
NEXT_PUBLIC_STREAM_URL="https://a5.asurahosting.com:7390/radio.mp3"
```

The frontend should get now-playing metadata from Rails at `/api/v1/station/now_playing`, not directly from authenticated AzuraCast APIs.

## Admin Delivery Test Path

Use this with one non-critical scheduled show before relying on the workflow for real programming:

1. Create and submit a short show in Human Frequency.
2. Mark it ready in Station Review.
3. Schedule it.
4. Select `AzuraCast AutoDJ` as the stream target.
5. Click `Build Broadcast Master`.
6. Wait until the master is ready and preview it.
7. Click `Queue Stream Package`.
8. Click `Run Delivery Test`.
9. Review the step report:
   - render master
   - queue AzuraCast package
   - upload master
   - confirm playlist assignment
   - check now-playing visibility
10. Confirm the uploaded media appears in AzuraCast under the configured playlist.
11. Confirm the Human Frequency listener page can reach the stream and now-playing data.

The now-playing step only reports a current playback match when AzuraCast actually reports the uploaded show as playing. If the upload succeeded but AutoDJ has not played it yet, the step is marked `skipped`, not falsely confirmed.

## Automation Path

The discovery panel should confirm the right station, playlist, and media path before uploads. The upload service now:

1. Render one broadcast master in Human Frequency.
2. Upload that master to AzuraCast through its authenticated media API.
3. Assign the uploaded media to the configured playlist.
4. Save AzuraCast media id, playlist id, remote path, upload timestamp, and assignment timestamp back into `delivery_manifest`.
5. Mark `delivery_status` as `sent` only after AzuraCast confirms both upload and playlist assignment.

Keep `queued` for packages that are exported but not yet accepted by AzuraCast.

The intended production playlist is `Human Frequency Shows`. Set `AZURACAST_PLAYLIST_NAME` to that exact name, or set `AZURACAST_PLAYLIST_ID` to the exact playlist id. Do not leave this ambiguous; the backend rejects upload instead of sending shows to the wrong playlist.

## Stage 3C: Guarded Upload and Playlist Assignment

Admins can upload a rendered broadcast master to AzuraCast from Station Review after:

- the show is scheduled,
- the AzuraCast stream package has been queued,
- the stream package is `single_master`,
- the broadcast master asset exists in the manifest,
- the rendered master has a durable S3 key,
- Rails can download the master server-side,
- an AzuraCast playlist id or exact playlist name can be resolved,
- the API key is configured.

The backend does not use stale signed URLs from old manifests when a durable Rails/S3 reference exists. It marks delivery as `sent` only after AzuraCast returns an uploaded media id and confirms the playlist assignment. Failures set `delivery_status` to `failed` and store a sanitized `azuracast_error` in the manifest without S3 query strings, signatures, or API keys.

Stage 3D can add station control, but only behind explicit admin confirmation and only after real upload and playlist assignment have been tested with a non-critical show.

## Timeline and Audit Trail

Human Frequency records timeline events for important show workflow changes:

- draft saved
- submitted
- approved
- needs edits
- rejected
- scheduled
- render requested
- rendered
- render failed
- stream package queued
- uploaded
- upload failed
- delivery test

Hosts can see timeline history on their profile and when reopening a show. Admins can see it in Station Review. Delivery-test reports are stored in `delivery_manifest.azuracast_delivery_test`.
