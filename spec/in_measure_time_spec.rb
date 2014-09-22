# encoding: UTF-8
require_relative 'spec_helper'
require 'fluent/plugin/in_forward'
require 'fluent/plugin/out_stdout'

describe Fluent::MeasureTimeInput do
  before { Fluent::Test.setup }

  def create_driver(conf=%[])
    d = Fluent::Test::InputTestDriver.new(Fluent::MeasureTimeInput).configure(conf)
    unless d.respond_to?(:router)
      d.singleton_class.send(:define_method, :router) { ::Fluent::Engine }
    end
  end

  describe 'test configure' do
    it { expect { create_driver }.not_to raise_error }
  end
end

describe "extends Fluent::ForwardInput" do
  before { Fluent::Test.setup }

  def create_driver(conf=CONFIG)
    Fluent::MeasureTimeInput.new.configure("")
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
      <measure_time>
        tag test
        interval 10
        hook on_message
      </measure_time>
    ]}
    let(:subject) { driver.instance.measure_time }
    its(:tag) { should == 'test' }
    its(:interval) { should == 10 }
    its(:hook) { should == 'on_message' }
  end

  describe 'test emit' do
    let(:config) {CONFIG + %[
      <measure_time>
        tag measure_time
        interval 1
        hook on_message
      </measure_time>
    ]}
    it 'should flush' do
      d = driver.instance
      data = ['tag1', 0, {'a'=>1}].to_msgpack
      d.__send__(:on_message, data, data.bytesize, "hi, yay!")
      triple = d.measure_time.flush(0)
      expect(triple[0]).to eql('measure_time')
      expect(triple[2].keys).to eql([:max, :avg, :num, :class, :hook, :object_id])
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
      <measure_time>
        tag test
        interval 10
        hook emit
      </measure_time>
    ]}
    let(:subject) { driver.instance.measure_time }
    its(:tag) { should == 'test' }
    its(:interval) { should == 10 }
    its(:hook) { should == 'emit' }
  end

  describe 'test emit' do
    let(:config) {CONFIG + %[
      <measure_time>
        tag measure_time
        hook emit
      </measure_time>
    ]}
    it 'should flush' do
      time = Fluent::Engine.now
      allow(Fluent::Engine).to receive(:now) { time }
      d = driver.instance
      expect(d.router).to receive(:emit) # .with("measure_time", time, {})
      d.emit('tag1', Fluent::OneEventStream.new(0, {'a'=>1}), Fluent::NullOutputChain.instance)
    end
  end

  describe 'test interval' do
    let(:config) {CONFIG + %[
      <measure_time>
        tag measure_time
        interval 1
        hook emit
      </measure_time>
    ]}
    it 'should flush' do
      d = driver.instance
      d.emit('tag1', Fluent::OneEventStream.new(0, {'a'=>1}), Fluent::NullOutputChain.instance)
      triple = d.measure_time.flush(0)
      expect(triple[0]).to eql('measure_time')
      expect(triple[2].keys).to eql([:max, :avg, :num, :class, :hook, :object_id])
    end
  end
end

