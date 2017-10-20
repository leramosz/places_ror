class Place
  include ActiveModel::Model

  attr_accessor :id, :formatted_address, :location, :address_components

  # initialize from both a Mongo and Web hash
  def initialize(hash)
    @id = hash[:_id].to_s if !hash[:_id].nil?
    @formatted_address = hash[:formatted_address] if !hash[:formatted_address].nil?
    if !hash[:address_components].nil?
      @address_components = []
      hash[:address_components].each do |item|
        @address_components << AddressComponent.new(item)
      end
    end
    @location = hash[:geometry][:location].nil? ? 
                    Point.new(hash[:geometry][:geolocation]) : Point.new(hash[:geometry][:location])
  end

  def persisted?
    !@id.nil?
  end

  # convenience method for access to client in console
  def self.mongo_client
   Mongoid::Clients.default
  end

  # convenience method for access to racers collection
  def self.collection
   self.mongo_client['places']
  end

  def self.to_places(view)
    places = []
    view.each do |v|
      places << self.new(v)
    end
    places
  end 

  def self.load_all(f)
    self.collection.delete_many
    content = File.read(f)
    hash = JSON.parse(content);
    self.collection.insert_many(hash);
  end

  def self.find(id)
    place = self.collection.find({_id: BSON::ObjectId.from_string(id.to_s)}).first
    place.nil? ? nil : self.new(place)
  end

  def self.find_by_short_name(short_name)
    self.collection.find({ 'address_components.short_name' => short_name })
  end

  def self.all(offset = 0, limit = nil)
    places = []
    view = self.collection.find({}).skip(offset)
    view = view.limit(limit) if !limit.nil?
    view.each do |item|
      places << self.new(item)
    end
    places
  end

  def self.get_address_components(sort = nil, offset = nil,  limit = nil)
    query = [
      {:$project=>{:_id=>1, :address_components=>1, :formatted_address=>1, 'geometry.geolocation'=>1}},
      {:$unwind=>'$address_components'}
    ]
    query << {:$sort=>sort} if !sort.nil?
    query << {:$skip=>offset} if !offset.nil?
    query << {:$limit=>limit} if !limit.nil?
    self.collection.find().aggregate(query)
  end

  def self.get_country_names
    self.collection.find().aggregate([
      {:$project=>{'address_components.long_name'=>1, 'address_components.types'=>1}},
      {:$unwind=>'$address_components'},
      {:$match=>{'address_components.types'=>'country'}},
      {:$group=>{:_id=>'$address_components.long_name'}}
    ]).to_a.map {|h| h[:_id]}
  end

  def self.find_ids_by_country_code(country_code)
    self.collection.find().aggregate([
      {:$match=>{'address_components.types'=>'country', 'address_components.short_name'=>country_code}},
      {:$project=>{:_id=>1}},
    ]).map {|doc| doc[:_id].to_s}
  end

  def destroy
    Place.collection.delete_one({_id: BSON::ObjectId.from_string(@id)})
  end

  def self.create_indexes
    self.collection.indexes.create_one('geometry.geolocation'=>Mongo::Index::GEO2DSPHERE)
  end

  def self.remove_indexes
    self.collection.indexes.drop_one('geometry.geolocation_2dsphere')
  end

  def self.near(p, max_meters = nil)
    near = {:$geometry=>{:type=>p.type, :coordinates=>[p.longitude, p.latitude]}}
    near[:$maxDistance] = max_meters if !max_meters.nil?
    self.collection.find(
      'geometry.geolocation'=>{
        :$near=>near
      }
    )
  end

  def near(max_meters = nil)
    near = {:$geometry=>{:type=>@location.type, :coordinates=>[@location.longitude, @location.latitude]}}
    near[:$maxDistance] = max_meters if !max_meters.nil?
    Place.to_places(Place.collection.find(
      'geometry.geolocation'=>{
        :$near=>near
      }
    ))
  end

  def photos(offset = 0, limit = nil)
    view = Photo.mongo_client.database.fs.find("metadata.place"=>BSON::ObjectId.from_string(@id)).skip(offset)
    view = view.limit(limit) if !limit.nil?
    view.to_a.map {|p| Photo.new(p)}
  end

end
