require 'rails_helper'

RSpec.describe Repository, type: :model do
  describe 'validations' do
    it 'requires name' do
      repo = Repository.new(name: nil)
      expect(repo).not_to be_valid
      expect(repo.errors[:name]).to include("can't be blank")
    end

    it 'requires unique name' do
      Repository.create!(name: 'myapp')
      repo = Repository.new(name: 'myapp')
      expect(repo).not_to be_valid
      expect(repo.errors[:name]).to include('has already been taken')
    end
  end

  describe 'associations' do
    it 'has many tags' do
      expect(Repository.reflect_on_association(:tags).macro).to eq(:has_many)
    end

    it 'has many manifests' do
      expect(Repository.reflect_on_association(:manifests).macro).to eq(:has_many)
    end

    it 'has many tag_events' do
      expect(Repository.reflect_on_association(:tag_events).macro).to eq(:has_many)
    end
  end
end
