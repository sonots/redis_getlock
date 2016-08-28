require 'redis'
require "redis_getlock/version"
require 'securerandom'
require 'json'

class RedisGetlock
  attr_reader :redis, :key, :logger, :expire, :interval, :uuid

  EXPIRE = 2
  INTERVAL = 1

  def initialize(redis:, key:, logger: nil, expire: EXPIRE, interval: INTERVAL)
    @redis = redis
    @key = key
    @logger = logger
    @expire = expire
    @interval = interval
    @uuid = SecureRandom.uuid
  end

  def lock
    logger.info { "#{log_head}Wait acquiring a redis lock '#{key}'" } if logger
    if set_options_available?
      lock_with_set_options
    else
      lock_without_set_options
    end
    @thr = Thread.new(&method(:keeplock))
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

  def self_locked?
    redis.exists(key) && uuid == JSON.parse(redis.get(key))['uuid']
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
    loop do
      current = Time.now.to_f
      payload = {uuid: uuid, expire_at: (current + expire).to_s}.to_json
      break if redis.set(key, payload, {nx: true, ex: expire}) # key does not exist
      sleep interval
    end
  end

  # redis < 2.6.12
  # ref. http://redis.io/commands/setnx
  def lock_without_set_options
    loop do
      current = Time.now.to_f
      payload = {uuid: uuid, expire_at: (current + expire).to_s}.to_json
      if redis.setnx(key, payload) # key does not exist
        redis.expire(key, expire)
        break # acquire lock
      end
      previous = JSON.parse(redis.get(key))
      if previous['expire_at'].to_f < current # key exists, but previous
        compared = redis.getset(key, paylod)
        break if previous['expire_at'] == compared['expire_at'] # acquire lock
      end
      sleep interval
    end
  end

  def keeplock
    loop do
      current = Time.now.to_f
      payload = {uuid: uuid, expire_at: (current + expire).to_s}.to_json
      redis.setex(key, expire, payload) # extend expiration
      sleep interval
    end
  end
end
