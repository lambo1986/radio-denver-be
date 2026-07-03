# Human Frequency Audio Rendering Roadmap

Human Frequency should create one broadcast-ready master for each approved show, while keeping the original track and host-break metadata for review and reporting.

## Current Renderer

- Downloads each lineup asset in show order.
- Converts each source to WAV.
- Applies FFmpeg loudnorm with a target of `-16 LUFS`, `-1.5 dBTP`, and `11 LRA`.
- Concatenates normalized sources into one 48 kHz stereo, 192 kbps MP3.
- Uploads the master back to Rails/S3 as a private full-show audio file.
- Stores Human Frequency metadata tags in the MP3.

This is enough for internal testing and early MVP use, assuming source files are clean.

## Next Production Audio Work

1. Add two-pass loudness normalization.
   - First pass measures each file.
   - Second pass applies measured values for more predictable loudness.
   - Store measured integrated loudness, true peak, LRA, and normalization settings.

2. Add a render quality report.
   - Total source count.
   - Total expected duration versus rendered duration.
   - Per-source duration, format, sample rate, channel count, and loudness.
   - FFmpeg version.
   - Any warnings surfaced to admins.

3. Add clipping and silence checks.
   - Detect samples over true-peak target.
   - Flag long silence at the beginning or end of a source.
   - Warn when a host break is unusually quiet or loud.

4. Add richer metadata.
   - Show title.
   - Host name.
   - Station name.
   - Scheduled air date.
   - Delivery reference.
   - Human Frequency canonical URL when available.

5. Keep originals untouched.
   - Never destructively rewrite host uploads.
   - Re-render masters from originals when metadata, order, or audio changes.

## Release Rule

Do not automate AzuraCast uploads until the renderer can produce a master that admins can preview and approve from Station Review.
