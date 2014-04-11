require 'fluent/input'

module Fluent
  module MeasureTimable
    def self.included(klass)
      klass.__send__(:alias_method, :configure_without_measure, :configure)
      klass.__send__(:alias_method, :configure, :configure_with_measure)
    end

    def configure_with_measure(conf)
      configure_without_measure(conf)
      if element = conf.elements.select { |element| element.name == 'measure' }.first
        @measure = MeasureTime.new(self, log)
        @measure.configure(element)
        # #start and #stop methods must be extended in concrete input plugins
        # because most of built-in input plugins do not call `super`
        klass = self.class
        unless klass.method_defined?(:start_without_measure)
          klass.__send__(:alias_method, :start_without_measure, :start)
          klass.__send__(:alias_method, :start, :start_with_measure)
          klass.__send__(:alias_method, :shutdown_without_measure, :shutdown)
          klass.__send__(:alias_method, :shutdown, :shutdown_with_measure)
        end
      end
    end

    def measure
      @measure
    end

    def start_with_measure
      start_without_measure
      @measure.start if @measure
    end

    def shutdown_with_measure
      shutdown_without_measure
      @measure.stop if @measure
    end
  end

  Input.__send__(:include, MeasureTimable)
  Output.__send__(:include, MeasureTimable)

  class MeasureTime
    attr_reader :input, :log, :times, :mutex, :thread, :tag, :interval, :hook
    def initialize(input, log)
      @input = input
      @log = log
      @times = []
      @mutex = Mutex.new
    end

    def configure(conf)
      @tag = conf['tag'] || 'measure'
      @interval = conf['interval'].to_i || 60
      unless @hook = conf['hook']
        raise Fluent::ConfigError, '`hook` option must be specified in <measure></elpased> directive'
      end
      apply_hook(@hook)
    end

    def add(time)
      @times << time
    end

    def clear
      @times.clear
    end

    def apply_hook(hook)
      if hook.include?('.')
        klass_name, method_name = hook.split('.', 2)
        klass = constantize(klass_name)
      else
        klass = @input.class
        method_name = hook
      end
      old_method_name = "#{method_name}_without_measure".to_sym 
      unless klass.method_defined?(old_method_name)
        klass.__send__(:alias_method, old_method_name, method_name)
        klass.__send__(:define_method, method_name) do |*args|
          measure.measure_time(klass, method_name) do
            self.__send__(old_method_name, *args)
          end
        end
      end
    end

    def measure_time(klass, method_name)
      started = Time.now
      output = yield
      measure = (Time.now - started).to_f
      log.debug "elapsed time at #{klass}##{method_name} is #{measure} sec"
      @mutex.synchronize { self.add(measure) }
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
          log.warn "in_forward: #{e.class} #{e.message} #{e.backtrace.first}"
        end
      end
    end

    def flush(now)
      times = []
      @mutex.synchronize do
        times = @times.dup
        self.clear
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

    private
    # File activesupport/lib/active_support/inflector/methods.rb, line 219
    def constantize(camel_cased_word)
      names = camel_cased_word.split('::')
      names.shift if names.empty? || names.first.empty?

      names.inject(Object) do |constant, name|
        if constant == Object
          constant.const_get(name)
        else
          candidate = constant.const_get(name)
          next candidate if constant.const_defined?(name, false)
          next candidate unless Object.const_defined?(name)

          # Go down the ancestors to check it it's owned
          # directly before we reach Object or the end of ancestors.
          constant = constant.ancestors.inject do |const, ancestor|
            break const    if ancestor == Object
            break ancestor if ancestor.const_defined?(name, false)
            const
          end

          # owner is in Object, so raise
          constant.const_get(name, false)
        end
      end
    end
  end
end
