#
# Fluent
#
# Copyright (C) 2011 FURUHASHI Sadayuki
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
module Fluent


  class ForwardInput < Input
    Plugin.register_input('forward', self)

    def initialize
      super
      require 'fluent/plugin/socket_util'
    end

    config_param :port, :integer, :default => DEFAULT_LISTEN_PORT
    config_param :bind, :string, :default => '0.0.0.0'
    config_param :backlog, :integer, :default => nil
    # SO_LINGER 0 to send RST rather than FIN to avoid lots of connections sitting in TIME_WAIT at src
    config_param :linger_timeout, :integer, :default => 0
    attr_reader :elapsed # for test

    def configure(conf)
      super

      if element = conf.elements.first { |element| element.name == 'elapsed' }
        tag = element["tag"] || 'elapsed'
        interval = element["interval"].to_i || 60
        hook = element['hook'] || 'on_message'
        @elapsed = ElapsedMeasure.new(log, tag, interval, hook)
      end
    end

    def start
      @loop = Coolio::Loop.new

      @lsock = listen
      @loop.attach(@lsock)

      @usock = SocketUtil.create_udp_socket(@bind)
      @usock.bind(@bind, @port)
      @usock.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
      @hbr = HeartbeatRequestHandler.new(@usock, method(:on_heartbeat_request))
      @loop.attach(@hbr)

      @thread = Thread.new(&method(:run))
      @elapsed.start if @elapsed
      @cached_unpacker = $use_msgpack_5 ? nil : MessagePack::Unpacker.new
    end

    def shutdown
      @loop.watchers.each {|w| w.detach }
      @loop.stop
      @usock.close
      listen_address = (@bind == '0.0.0.0' ? '127.0.0.1' : @bind)
      # This line is for connecting listen socket to stop the event loop.
      # We should use more better approach, e.g. using pipe, fixing cool.io with timeout, etc.
      TCPSocket.open(listen_address, @port) {|sock| } # FIXME @thread.join blocks without this line
      @thread.join
      @lsock.close
      @elapsed.stop if @elapsed
    end

    class ElapsedMeasure
      attr_reader :tag, :interval, :hook, :times, :sizes, :mutex, :thread, :log
      def initialize(log, tag, interval, hook)
        @log = log
        @tag = tag
        @interval = interval
        @hook = hook.split(',')
        @times = []
        @sizes = []
        @mutex = Mutex.new
      end

      def add(time, size)
        @times << time
        @sizes << size
      end

      def clear
        @times.clear
        @sizes.clear
      end

      def hookable?(caller)
        @hook.include?(caller.to_s)
      end

      def measure_time(caller, size)
        if hookable?(caller)
          started = Time.now
          yield
          elapsed = (Time.now - started).to_f
          log.debug "in_forward: elapsed time at #{caller} is #{elapsed} sec for #{size} bytes"
          @mutex.synchronize { self.add(elapsed, size) }
        else
          yield
        end
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
        times, sizes = [], []
        @mutex.synchronize do
          times = @times.dup
          sizes = @sizes.dup
          self.clear
        end
        if !times.empty? and !sizes.empty?
          num = times.size
          max = num == 0 ? 0 : times.max
          avg = num == 0 ? 0 : times.map(&:to_f).inject(:+) / num.to_f
          size_max = num == 0 ? 0 : sizes.max
          size_avg = num == 0 ? 0 : sizes.map(&:to_f).inject(:+) / num.to_f
          Engine.emit(@tag, now, {:num => num, :max => max, :avg => avg, :size_max => size_max, :size_avg => size_avg})
        end
      end
    end

    def listen
      log.info "listening fluent socket on #{@bind}:#{@port}"
      s = Coolio::TCPServer.new(@bind, @port, Handler, @linger_timeout, log, method(:on_message), @elapsed)
      s.listen(@backlog) unless @backlog.nil?
      s
    end

    #config_param :path, :string, :default => DEFAULT_SOCKET_PATH
    #def listen
    #  if File.exist?(@path)
    #    File.unlink(@path)
    #  end
    #  FileUtils.mkdir_p File.dirname(@path)
    #  log.debug "listening fluent socket on #{@path}"
    #  Coolio::UNIXServer.new(@path, Handler, method(:on_message))
    #end

    def run
      @loop.run
    rescue => e
      log.error "unexpected error", :error => e, :error_class => e.class
      log.error_backtrace
    end

    protected
    # message Entry {
    #   1: long time
    #   2: object record
    # }
    #
    # message Forward {
    #   1: string tag
    #   2: list<Entry> entries
    # }
    #
    # message PackedForward {
    #   1: string tag
    #   2: raw entries  # msgpack stream of Entry
    # }
    #
    # message Message {
    #   1: string tag
    #   2: long? time
    #   3: object record
    # }
    def on_message(msg)
      if msg.nil?
        # for future TCP heartbeat_request
        return
      end

      # TODO format error
      tag = msg[0].to_s
      entries = msg[1]

      if entries.class == String
        # PackedForward
        bytesize = tag.bytesize + entries.bytesize
        measure_time(:on_message, bytesize) do
          es = MessagePackEventStream.new(entries, @cached_unpacker)
          Engine.emit_stream(tag, es)
        end

      elsif entries.class == Array
        # Forward
        es = MultiEventStream.new
        entries.each {|e|
          record = e[1]
          next if record.nil?
          time = e[0].to_i
          time = (now ||= Engine.now) if time == 0
          es.add(time, record)
        }
        measure_time(:on_message, 0) do
          Engine.emit_stream(tag, es)
        end

      else
        # Message
        record = msg[2]
        return if record.nil?
        time = msg[1]
        time = Engine.now if time == 0
        bytesize = time.size + record.to_s.bytesize
        measure_time(:on_message, bytesize) do
          Engine.emit(tag, time, record)
        end
      end
    end

    def measure_time(caller, size)
      @elapsed ? @elapsed.measure_time(caller, size) { yield } : yield
    end

    class Handler < Coolio::Socket
      def initialize(io, linger_timeout, log, on_message, elapsed)
        super(io)
        if io.is_a?(TCPSocket)
          opt = [1, linger_timeout].pack('I!I!')  # { int l_onoff; int l_linger; }
          io.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, opt)
        end
        @on_message = on_message
        @log = log
        @log.trace {
          remote_port, remote_addr = *Socket.unpack_sockaddr_in(@_io.getpeername) rescue nil
          "accepted fluent socket from '#{remote_addr}:#{remote_port}': object_id=#{self.object_id}"
        }
        @elapsed = elapsed
      end

      def on_connect
      end

      def on_read(data)
        first = data[0]
        if first == '{' || first == '['
          m = method(:on_read_json)
          @y = Yajl::Parser.new
          @y.on_parse_complete = @on_message
        else
          m = method(:on_read_msgpack)
          @u = MessagePack::Unpacker.new
        end

        (class << self; self; end).module_eval do
          define_method(:on_read, m)
        end
        m.call(data)
      end

      def measure_time(caller, size)
        @elapsed ? @elapsed.measure_time(caller, size) { yield } : yield
      end

      def on_read_json(data)
        measure_time(:on_read, data.bytesize) do
          @y << data
        end
      rescue => e
        @log.error "forward error", :error => e, :error_class => e.class
        @log.error_backtrace
        close
      end

      def on_read_msgpack(data)
        measure_time(:on_read, data.bytesize) do
          @u.feed_each(data, &@on_message)
        end
      rescue => e
        @log.error "forward error", :error => e, :error_class => e.class
        @log.error_backtrace
        close
      end

      def on_close
        @log.trace { "closed fluent socket object_id=#{self.object_id}" }
      end
    end

    class HeartbeatRequestHandler < Coolio::IO
      def initialize(io, callback)
        super(io)
        @io = io
        @callback = callback
      end

      def on_readable
        begin
          msg, addr = @io.recvfrom(1024)
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::EINTR
          return
        end
        host = addr[3]
        port = addr[1]
        @callback.call(host, port, msg)
      rescue
        # TODO log?
      end
    end

    def on_heartbeat_request(host, port, msg)
      #log.trace "heartbeat request from #{host}:#{port}"
      begin
        @usock.send "\0", 0, host, port
      rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::EINTR
      end
    end
  end
end
