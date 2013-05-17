# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::Models
  class ServicePlan < ActiveRecord::Base
    include CF::ModelGuid
    include CF::ModelRelationships

    belongs_to :service
    has_many :service_instances, :dependent => :destroy

    validates :name, :description, :service, :presence => true

    validates :free, :inclusion => { :in => [true, false ] }

    validates :name, :uniqueness => {
      :scope => :service_id,
      :case_sensitive => false
    }

    validate :has_fallback_unique_id

    export_attributes :name, :free, :description, :service_guid, :extra, :unique_id

    import_attributes :name, :free, :description, :service_guid, :extra, :unique_id, :public

    strip_attributes  :name

    def self.configure(trial_db_config)
      @trial_db_guid = trial_db_config ? trial_db_config[:guid] : nil
    end

    def self.trial_db_guid
      @trial_db_guid
    end

    def self.user_visibility_filter(user, set = self)
      if user.can_access_non_public_plans?
        set.scoped
      else
        set.where(:public => true)
      end
    end

    def trial_db?
      unique_id == self.class.trial_db_guid
    end

    private

    def has_fallback_unique_id
      self.unique_id ||= [service.unique_id, name].join("_") if service
    end
  end
end
