require 'activemodel'

class YamlModel
  include ActiveModel::Validations

  attr_accessor :id

  def self.model_name
    return @mn if @mn
    @mn = "Person"
    def @mn.singular; "person"; end
    def @mn.plural; "people"; end
    def @mn.member; "person"; end
    def @mn.collection; "people"; end
    def @mn.partial_path; "people/person"; end
    @mn
  end

  def self.inherited(c)
    def c.filename
      @filename ||= RAILS_ROOT + "/db/" + name.underscore.pluralize + ".yml"
    end
  end

  def to_param
    id.to_s
  end

  def filename
    self.class.filename
  end

  def self.new(attributes = {})
    s = super()
    attributes.each do |attr, val|
      s.send("#{attr}=", val)
    end
    s
  end

  def self.create(attributes = {})
    record = new(attributes)
    record.save
    record
  end

  def update_attributes(attributes = {})
    attributes.each do |attr, val|
      self.send("#{attr}=", val)
    end
    save
  end

  def self.read_records
    FileUtils.touch(filename) unless test(?f, filename)
    records = YAML.load(File.read(filename)) || {}
    records.each do |id,r|
      r.errors.instance_variable_set("@base", r)
    end
    records
  end

  def self.find(id)
    read_records[id.to_i]
  end

  def initialize
    @new_record = true
  end

  def to_model
    self
  end

  def new_record?
    !!@new_record
  end

  def save
    return false unless valid?
    records = self.class.read_records
    next_id = records.keys.max.to_i + 1
    self.id ||= next_id
    records[self.id] = self
    File.open(filename, "w") do |fh|
      begin
        @new_record = false
        fh.print(records.to_yaml)
      rescue
        @new_record = true
        fh.close
      end
    end
    true
  end
end
