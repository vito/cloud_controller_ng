# Copyright (c) 2009-2012 VMware, Inc.

require "securerandom"

module CF::ModelGuid
  module ClassMethods
    attr_accessor :no_auto_guid_flag

    def no_auto_guid
      self.no_auto_guid_flag = true
    end

    def has_many(name, *args)
      singular = name.to_s.singularize

      define_method(:"add_#{singular}_by_guid") do |guid|
        objs = send(name)
        x = reflections[name].klass.find_by_guid(guid)
        objs << x unless objs.include?(x)
        x
      end

      define_method(:"remove_#{singular}_by_guid") do |guid|
        x = reflections[name].klass.find_by_guid(guid)
        send(name).delete(x)
      end

      super
    end

    def has_and_belongs_to_many(name, *args)
      singular = name.to_s.singularize

      define_method(:"add_#{singular}_by_guid") do |guid|
        objs = send(name)
        x = reflections[name].klass.find_by_guid(guid)
        objs << x unless objs.include?(x)
        x
      end

      define_method(:"remove_#{singular}_by_guid") do |guid|
        x = reflections[name].klass.find_by_guid(guid)
        send(name).delete(x)
      end

      super
    end
  end

  def self.included(base)
    base.extend(ClassMethods)

    base.class_eval do
      before_create :generate_guid

      private

      def generate_guid
        unless self.class.no_auto_guid_flag
          self.guid = SecureRandom.uuid
        end
      end
    end
  end
end
