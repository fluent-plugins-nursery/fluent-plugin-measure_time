# encoding: UTF-8
require_relative 'spec_helper'

describe 'Fluent::Mixin::ElapsedTime' do
  before { Fluent::Test.setup }

  def create_driver(conf=CONFIG)
    Fluent::Test::InputTestDriver.new(Fluent::ForwardInput).configure(conf)
  end

  def connect
    TCPSocket.new('127.0.0.1', PORT)
  end

  def send_data(data)
    io = connect
    begin
      io.write data
    ensure
      io.close
    end
  end

  def self.unused_port
    s = TCPServer.open(0)
    port = s.addr[1]
    s.close
    port
  end

  PORT = unused_port
  CONFIG = %[
    port #{PORT}
    bind 127.0.0.1
  ]

  let(:driver) { create_driver(config) }

  describe 'test configure' do
    let(:config) {CONFIG + %[
      <elapsed>
        tag test
        interval 10
        hook Fluent::ForwardInput::Handler.on_read
      </elapsed>
    ]}
    let(:subject) { driver.instance.instance_variable_get(:@elapsed) }
    its(:tag) { should == 'test' }
    its(:interval) { should == 10 }
    its(:hook) { should == 'Fluent::ForwardInput::Handler.on_read' }
  end

  describe 'test emit' do
    let(:config) {CONFIG + %[
      <elapsed>
        tag elapsed
        interval 1
        hook on_message
      </elapsed>
    ]}
    it 'should flush' do
      driver.instance.__send__(:on_message, ['tag1', 0, {'a'=>1}].to_msgpack)
      triple = driver.instance.instance_variable_get(:@elapsed).flush(0)
      triple[0].should == 'elapsed'
      triple[2].keys.should =~ [:num, :max, :avg]
    end
  end
end
