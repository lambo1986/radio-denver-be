require 'digest'

class RequestRateLimiter
  FALLBACK_STORE = ActiveSupport::Cache::MemoryStore.new(size: 4.megabytes)
  MUTEX = Mutex.new

  class << self
    def blocked?(scope:, identifier:, limit:, period:)
      count(scope: scope, identifier: identifier, period: period) >= limit
    end

    def record!(scope:, identifier:, period:)
      MUTEX.synchronize do
        key = cache_key(scope: scope, identifier: identifier, period: period)
        store.write(key, store.read(key).to_i + 1, expires_in: period * 2)
      end
    end

    def retry_after(period:)
      period - (Time.current.to_i % period)
    end

    def reset!
      FALLBACK_STORE.clear
      Rails.cache.clear unless Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
    end

    private

    def count(scope:, identifier:, period:)
      store.read(cache_key(scope: scope, identifier: identifier, period: period)).to_i
    end

    def store
      Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? FALLBACK_STORE : Rails.cache
    end

    def cache_key(scope:, identifier:, period:)
      window = Time.current.to_i / period
      digest = Digest::SHA256.hexdigest(identifier.to_s.downcase.strip)
      "rate-limit:#{scope}:#{window}:#{digest}"
    end
  end
end
