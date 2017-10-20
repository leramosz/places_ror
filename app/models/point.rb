class Point
  include ActiveModel::Model

  attr_accessor :type, :longitude, :latitude

  # initialize from both a Mongo and Web hash
  def initialize(hash)
    @longitude = hash[:lng] if hash.key?(:lng)
    @latitude = hash[:lat] if hash.key?(:lat)
    if hash.key?(:type)
      @type = hash[:type] 
      @longitude = hash[:coordinates][0]
      @latitude = hash[:coordinates][1]
    end
  end

  def to_hash
    hash = {}
    hash[:type] = "Point" 
    hash[:coordinates] = []
    hash[:coordinates][0] = @longitude
    hash[:coordinates][1] = @latitude
    return hash
  end

end
