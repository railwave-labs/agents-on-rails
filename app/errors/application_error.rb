# frozen_string_literal: true

class ApplicationError < StandardError
  attr_reader :code, :context, :retryable

  def initialize(message = nil, code: nil, context: {}, retryable: true)
    super(message)
    @code = code
    @context = context || {}
    @retryable = retryable
  end

  def retryable?
    @retryable
  end

  def to_h
    {
      code: code,
      message: message,
      context: context,
      retryable: retryable?
    }
  end
end
