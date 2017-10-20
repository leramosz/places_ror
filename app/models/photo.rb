require 'exifr/jpeg'

class Photo
  include ActiveModel::Model

  attr_accessor :id, :location
  attr_reader :place
  attr_writer :contents, :place

  # initialize from both a Mongo and Web hash
  def initialize(params = nil)
    if !params.nil?
      if params[:_id]  #hash came from GridFS
        @id = params[:_id].to_s
        @location = params[:metadata].nil? ? nil : Point.new(params[:metadata][:location])
        @place = params[:metadata][:place] if  !params[:metadata][:place].nil?
      else              #assume hash came from Rails
        @id = params[:id]
        @location = Point.new(params[:location]) if !params[:location].nil?
        @place = params[:place] if  !params[:place].nil?
      end
      @chunkSize = params[:chunkSize] if !params[:chunkSize].nil?
      @uploadDate = params[:uploadDate] if !params[:uploadDate].nil?
      @contentType = params[:contentType] if !params[:contentType].nil?
      @filename = params[:filename] if !params[:filename].nil?
      @length = params[:length] if !params[:length].nil?
      @md5 = params[:md5] if !params[:md5].nil?
      @contents = params[:contents] if !params[:contents].nil?
    end
  end

  def place=(value)
    case 
      when value.is_a?(Place)
        @place = BSON::ObjectId.from_string(value.id)
      when value.is_a?(String)
        @place = BSON::ObjectId.from_string(value)
      when value.is_a?(BSON::ObjectId)
        @place = value
    end
  end

  def place
    @place.nil? ? nil : Place.find(@place)
  end

  # tell Rails whether this instance is persisted
  def persisted?
    !@id.nil?
  end
  def created_at
    nil
  end
  def updated_at
    nil
  end

  # convenience method for access to client in console
  def self.mongo_client
   @@db ||= Mongoid::Clients.default
  end

  def self.id_criteria(id)
    {_id:BSON::ObjectId.from_string(id)}
  end
  
  def id_criteria
    self.class.id_criteria @id
  end

  def save
    description = {}
    description[:content_type] = "image/jpeg"
    description[:metadata] = {}
    description[:metadata][:place] = @place
    if !persisted?
      gps = EXIFR::JPEG.new(@contents).gps
      @contents.rewind
      @location = Point.new({:lat => gps.latitude, :lng => gps.longitude })
      description[:metadata][:location] = @location.to_hash
      grid_file = Mongo::Grid::File.new(@contents.read, description)
      id = self.class.mongo_client.database.fs.insert_one(grid_file)
      @id = id.to_s
    else
      description[:metadata][:location] = @location.to_hash
      self.class.mongo_client.database.fs.find(id_criteria)
              .update_one('$set' => description)
    end
    @id
  end

  def self.all(offset = 0, limit = nil)
    view = mongo_client.database.fs.find.skip(offset)
    view = view.limit(limit) if !limit.nil?
    view.each.map{ |doc| Photo.new(doc) }
  end

  def self.find(id)
    raw_result = mongo_client.database.fs.find(id_criteria(id)).first
    raw_result.nil? ? nil : Photo.new(raw_result)
  end

  # RETURNING VALUE HAS TO BE AN BSON OBJECT
  def find_nearest_place_id(max_meters)
    nearest = Place.near(location, max_meters).first
    nearest.nil? ? 0 : nearest[:_id]
  end

  def self.find_photos_for_place(place_id)
    Photo.mongo_client.database.fs.find("metadata.place"=>BSON::ObjectId.from_string(place_id))
    #Photo.mongo_client.database.fs.find("metadata.place"=>place_id.to_s)
  end

  def contents
    f=self.class.mongo_client.database.fs.find_one(id_criteria)
    if f 
      buffer = ""
      f.chunks.reduce([]) do |x,chunk| 
          buffer << chunk.data.data 
      end
      return buffer
    end 
  end

  def destroy
    self.class.mongo_client.database.fs.find(id_criteria).delete_one
  end

end
