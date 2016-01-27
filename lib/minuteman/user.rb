require 'ohm'
require 'securerandom'

module Minuteman
  class User < ::Ohm::Model
    attribute :uid
    attribute :identifier
    attribute :anonymous
    attribute :consultant_identifier

    unique :uid
    unique :identifier

    index :anonymous

    def save
      self.uid ||= SecureRandom.uuid
      self.anonymous ||= !identifier
      super
    end

    def track(action, time = Minuteman.time)
      Minuteman.track(action, self, time)
    end

    def add(action, time = Minuteman.time)
      Minuteman.add(action, time, self)
    end

    def count(action, time = Minuteman.time)
      Minuteman::Analyzer.new(action, Minuteman::Counter::User, self)
    end

    def anonymous?
      self.anonymous == true
    end

    def make_consultant
      Minuteman.config.redis.call("SETBIT", "#{Minuteman.prefix}::Consultants", self.id, 1)
    end

    def revoke_consultant
      Minuteman.config.redis.call("SETBIT", "#{Minuteman.prefix}::Consultants", self.id, 0)
    end

    def consultant?
      Minuteman.config.redis.call("GETBIT", "#{Minuteman.prefix}::Consultants", self.id) == 1
    end

    def attribute(consultant, add = true)
      Minuteman.attribute(consultant, self, add)
      self.consultant_identifier = consultant.identifier
      save
    end

    def attributed_to?(consultant)
      consultant.attribution.include?(self)
    end

    def customer_ids
      self.attribution.get_ids
    end

    def attribution
      Minuteman::Attribution.find_or_create(
        consultant_id: self.id
      )
    end

    def users_who_did(event)
      Minuteman(event).month.included(customer_ids)
    end

    def most_popular(event_prefix = "", days = 7)
      popular = {}
      Minuteman.events(event_prefix).each do |event|
        sum = 0
        days.times{|i| sum += (Minuteman(event).day(Minuteman.time - (i+1).days) & attribution).count}
        popular[event.gsub(/^#{event_prefix}:/, "")] = sum
      end
      return Hash[popular.sort_by{|k, v| v}.reverse]
    end

    def promote(identifier)
      self.identifier = identifier
      self.anonymous = false
      save
    end

    def self.[](identifier_or_uuid)
      with(:uid, identifier_or_uuid) || with(:identifier, identifier_or_uuid)
    end
  end
end
