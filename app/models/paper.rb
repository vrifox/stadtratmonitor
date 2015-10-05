require 'elasticsearch/model'
require 'json'
require 'parseable_date_validator'

class Paper < ActiveRecord::Base
  include Elasticsearch::Model
  include Elasticsearch::Model::Callbacks

  validates :name,         presence: true, length: { maximum: 1000 }
  validates :url,          presence: true,
                           length: { maximum: 1000 },
                           uniqueness: true, # TODO use unique index instead
                           url: true
  validates :reference,    presence: true, length: { maximum: 100 }
  validates :body,         presence: true, length: { maximum: 100 }
  validates :content,      presence: true, length: { maximum: 100_000 }
  validates :originator,   presence: true, length: { maximum: 300 }
  validates :paper_type,   presence: true, length: { maximum: 50 }
  validates :published_at, presence: true, parseable_date: true
  validates :resolution,   length: { maximum: 30_000 }

  settings index: { number_of_shards: 1 } do
    mappings dynamic: false do
      indexes :name, type: :string, analyzer: "german"
      indexes :content, type: :string, analyzer: "german"
      indexes :resolution, type: :string, analyzer: "german"
      indexes :paper_type, type: :string, index: :not_analyzed
      indexes :originator, type: :string, index: :not_analyzed
    end
  end

  def split_originator
    originator.split(/\d\.\s/).reject {|s| s.blank?} || originator
  end

  def as_indexed_json(options={})
    as_json.merge(originator: split_originator)
  end

  class << self
    def import_from_json(json_string)
      old_count = count
      JSON.parse(json_string).each do |record|
        attributes = {
          body: record['body'],
          content: record['content'],
          name: record['name'],
          resolution: record['resolution'],
          originator: record['originator'],
          paper_type: record['paper_type'],
          published_at: record['published_at'],
          reference: record['reference'],
          url: record['url'],
        }
        record = find_or_initialize_by(url: attributes[:url])
        record.update_attributes(attributes)
      end
      puts "Imported #{count - old_count} Papers!"
    end

    # use DSL to define search queries
    # see https://github.com/elastic/elasticsearch-ruby/tree/master/elasticsearch-dsl
    # and https://github.com/elastic/elasticsearch-rails/tree/master/elasticsearch-rails/lib/rails/templates
    def search(q, options={})
      @search_definition = PaperSearch.definition(q, options)
      Rails.logger.debug "Query: #{@search_definition.to_json}"
      __elasticsearch__.search(@search_definition)
    end

    def reset_index!
      __elasticsearch__.create_index! force: true
      all.each {|p| p.__elasticsearch__.index_document }
    end

  end
end
