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

  describe '#tag_protected?' do
    let(:repo) { Repository.create!(name: 'example') }

    context 'when policy is none (default)' do
      it 'returns false for any tag name' do
        expect(repo.tag_protected?('v1.0.0')).to be false
        expect(repo.tag_protected?('latest')).to be false
        expect(repo.tag_protected?('anything')).to be false
      end
    end

    context 'when policy is semver' do
      before { repo.update!(tag_protection_policy: 'semver') }

      it 'protects v-prefixed semver' do
        expect(repo.tag_protected?('v1.2.3')).to be true
      end

      it 'protects bare semver' do
        expect(repo.tag_protected?('1.2.3')).to be true
      end

      it 'protects semver with pre-release' do
        expect(repo.tag_protected?('1.2.3-rc1')).to be true
      end

      it 'protects semver with build metadata' do
        expect(repo.tag_protected?('1.2.3+build.5')).to be true
      end

      it 'does NOT protect latest' do
        expect(repo.tag_protected?('latest')).to be false
      end

      it 'does NOT protect partial versions' do
        expect(repo.tag_protected?('v1.2')).to be false
      end

      it 'does NOT protect branch names' do
        expect(repo.tag_protected?('main')).to be false
      end
    end

    context 'when policy is all_except_latest' do
      before { repo.update!(tag_protection_policy: 'all_except_latest') }

      it 'does NOT protect latest' do
        expect(repo.tag_protected?('latest')).to be false
      end

      it 'protects everything else (including other floating names)' do
        expect(repo.tag_protected?('v1.0.0')).to be true
        expect(repo.tag_protected?('main')).to be true
        expect(repo.tag_protected?('develop')).to be true
        expect(repo.tag_protected?('anything')).to be true
      end
    end

    context 'when policy is custom_regex' do
      before do
        repo.update!(tag_protection_policy: 'custom_regex', tag_protection_pattern: '^release-\d+$')
      end

      it 'protects names matching the pattern' do
        expect(repo.tag_protected?('release-1')).to be true
        expect(repo.tag_protected?('release-42')).to be true
      end

      it 'does NOT protect non-matching names' do
        expect(repo.tag_protected?('release-1a')).to be false
        expect(repo.tag_protected?('v1.0.0')).to be false
      end
    end
  end

  describe 'tag_protection_pattern validation' do
    it 'requires pattern when policy is custom_regex' do
      repo = Repository.new(name: 'x', tag_protection_policy: 'custom_regex', tag_protection_pattern: nil)
      expect(repo).not_to be_valid
      expect(repo.errors[:tag_protection_pattern]).to include("can't be blank")
    end

    it 'rejects invalid regex' do
      repo = Repository.new(name: 'x', tag_protection_policy: 'custom_regex', tag_protection_pattern: '[unclosed')
      expect(repo).not_to be_valid
      expect(repo.errors[:tag_protection_pattern].first).to match(/is not a valid regex/)
    end

    it 'does NOT require pattern when policy is not custom_regex' do
      repo = Repository.new(name: 'x', tag_protection_policy: 'semver', tag_protection_pattern: nil)
      expect(repo).to be_valid
    end
  end

  describe 'before_save clears pattern when policy is not custom_regex' do
    it 'nullifies pattern when policy transitions to semver' do
      repo = Repository.create!(name: 'x', tag_protection_policy: 'custom_regex', tag_protection_pattern: '^v.+$')
      repo.update!(tag_protection_policy: 'semver')
      expect(repo.reload.tag_protection_pattern).to be_nil
    end

    it 'keeps pattern when policy stays custom_regex' do
      repo = Repository.create!(name: 'y', tag_protection_policy: 'custom_regex', tag_protection_pattern: '^v.+$')
      repo.update!(tag_protection_pattern: '^release-\d+$')
      expect(repo.reload.tag_protection_pattern).to eq('^release-\d+$')
    end
  end
end
