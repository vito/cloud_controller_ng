# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::ModelNormalization
  module InstanceMethods
    def strip_if_needed
      attrs = self.class.strip_attrs
      return unless attrs

      attrs.each do |attr|
        val = read_attribute(attr)
        next unless val.respond_to?(:strip)

        write_attribute(attr, val.strip)
      end
    end
  end

  module ClassMethods
    # Specify the attributes to perform whitespace normaliation on
    #
    # @param [Array<Symbol>] List of attributes to include when performing
    # whitespace normalization.
    def strip_attributes(*attributes)
      self.strip_attrs = attributes
      before_validation :strip_if_needed
    end

    attr_accessor :strip_attrs
  end

  ActiveRecord::Base.class_eval do
    extend(ClassMethods)
    include(InstanceMethods)
  end
end
