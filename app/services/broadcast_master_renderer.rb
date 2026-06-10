require 'fileutils'
require 'open3'
require 'tmpdir'

class BroadcastMasterRenderer
  RenderError = Class.new(StandardError)
  TARGET_LOUDNESS = ENV.fetch('BROADCAST_TARGET_LUFS', '-16')
  TRUE_PEAK = ENV.fetch('BROADCAST_TRUE_PEAK_DB', '-1.5')
  LOUDNESS_RANGE = ENV.fetch('BROADCAST_LOUDNESS_RANGE', '11')

  def initialize(playlist, s3_service: nil, downloader: nil, command_runner: Open3)
    @playlist = playlist
    @s3_service = s3_service || AwsS3Service.new(ENV.fetch('AWS_BUCKET_NAME', 'radio-denver'))
    @downloader = downloader || AudioSourceDownloader.new(s3_service: @s3_service)
    @command_runner = command_runner
  end

  def render
    sources = render_sources
    raise RenderError, 'Add playable audio before rendering a broadcast master.' if sources.empty?

    playlist.update!(render_status: 'rendering', render_error: nil)

    Dir.mktmpdir("human-frequency-show-#{playlist.id}-") do |directory|
      normalized_paths = normalize_sources(sources, directory)
      master_path = File.join(directory, master_filename)
      concatenate(normalized_paths, master_path, directory)
      persist_master(master_path)
    end
  rescue RenderError => error
    playlist.update_columns(render_status: 'failed', render_error: error.message, rendered_at: nil)
    raise
  rescue StandardError => error
    playlist.update_columns(render_status: 'failed', render_error: 'Broadcast master rendering failed.', rendered_at: nil)
    Rails.logger.error("Broadcast master render failed for playlist #{playlist.id}: #{error.class}: #{error.message}")
    raise RenderError, 'Broadcast master rendering failed.'
  end

  private

  attr_reader :playlist, :s3_service, :downloader, :command_runner

  def render_sources
    if playlist.full_show_audio_file.present?
      return [audio_file_source(playlist.full_show_audio_file, playlist.name)]
    end

    playlist.songs.includes(:audio_file).map do |song|
      if song.audio_file.present?
        audio_file_source(song.audio_file, song.name)
      elsif song.file_url.present?
        { title: song.name, url: song.file_url, extension: File.extname(song.file_name.to_s).presence || '.audio' }
      end
    end.compact
  end

  def audio_file_source(audio_file, title)
    {
      title: title,
      s3_key: audio_file.s3_key,
      url: audio_file.url,
      extension: File.extname(audio_file.name.to_s).presence || '.audio'
    }
  end

  def normalize_sources(sources, directory)
    sources.each_with_index.map do |source, index|
      input_path = File.join(directory, format('source-%03d%s', index + 1, source[:extension]))
      output_path = File.join(directory, format('normalized-%03d.wav', index + 1))
      downloader.download(source, input_path)
      run_ffmpeg(
        '-i', input_path,
        '-vn',
        '-af', "loudnorm=I=#{TARGET_LOUDNESS}:TP=#{TRUE_PEAK}:LRA=#{LOUDNESS_RANGE}",
        '-ar', '48000',
        '-ac', '2',
        '-c:a', 'pcm_s16le',
        output_path
      )
      output_path
    end
  end

  def concatenate(normalized_paths, output_path, directory)
    concat_path = File.join(directory, 'concat.txt')
    File.write(concat_path, normalized_paths.map { |path| "file '#{path}'" }.join("\n"))

    run_ffmpeg(
      '-f', 'concat',
      '-safe', '0',
      '-i', concat_path,
      '-vn',
      '-c:a', 'libmp3lame',
      '-b:a', '192k',
      '-ar', '48000',
      '-ac', '2',
      '-metadata', "title=#{playlist.name}",
      '-metadata', "artist=#{playlist.host_name}",
      output_path
    )
  end

  def run_ffmpeg(*arguments)
    _stdout, stderr, status = command_runner.capture3('ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *arguments)
    return if status.success?

    message = stderr.to_s.lines.last(3).join(' ').strip
    raise RenderError, "FFmpeg could not process the show audio. #{message}".strip
  rescue Errno::ENOENT
    raise RenderError, 'FFmpeg is not installed on the rendering server.'
  end

  def persist_master(master_path)
    object_key = "broadcast_masters/#{playlist.id}/#{SecureRandom.uuid}/#{master_filename}"
    s3_service.upload_file(master_path, object_key)
    previous_master = playlist.rendered_master_audio_file
    master = nil

    ActiveRecord::Base.transaction do
      master = playlist.user.audio_files.create!(
        name: master_filename,
        title: playlist.name,
        artist: playlist.host_name,
        kind: 'full_show',
        visibility: 'private',
        size: File.size(master_path),
        content_type: 'audio/mpeg',
        duration: playlist.duration_seconds,
        s3_key: object_key,
        notes: 'Broadcast master normalized to -16 LUFS, 48 kHz stereo, 192 kbps MP3.'
      )
      playlist.update!(
        rendered_master_audio_file: master,
        render_status: 'ready',
        render_error: nil,
        rendered_at: Time.current
      )
    end

    cleanup_previous_master(previous_master, master)
    playlist
  rescue StandardError
    s3_service.delete_file(object_key) if object_key.present?
    raise
  end

  def cleanup_previous_master(previous_master, new_master)
    return if previous_master.blank? || previous_master.id == new_master.id

    s3_service.delete_file(previous_master.s3_key) if previous_master.s3_key.present?
    previous_master.destroy!
  rescue StandardError => error
    Rails.logger.error("Old broadcast master cleanup failed for playlist #{playlist.id}: #{error.message}")
  end

  def master_filename
    "#{playlist.name.parameterize}-broadcast-master.mp3"
  end
end
