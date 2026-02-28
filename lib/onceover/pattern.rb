# frozen_string_literal: true

class Onceover
  # Shared module for regex pattern handling in Class and Node.
  # Provides methods to detect and convert `/pattern/` strings to Regexp objects.
  module Pattern
    def self.regexp?(string)
      string.is_a?(String) && string.start_with?('/') && string.end_with?('/')
    end

    def self.to_regexp(string)
      raise ArgumentError, "#{string} is not a valid pattern" unless regexp?(string)

      Regexp.new(string[1..-2])
    end
  end
end
