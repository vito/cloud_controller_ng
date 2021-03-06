# Copyright (c) 2009-2012 VMware, Inc.

require "yajl"

module VCAP::ModelSerialization
  # This plugin implements serialization and deserialization of
  # Sequel::Models to/from hashes and json.

  module InstanceMethods
    # Return a hash of the model instance containing only the parameters
    # specified by export_attributes.
    #
    # @option opts [Array<String>] :only Only export an attribute if it is both
    # included in export_attributes and in the :only option.
    #
    # @return [Hash] The hash representation of the instance only containing
    # the attributes specified by export_attributes and the optional :only
    # parameter.
    def to_hash(opts = {})
      hash = {}
      attrs = self.class.export_attrs || []

      attrs.each do |k|
        next unless opts[:only].nil? || opts[:only].include?(k)

        hash[k] = send(k)
      end

      normalize_attributes(hash)
    end

    # Return a json serialization of the model instance containing only
    # the parameters specified by export_attributes.
    #
    # @option opts [Array<String>] :only Only export an attribute if it is both
    # included in export_attributes and in the :only option.
    #
    # @return [String] The json serialization of the instance only containing
    # the attributes specified by export_attributes and the optional :only
    # parameter.
    def to_json(opts = {})
      Yajl::Encoder.encode(to_hash(opts))
    end

    # Update the model instance from the supplied json string.  Only update
    # attributes specified by import_attributes.
    #
    # @param [String] Json encoded representation of the updated attributes.
    #
    # @option opts [Array<String>] :only Only import an attribute if it is both
    # included in import_attributes and in the :only option.
    def update_from_json(json, opts = {})
      parsed = Yajl::Parser.new.parse(json)
      update_from_hash(parsed, opts)
    end

    # Update the model instance from the supplied hash.  Only update
    # attributes specified by import_attributes.
    #
    # @param [Hash] Hash of the updated attributes.
    #
    # @option opts [Array<String>] :only Only import an attribute if it is both
    # included in import_attributes and in the :only option.
    def update_from_hash(hash, opts = {})
      update_opts = self.class.update_or_create_options(hash, opts)

      self.attributes = update_opts

      save!
    end

    private

    def normalize_attributes(value)
      case value
      when Hash
        stringified = {}

        value.each do |k, v|
          stringified[k.to_s] = normalize_attributes(v)
        end

        stringified
      when Array
        value.collect { |x| normalize_attributes(x) }
      when Numeric, nil, true, false
        value
      when Time
        value.to_s(
          VCAP::CloudController::RestController::ObjectSerialization.timestamp_format)
      else
        value.to_s
      end
    end
  end

  module ClassMethods
    # Return a json serialization of data set containing only
    # the parameters specified by export_attributes.
    #
    # @option opts [Array<String>] :only Only export an attribute if it is both
    # included in export_attributes and in the :only option.
    #
    # @return [String] The json serialization of the data set only containing
    # the attributes specified by export_attributes and the optional :only
    # parameter.  The resulting data set is sorted by :id unless an order
    # is set via default_order_by.
    def to_json(opts = {})
      # TODO: pagination
      order_attr = @default_order_by || :id
      elements = all(:order => "#{order_attr} ASC").map { |e| e.to_hash(opts) }
      Yajl::Encoder.encode(elements)
    end

    # Create a new model instance from the supplied json string.  Only include
    # attributes specified by import_attributes.
    #
    # @param [String] Json encoded representation attributes.
    #
    # @option opts [Array<String>] :only Only include an attribute if it is
    # both included in import_attributes and in the :only option.
    #
    # @return [Sequel::Model] The created model.
    def create_from_json(json, opts = {})
      hash = Yajl::Parser.new.parse(json)
      create_from_hash(hash, opts)
    end

    # Create and save a new model instance from the supplied json string.
    # Only include attributes specified by import_attributes.
    #
    # @param [Hash] Hash of the attributes.
    #
    # @option opts [Array<String>] :only Only include an attribute if it is
    # both included in import_attributes and in the :only option.
    #
    # @return [Sequel::Model] The created model.
    def create_from_hash(hash, opts = {})
      create_opts = update_or_create_options(hash, opts)
      new(create_opts).tap(&:save!)
    end

    # Instantiates, but does not save, a new model instance from the
    # supplied json string.  Only include # attributes specified by
    # import_attributes.
    #
    # @param [Hash] Hash of the attributes.
    #
    # @option opts [Array<String>] :only Only include an attribute if it is
    # both included in import_attributes and in the :only option.
    #
    # @return [Sequel::Model] The created model.
    def new_from_hash(hash, opts = {})
      create_opts = update_or_create_options(hash, opts)
      new(create_opts)
    end

    # Set the default order during a to_json on the model class.
    #
    # @param [Symbol] Name of the attribute to order by.
    def default_order_by(attribute)
      @default_order_by = attribute
    end

    # Set the default order during a to_json on the model class.
    #
    # @param [Array<Symbol>] List of attributes to include when serializing to
    # json or a hash.
    def export_attributes(*attributes)
      self.export_attrs = attributes
    end

    # @param [Array<Symbol>] List of attributes to include when importing
    # from json or a hash.
    def import_attributes(*attributes)
      self.import_attrs = attributes
    end

    # Not intended to be called by consumers of the API, but needed
    # by instance of the class, so it can't be made private.
    def update_or_create_options(hash, opts)
      results = {}

      attrs = self.import_attrs || []
      attrs -= opts[:only] if opts[:only]

      attrs.each do |attr|
        key = nil
        if hash.has_key?(attr)
          key = attr
        elsif hash.has_key?(attr.to_s)
          key = attr.to_s
        end

        results[attr] = hash[key] if key
      end

      results
    end

    attr_accessor :export_attrs, :import_attrs
  end

  ActiveRecord::Base.class_eval do
    extend(ClassMethods)
    include(InstanceMethods)
  end
end

