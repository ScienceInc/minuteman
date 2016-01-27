require 'redic'

module Minuteman
  LUA_CACHE      = Hash.new { |h, k| h[k] = Hash.new }
  LUA_OPERATIONS = File.expand_path("../minuteman/lua/operations.lua",   __FILE__)

  class << self
    def config
      @_configuration ||= Configuration.new
    end

    def configure
      yield(config)
    end

    def prefix
      config.prefix
    end

    def patterns
      config.patterns
    end

    def time_spans
      @_time_spans = patterns.keys
    end

    def time
      Time.now.in_time_zone("Pacific Time (US & Canada)")
    end

    def events(filter = "")
      config.redis.call("SMEMBERS", "#{Minuteman.prefix}::Events").select{|e| e.match(/^#{filter}/)}
    end

    def attributions
      config.redis.call("SMEMBERS", "#{Minuteman.prefix}::Attributions")
    end

    def track(action, users = nil, time = time)
      users = Minuteman::User.create if users.nil?

      Array(users).each do |user|
        process do
          time_spans.each do |time_span|
            event = Minuteman::Event.find_or_create(
              type: action,
              time: patterns[time_span].call(time)
            )

            event.setbit(user.id)
          end
        end
      end

      users
    end

    def attribute(consultant, users = nil, add = true)
      users = Minuteman::User.create if users.nil?
      Array(users).each do |user|
        attribution = Minuteman::Attribution.find_or_create(
          consultant_id: consultant.id
        )
        attribution.update_consultant(user.id, add)
      end
      users
    end

    def add(action, time = time, users = [])
      time_spans.each do |time_span|
        process do
          counter = Minuteman::Counter.create({
            type: action,
            time: patterns[time_span].call(time)
          })

          counter.incr
        end
      end

      Array(users).each do |user|
        time_spans.each do |time_span|
          counter = Minuteman::Counter::User.create({
            user_id: user.id,
            type: action,
            time: patterns[time_span].call(time)
          })

          counter.incr
        end
      end
    end

    def analyze(action)
      analyzers_cache[action]
    end

    def count(action)
      counters_cache[action]
    end

    def most_popular(event_prefix = "")
      popular = {}
      Minuteman.events(event_prefix).each do |event|
        # TODO different time periods
        popular[event.gsub(/^#{event_prefix}:/, "")] = Minuteman.count(event).month.count
      end
      return Hash[popular.sort_by{|k, v| v}.reverse]
    end

    private

    def process(&block)
      if !!config.parallel
        Thread.current(&block)
      else
        block.call
      end
    end

    def analyzers_cache
      @_analyzers_cache ||= Hash.new do |h,k|
        h[k] = Minuteman::Analyzer.new(k)
      end
    end

    def counters_cache
      @_counters_cache ||= Hash.new do |h,k|
        h[k] = Minuteman::Analyzer.new(k, Minuteman::Counter)
      end
    end
  end
end

# Helper method to easily access the analytics part
def Minuteman(action)
  Minuteman.analyze(action)
end

# Why call this method so different from Minuteman?
# for the lulz: https://github.com/maccman/counterman/issues/1
def Counterman(action)
  Minuteman.count(action)
end

require 'minuteman/user'
require 'minuteman/event'
require 'minuteman/attribution'
require 'minuteman/counter'
require 'minuteman/result'
require 'minuteman/analyzer'
require 'minuteman/configuration'
