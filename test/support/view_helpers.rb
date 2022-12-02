# frozen_string_literal: true

module ViewHelpers
  def capture(&block)
    block.call
  end
end
