require 'rails_helper'

RSpec.describe RenderBroadcastMasterJob, type: :job do
  it 'renders the requested playlist' do
    playlist = create(:playlist)
    renderer = instance_double(BroadcastMasterRenderer, render: playlist)
    allow(BroadcastMasterRenderer).to receive(:new).with(playlist).and_return(renderer)

    described_class.perform_now(playlist.id)

    expect(renderer).to have_received(:render)
  end

  it 'does not retry a missing playlist' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
