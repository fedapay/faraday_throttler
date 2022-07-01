module FaradayThrottler
  class RedisCache
    NAMESPACE = 'throttler:cache:'.freeze

    def initialize(redis: Redis.new, ttl: 0)
      @redis = redis
      @ttl = ttl
    end

    def set(key, value)
      opts = {}
      opts[:ex] = ttl if ttl > 0
      redis.set [NAMESPACE, key].join, value, opts
    end

    def get(key, default = nil)
      redis.get([NAMESPACE, key].join) || default
    end

    private
    attr_reader :redis, :ttl
  end
end
