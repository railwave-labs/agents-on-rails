# frozen_string_literal: true

module Anthropic
  class ToolLoop
    MAX_TURNS = 10

    def initialize(client: Anthropic::ApiClient.new, mcp_servers: [], on_step: ->(_) {})
      @client      = client
      @mcp_servers = mcp_servers
      @on_step     = on_step
    end

    def run(system:, messages:, model: AppConfig.anthropic_model, max_tokens: 4096)
      params = {
        model:      model,
        max_tokens: max_tokens,
        system:     system,
        messages:   messages
      }
      params[:mcp_servers] = @mcp_servers if @mcp_servers.any?

      response = @client.messages_create(**params)
      record_steps(response)
      extract_final_text(response)
    rescue ApplicationError
      raise
    rescue StandardError => e
      raise ErrorHandler.standardize_error(e, service: "anthropic", context: { component: "tool_loop" })
    end

    private

    def record_steps(response)
      Array(response.content).each do |block|
        block_type = block_type_str(block)
        case block_type
        when "mcp_tool_use"
          @on_step.call(name: "mcp_tool_use", data: {
            server: block_field(block, :server_name),
            name:   block_field(block, :name),
            input:  block_field(block, :input)
          })
        when "mcp_tool_result"
          @on_step.call(name: "mcp_tool_result", data: {
            tool_use_id: block_field(block, :tool_use_id),
            is_error:    block_field(block, :is_error),
            content:     block_field(block, :content)
          })
        end
      end

      if response.respond_to?(:usage) && response.usage
        usage = response.usage
        @on_step.call(name: "usage", data: {
          "input_tokens"  => usage.input_tokens,
          "output_tokens" => usage.output_tokens
        })
      end
    end

    def extract_final_text(response)
      text_blocks = Array(response.content).select { |b| block_type_str(b) == "text" }
      raise ValidationError.new("No text content in Anthropic response") if text_blocks.empty?

      text_blocks.map { |b| block_field(b, :text).to_s }.join("\n").strip
    end

    # Returns the block type as a plain string.
    # Handles both SDK objects (.type) and plain hashes (for tests / unknown block types).
    def block_type_str(block)
      if block.respond_to?(:type)
        block.type.to_s
      elsif block.respond_to?(:[])
        (block["type"] || block[:type]).to_s
      end
    end

    # Reads a field from a block using progressive fallback:
    #   1. Direct Ruby accessor (e.g., block.name)
    #   2. to_h with symbol key (handles extra fields the SDK stores via the base model)
    #   3. Hash [] access for plain-hash test doubles
    def block_field(block, key)
      if block.respond_to?(key)
        block.public_send(key)
      elsif block.respond_to?(:to_h)
        h = block.to_h
        h[key] || h[key.to_s]
      elsif block.respond_to?(:[])
        block[key.to_s] || block[key]
      end
    end
  end
end
