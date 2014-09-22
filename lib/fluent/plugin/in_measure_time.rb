require 'fluent/input'

module Fluent
  class MeasureTimeInput < Input
    Plugin.register_input('measure_time', self)

    unless method_defined?(:router)
      define_method(:router) { ::Fluent::Engine }
    end

    def configure(conf)
      ::Fluent::Input.__send__(:include, MeasureTimable)
      ::Fluent::Output.__send__(:include, MeasureTimable)
    end
  end

  module MeasureTimable
    def self.included(klass)
      unless klass.method_defined?(:configure_without_measure_time)
        klass.__send__(:alias_method, :configure_without_measure_time, :configure)
        klass.__send__(:alias_method, :configure, :configure_with_measure_time)
      end

      unless klass.method_defined?(:router)
        define_method(:router) { ::Fluent::Engine }
      end
    end

    attr_reader :measure_time

    def configure_with_measure_time(conf)
      configure_without_measure_time(conf)
      if element = conf.elements.select { |element| element.name == 'measure_time' }.first
        @measure_time = MeasureTime.new(self, log, router)
        @measure_time.configure(element)
      end
    end
  end

  class MeasureTime
    attr_reader :plugin, :log, :router, :times, :mutex, :thread, :tag, :interval, :hook
    def initialize(plugin, log, router)
      @plugin = plugin
      @klass = @plugin.class
      @log = log
      @router = router
      @times = []
      @mutex = Mutex.new
    end

    def configure(conf)
      @tag = conf['tag'] || 'measure_time'
      unless @hook = conf['hook']
        raise Fluent::ConfigError, '`hook` option must be specified in <measure_time></measure_time> directive'
      end
      @hook_msg = {:class => @klass.to_s, :hook => @hook.to_s, :object_id => @plugin.object_id.to_s}
      @interval = conf['interval'].to_i if conf['interval']
      @add_or_emit_proc =
        if @interval
          # add to calculate statistics in each interval
          Proc.new {|elapsed|
            @mutex.synchronize { @times << elapsed }
          }
        else
          # emit information immediately
          Proc.new {|elapsed|
            msg = {:time => elapsed}.merge(@hook_msg)
            router.emit(@tag, ::Fluent::Engine.now, msg)
          }
        end
      apply_hook
    end

    def apply_hook
      @plugin.instance_eval <<EOF
        def #{@hook}(*args)
          measure_time.measure_time do
            super
          end
        end
        def start
          super
          measure_time.start
        end
        def stop
          super
          measure_time.stop
        end
EOF
    end

    def measure_time
      started = Time.now
      output = yield
      elapsed = (Time.now - started).to_f
      log.debug "elapsed time at #{@klass}##{@hook} is #{elapsed} sec"
      @add_or_emit_proc.call(elapsed)
      output
    end

    def start
      return unless @interval
      @thread = Thread.new(&method(:run))
    end

    def stop
      return unless @interval
      @thread.terminate
      @thread.join
    end

    def run
      @last_checked ||= ::Fluent::Engine.now
      while (sleep 0.5)
        begin
          now = ::Fluent::Engine.now
          if now - @last_checked >= @interval
            flush(now)
            @last_checked = now
          end
        rescue => e
          log.warn "in_measure_time: hook #{@klass}##{@hook} #{e.class} #{e.message} #{e.backtrace.first}"
        end
      end
    end

    def flush(now)
      times = []
      @mutex.synchronize do
        times = @times.dup
        @times.clear
      end
      triple = nil
      unless times.empty?
        num = times.size
        max = num == 0 ? 0 : times.max
        avg = num == 0 ? 0 : times.map(&:to_f).inject(:+) / num.to_f
        triple = [@tag, now, {:max => max, :avg => avg, :num => num}.merge(@hook_msg)]
        router.emit(*triple)
      end
      triple
    end
  end
end
