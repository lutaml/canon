# frozen_string_literal: true

require "spec_helper"
require "canon/config/config_dsl"

RSpec.describe Canon::Config::ConfigDSL do
  # Minimal stub class that records calls to the underlying resolver
  # so the specs can verify wiring without depending on OverrideResolver
  # semantics.  This is a plain Ruby object (no double) per project rule.
  let(:resolver_class) do
    Struct.new(:store, :lookups) do
      def initialize
        self.store = {}
        self.lookups = {}
      end

      def resolve(name)
        lookups[name] = true
        store[name]
      end

      def set_programmatic(name, value)
        store[name] = value
      end
    end
  end

  def define_class(&block)
    klass = Class.new do
      extend Canon::Config::ConfigDSL

      attr_reader :resolver

      def initialize(resolver)
        @resolver = resolver
      end

      def self.name
        "TestConfig"
      end
    end
    klass.class_eval(&block)
    klass
  end

  describe "#config_key" do
    it "registers the attribute in config_keys" do
      klass = define_class do
        config_key :volume, type: :integer, default: 7
      end

      expect(klass.config_keys[:volume]).to include(
        type: :integer,
        default: 7,
        enum: nil,
      )
    end

    it "generates a getter that reads through the resolver" do
      klass = define_class do
        config_key :volume, type: :integer, default: 7
      end
      resolver = resolver_class.new
      resolver.store[:volume] = 11
      instance = klass.new(resolver)

      expect(instance.volume).to eq(11)
      expect(resolver.lookups[:volume]).to be(true)
    end

    it "generates a setter that writes through the resolver" do
      klass = define_class do
        config_key :volume, type: :integer, default: 7
      end
      resolver = resolver_class.new
      instance = klass.new(resolver)

      instance.volume = 5

      expect(resolver.store[:volume]).to eq(5)
    end

    it "applies the coerce proc on write before storing" do
      klass = define_class do
        config_key :volume, type: :integer,
                            default: 0,
                            coerce: ->(v) { Integer(v) }
      end
      resolver = resolver_class.new
      instance = klass.new(resolver)

      instance.volume = "9"

      expect(resolver.store[:volume]).to eq(9)
    end

    it "applies the getter_coerce proc on read" do
      klass = define_class do
        config_key :volume, type: :integer, default: 0,
                            getter_coerce: ->(v) { v ? v * 2 : 0 }
      end
      resolver = resolver_class.new
      resolver.store[:volume] = 4
      instance = klass.new(resolver)

      expect(instance.volume).to eq(8)
    end
  end

  describe ".validate_config_value!" do
    it "passes when the value is in the enum" do
      klass = define_class do
        config_key :mode, type: :symbol,
                          enum: %i[on off standby],
                          default: :on
      end

      expect { klass.validate_config_value!(:mode, :off) }.not_to raise_error
    end

    it "raises ArgumentError when the value is not in the enum" do
      klass = define_class do
        config_key :mode, type: :symbol,
                          enum: %i[on off standby],
                          default: :on
      end

      expect { klass.validate_config_value!(:mode, :broken) }
        .to raise_error(ArgumentError, /Invalid value :broken/)
    end

    it "is invoked by the generated setter" do
      klass = define_class do
        config_key :mode, type: :symbol,
                          enum: %i[on off],
                          default: :on
      end
      resolver = resolver_class.new
      instance = klass.new(resolver)

      expect { instance.mode = :broken }.to raise_error(ArgumentError)
    end

    it "skips validation when the attribute has no enum" do
      klass = define_class do
        config_key :volume, type: :integer, default: 0
      end

      expect { klass.validate_config_value!(:volume, 999) }.not_to raise_error
    end
  end

  describe ".resolve_default" do
    it "returns the stored default value" do
      klass = define_class do
        config_key :volume, type: :integer, default: 7
      end

      expect(klass.resolve_default(:volume)).to eq(7)
    end

    it "returns nil for an unknown key" do
      klass = define_class do
        config_key :volume, type: :integer, default: 7
      end

      expect(klass.resolve_default(:missing)).to be_nil
    end

    it "invokes a proc default each time it is called" do
      counter = [0]
      klass = define_class do
        config_key :next_id, type: :integer,
                             default: -> { counter[0] += 1 }
      end

      first = klass.resolve_default(:next_id)
      second = klass.resolve_default(:next_id)

      expect(first).to eq(1)
      expect(second).to eq(2)
    end
  end

  describe ".enum_values" do
    it "returns a hash mapping each enummed key to its enum array" do
      klass = define_class do
        config_key :on, type: :symbol, enum: %i[a b], default: :a
        config_key :plain, type: :integer, default: 0
        config_key :off, type: :symbol, enum: %i[x y], default: :x
      end

      expect(klass.enum_values).to eq(on: %i[a b], off: %i[x y])
    end

    it "returns an empty hash when no keys have enums" do
      klass = define_class do
        config_key :plain, type: :integer, default: 0
      end

      expect(klass.enum_values).to eq({})
    end
  end

  describe "per-class isolation" do
    it "does not share config_keys between classes" do
      first = define_class do
        config_key :alpha, type: :integer, default: 1
      end
      second = define_class do
        config_key :beta, type: :integer, default: 2
      end

      expect(first.config_keys).to include(:alpha)
      expect(first.config_keys).not_to include(:beta)
      expect(second.config_keys).to include(:beta)
      expect(second.config_keys).not_to include(:alpha)
    end
  end

  describe "integration with DiffConfig (smoke check)" do
    it "DiffConfig declares mode with the expected enum" do
      expect(Canon::Config::DiffConfig.config_keys[:mode])
        .to include(type: :symbol, enum: %i[by_line by_object pretty_diff])
    end

    it "DiffConfig exposes VALID_ENUM_VALUES derived from the registry" do
      expect(Canon::Config::DiffConfig::VALID_ENUM_VALUES[:mode])
        .to eq(%i[by_line by_object pretty_diff])
    end

    it "DiffConfig resolves use_color lazily through ColorDetector" do
      # The default is a proc; resolve_default must invoke it.
      stubbed = Canon::Config::DiffConfig.resolve_default(:use_color)
      expect(stubbed).to eq(Canon::ColorDetector.supports_color?)
    end
  end
end
