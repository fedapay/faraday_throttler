module FaradayThrottler
  class Cache
    def initialize(store = {})
      @mutex = Mutex.new
      @store = store
    end

    def set(key, resp, _ = {})
      mutex.synchronize { store[key] = resp }
    end

    def get(key)
      mutex.synchronize { store[key] }
    end

    private
    attr_reader :store, :mutex
  end
end
