# AzuraCast Bridge

Melody Mixer Network should treat AzuraCast as the broadcast engine, not the place where hosts build shows.

## Current Flow

1. Hosts upload audio and build shows in Melody Mixer.
2. Admins review submitted shows.
3. Admins schedule approved shows.
4. Admins queue a stream package with the `azuracast` delivery target.
5. Rails stores a `delivery_manifest` with show metadata, ordered assets, playout order, and AzuraCast handoff details.

This is currently a manual-export bridge. It prepares the package cleanly, but it does not upload files into AzuraCast yet.

## Recommended First AzuraCast Setup

1. Install AzuraCast on a small VPS using the official Docker install.
2. Create one station named `Alpine Groove Guide`.
3. Create an AutoDJ playlist named `Alpine Groove Guide Shows`.
4. Create an API key from the AzuraCast user menu.
5. Add the public stream URL to the frontend as `NEXT_PUBLIC_STREAM_URL`.

## Backend Environment Variables

Set these when an AzuraCast instance exists:

```bash
STREAM_STATION_NAME="Alpine Groove Guide"
AZURACAST_BASE_URL="https://radio.example.com"
AZURACAST_STATION_ID="1"
AZURACAST_STATION_SHORTCODE="alpine_groove_guide"
AZURACAST_STREAM_URL="https://radio.example.com/listen/alpine_groove_guide/radio.mp3"
AZURACAST_API_KEY="replace-with-azuracast-api-key"
AZURACAST_PLAYLIST_NAME="Alpine Groove Guide Shows"
```

## Frontend Environment Variable

```bash
NEXT_PUBLIC_STREAM_URL="https://radio.example.com/listen/alpine_groove_guide/radio.mp3"
```

## Manual Test Path

Use this before automating API uploads:

1. Create and submit a short show in Melody Mixer.
2. Mark it ready in Station Review.
3. Schedule it.
4. Select `AzuraCast AutoDJ` as the stream target.
5. Click `Queue Stream Package`.
6. Open the stream export manifest.
7. Upload the full-show file or ordered assets into AzuraCast media.
8. Assign the media to the recommended playlist.
9. Confirm the stream URL plays on the Alpine Groove Guide page.

## Automation Path

Once the manual test works, the next backend service should:

1. Download or stream each Rails/S3 asset from the manifest.
2. Upload media to AzuraCast through its authenticated API.
3. Assign uploaded media to the configured playlist.
4. Save AzuraCast media IDs back into `delivery_manifest`.
5. Mark `delivery_status` as `sent` only after AzuraCast confirms the upload and playlist assignment.

Keep `queued` for packages that are exported but not yet accepted by AzuraCast.
