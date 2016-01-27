require 'minuteman/model'
require 'minuteman/analyzable'

module Minuteman
  class Attribution < Minuteman::Model
    include Minuteman::Analyzable

    attribute :consultant_id

    def update_consultant(id, add = true)
      setbit(id, add)
      update_list(id, add)
    end

    def setbit(int, add = true)
      bit = add ? 1 : 0
      Minuteman.config.redis.call("SETBIT", key, int, bit)
    end

    def getbit(int)
      Minuteman.config.redis.call("GETBIT", key, int)
    end

    def update_list(id, add = true)
      action = add ? "SADD" : "SREM"
      Minuteman.config.redis.call(action, "#{Minuteman.prefix}::AttributionIDs::#{consultant_id}", id)
    end

    def get_ids
      Minuteman.config.redis.call("SMEMBERS", "#{Minuteman.prefix}::AttributionIDs::#{consultant_id}")
    end

    def self.find(*args)
      looked_up = "#{self.name}::#{args.first[:consultant_id]}:id"
      potential_id = Minuteman.config.redis.call("GET", looked_up)

      return nil if !potential_id

      attribution = self[potential_id]
      attribution.consultant_id = args.first[:consultant_id]

      attribution
    end

    def self.create(*args)
      attribution = super(*args)
      Minuteman.config.redis.call("SET", "#{attribution.key}:id", attribution.id)
      Minuteman.config.redis.call("SETBIT", "#{Minuteman.prefix}::Consultants", attribution.consultant_id, 1)

      attribution
    end

    def key
      "#{self.class.name}::#{consultant_id}"
    end
  end
end
