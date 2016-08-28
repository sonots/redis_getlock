require 'redis'
require "redis_getlock/version"
require 'securerandom'

class RedisGetlock
  attr_reader :redis, :key, :logger, :expire, :interval

  EXPIRE = 2
  INTERVAL = 1

  def initialize(redis:, key:, logger: nil, expire: EXPIRE, interval: INTERVAL)
    @redis = redis
    @key = key
    @logger = logger
    @expire = expire
    @interval = interval
  end

  def lock
    logger.info { "#{log_head}Wait acquiring a redis lock '#{key}'" } if logger
    if set_options_available?
      lock_with_set_options
      @thr = Thread.new(&method(:keeplock_with_set_options))
    else
      lock_without_set_options
      @thr = Thread.new(&method(:keeplock_without_set_options))
    end
    logger.info { "#{log_head}Acquired a redis lock '#{key}'" } if logger
  end

  def unlock
    @thr.terminate
    redis.del(key)
    logger.info { "#{log_head}Released a redis lock '#{key}'" } if logger
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

  def log_head
    "PID-#{::Process.pid} TID-#{::Thread.current.object_id.to_s(36)}: "
  end

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
      break if redis.set(key, uuid, {nx: true, ex: expire}) # key does not exist
      sleep interval
    end
  end

  def keeplock_with_set_options
    loop do
      redis.expire(key, expire) # extend expiration
      sleep interval
    end
  end

  # redis < 2.6.12
  # ref. http://redis.io/commands/setnx
  def lock_without_set_options
    loop do
      current = Time.now.to_f
      if redis.setnx(key, (current + expire).to_s) # key does not exist
        redis.expire(key, expire)
        break # acquire lock
      end
      expired = redis.get(key)
      if expired.to_f < current # key exists, but expired
        compared = redis.getset(key, (current + expire).to_s)
        break if expired == compared # acquire lock
      end
      sleep interval
    end
  end

  def keeplock_without_set_options
    loop do
      current = Time.now.to_f
      redis.setex(key, expire,  (current + expire).to_s) # extend expiration
      sleep interval
    end
  end
end
