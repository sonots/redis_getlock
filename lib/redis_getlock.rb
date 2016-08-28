require 'redis'
require "redis_getlock/version"
require 'securerandom'
require 'json'

class RedisGetlock
  attr_reader :redis, :key, :logger, :timeout, :expire, :interval, :uuid

  TIMEOUT = -1 # infinity
  EXPIRE = 2
  INTERVAL = 1

  class LockError < ::StandardError; end

  def initialize(redis:, key:, logger: nil, timeout: TIMEOUT, expire: EXPIRE, interval: INTERVAL)
    @redis = redis
    @key = key
    @logger = logger
    @timeout = timeout
    @expire = expire
    @interval = interval
    @uuid = SecureRandom.uuid
  end

  def lock
    logger.info { "#{log_head}Wait #{timeout < 0 ? '' : "#{timeout} sec "}to acquire a mysql lock '#{key}'" } if logger
    if set_options_available?
      locked = lock_with_set_options
    else
      locked = lock_without_set_options
    end
    @thr.terminate if @thr and @thr.alive?
    if locked
      @thr = Thread.new(&method(:keeplock))
      logger.info { "#{log_head}Acquired a redis lock '#{key}'" } if logger
      true
    else
      logger.info { "#{log_head}Timeout to acquire a redis lock '#{key}'" } if logger
      false
    end
  end

  def unlock
    @thr.terminate if @thr and @thr.alive?
    if self_locked?
      redis.del(key)
      logger.info { "#{log_head}Released a redis lock '#{key}'" } if logger
      true
    elsif locked?
      logger.info { "#{log_head}Failed to release a redis lock since somebody else locked '#{key}'" } if logger
      false
    else
      logger.info { "#{log_head}Redis lock did not exist '#{key}'" } if logger
      true
    end
  end

  def locked?
    redis.exists(key)
  end

  def self_locked?
    locked? && uuid == JSON.parse(redis.get(key))['uuid']
  end

  def synchronize(&block)
    raise LockError unless lock
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
    started = Time.now.to_f
    loop do
      current = Time.now.to_f
      payload = {uuid: uuid, expire_at: (current + expire).to_s}.to_json
      return true if redis.set(key, payload, {nx: true, ex: expire}) # key does not exist
      return false if timeout >= 0 and (current - started) >= timeout
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
        return true # acquire lock
      end
      previous = JSON.parse(redis.get(key))
      if previous['expire_at'].to_f < current # key exists, but previous
        compared = redis.getset(key, paylod)
        return true if previous['expire_at'] == compared['expire_at'] # acquire lock
      end
      return false if timeout >= 0 and (current - started) >= timeout
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
