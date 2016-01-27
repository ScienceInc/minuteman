require 'minuteman/event'

module Minuteman
  class Analyzer
    def initialize(action, klass = Minuteman::Event, user = nil)
      Minuteman.patterns.keys.each do |method|
        define_singleton_method(method) do |time = Minuteman.time|
          key = Minuteman.patterns[method].call(time)
          search = { type: action, time: key }
          search[:user_id] = user.id if !user.nil?

          klass.find_or_create(search)
        end
      end
    end
  end
end
