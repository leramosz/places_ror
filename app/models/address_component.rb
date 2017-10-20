class AddressComponent
  include ActiveModel::Model

  attr_reader :long_name, :short_name, :types

  # initialize from both a Mongo and Web hash
  def initialize(hash)
    @long_name = hash[:long_name]
    @short_name = hash[:short_name]
    @types = hash[:types]
  end

end
