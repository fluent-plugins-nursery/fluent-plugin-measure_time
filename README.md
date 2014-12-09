# fluent-plugin-measure_time

[![Build Status](https://secure.travis-ci.org/sonots/fluent-plugin-measure_time.png?branch=master)](http://travis-ci.org/sonots/fluent-plugin-measure_time)
[![Code Climate](https://codeclimate.com/github/sonots/fluent-plugin-measure_time.png)](https://codeclimate.com/github/sonots/fluent-plugin-measure_time)

Fluentd plugin to measure elapsed time to process messages


## Installation

Use RubyGems:

    gem install fluent-plugin-measure_time

## Parameters

* tag

    The output tag name. Default is `measure_time`

* hook (required)

    Specify the method to measure time.

* interval

    The time interval to emit measurement results. Default is nil which do not compute statistics and emit the time in each measurement.

## Configuration Example 1 - Profile an Output Plugin

As an example, let's profile how long the [emit](https://github.com/sonots/fluent-plugin-grep/blob/master/lib/fluent/plugin/out_grep.rb#L56) method of [fluent-plugin-grep](https://github.com/sonots/fluent-plugin-grep) is taking.
Configure fluentd.conf as below:

```apache
<source>
  type measure_time
  # This makes available the `measure_time` directive for all plugins
</source>

<source>
  type forward
  port 24224
</source>

# measure_time plugin output comes here
<match measure_time>
  type stdout
</match>

# Whatever you want to do
<match greped.**>
  type stdout
</match>

<match **>
  type grep
  add_tag_prefix greped
  <measure_time>
    tag measure_time
    hook emit
  </measure_time>
</source>
```

The output of fluent-plugin-measure_time will be as below:

```
measure_time: {"time":0.000849735,"class":"Fluent::GrepOutput","hook":"emit","object_id":83935080}
```

where `time` denotes the measured elapsed time, and `class`, `hook`, and `object_id` denotes the hooked class, the hooked method, and the object id of the plugin instance.

### interval option

fluent-plugin-measure_time outputs the elapsed time for each calling, but you can use the `interval` option when you want to get statistics in each interval.

```
measure_time: {"max":1.011,"avg":0.002","num":10,"class":"Fluent::GrepOutput","hook":"emit","object_id":83935080}
```

where `max` and `avg` are the maximum and average elapsed times, and `num` is the number of being called in each interval.

## Configuration Example (2) - Profile the in_forward plugin

I introduce an interesting example here.

Following illustration draws the sequence of that `in_forward` plugin receives a data, processes, and passes the data to output plugins.

*Sequence Diagram*

```
     +–––––––––––––+    +––––––––––––––+   +––––––––––––––+
     |  in_forwrd  |    |   Output     |   |   Output     |
     +––––––+––––––+    +––––––+–––––––+   +––––––+–––––––+
#on_message | start = Time.now |                  |
            +––––––––––––––––––>                  |
            |      #emit       |                  |
            |                  +––––––––––––––––––>
            |                  |      #emit       |
            |                  |                  |
            |                  |                  |
            |                  <– – – – – – – – – +
            | elapsed = Time.now - start          |
            <– – – – – - – – – +                  |
            |                  |                  |
            +                  +                  +
```

As the illustration, by hooking `on_message` method of `in_forward` plugin,
we can measure the blocking time taking to process the received data,
which also means that the time taking until `in_forward` will be ready for receiving a next data.

This profiling is very useful to investigate when you have a suspicion that throughputs of Fluentd fell down extremely.

The configuration will be as follows:

```apache
<source>
  type measure_time
  # This makes available the `measure_time` directive for all plugins
</source>

<source>
  type forward
  port 24224
  <measure_time>
    tag measure_time
    hook on_message
  </measure_time>
</source>

<match measure_time>
  type stdout
</match>

# whatever you want
<match **>
  type stdout
</match>
```

Output becomes as below:

```
measure_time: {"time":0.000849735,"class":"Fluent::ForwardInput","hook":"on_message","object_id":83935080}
```

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
