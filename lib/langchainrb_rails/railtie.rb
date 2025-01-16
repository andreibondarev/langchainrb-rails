# frozen_string_literal: true

module LangchainrbRails
  class Railtie < Rails::Railtie
    initializer "langchainrb_rails" do
      ActiveSupport.on_load(:active_record) do
        require "sqlite_vec" if defined?(SqliteVec)
        ::ActiveRecord::Base.include LangchainrbRails::ActiveRecord::Hooks
      end
    end

    generators do
      require_relative "generators/langchainrb_rails/assistant_generator"
      require_relative "generators/langchainrb_rails/chroma_generator"
      require_relative "generators/langchainrb_rails/pinecone_generator"
      require_relative "generators/langchainrb_rails/pgvector_generator"
      require_relative "generators/langchainrb_rails/qdrant_generator"
      require_relative "generators/langchainrb_rails/prompt_generator"
      require_relative "generators/langchainrb_rails/sqlite_vec_generator"
    end
  end
end
