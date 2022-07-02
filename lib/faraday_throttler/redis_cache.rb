module FaradayThrottler
  class RedisCache
    NAMESPACE = 'throttler:cache:'.freeze

    def initialize(redis: Redis.new, default_ttl: 60)
      @redis = redis
      @default_ttl = default_ttl
    end

    def set(key, value, ex: default_ttl)
      opts = {}
      opts[:ex] = ex if ex > 0
      redis.set [NAMESPACE, key].join, value, opts
    end

    def get(key, default = nil)
      redis.get([NAMESPACE, key].join) || default
    end

    private
    attr_reader :redis, :default_ttl
  end
end
