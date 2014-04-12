require 'fluent/input'

module Fluent
  class MeasureTimeInput < Input
    Plugin.register_input('measure_time', self)

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
    end

    attr_reader :measure_time

    def configure_with_measure_time(conf)
      configure_without_measure_time(conf)
      if element = conf.elements.select { |element| element.name == 'measure_time' }.first
        @measure_time = MeasureTime.new(self, log)
        @measure_time.configure(element)
      end
    end
  end

  class MeasureTime
    attr_reader :plugin, :log, :times, :mutex, :thread, :tag, :interval, :hook
    def initialize(plugin, log)
      @plugin = plugin
      @log = log
      @times = []
      @mutex = Mutex.new
    end

    def configure(conf)
      @tag = conf['tag'] || 'measure_time'
      @interval = conf['interval'].to_i || 60
      unless @hook = conf['hook']
        raise Fluent::ConfigError, '`hook` option must be specified in <measure_time></measure_time> directive'
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
      log.debug "elapsed time at #{@plugin.class}##{@hook} is #{elapsed} sec"
      @mutex.synchronize { @times << elapsed }
      output
    end

    def start
      @thread = Thread.new(&method(:run))
    end

    def stop
      @thread.terminate
      @thread.join
    end

    def run
      @last_checked ||= Engine.now
      while (sleep 0.5)
        begin
          now = Engine.now
          if now - @last_checked >= @interval
            flush(now)
            @last_checked = now
          end
        rescue => e
          log.warn "in_measure_time: hook #{klass}##{method_name} #{e.class} #{e.message} #{e.backtrace.first}"
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
        triple = [@tag, now, {:num => num, :max => max, :avg => avg}]
        Engine.emit(*triple)
      end
      triple
    end
  end
end
