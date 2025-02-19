require "spec_helper"
require_relative "../../lib/langchainrb_overrides/assistant"

# Stub ActiveRecord::Base
module ActiveRecord
  class Base
    def self.transaction
      yield
    end
  end
end

# Stub Assistant class
class Assistant
  attr_accessor :id, :instructions, :tool_choice, :tools
  attr_writer :messages

  def initialize(attributes = {})
    attributes.each { |k, v| send(:"#{k}=", v) }
    @messages ||= []
  end

  def self.find(id)
  end

  def update!(*)
  end

  def messages
    @messages ||= []
  end

  def llm
    Langchain::LLM::GoogleGemini.new(api_key: "123")
  end
end

# Stub Message class
class Message
  attr_accessor :id, :role, :content, :tool_calls, :tool_call_id

  def update!(*)
  end
end

RSpec.describe Langchain::Assistant do
  let(:test_block) { proc { "test block executed" } }
  let(:tools) { [] }
  let(:llm) { Langchain::LLM::GoogleGemini.new(api_key: "123") }
  let(:assistant) do
    described_class.new(llm: llm, id: nil, tools: tools, instructions: "Test instructions", tool_choice: "auto", &test_block)
  end

  describe "#initialize" do
    it "sets the id and calls original_initialize" do
      expect(assistant.id).to be_nil
      expect(assistant.tools).to eq(tools)
      expect(assistant.instructions).to eq("Test instructions")
      expect(assistant.tool_choice).to eq("auto")
    end

    it "passes the block to the original_initialize" do
      assigned_block = assistant.instance_variable_get(:@block)
      expect(assigned_block).to eq(test_block)
    end
  end

  describe "#save" do
    it "creates a new Assistant record when id is nil" do
      expect(Assistant).to receive(:new).and_return(Assistant.new(id: 1))
      expect_any_instance_of(Assistant).to receive(:update!)
      assistant.save
      expect(assistant.id).to eq(1)
    end

    it "updates an existing Assistant record when id is present" do
      assistant.id = 1
      expect(Assistant).to receive(:find).with(1).and_return(Assistant.new(id: 1))
      expect_any_instance_of(Assistant).to receive(:update!)
      assistant.save
    end

    it "saves messages associated with the assistant" do
      assistant.add_message(role: "user", content: "Hello")
      expect_any_instance_of(Message).to receive(:update!)
      expect_any_instance_of(Assistant).to receive_message_chain(:messages, :find_or_initialize_by).and_return(Message.new)
      assistant.save
    end
  end

  describe ".load" do
    let(:ar_assistant) { Assistant.new(id: 1, instructions: "Test", tool_choice: "auto", tools: []) }
    let(:ar_message) { Message.new }

    before do
      allow(described_class).to receive(:find_assistant).and_return(ar_assistant)
      ar_assistant.messages << ar_message
      allow(ar_message).to receive_messages(role: "user", content: "Hello", tool_calls: [], tool_call_id: nil, id: 1)
    end

    it "loads an assistant with its attributes and messages" do
      loaded_assistant = described_class.load(1)
      expect(loaded_assistant.id).to eq(1)
      expect(loaded_assistant.instructions).to eq("Test")
      expect(loaded_assistant.tool_choice).to eq("auto")
      expect(loaded_assistant.tools).to eq([])
      expect(loaded_assistant.messages.size).to eq(1)
      expect(loaded_assistant.messages.first.content).to eq("Hello")
    end
  end
end
