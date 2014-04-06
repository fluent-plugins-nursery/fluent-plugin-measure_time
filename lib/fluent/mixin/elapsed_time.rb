require 'fluent/input'

module Fluent
  module ElapsedMeasurable
    def self.included(klass)
      klass.__send__(:alias_method, :configure_without_elapsed, :configure)
      klass.__send__(:alias_method, :configure, :configure_with_elapsed)
    end

    def configure_with_elapsed(conf)
      self.configure_without_elapsed(conf)
      if element = conf.elements.first { |element| element.name == 'elapsed' }
        @elapsed = ElapsedMeasure.new(self, log)
        @elapsed.configure(element)
        klass = self.class
        klass.__send__(:alias_method, :start_without_elapsed, :start)
        klass.__send__(:alias_method, :start, :start_with_elapsed)
        klass.__send__(:alias_method, :shutdown_without_elapsed, :shutdown)
        klass.__send__(:alias_method, :shutdown, :shutdown_with_elapsed)
      end
    end

    def start_with_elapsed
      start_without_elapsed
      @elapsed.start if @elapsed
    end

    def shutdown_with_elapsed
      shutdown_without_elapsed
      @elapsed.stop if @elapsed
    end
  end

  Input.__send__(:include, ElapsedMeasurable)

  class ElapsedMeasure
    attr_reader :input, :log, :times, :mutex, :thread, :tag, :interval, :hook
    def initialize(input, log)
      @input = input
      @log = log
      @times = []
      @mutex = Mutex.new
    end

    def configure(conf)
      @tag = conf['tag'] || 'elapsed'
      @interval = conf['interval'].to_i || 60
      unless @hook = conf['hook']
        raise Fluent::ConfigError, '<elapsed></elpased> directive does not specify `hook` option. Specify as `on_message`'
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
      old_method_name = "#{method_name}_without_elapsed".to_sym 
      klass.__send__(:alias_method, old_method_name, method_name)
      elapsed = self
      klass.__send__(:define_method, method_name) do |*args|
        elapsed.measure_time(hook) do
          self.__send__(old_method_name, *args)
        end
      end
    end

    def measure_time(hook)
      started = Time.now
      yield
      elapsed = (Time.now - started).to_f
      log.info "in_forward: elapsed time at #{hook} is #{elapsed} sec"
      @mutex.synchronize { self.add(elapsed) }
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
      unless times.empty?
        num = times.size
        max = num == 0 ? 0 : times.max
        avg = num == 0 ? 0 : times.map(&:to_f).inject(:+) / num.to_f
        Engine.emit(@tag, now, {:num => num, :max => max, :avg => avg})
      end
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
