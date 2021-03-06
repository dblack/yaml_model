#require 'ruby-debug'
# YamlModel -- an experimental object-YAML mapper for Rails (mainly)
#
# David A. Black
# September 2009
#
# I'm writing this mainly as a way to explore and learn about ActiveModel and
# other aspects of Rails 3. See the YamlModel class for main documentation. I'll
# also leave the old README lying around for now.

require 'active_model'

# YamlModel -- parent class for the "OYM" classes
#
# This class implements basic CRUD operations, using a YAML file for storage. It
# tries to imitate ActiveRecord, at least up to a point, for easy use in Rails
# projects. (Not that it's a production tool; it's more of a learning tool, for
# me.) 
#
# YamlModel includes ActiveModel::Validations, so you can do validations on your
# objects. Also, it implements a rudimentary before_save and after_save feature.
#
# Here's a sample subclass:
#
#  class Person < YamlModel
#    attr_accessor :name
#    validates_presence_of :name
#    before_save { self.name = self.name.upcase }     # or whatever
#    after_save  { "do some logging or whatever here" } 
#  end
#
# Given this class, you can do things like:
#
#   person = Person.new
#   person.save              => false (not valid)
#   person.name = "David"
#   person.save              => true
#   person.name              => DAVID
#
# The class can also do simple find operations:
#
#   Person.find(1)           => finds by id
#   Person.find([1,2,3])     => an array of records
#
# Error handling and reporting are pretty barebones at the moment. 
#

class YamlModel
  include ActiveModel::Validations

# YamlModel::Queue -- provides mechanism for creation of before_save-style
# queues of procs.
#
# This module is used to extend YamlModel, so YamlModel can quickly create hooks
# like this:
#
#   qcreate :before_save
#
# and then you can do
#
#   before_save { some_block_that_gets_instance_evaled_by_your_object }
#
# in your YamlModel subclasses. 
  module Queue
    def qcreate(action)
      sc = class << self; self; end
      qname = "#{action}_queue"
      ivar = "@#{qname}"

      sc.class_eval do
        define_method(qname) do
          instance_variable_get(ivar) || instance_variable_set(ivar, [])
        end
      end

      sc.class_eval <<-EOM
        def #{action}(&block)
          send("#{qname}") << block if block
        end
      EOM
    end
  end

  extend Queue

  attr_accessor :id

  qcreate :before_save
  qcreate :after_save

# On inheritance, create the canonical filename for this class's YAML records.
  def self.inherited(c)
    def c.filename
      @filename ||= File.join(
        RAILS_ROOT, "db", name.underscore.pluralize + ".yml"
      )
    end
  end

# new -- initialize new object with given attributes
  def self.new(attributes = {})
    super
  end

# create -- new + save
  def self.create(attributes = {})
    record = new(attributes)
    record.save
    record
  end

# delete -- delete a record from memory and persist the remaining records
  def self.delete(id)
    @records.delete(id.to_i)
    dump_records
  end

# find -- takes one or more id numbers
  def self.find(*ids)
    ids.flatten!
    if ids.size == 1
      all_records[ids[0].to_i]
    else
      all_records.values_at(*ids.map(&:to_i))
    end
  end

# all_records -- load from file if needed and return all records
  def self.all_records
    @records ||= load_records
  end

# load_records -- load all records from file
  def self.load_records
    FileUtils.touch(filename) unless test(?f, filename)
    records = YAML.load(File.read(filename)) || {}
    records.each do |id, record|
      record.instance_eval { @errors = ActiveModel::Errors.new(self) }
    end
    records
  end

# dump_records -- dump existing records to file
  def self.dump_records
    File.open(filename, "w") do |fh|
      fh.print(@records.to_yaml)
    end
  end

# next_id -- generate the next id number
  def self.next_id
    all_records.keys.max.to_i + 1
  end

# Initialize object (as you might have guessed)
  def initialize(attributes = {})
    attributes.each do |attr, val|
      send("#{attr}=", val)
    end
    @errors = ActiveModel::Errors.new(self)
    @new_record = true
  end

# For ActionPack's benefit
  def to_param
    id.to_s
  end

# From the ActiveModel API
  def to_model
    self
  end

# Instance-level access to the storage filename
  def filename
    self.class.filename
  end

# From the ActiveModel API
  def new_record?
    @new_record
  end

# Update attributes according to given hash and save the record
  def update_attributes(attributes = {})
    attributes.each do |attr, val|
      self.send("#{attr}=", val)
    end
    save
  end

# Save the record. A bit spaghetti-ish, but not disastrously so. 
  def save
    return false unless valid?

    records = self.class.all_records
    old_state = self.id, @new_record

    self.id ||= self.class.next_id
    records[self.id.to_i] = self

    @new_record = false

    self.class.before_save_queue.each do |block|
      instance_eval(&block)
    end

    begin
      self.class.dump_records
    rescue
      self.id, @new_record = old_state
      false
    else

    self.class.after_save_queue.each do |block|
      instance_eval(&block)
    end
      true
    end
  end
end
