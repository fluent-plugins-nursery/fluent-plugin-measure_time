require 'fluent/plugin/measure_timable'

module Fluent
  class MeasureTimeInput < Input
    Plugin.register_input('measure_time', self)

    unless method_defined?(:router)
      define_method(:router) { ::Fluent::Engine }
    end

    def configure(conf)
      if Fluent::VERSION !~ /^0\.10/
        raise ConfigError, "fluent-plugin-measure_time: Use <label @measure_time><match></match></label> instead of <source></source> for v0.12 or above"
      end
      ::Fluent::Input.__send__(:include, MeasureTimable)
      ::Fluent::Output.__send__(:include, MeasureTimable)
    end
  end
end
