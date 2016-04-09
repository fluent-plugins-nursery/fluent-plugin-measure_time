require 'fluent/plugin/measure_timable'

module Fluent
  class MeasureTimeOutput < Output
    Plugin.register_output('measure_time', self)

    unless method_defined?(:router)
      define_method(:router) { ::Fluent::Engine }
    end

    def configure(conf)
      ::Fluent::Input.__send__(:include, MeasureTimable)
      ::Fluent::Output.__send__(:include, MeasureTimable)
    end

    def emit(tag, time, msg)
    end
  end
end
