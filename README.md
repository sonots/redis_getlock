# RedisGetlock

Distributed locking using redis. Unlike other implementations avilable, this gem ensures releasing orphaned lock shortly.

# How It Works

This gem basically works as [http://redis.io/commands/set](http://redis.io/commands/set) describes for redis >= 2.6.12, and [http://redis.io/commands/setnx](http://redis.io/commands/setnx) describes for redis < 2.6.12.

Simple ruby codes which [http://redis.io/commands/set](http://redis.io/commands/set) describes are as follows:

```ruby
loop do
  break if redis.set(key, 'anystring', {nx: true, ex: expire})
  sleep 1
end
puts 'get lock'
begin
  # do a job
ensure
  redis.del(key) # unlock
end
```

The problem here is the value of `expire`.
The expiration time `expire` is necessary so that a lock will eventually be released even if a process is crashed or killed by SIGKILL before deleting the key.
However, how long should we set if we are uncertain how long a job takes?

This gem takes a following approach to resolve this problem.

1. Expiration time is set to `2` (default) seconds
2. Extend the lock in each `1` (default) second interval invoking another thread

This way ensures to release orphaned lock in 2 seconds. We are released from caring of the value of `expire`!!

Simple ruby codes to explain how this gem works are as follows:

```ruby
loop do
  break if redis.set(key, 'anystring', {nx: true, ex: 2})
  sleep 1
end
puts 'get lock'
thr = Thread.new do
  loop do
    redis.expire(key, 2)
    sleep 1
  end
end
begin
  # do a job
ensure
  thr.terminate
  redis.del(key) # unlock
end
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'redis_getlock'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install redis_getlock

## Usage

Similarly with ruby standard library [mutex](https://ruby-doc.org/core-2.2.0/Mutex.html), following methods are available:

* lock
  * Attempts to grab the lock and waits if it isn’t available. Returns true if successfully acquired a lock
* locked?
  * Returns true if this lock is currently held by some (including myself).
* synchronize {}
  * Obtains a lock, runs the block, and releases the lock when the block completes. Raises `RedisGetlock::LockError` error when failed to acquire a lock.
* unlock
  * Releases the lock. Returns true if successfully released a lock
* self_locked?
  * Returns true if this lock is currently held by myself.
* try_lock
  * Attempts to grab the lock and returns immediately without waits. Returns true if successfully acquired a lock  

Options of `RedisGetlock.new` are:

* redis
  * Provide a redis instance
* key
  * Key name for a distributed lock
* timeout
  * The timeout of trying to get the lock. A negative value means infinite timeout (default: -1)
* logger
  * Provide a logger for RedisGetlock (for debug)
* expire
  * The expiration seconds of the lock. The default is `2` second. Users usually do not need to care of this because the expiration is automatically extended in a invoked thread.
* interval
  * Interval to extend lock expiration. Must be `expire > interval`. The default is `1` second.

### Example

```ruby
require 'redis'
require 'redis_getlock'

redis = Redis.new # Redis.new(options)
mutex = RedisGetlock.new(redis: redis, key: 'lock_key')

mutex.lock
begin
  puts 'get lock'
ensure
  mutex.unlock
end

mutex.synchronize do
  puts 'get lock'
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sonots/redis_getlock. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

## ChangeLog

[CHANGELOG.md](./CHANGELOG.md)
