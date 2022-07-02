require 'timeout'
require 'faraday'
require 'logger'
require 'faraday_throttler/key_resolver'
require 'faraday_throttler/cache'
require 'faraday_throttler/rate_limit_response_checker'

module FaradayThrottler
  class Middleware < Faraday::Middleware
    def initialize(
        # The base Faraday adapter.
        app,

        # Sticks cache.
        cache: Cache.new,

        # Resolves response unique key to use as cache key
        # Interface:
        #   #call(response_env Hash) String
        cache_key_resolver: KeyResolver.new,

        # Maximum requests to sent to the backend api simultanous
        rate: 10,

        # Queued requests will wait for up to 1 seconds for current in-flight request
        # to the same path.
        # If in-flight request hasn't finished after that time, return a default placeholder response.
        wait: 1,

        # Wraps requests to backend service in a timeout block, in seconds.
        # timeout: 0 disables this behaviour.
        timeout: 0,

        # Use to check if backend api response is a rate limit
        rate_limit_response_checker: RateLimitResponseChecker.new,

        # Pass your own Logger instance (for example Rails.logger in a Rails app).
        # Defaults to STDOUT.
        # http://ruby-doc.org/stdlib-2.1.0/libdoc/logger/rdoc/Logger.html
        # Interface:
        #   #debug(msg String, &block)
        #   #warn(msg String, &block)
        #   #error(msg String, &block)
        #   #info(msg String, &block)
        #   #fatal(msg String, &block)
        logger: Logger.new(STDOUT)
    )

      validate_dep! cache, :cache, :get, :set
      validate_dep! cache_key_resolver, :cache_key_resolver, :call
      validate_dep! rate_limit_response_checker, :rate_limit_response_checker, :call
      validate_dep! logger, :info, :error, :warn, :debug

      @cache = cache
      @cache_key_resolver = cache_key_resolver
      @rate = rate.to_i
      @wait = wait.to_i
      @timeout = timeout.to_i
      @rate_limit_response_checker = rate_limit_response_checker
      @logger = logger

      super app
    end

    def call(request_env)
      return app.call(request_env) if request_env[:method] != :get

      start = Time.now

      cache_key = cache_key_resolver.call(request_env)

      # Wait stick to be available
      until request_stick?(cache_key)
        logger.debug logline(cache_key, "A.1. No stick available. Wait for new one.")
        sleep(wait)
      end

      logger.debug logline(cache_key, "A.2. start backend request.")
      handle_request(request_env, cache_key, start)
    end

    private
    attr_reader :app, :cache, :cache_key_resolver, :rate, :wait, :timeout,
                :rate_limit_response_checker, :logger

    def handle_request(request_env, cache_key, start)
      logger.debug logline(cache_key, "B.1.1. handle sync. Timeout: #{timeout}")
      with_timeout(timeout) {
        fetch_and_check_rate_limit(request_env, cache_key, start)
      }
    rescue ::Timeout::Error => e
      release_request_stick(cache_key)
      logger.error logline(cache_key, "B.1.2. timeout error. Timeout: #{timeout}. Message: #{e.message}")
      raise Faraday::TimeoutError
    end

    def fetch_and_check_rate_limit(request_env, cache_key, start)
      app.call(request_env).on_complete do |response_env|
        if rate_limit_response_checker.call(response_env)
          wait_and_replay_call(request_env, cache_key, start)
        else
          # Everything alright
          logger.debug logline(cache_key, "C.1.2. Everything alright, request finished. Took #{Time.now - start}")
          debug_headers response_env, :fresh, start
          release_request_stick(cache_key)
        end
      end
    rescue Faraday::Error => e
      if e.is_a?(Faraday::ClientError) && rate_limit_response_checker.call(e.response)
        wait_and_replay_call(request_env, cache_key, start)
      else
        release_request_stick(cache_key)
        raise e
      end
    end

    def wait_and_replay_call(request_env, cache_key, start)
      # Replay request call
      sleep wait
      logger.debug logline(cache_key, "C.1.1. Rate limited on backend. Took #{Time.now - start}")
      fetch_and_check_rate_limit(request_env, cache_key, start)
    end

    def validate_dep!(dep, dep_name, *methods)
      methods.each do |m|
        raise ArgumentError, %(#{dep_name} must implement :#{m}) unless dep.respond_to?(m)
      end
    end

    def debug_headers(resp_env, status, start)
      resp_env[:response_headers].merge!(
        'X-Throttler' => status.to_s,
        'X-ThrottlerTime' => (Time.now - start)
      )
    end

    def with_timeout(seconds, &block)
      if seconds == 0
        yield
      else
        ::Timeout.timeout(seconds, &block)
      end
    end

    def request_stick?(cache_key)
      counter = cache.get(cache_key).to_i
      if counter < rate
        cache.set(cache_key, counter + 1)
        true
      else
        false
      end
    end

    def release_request_stick(cache_key)
      counter = cache.get(cache_key).to_i
      cache.set(cache_key, counter - 1) if counter > 0
    end

    def logline(cache_key, line)
      "[Throttler:#{cache_key}] #{line}"
    end
  end

  Faraday::Middleware.register_middleware throttler: ->{ Middleware }
end
