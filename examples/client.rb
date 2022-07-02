require 'bundler/setup'
require 'redis'
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'faraday_throttler/middleware'
require 'faraday_throttler/redis_cache'


redis = Redis.new
cache = FaradayThrottler::RedisCache.new(redis: redis, default_ttl: 60)

conn = Faraday.new(:url => 'http://localhost:9800') do |faraday|
  # faraday.response :logger                  # log requests to STDOUT
  faraday.use :throttler, rate: 10, wait: 1, cache: cache
  faraday.adapter  Faraday.default_adapter
end

start = Time.now
success = 0
tr = (1..100).map do |i|
  Thread.new do
    sleep (rand * 10)
    n = Time.now
    r = conn.get('/foo/bar')
    success += 1 if r.status == 200
    # puts %([#{n}] #{r.headers['X-Throttler']} took: #{r.headers['X-ThrottlerTime']} - #{r.body})
  end
end

tr.map{|t| t.join }


p "Success ------- #{success}  --- Time = #{Time.now - start}"
