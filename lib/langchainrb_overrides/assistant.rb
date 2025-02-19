# frozen_string_literal: true

require "active_record"

module Langchain
  class Assistant
    attr_accessor :id

    alias_method :original_initialize, :initialize

    def initialize(id: nil, **kwargs, &block) # rubocop:disable Style/ArgumentsForwarding
      @id = id
      original_initialize(**kwargs, &block) # rubocop:disable Style/ArgumentsForwarding
    end

    def save
      ::ActiveRecord::Base.transaction do
        ar_assistant = if id
          self.class.find_assistant(id)
        else
          ::Assistant.new
        end

        ar_assistant.update!(
          instructions: instructions,
          tool_choice: tool_choice,
          tools: tools.map(&:class).map(&:name)
        )

        messages.each do |message|
          ar_message = ar_assistant.messages.find_or_initialize_by(id: message.id)
          ar_message.update!(
            role: message.role,
            content: message.content,
            tool_calls: message.tool_calls,
            tool_call_id: message.tool_call_id
          )
          message.id = ar_message.id
        end

        @id = ar_assistant.id
        true
      end
    end

    class << self
      def find_assistant(id)
        ::Assistant.find(id)
      end

      def load(id)
        ar_assistant = find_assistant(id)

        tools = ar_assistant.tools.map { |tool_name| Object.const_get(tool_name).new }

        assistant = Langchain::Assistant.new(
          id: ar_assistant.id,
          llm: ar_assistant.llm,
          tools: tools,
          instructions: ar_assistant.instructions,
          # Default to auto to match the behavior of the original Langchain::Assistant
          tool_choice: ar_assistant.tool_choice || "auto"
        )

        ar_assistant.messages.each do |ar_message|
          messages = assistant.add_message(
            role: ar_message.role,
            content: ar_message.content,
            tool_calls: ar_message.tool_calls,
            tool_call_id: ar_message.tool_call_id
          )
          messages.last.id = ar_message.id
        end

        assistant
      end
    end
  end
end
