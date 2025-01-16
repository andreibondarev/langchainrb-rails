# frozen_string_literal: true

# Overriding Langchain.rb's SqliteVec implementation to use ActiveRecord.
# Original implementation: https://github.com/andreibondarev/langchainrb/blob/main/lib/langchain/vectorsearch/sqlite_vec.rb

require "sqlite_vec"

module Langchain::Vectorsearch
  class SqliteVec < Base
    #
    # The SQLite vector search adapter
    #
    # Gem requirements:
    #     gem "sqlite_vec", "~> 0.1"
    #
    # Usage:
    #     sqlite_vec = Langchain::Vectorsearch::SqliteVec.new(
    #       url: ":memory:",
    #       index_name: "documents",
    #       namespace: "test",
    #       llm: llm
    #     )
    #

    attr_reader :llm
    attr_accessor :model

    # @param llm [Object] The LLM client to use
    def initialize(llm:)
      depends_on "sqlite3"
      depends_on "sqlite_vec"

      # Use the existing ActiveRecord connection
      # TODO this doesn't appear to work so weird hack in the initializer
      @db = ActiveRecord::Base.connection.raw_connection
      @db.enable_load_extension(true)
      ::SqliteVec.load(@db)
      @db.enable_load_extension(false)

      @llm = llm

      super
    end

    # Add a list of texts to the index
    # @param texts [Array<String>] The texts to add to the index
    # Add a list of texts to the index
    # @param texts [Array<String>] The texts to add to the index
    # @param ids [Array<String>] The ids to add to the index, in the same order as the texts
    # @return [Array<Integer>] The ids of the added texts.
    def add_texts(texts:, ids:)
      embeddings = texts.map do |text|
        llm.embed(text: text).embedding
      end

      model.find(ids).each.with_index do |record, i|
        record.update_column(:embedding, embeddings[i].pack("f*"))
      end
    end

    def update_texts(texts:, ids:)
      add_texts(texts: texts, ids: ids)
    end

    # Remove vectors from the index
    #
    # @param ids [Array<String>] The ids of the vectors to remove
    # @return [Boolean] true
    def remove_texts(ids:)
      # Since the record is being destroyed and the `embedding` is a column on the record,
      # we don't need to do anything here.
      true
    end

    # Create default schema
    def create_default_schema
      Rake::Task["sqlite_vec"].invoke
    end

    # Destroy default schema
    def destroy_default_schema
      # Tell the user to rollback the migration
    end

    # Search for similar texts in the index
    # @param query [String] The text to search for
    # @param k [Integer] The number of top results to return
    # @return [Array<Hash>] The results of the search
    def similarity_search(query:, k: 4)
      embedding = llm.embed(text: query).embedding

      similarity_search_by_vector(
        embedding: embedding,
        k: k
      )
    end

    # Search for similar texts in the index by the passed in vector.
    # You must generate your own vector using the same LLM that generated the embeddings stored in the Vectorsearch DB.
    # @param embedding [Array<Float>] The vector to search for
    # @param k [Integer] The number of top results to return
    # @return [Array<Hash>] The results of the search
    def similarity_search_by_vector(embedding:, k: 4)
      model
        .nearest_neighbors(:embedding, embedding)
        .limit(k)
    end

    # Ask a question and return the answer
    # @param question [String] The question to ask
    # @param k [Integer] The number of results to have in context
    # @yield [String] Stream responses back one String at a time
    # @return [String] The answer to the question
    def ask(question:, k: 4, &block)
      # Noisy as the embedding column has a lot of data
      ActiveRecord::Base.logger.silence do
        search_results = similarity_search(query: question, k: k)

        context = search_results.map do |result|
          result.as_vector
        end
        context = context.join("\n---\n")
        prompt = generate_rag_prompt(question: question, context: context)
        messages = [{ role: "user", content: prompt }]
        llm.chat(messages: messages, &block)
      end
    end
  end
end
