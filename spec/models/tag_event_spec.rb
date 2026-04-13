require 'rails_helper'

RSpec.describe TagEvent, type: :model do
  let(:repository) { Repository.create!(name: 'test-repo') }

  describe 'validations' do
    it 'requires tag_name, action, occurred_at' do
      event = TagEvent.new(repository: repository)
      expect(event).not_to be_valid
      expect(event.errors[:tag_name]).to include("can't be blank")
      expect(event.errors[:action]).to include("can't be blank")
      expect(event.errors[:occurred_at]).to include("can't be blank")
    end
  end
end
