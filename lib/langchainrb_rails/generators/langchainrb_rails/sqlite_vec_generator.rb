# frozen_string_literal: true

module LangchainrbRails
  module Generators
    #
    # Usage:
    #     rails generate langchainrb_rails:sqlite_vec --model=Product --llm=openai
    #
    class SqliteVecGenerator < LangchainrbRails::Generators::BaseGenerator
      desc "This generator adds sqlite-vec vectorsearch integration to your ActiveRecord model"
      source_root File.join(__dir__, "templates")

      def copy_migration
        migration_template "enable_sqlite_vector_extension_template.rb", "db/migrate/enable_sqlite_vector_extension.rb",
                           migration_version: migration_version
        migration_template "add_sqlite_vector_column_template.rb", "db/migrate/add_sqlite_vector_column_to_#{table_name}.rb",
                           migration_version: migration_version
      end

      def create_initializer_file
        template "sqlite_vec_initializer.rb", "config/initializers/langchainrb_rails.rb"
      end

      def migration_version
        "[#{::ActiveRecord::VERSION::MAJOR}.#{::ActiveRecord::VERSION::MINOR}]"
      end

      def add_to_model
        inject_into_class "app/models/#{model_name.underscore}.rb", model_name do
          "  vectorsearch\n\n  after_save :upsert_to_vectorsearch\n\n  after_destroy :destroy_from_vectorsearch\n\n"
        end
      end

      # def add_to_gemfile
      #   # Dependency for Sqlite-vec
      #   gem_group :default do
      #     gem "sqlite3", "> 2.1" unless gem_exists?("sqlite3")
      #     gem "sqlite-vec", "~> 0.1.7.alpha.2" unless gem_exists?("sqlite-vec")

      #     if options["llm"] == "ollama"
      #       gem "faraday" unless gem_exists?("faraday")
      #     elsif options["llm"] == "openai"
      #       gem "ruby-openai" unless gem_exists?("ruby-openai")
      #     end
      #   end
      # end

      private

      # @return [String] Name of the model
      def model_name
        options["model"]
      end

      # @return [String] Table name of the model
      def table_name
        model_name.tableize
      end

      # @return [String] LLM provider to use
      def llm
        options["llm"]
      end

      # @return [Langchain::LLM::*] LLM class
      def llm_class
        Langchain::LLM.const_get(LLMS[llm])
      end

      # @return [Integer] Dimension of the vector to be used
      def vector_dimensions
        llm_class.default_dimensions
      end
    end
  end
end
