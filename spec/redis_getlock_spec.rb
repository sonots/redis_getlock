require 'spec_helper'

describe RedisGetlock do
  it 'has a version number' do
    expect(RedisGetlock::VERSION).not_to be nil
  end
end
