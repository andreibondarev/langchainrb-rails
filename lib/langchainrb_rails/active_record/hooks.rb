# frozen_string_literal: true

module LangchainrbRails
  module ActiveRecord
    # This module adds the following functionality to your ActiveRecord models:
    # * `vectorsearch` class method to set the vector search provider
    # * `similarity_search` class method to search for similar texts
    # * `upsert_to_vectorsearch` instance method to upsert the record to the vector search provider
    # * `destroy_from_vectorsearch` instance method to remove the record from the vector search provider
    #
    # Usage:
    #     class Recipe < ActiveRecord::Base
    #       vectorsearch
    #
    #       after_save :upsert_to_vectorsearch
    #       after_destroy :destroy_from_vectorsearch
    #
    #       # Overwriting how the model is serialized before it's indexed
    #       def as_vector
    #         [
    #           "Title: #{title}",
    #           "Description: #{description}",
    #           ...
    #         ]
    #         .compact
    #         .join("\n")
    #       end
    #     end
    #
    # Create the default schema
    #     Recipe.class_variable_get(:@@provider).create_default_schema
    # Query the vector search provider
    #     Recipe.similarity_search("carnivore dish")
    # Delete the default schema to start over
    #     Recipe.class_variable_get(:@@provider).destroy_default_schema
    #
    module Hooks
      def self.included(base)
        base.extend ClassMethods
      end

      # Index the text to the vector search provider
      # You'd typically call this method in an ActiveRecord callback
      #
      # @return [Boolean] true
      # @raise [Error] Indexing to vector search DB failed
      def upsert_to_vectorsearch
        if previously_new_record?
          self.class.class_variable_get(:@@provider).add_texts(
            texts: [as_vector],
            ids: [id]
          )
        else
          self.class.class_variable_get(:@@provider).update_texts(
            texts: [as_vector],
            ids: [id]
          )
        end
      end

      # Remove the record from the vector search provider
      # This method should be called in an ActiveRecord `after_destroy` callback
      #
      # @return [Boolean] true
      # @raise [Error] Removing from vector search DB failed
      def destroy_from_vectorsearch
        self.class.class_variable_get(:@@provider).remove_texts(
          ids: [id]
        )
      end

      # Used to serialize the DB record to an indexable vector text
      # Overwrite this method in your model to customize
      #
      # @return [String] the text representation of the model
      def as_vector
        # Don't vectorize the embedding ... this would happen if it already exists
        # for a record and we update.
        to_json(except: :embedding)
      end

      module ClassMethods
        # Set the vector search provider
        #
        # @param provider [Object] The `Langchain::Vectorsearch::*` instance
        def vectorsearch
          class_variable_set(:@@provider, LangchainrbRails.config.vectorsearch.dup)

          # Pgvector-specific configuration
          if LangchainrbRails.config.vectorsearch.is_a?(Langchain::Vectorsearch::Pgvector)
            has_neighbors(:embedding)
            class_variable_get(:@@provider).model = self
          end

          # SQLite-Vec-specific configuration
          return unless LangchainrbRails.config.vectorsearch.is_a?(Langchain::Vectorsearch::SqliteVec)

          # Define nearest_neighbors scope for SQLite-Vec
          scope :nearest_neighbors, lambda { |column, vector|
            unscoped.select("#{table_name}.*, vec_distance_cosine(#{column}, '#{vector.to_json}') as distance")
                    .order("distance")
          }
          class_variable_get(:@@provider).model = self
        end

        # Iterates over records and generate embeddings.
        # Will re-generate for ALL records (not just records with embeddings).
        def embed!
          find_each do |record|
            record.upsert_to_vectorsearch
          end
        end

        # Search for similar texts
        #
        # @param query [String] The query to search for
        # @param k [Integer] The number of results to return
        # @return [ActiveRecord::Relation] The ActiveRecord relation
        def similarity_search(query, k: 1)
          records = class_variable_get(:@@provider).similarity_search(
            query: query,
            k: k
          )

          return records if LangchainrbRails.config.vectorsearch.is_a?(Langchain::Vectorsearch::Pgvector) ||
                            LangchainrbRails.config.vectorsearch.is_a?(Langchain::Vectorsearch::SqliteVec)

          # We use "__id" when Weaviate is the provider
          ids = records.map { |record| record.try("id") || record.dig("__id") }
          where(id: ids)
        end

        # Ask a question and return the answer
        #
        # @param question [String] The question to ask
        # @param k [Integer] The number of results to have in context
        # @yield [String] Stream responses back one String at a time
        # @return [String] The answer to the question
        # standard:disable Style/ArgumentsForwarding
        def ask(question, k: 4, &block)
          class_variable_get(:@@provider).ask(
            question: question,
            k: k,
            &block
          ).chat_completion
        end
        # standard:enable Style/ArgumentsForwarding
      end
    end
  end
end
