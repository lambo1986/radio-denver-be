require 'net/http'

class AudioSourceDownloader
  MAX_REDIRECTS = 3

  def initialize(s3_service:)
    @s3_service = s3_service
  end

  def download(source, destination_path)
    return s3_service.download_file(source.fetch(:s3_key), destination_path) if source[:s3_key].present?

    download_url(URI.parse(source.fetch(:url)), destination_path, redirects_remaining: MAX_REDIRECTS)
  end

  private

  attr_reader :s3_service

  def download_url(uri, destination_path, redirects_remaining:)
    raise BroadcastMasterRenderer::RenderError, 'Audio source URL must use HTTPS.' unless uri.is_a?(URI::HTTPS)

    redirect_location = nil
    response_code = nil

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 120) do |http|
      http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
        response_code = response.code
        if response.is_a?(Net::HTTPRedirection)
          redirect_location = response['location']
        elsif response.is_a?(Net::HTTPSuccess)
          File.open(destination_path, 'wb') { |file| response.read_body { |chunk| file.write(chunk) } }
        end
      end
    end

    if redirect_location.present?
      raise BroadcastMasterRenderer::RenderError, 'Too many audio source redirects.' if redirects_remaining.zero?

      return download_url(URI.join(uri, redirect_location), destination_path, redirects_remaining: redirects_remaining - 1)
    end

    unless response_code.to_i.between?(200, 299)
      raise BroadcastMasterRenderer::RenderError, "Could not download an audio source (HTTP #{response_code})."
    end

    destination_path
  rescue URI::InvalidURIError, SocketError, SystemCallError, Timeout::Error => error
    raise BroadcastMasterRenderer::RenderError, "Could not download an audio source: #{error.message}"
  end
end
