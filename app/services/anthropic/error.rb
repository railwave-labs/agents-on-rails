# frozen_string_literal: true

module Anthropic
  # Base application-level error for Anthropic service failures.
  # The official SDK's exceptions live under Anthropic::Errors::* and are separate.
  class Error < ApplicationError; end
end
