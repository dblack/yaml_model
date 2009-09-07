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
      @filename ||= File.join(
        RAILS_ROOT, "tmp", name.underscore.pluralize + ".yml"
      )
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

  def self.all_records
    load_records unless @records
    @records
  end

  def self.load_records
    FileUtils.touch(filename) unless test(?f, filename)
    @records = YAML.load(File.read(filename)) || {}
    @records.each do |id,r|
      r.errors.instance_variable_set("@base", r)
    end
    @records
  end

  def self.find(*ids)
    ids.flatten!
    if ids.size == 1
      all_records[ids[0].to_i]
    else
      all_records.values_at(*ids.map(&:to_i))
    end
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

  def update_attributes(attributes = {})
    attributes.each do |attr, val|
      self.send("#{attr}=", val)
    end
    save
  end

  def self.dump_records
    File.open(filename, "w") do |fh|
      fh.print(all_records.to_yaml)
    end
  end
 
  def save
    return false unless valid?
    records = self.class.all_records
    self.id ||= records.keys.max.to_i + 1
    records[self.id.to_i] = self
    old_new_record = @new_record
    @new_record = false
    begin
      self.class.dump_records
    rescue
      @new_record = old_new_record
      false
    else
      true
    end
  end

  def self.delete(id)
    @records.delete(id.to_i)
    dump_records
  end
end
