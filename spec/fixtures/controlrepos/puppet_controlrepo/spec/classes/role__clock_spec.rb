# frozen_string_literal: true

# Custom spec that uses Onceover::RSpec::Helper shared context
# This tests the helper's integration with onceover-generated spec_helper

require 'spec_helper'

describe 'role::clock' do
  # Filter to only CentOS factsets (role::clock is in linux_classes, not windows_classes)
  Onceover::RSpec::Helper.factsets(filter: { 'os' => { 'family' => 'RedHat' } }).each do |factset|
    context "on #{factset[:name]}" do
      include_context 'onceover', factset

      it { is_expected.to compile.with_all_deps }
    end
  end
end
