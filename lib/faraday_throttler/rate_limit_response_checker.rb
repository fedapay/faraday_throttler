module FaradayThrottler
  class RateLimitResponseChecker
    def call(response)
      response.has_key?(:status) && response[:status] == 429
    end
  end
end
