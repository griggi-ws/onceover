require 'onceover/controlrepo'
require 'onceover/pattern'

class Onceover
  class Node
    @@all = []

    attr_accessor :name
    attr_accessor :beaker_node
    attr_accessor :fact_set
    attr_accessor :trusted_set
    attr_accessor :trusted_external_set

    def initialize(name)
      # If the node name is a regex, create node objects for everything that matches
      if Onceover::Pattern.regexp?(name)
        expression = Onceover::Pattern.to_regexp(name)
        matched_nodes = Onceover::Controlrepo.facts_files
                                             .map { |f| File.basename(f, '.json') }
                                             .keep_if { |n| n =~ expression }
        matched_nodes.each { |n| Onceover::Node.new(n) }
      else
        @name = name
        @beaker_node = nil

        # If we can't find the factset it will fail, so just catch that error and ignore it
        begin
          facts_file_index = Onceover::Controlrepo.facts_files.index do |facts_file|
            File.basename(facts_file, '.json') == name
          end
          @fact_set = Onceover::Node.clean_facts(Onceover::Controlrepo.facts[facts_file_index])

          # First see if we can find a 'trusted' hash at the top level of our factset
          @trusted_set = Onceover::Controlrepo.trusted_facts[facts_file_index]
          # If we don't find it, attempt to find a 'trusted' hash nested in our fact_set
          @trusted_set = @fact_set.dig('trusted') if @trusted_set.nil?
          # If we still can't find any, return an empty hash so the following doesn't blow up user written tests:
          #   let(:trusted_facts) { trusted_facts }
          @trusted_set = {} if @trusted_set.nil?

          # Merge trusted extensions to root level to support the format output by a compiler without modification
          @trusted_set = @trusted_set['extensions'].merge(@trusted_set) if @trusted_set && @trusted_set['extensions'].is_a?(Hash)

          # First see if we can find a 'trusted_external' hash at the top level of our factset
          @trusted_external_set = Onceover::Controlrepo.trusted_external_facts[facts_file_index]
          # If we don't find it, attempt to find a 'trusted.external' hash nested in our fact_set
          @trusted_external_set = @fact_set.dig('trusted', 'external') if @trusted_external_set.nil?
          # If we still can't find any, return an empty hash so the following doesn't blow up user written tests:
          #   let(:trusted_external_data) { trusted_external_data }
          @trusted_external_set = {} if @trusted_external_set.nil?
        rescue TypeError
          @fact_set = {}
          @trusted_set = {}
          @trusted_external_set = {}
        end

        # Only add if not already present (prevents duplicates from multiple regex matches)
        @@all << self unless @@all.any? { |node| node.name == @name }
      end
    end

    def self.find(node_name)
      return @@all.select { |node| node.name =~ Onceover::Pattern.to_regexp(node_name) } if Onceover::Pattern.regexp?(node_name)
        
      
      @@all.each do |node|
        if node_name.is_a?(Onceover::Node)
          return node_name if node == node_name
        elsif node.name == node_name
          return node
        end
      end
      
      logger.warn "Node #{node_name} not found"
      nil
    end

    def self.all
      @@all
    end

    # This method ensures that all facts are valid and clean anoything that we can't handle
    def self.clean_facts(factset)
      factset.delete('environment')
      factset
    end
  end
end
