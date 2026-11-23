module Capture
  # Turn-by-turn: the chain of skills that gets someone from one skill to another,
  # following "next" roads. Fewest hops wins. Between equally short routes the one
  # through less congested skills wins (each congestion tier above free-flowing costs
  # a fraction of a hop), then the busier roads.
  class RoutePlanner
    Route = Struct.new(:keys, :legs, keyword_init: true)

    def self.call(from:, to:, map: nil) = new(map || RouteMap.call).route(from, to)

    def initialize(map)
      @nodes = map[:nodes].index_by { |n| n[:id] }
      @schedule = PricingSchedule.current
      @out = Hash.new { |h, k| h[k] = [] }
      map[:edges].each { |e| @out[e[:from]] << e if e[:kind] == "next" }
    end

    def congestion_cost(key)
      rank = @schedule.rank(@nodes[key][:tier])
      rank ? 0.3 * rank : 0.0
    end

    def route(from, to)
      return nil unless @nodes[from] && @nodes[to]
      return Route.new(keys: [from], legs: []) if from == to

      dist = { from => 0.0 }
      prev = {}
      queue = [[0.0, from]]
      done = Set.new
      until queue.empty?
        d, node = queue.min_by(&:first)
        queue.delete([d, node])
        next if done.include?(node)
        done << node
        break if node == to
        @out[node].each do |e|
          cost = d + 1.0 + 1.0 / (2 + e[:traffic]) + congestion_cost(e[:to])
          next unless cost < dist.fetch(e[:to], Float::INFINITY)
          dist[e[:to]] = cost
          prev[e[:to]] = e
          queue << [cost, e[:to]]
        end
      end
      return nil unless prev[to]

      legs = []
      node = to
      while (e = prev[node])
        legs.unshift(e)
        node = e[:from]
      end
      Route.new(keys: [from] + legs.map { |e| e[:to] }, legs: legs)
    end
  end
end
