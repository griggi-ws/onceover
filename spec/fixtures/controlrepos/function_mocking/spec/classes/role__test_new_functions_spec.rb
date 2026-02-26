# frozen_string_literal: true

# Custom spec that uses Onceover::RSpec::Helper
# This tests the helper's shared context in a real rspec-puppet scenario

require 'spec_helper'

describe 'role::test_new_functions' do
  # Iterate over factsets, including the onceover shared context for each:
  # - facts, trusted_facts from the factset
  # - function mocking from onceover.yaml
  # - cross-platform workarounds
  Onceover::RSpec::Helper.factsets.each do |factset|
    context "on #{factset[:name]}" do
      include_context 'onceover', factset

      it { is_expected.to compile.with_all_deps }
    end
  end
end
