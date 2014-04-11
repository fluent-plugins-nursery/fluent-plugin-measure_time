# encoding: UTF-8
require_relative 'spec_helper'
require 'fluent/plugin/in_forward'
require 'fluent/plugin/out_stdout'

describe Fluent::MeasureTimeInput do
  before { Fluent::Test.setup }

  def create_driver(conf=%[])
    Fluent::Test::InputTestDriver.new(Fluent::MeasureTimeInput).configure(conf)
  end

  describe 'test configure' do
    it { expect { create_driver }.not_to raise_error }
  end
end

describe "extends Fluent::ForwardInput" do
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
      <measure>
        tag test
        interval 10
        hook on_message
      </measure>
    ]}
    let(:subject) { driver.instance.measure }
    its(:tag) { should == 'test' }
    its(:interval) { should == 10 }
    its(:hook) { should == 'on_message' }
  end

  describe 'test emit' do
    let(:config) {CONFIG + %[
      <measure>
        tag measure
        interval 1
        # hook Fluent::ForwardInput::Handler.on_read # not support inner class yet
        hook Fluent::ForwardInput.on_message
      </measure>
    ]}
    it 'should flush' do
      d = driver.instance
      d.__send__(:on_message, ['tag1', 0, {'a'=>1}].to_msgpack)
      triple = d.measure.flush(0)
      triple[0].should == 'measure'
      triple[2].keys.should =~ [:num, :max, :avg]
    end
  end
end

describe "extends Fluent::StdoutOutput" do
  before { Fluent::Test.setup }

  def create_driver(conf=CONFIG, tag = 'test')
    Fluent::Test::OutputTestDriver.new(Fluent::StdoutOutput, tag).configure(conf)
  end

  CONFIG = %[
  ]

  let(:driver) { create_driver(config) }

  describe 'test configure' do
    let(:config) {CONFIG + %[
      <measure>
        tag test
        interval 10
        hook emit
      </measure>
    ]}
    let(:subject) { driver.instance.instance_variable_get(:@measure) }
    its(:tag) { should == 'test' }
    its(:interval) { should == 10 }
    its(:hook) { should == 'emit' }
  end

  describe 'test emit' do
    let(:config) {CONFIG + %[
      <measure>
        tag measure
        interval 1
        hook emit
      </measure>
    ]}
    it 'should flush' do
      d = driver.instance
      d.emit('tag1', Fluent::OneEventStream.new(0, {'a'=>1}), Fluent::NullOutputChain.instance)
      triple = d.measure.flush(0)
      triple[0].should == 'measure'
      triple[2].keys.should =~ [:num, :max, :avg]
    end
  end
end

