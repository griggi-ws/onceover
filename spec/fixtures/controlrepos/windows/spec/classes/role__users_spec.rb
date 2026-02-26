# frozen_string_literal: true

# Custom spec that uses Onceover::RSpec::Helper shared context
# This tests the helper's integration with onceover-generated spec_helper

require 'spec_helper'

describe 'role::users' do
  Onceover::RSpec::Helper.factsets.each do |factset|
    context "on #{factset[:name]}" do
      include_context 'onceover', factset

      it { is_expected.to compile.with_all_deps }
    end
  end
end
