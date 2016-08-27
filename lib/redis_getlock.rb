require 'redis'
require "redis_getlock/version"
require 'securerandom'

class RedisGetlock
  attr_reader :redis, :key, :logger, :timeout, :interval

  TIMEOUT = 2
  INTERVAL = 1

  def initialize(redis:, key:, logger: nil, timeout: TIMEOUT, interval: INTERVAL)
    @redis = redis
    @key = key
    @logger = logger
    @timeout = timeout
    @interval = interval
  end

  def lock
    logger.info { "RedisGetlock: Wait acquiring a lock: #{key}" } if logger
    if set_options_available?
      lock_with_set_options
      @thr = Thread.new(&method(:keeplock_with_set_options))
    else
      lock_without_set_options
      @thr = Thread.new(&method(:keeplock_without_set_options))
    end
    logger.info { "RedisGetlock: Acquired a lock: #{key}" } if logger
  end

  def unlock
    @thr.terminate
    redis.del(key)
    logger.info { "RedisGetlock: Released a lock: #{key}" } if logger
  end

  def locked?
    redis.exists(key)
  end

  def synchronize(&block)
    lock
    begin
      yield
    ensure
      unlock
    end
  end

  private

  def set_options_available?
    return @set_options_avialble unless @set_options_avialble.nil?
    major, minor, patch = redis.info['redis_version'].split('.').map(&:to_i)
    @set_options_avialble = major > 2 || (major == 2 && minor > 7) || (major == 2 && minor == 6 && patch >= 12)
  end

  # redis >= 2.6.12
  # ref. http://redis.io/commands/set
  def lock_with_set_options
    uuid = SecureRandom.uuid
    loop do
      break if redis.set(key, uuid, {nx: true, ex: timeout}) # key does not exist
      sleep interval
    end
  end

  def keeplock_with_set_options
    loop do
      redis.expire(key, timeout) # extend expiration
      sleep interval
    end
  end

  # redis < 2.6.12
  # ref. http://redis.io/commands/setnx
  def lock_without_set_options
    loop do
      current = Time.now.to_f
      if redis.setnx(key, (current + timeout).to_s) # key does not exist
        redis.expire(key, timeout)
        break # acquire lock
      end
      expired = redis.get(key)
      if expired.to_f < current # key exists, but expired
        compared = redis.getset(key, (current + timeout).to_s)
        break if expired == compared # acquire lock
      end
      sleep interval
    end
  end

  def keeplock_without_set_options
    loop do
      current = Time.now.to_f
      redis.setex(key, timeout,  (current + timeout).to_s) # extend expiration
      sleep interval
    end
  end
end
