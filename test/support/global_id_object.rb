# frozen_string_literal: true

class GlobalIDObject
  include GlobalID::Identification

  attr_reader :id

  def initialize(id: 42)
    @id = id
  end

  def to_global_id
    raise "to_global_id" if id == 666
    super
  end

  def inspect
    "#<GlobalIDObject:0xXXXXXX @id=#{id}>"
  end
end
