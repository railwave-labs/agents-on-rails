# frozen_string_literal: true

module ThreadAgent
  # Simple Result object for consistent return values across ThreadAgent services
  class Result
    attr_reader :success, :data, :error, :metadata

    def initialize(success, data = nil, error = nil, metadata = {})
      @success = success
      @data = data
      @error = error
      @metadata = metadata
    end

    def self.success(data = nil, metadata = {})
      new(true, data, nil, metadata)
    end

    def self.failure(error = nil, metadata = {})
      new(false, nil, error, metadata)
    end

    def success?
      @success
    end

    def failure?
      !@success
    end
  end
end
