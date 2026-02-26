# frozen_string_literal: true

require 'onceover/controlrepo'
require 'onceover/testconfig'

class Onceover
  module RSpec
    # Helper module for user-defined spec tests that want to leverage
    # Onceover's factsets, function mocking, pre_conditions, and workarounds.
    # This allows custom spec tests to have the same context as
    # Onceover's auto-generated tests without duplicating configuration.
    module Helper
      class << self
        def config
          @config ||= begin
            repo = controlrepo
            Onceover::TestConfig.new(repo.onceover_yaml, repo.opts)
          end
        end

        def controlrepo
          @controlrepo ||= Onceover::Controlrepo.new
        end

        # Returns all factsets configured in onceover.yaml as an array of hashes.
        def factsets(filter: nil)
          # Ensure nodes are initialized
          config

          Onceover::Node.all.map do |node|
            factset = {
              name: node.name,
              facts: node.fact_set,
              trusted_facts: node.trusted_set || {},
              trusted_external_data: node.trusted_external_set || {},
              certname: node.trusted_set&.dig('certname')
            }

            # Apply filter if provided
            if filter
              matches = filter.all? do |key, value|
                deep_match?(factset[:facts], key, value)
              end
              next nil unless matches
            end

            factset
          end.compact
        end

        # Iterates over the test matrix from onceover.yaml, yielding context for each test.
        # This mirrors what Onceover does when generating tests.
        def spec_tests
          repo = controlrepo
          testconfig = Onceover::TestConfig.new(repo.onceover_yaml, repo.opts)
          testconfig.spec_tests.each { |tst| testconfig.verify_spec_test(repo, tst) }
          tests = testconfig.run_filters(Onceover::Test.deduplicate(testconfig.spec_tests))

          tests.each do |tst|
            tst.classes.each do |cls|
              tst.nodes.each do |node|
                yield({
                  class_name: cls.name,
                  node_name: node.name,
                  name: node.name, # Alias for consistency with factsets method
                  facts: node.fact_set,
                  trusted_facts: node.trusted_set || {},
                  trusted_external_data: node.trusted_external_set || {},
                  pre_condition: testconfig.pre_condition,
                  certname: node.trusted_set&.dig('certname'),
                  tags: tst.tags
                })
              end
            end
          end
        end

        # Returns the mock functions configuration from onceover.yaml.
        def mock_functions
          config.mock_functions
        end

        # Returns the before conditions from onceover.yaml.
        def before_conditions
          config.before_conditions || []
        end

        # Returns the after conditions from onceover.yaml.
        def after_conditions
          config.after_conditions || []
        end

        # Returns the pre_condition Puppet code (from spec/pre_conditions/*.pp).
        def pre_condition
          config.pre_condition
        end

        # Generates the Puppet code for mocking functions, suitable for use in pre_condition.
        def mock_functions_puppet_code(class_name: nil, node_name: nil)
          code_lines = []

          # Add onceover variables (always set for pre_condition compatibility)
          code_lines << "$onceover_class = '#{class_name}'"
          code_lines << "$onceover_node = '#{node_name}'"
          code_lines << ""

          # Add user pre_conditions
          if pre_condition
            code_lines << "# Begin user-specified pre_condition"
            code_lines << pre_condition.chomp
            code_lines << "# End user-specified pre_condition"
            code_lines << ""
          end

          # Add mocked functions
          if mock_functions
            require 'multi_json'
            code_lines << "# Mocking functions"
            mock_functions.each do |function, params|
              json = if params['returns'].is_a?(String)
                       params['returns'].dump[1..-2].to_json
                     else
                       params['returns'].to_json
                     end
              code_lines << "function #{function} (*$args) { from_json('#{json}') }"
            end
          end

          code_lines.join("\n")
        end

        # Registers the from_json Puppet function needed for function mocking.
        def register_from_json_function!
          return if @from_json_registered

          Puppet::Parser::Functions.newfunction(:from_json, type: :rvalue) do |args|
            require 'multi_json'
            MultiJson.load(args[0])
          end
          @from_json_registered = true
        end

        private

        def deep_match?(hash, key, value)
          return false unless hash.is_a?(Hash)

          if hash.key?(key)
            if value.is_a?(Hash)
              value.all? { |k, v| deep_match?(hash[key], k, v) }
            else
              hash[key] == value
            end
          else
            false
          end
        end
      end

      # Register the shared context when this module is included or when
      # explicitly requested. Only registers if RSpec is available.
      def self.included(_base)
        register_shared_context!
      end

      # Explicitly register the shared context.
      def self.register_shared_context!
        return if @shared_context_registered
        return unless defined?(::RSpec)

        ::RSpec.shared_context 'onceover' do |context = {}|
          let(:facts) { context[:facts] || {} }

          let(:trusted_facts) { context[:trusted_facts] || {} }

          let(:trusted_external_data) { context[:trusted_external_data] || {} }

          let(:node) { context[:certname] } if context[:certname]

          let(:pre_condition) do
            # Auto-detect class_name from describe block if not provided
            # (top_level_description is used by RSpec anyhow)
            Onceover::RSpec::Helper.mock_functions_puppet_code(
              class_name: context[:class_name] || self.class.top_level_description,
              node_name: context[:node_name] || context[:name]
            )
          end

          before(:each) do
            Onceover::RSpec::Helper.register_from_json_function! if Onceover::RSpec::Helper.mock_functions

            # Use eval with binding so conditions can access node_facts and trusted_facts
            Onceover::RSpec::Helper.before_conditions.each do |condition|
              node_facts = context[:facts] || {} # rubocop:disable Lint/UselessAssignment
              trusted_facts = context[:trusted_facts] || {} # rubocop:disable Lint/UselessAssignment
              eval(condition, binding) # rubocop:disable Security/Eval
            end
          end

          after(:each) do
            Onceover::RSpec::Helper.after_conditions.each do |condition|
              node_facts = context[:facts] || {} # rubocop:disable Lint/UselessAssignment
              trusted_facts = context[:trusted_facts] || {} # rubocop:disable Lint/UselessAssignment
              eval(condition, binding) # rubocop:disable Security/Eval
            end
          end

          # Apply cross-platform workarounds (same as generated tests)
          before(:each) do
            next if Onceover::RSpec::Helper.config.opts[:no_workarounds]

            # Curtrently there is some code within Puppet that will try to execute
            # commands when compiling a catalog even though it shouldn't. One example is
            # the groups attribute of the user resource on AIX. If we are running on
            # Windows but pretending to be UNIX this will definitely fail so we need to
            # mock it (or vice versa)
            # Details:
            # https://github.com/puppetlabs/puppet/blob/master/lib/puppet/util/execution.rb#L191
            expected_null_file = Puppet::Util::Platform.windows? ? 'NUL' : '/dev/null'
            unless File.exist?(expected_null_file)
              allow(Puppet::Util::Execution).to receive(:execute)
                .and_raise(Puppet::ExecutionFailure.new("Onceover cross-platform workaround"))
            end

            # The windows ACL module causes issues when compiled on other platforms
            # These are detailed in the following ticket:
            #   https://github.com/rodjek/rspec-puppet/issues/665
            #
            # The below should work around this common issue
            if Puppet::Type.type(:acl)
              allow_any_instance_of(Puppet::Type.type(:acl).provider(:windows)).to receive(:validate)
              allow_any_instance_of(Puppet::Type.type(:acl).provider(:windows))
                .to receive(:respond_to?).with(:get_account_name).and_return(false)
              allow_any_instance_of(Puppet::Type.type(:acl).provider(:windows))
                .to receive(:respond_to?).with(:get_group_name).and_return(false)
              allow_any_instance_of(Puppet::Type.type(:acl).provider(:windows))
                .to receive(:respond_to?).with(:validate).and_return(true)
            end

            # The windows_adsi provider also has an issue where the contructor takes
            # a different number of arguments depending on whether the ADSI
            # underlying connectivity exists. This causes the following error:
            #
            #      wrong number of arguments (given 1, expected 0)
            #
            # This fixes that if we aren't using Windows.
            # The stub module/class definitions are created at load time in
            # spec_helper.rb.erb. Here we apply the mocks to those stub classes.
            begin
              require 'puppet/util/windows'
              require 'puppet/util/windows/adsi'
              Puppet::Util::Windows::ADSI.computer_name
            rescue LoadError, StandardError
              # Mock commonly used Windows methods on the stub classes.
              # These stubs are defined in spec_helper.rb.erb at load time.
              if defined?(Puppet::Util::Windows::SID)
                allow(Puppet::Util::Windows::SID).to receive(:name_to_sid).and_return('S-1-5-32-544')
                allow(Puppet::Util::Windows::SID).to receive(:name_to_principal).and_return(nil)
              end

              if defined?(Puppet::Util::Windows::ADSI::User)
                allow_any_instance_of(Puppet::Util::Windows::ADSI::User).to receive(:initialize)
                allow_any_instance_of(Puppet::Util::Windows::ADSI::User).to receive(:groups).and_return([])
                allow_any_instance_of(Puppet::Util::Windows::ADSI::User).to receive(:name_sid_hash).and_return({})
              end

              if defined?(Puppet::Util::Windows::ADSI::Group)
                allow_any_instance_of(Puppet::Util::Windows::ADSI::Group).to receive(:members).and_return([])
                allow_any_instance_of(Puppet::Util::Windows::ADSI::Group).to receive(:members_sids).and_return([])
                allow(Puppet::Util::Windows::ADSI::Group).to receive(:name_sid_hash).and_return({})
              end
            end
          end
        end

        @shared_context_registered = true
      end

      register_shared_context! if defined?(::RSpec)
    end
  end
end
