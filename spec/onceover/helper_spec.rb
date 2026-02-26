require 'spec_helper'
require 'onceover/rspec/helper'

describe "Onceover::RSpec::Helper" do
  before(:each) do
    # Reset memoized state between tests
    Onceover::RSpec::Helper.instance_variable_set(:@config, nil)
    Onceover::RSpec::Helper.instance_variable_set(:@controlrepo, nil)
    Onceover::Node.instance_variable_set(:@all, nil)
    Onceover::Class.instance_variable_set(:@all, nil)
    Onceover::Group.instance_variable_set(:@all, nil)
  end

  context "with function_mocking controlrepo" do
    before do
      @repo = Onceover::Controlrepo.new(path: 'spec/fixtures/controlrepos/function_mocking')
      allow(Onceover::RSpec::Helper).to receive(:controlrepo).and_return(@repo)
    end

    describe ".config" do
      it "returns an Onceover::TestConfig instance" do
        expect(Onceover::RSpec::Helper.config).to be_a(Onceover::TestConfig)
      end
    end

    describe ".factsets" do
      it "returns an array of factset hashes" do
        factsets = Onceover::RSpec::Helper.factsets
        expect(factsets).to be_an(Array)
        expect(factsets.first).to have_key(:name)
        expect(factsets.first).to have_key(:facts)
        expect(factsets.first).to have_key(:trusted_facts)
        expect(factsets.first).to have_key(:trusted_external_data)
      end

      it "includes CentOS-7.0-64 factset" do
        factsets = Onceover::RSpec::Helper.factsets
        names = factsets.map { |f| f[:name] }
        expect(names).to include('CentOS-7.0-64')
      end
    end

    describe ".mock_functions" do
      it "returns the mock functions hash from onceover.yaml" do
        mock_funcs = Onceover::RSpec::Helper.mock_functions
        expect(mock_funcs).to be_a(Hash)
        expect(mock_funcs).to have_key('return_string')
        expect(mock_funcs['return_string']['returns']).to eq('string')
      end

      it "includes functions with various return types" do
        mock_funcs = Onceover::RSpec::Helper.mock_functions
        expect(mock_funcs['return_number']['returns']).to eq(400)
        expect(mock_funcs['return_boolean']['returns']).to eq(true)
        expect(mock_funcs['return_array']['returns']).to eq([1, 2, 3])
        expect(mock_funcs['return_hash']['returns']).to eq({ 'foo' => 'bar' })
      end
    end

    describe ".mock_functions_puppet_code" do
      it "generates Puppet code with onceover variables" do
        code = Onceover::RSpec::Helper.mock_functions_puppet_code(
          class_name: 'role::test',
          node_name: 'CentOS-7.0-64'
        )
        expect(code).to include("$onceover_class = 'role::test'")
        expect(code).to include("$onceover_node = 'CentOS-7.0-64'")
      end

      it "generates function definitions for each mock" do
        code = Onceover::RSpec::Helper.mock_functions_puppet_code
        expect(code).to include('function return_string')
        expect(code).to include('function return_number')
        expect(code).to include('from_json')
      end
    end

    describe ".spec_tests" do
      it "yields context hashes for each class/node combination" do
        contexts = []
        Onceover::RSpec::Helper.spec_tests { |ctx| contexts << ctx }
        expect(contexts).not_to be_empty
        expect(contexts.first).to have_key(:class_name)
        expect(contexts.first).to have_key(:node_name)
        expect(contexts.first).to have_key(:facts)
      end
    end
  end

  context "with caching controlrepo (no functions configured)" do
    before do
      @repo = Onceover::Controlrepo.new(path: 'spec/fixtures/controlrepos/caching')
      allow(Onceover::RSpec::Helper).to receive(:controlrepo).and_return(@repo)
    end

    describe ".mock_functions" do
      it "returns nil when no functions are configured" do
        expect(Onceover::RSpec::Helper.mock_functions).to be_nil
      end
    end

    describe ".before_conditions" do
      it "returns an empty array when no before conditions are configured" do
        expect(Onceover::RSpec::Helper.before_conditions).to eq([])
      end
    end

    describe ".after_conditions" do
      it "returns an empty array when no after conditions are configured" do
        expect(Onceover::RSpec::Helper.after_conditions).to eq([])
      end
    end
  end

  describe ".deep_match?" do
    let(:helper) { Onceover::RSpec::Helper }

    it "matches simple key-value pairs" do
      hash = { 'os' => { 'family' => 'RedHat' } }
      expect(helper.send(:deep_match?, hash, 'os', { 'family' => 'RedHat' })).to be true
    end

    it "does not match when values differ" do
      hash = { 'os' => { 'family' => 'RedHat' } }
      expect(helper.send(:deep_match?, hash, 'os', { 'family' => 'Debian' })).to be false
    end

    it "returns false for non-existent keys" do
      hash = { 'os' => { 'family' => 'RedHat' } }
      expect(helper.send(:deep_match?, hash, 'nonexistent', 'value')).to be false
    end
  end
end
