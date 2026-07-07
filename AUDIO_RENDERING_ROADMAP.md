# Human Frequency Audio Rendering Roadmap

Human Frequency should create one broadcast-ready master for each approved show, while keeping the original track and host-break metadata for review and reporting.

## Current Renderer

- Downloads each lineup asset in show order.
- Measures each source with FFmpeg `loudnorm` when ffmpeg returns measurement JSON.
- Converts each source to WAV using two-pass loudnorm values when available.
- Falls back to one-pass loudnorm with a target of `-16 LUFS`, `-1.5 dBTP`, and `11 LRA` when measurements are unavailable.
- Concatenates normalized sources into one 48 kHz stereo, 192 kbps MP3.
- Uploads the master back to Rails/S3 as a private full-show audio file.
- Stores Human Frequency metadata tags in the MP3.
- Stores a render quality report in `playlist.delivery_manifest.render_quality_report`.
- Records measured loudness/true peak values only when ffmpeg actually returns them.
- Adds true-peak warnings when measured source audio is above the broadcast target.

This is enough for internal testing and early MVP use, assuming source files are clean.

## Next Production Audio Work

1. Add deeper render verification.
   - Measure the finished MP3 after concat.
   - Compare expected duration versus rendered duration.
   - Store FFmpeg version and output sample/bitrate details.

2. Add silence and more advanced clipping checks.
   - Detect clipped samples, not just measured true peak above target.
   - Flag long silence at the beginning or end of a source.
   - Warn when a host break is unusually quiet or loud.

3. Add richer metadata when those fields are available.
   - Station name.
   - Scheduled air date.
   - Delivery reference.
   - Human Frequency canonical URL when available.

4. Continue improving admin render report visibility.
   - Current Station Review shows render health, normalization mode, target loudness, clipping warnings, render errors, output reference, and an expandable render report.
   - Next step: add final-master verification details once the renderer measures the completed MP3.
   - Keep raw ffmpeg output out of public/frontend JSON unless sanitized.

5. Keep originals untouched.
   - Never destructively rewrite host uploads.
   - Re-render masters from originals when metadata, order, or audio changes.

## Release Rule

Do not rely on AzuraCast uploads for real programming until one non-critical scheduled show has passed the Station Review delivery test and the uploaded media has been confirmed in the configured AzuraCast playlist.
