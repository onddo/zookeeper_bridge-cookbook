# encoding: UTF-8

class Chef
  class ZookeeperBridge
    # ZooKeeper lockers until the desired state is met
    class StatusLocker < ZookeeperBridge
      private

      def event_types_hash(event_types)
        event_types_ary = [event_types].flatten
        event_types_ary.each_with_object({}) do |v, r|
          r["ZOO_#{v.to_s.upcase}_EVENT"] = v.to_sym
        end
      end

      def satisfies_status?(path, status)
        case status
        when :created then @zk.exists?(path, watch: true)
        when :deleted then !@zk.exists?(path, watch: true)
        else
          fail "#{__method__.to_s}: unknown status: #{status.inspect}"
        end
      end

      def subscribe_until_event(path, event_types)
        event_types_hs = event_types_hash(event_types)
        @zk.register(path) do |event|
          yield(event_types_hs[event]) if event_types_hs.key?(event.event_name)
        end
      end

      def subscribe_until_status(path, status)
        @zk.register(path) do |event|
          if event.send("node_#{status.to_s}?")
            yield(status)
          else
            if satisfies_status?(event.path, status)
              yield(status) # ooh! surprise! the status is already correct
            end
          end
        end
      end

      def until_znode_status(path, status)
        queue = Queue.new
        ev_sub = subscribe_until_status(path, status) { |e| queue.enq(e) }
        # set up the callback, but bail if we don't need to wait
        return true if satisfies_status?(path, status)
        queue.pop # block waiting for node creation
      ensure
        ev_sub.unsubscribe unless ev_sub.nil?
      end

      public

      def until_znode_event(path, events)
        queue = Queue.new
        ev_sub = subscribe_until_event(path, events) { |e| queue.enq(e) }
        @zk.stat(path, watch: true)
        queue.pop # block waiting for node change
      ensure
        ev_sub.unsubscribe unless ev_sub.nil?
      end

      def until_znode_created(path)
        until_znode_status(path, :created)
      end

      def until_znode_changed(path)
        block_until_znode_event(path, :changed)
      end

      def until_znode_deleted(path)
        until_znode_status(path, :deleted)
      end
    end # StatusLocker
  end # ZookeeperBridge
end
