# fluent-plugin-measure_time

[![Build Status](https://secure.travis-ci.org/sonots/fluent-plugin-measure_time.png?branch=master)](http://travis-ci.org/sonots/fluent-plugin-measure_time)
[![Code Climate](https://codeclimate.com/github/sonots/fluent-plugin-measure_time.png)](https://codeclimate.com/github/sonots/fluent-plugin-measure_time)

Fluentd plugin to measure elapsed time to process messages

## Installation

Use RubyGems:

    gem install fluent-plugin-measure_time

## Configuration

This plugin is doing something tricky, which extends arbitrary plugins so that it can use `<measure_time></measure_time>` directive to measure elapsed times. 

Example:

```apache
<source>
  type measure_time
  # This makes available the `masure_time` directive for all plugins
</source>

<source>
  type forward
  port 24224
  <measure_time>
    tag measure_time
    interval 60
    hook on_message
  </measure_time>
</source>

<match measure_time>
  type stdout
</match>
```

This example hooks the [on_message](https://github.com/fluent/fluentd/blob/e5a9a4ca03d18b45fdb89061d8251592a044e9fc/lib/fluent/plugin/in_forward.rb#L112) method of in_forward plugin, and measures how long it takes for processing.

And, this plugin emits the statistics of measured elapsed times in each specified interval like below:

```
elapsed: {"max":1.011,"avg":0.002","num":10}
```

where `max` and `avg` are the maximum and average elapsed times, and `num` is the number of being called in each interval.

## Parameters

* interval

    The time interval to emit measurement results. Default is `60`. 

* tag

    The output tag name. Default is `measure_time`

* hook (required)

    Specify the method to measure time.
    
## ChangeLog

See [CHANGELOG.md](CHANGELOG.md) for details.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new [Pull Request](../../pull/new/master)

## Copyright

Copyright (c) 2014 Naotoshi Seo. See [LICENSE](LICENSE) for details.
