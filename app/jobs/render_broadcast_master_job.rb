class RenderBroadcastMasterJob < ApplicationJob
  queue_as :default

  def perform(playlist_id)
    playlist = Playlist.find(playlist_id)
    BroadcastMasterRenderer.new(playlist).render
  rescue ActiveRecord::RecordNotFound
    nil
  rescue BroadcastMasterRenderer::RenderError => error
    Rails.logger.error("Broadcast master job failed for playlist #{playlist_id}: #{error.message}")
  end
end
