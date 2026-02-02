# frozen_string_literal: true

class Repository
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :tag_count, :integer, default: 0
  attribute :last_updated, :datetime

  def self.from_catalog(repositories_data)
    repositories_data.map do |repo_name|
      new(name: repo_name)
    end
  end

  def to_param
    name
  end
end
