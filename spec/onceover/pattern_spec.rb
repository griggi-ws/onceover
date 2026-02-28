require 'spec_helper'
require 'onceover/pattern'
require 'onceover/node'
require 'onceover/class'

describe 'Onceover::Pattern' do
  describe '.regexp?' do
    it 'returns true for strings wrapped in slashes' do
      expect(Onceover::Pattern.regexp?('/CentOS/')).to be true
    end

    it 'returns false for plain strings' do
      expect(Onceover::Pattern.regexp?('CentOS-7.0-64')).to be false
    end

    it 'returns false for strings starting but not ending with slash' do
      expect(Onceover::Pattern.regexp?('/CentOS')).to be false
    end

    it 'returns false for non-strings' do
      expect(Onceover::Pattern.regexp?(nil)).to be false
      expect(Onceover::Pattern.regexp?(123)).to be false
    end
  end

  describe '.to_regexp' do
    it 'converts a pattern string to a Regexp' do
      result = Onceover::Pattern.to_regexp('/CentOS/')
      expect(result).to be_a(Regexp)
      expect('CentOS-7.0-64').to match(result)
    end

    it 'raises for non-pattern strings' do
      expect { Onceover::Pattern.to_regexp('CentOS') }.to raise_error(ArgumentError)
    end
  end
end

describe 'Onceover::Node regex support' do
  before(:each) do
    # Reset the Node class variable between tests
    Onceover::Node.class_variable_set(:@@all, [])
  end

  context 'in puppet_controlrepo fixture' do
    before do
      @repo = Onceover::Controlrepo.new(
        path: 'spec/fixtures/controlrepos/puppet_controlrepo'
      )
      # Initialize nodes from the factsets
      Onceover::Controlrepo.facts_files.map { |f| File.basename(f, '.json') }.each do |name|
        Onceover::Node.new(name)
      end
    end

    describe '.find with regex' do
      it 'returns nodes matching the pattern' do
        results = Onceover::Node.find('/CentOS/')
        expect(results).to be_an(Array)
        expect(results.length).to be > 0
        results.each do |node|
          expect(node.name).to match(/CentOS/)
        end
      end

      it 'returns empty array when no nodes match' do
        results = Onceover::Node.find('/NonExistent/')
        expect(results).to eq([])
      end
    end

    describe '.find without regex' do
      it 'returns a single node for exact match' do
        result = Onceover::Node.find('CentOS-7.0-64')
        expect(result).to be_an(Onceover::Node)
        expect(result.name).to eq('CentOS-7.0-64')
      end
    end
  end
end

describe 'Onceover::Class regex support' do
  before(:each) do
    # Reset the Class class variable between tests
    Onceover::Class.class_variable_set(:@@all, [])
  end

  context 'in puppet_controlrepo fixture' do
    before do
      @repo = Onceover::Controlrepo.new(
        path: 'spec/fixtures/controlrepos/puppet_controlrepo'
      )
      # Initialize classes from the repo
      Onceover::Controlrepo.classes.each do |cls|
        Onceover::Class.new(cls)
      end
    end

    describe '.find with regex' do
      it 'returns classes matching the pattern' do
        results = Onceover::Class.find('/^role::/')
        expect(results).to be_an(Array)
        expect(results.length).to be > 0
        results.each do |cls|
          expect(cls.name).to match(/^role::/)
        end
      end
    end
  end
end
