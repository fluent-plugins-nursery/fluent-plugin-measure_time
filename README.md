# fluent-mixin-elapsed_time

[![Build Status](https://secure.travis-ci.org/sonots/fluent-mixin-elapsed_time.png?branch=master)](http://travis-ci.org/sonots/fluent-mixin-elapsed_time)

Fluentd mixin to measure elapsed time to process messages

## Installation

Use RubyGems:

    gem install fluent-mixin-elapsed_time

Run Fluentd with -r option to require this gem.

    fluentd -c fluent.conf -r 'fluent/mixin/elapsed_time'

## Configuration

This mixin module extends arbitrary input plugins so that it can use `<elapsed></elapsed>` directive to measure elapsed times. 

Example:

```apache
<source>
  type forward
  port 24224
  <elapsed>
    tag elapsed
    interval 60
    hook on_message
  </elapsed>
</source>

<match elapsed>
  type stdout
</match>
```

This example hooks the `#on_message` method of in_forward plugin for measuring elapsed times which the method takes.

This plugin outputs the statistics of elapsed times in each interval like below:

```
elapsed: {"max":1.011,"avg":0.002","num":10}
```

where `max` and `avg` are the maximum and average elapsed times, and `num` is the number of being called. 

## Illustration

Following figure draws the conceptual mechanism of how this module measures elapsed times.

```
     +–––––––––––––+    +––––––––––––––+   +––––––––––––––+   +–––––––––––––––+
     |   Engine    |    |  Input       |   |   Output     |   |   Output      |
     +––––––+––––––+    +––––––+–––––––+   +––––––+–––––––+   +–––––––+–––––––+
            |                  |                  |                   |
            +––––––––––––––––––>                  |                   |
            |  hooked method   | start = Time.now |                   |
            |                  +––––––––––––––––––>                   |
            |                  |      #emit       +–––––––––––––––––––>        
            |                  |                  |     #emit         |        
            |                  |                  <– – – – –  – – – – +        
            |                  <– – – – – – – – – +                   |
            |                  | elapsed = Time.now - start           |
            <– – – – – - – – – +                  |                   |
            |                  |                  |                   |
            +                  +                  +                   +
```

## Parameters

* interval

    The time interval to emit measurement results. Default is `60`. 

* tag

    The output tag name. Default is `elapsed`

* hook (required)

    Specify the method to hook. You can also explicitly explicitly specify the class name like `Fluent::ForwardOutput#on_message`
    
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
