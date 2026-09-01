# frozen_string_literal: true

# Stands in for a view context in the unit tests, so the placeholder swapping
# can be exercised without booting a Rails app.
module ViewHelpers
  def capture(&block)
    block.call
  end
end
