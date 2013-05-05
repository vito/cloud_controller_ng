# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::Models
  class QuotaDefinition < ActiveRecord::Base
    include CF::ModelGuid
    include CF::ModelRelationships

    has_many :organizations, :dependent => :destroy

    validates :name, :total_services, :memory_limit, :presence => true

    validates :non_basic_services_allowed,
              :inclusion => { :in => [true, false] }

    validates :name, :uniqueness => true

    export_attributes :name, :non_basic_services_allowed, :total_services,
                      :memory_limit, :trial_db_allowed
    import_attributes :name, :non_basic_services_allowed, :total_services,
                      :memory_limit, :trial_db_allowed

    def self.populate_from_config(config)
      config[:quota_definitions].each do |k, v|
        name = k.to_s

        if qd = find_by_name(name)
          qd.update_from_hash(v)
        else
          create(v.merge(:name => name))
        end
      end
    end

    def self.configure(config)
      @default_quota_name = config[:default_quota_definition]
    end

    def self.default
      @default ||= QuotaDefinition.find_by_name(@default_quota_name)
    end
  end
end
