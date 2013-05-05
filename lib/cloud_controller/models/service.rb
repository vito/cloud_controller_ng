# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::Models
  class Service < ActiveRecord::Base
    include CF::ModelGuid
    include CF::ModelRelationships

    has_many :service_plans, :dependent => :destroy

    validates :label, :provider, :url, :description, :version,
              :presence => true

    validates :label, :uniqueness => {
      :scope => :provider,
      :case_sensitive => false
    }

    validate :has_fallback_unique_id

    validates :url, :format => URI.regexp(%w(http https)), :allow_nil => true
    validates :info_url, :format => URI.regexp(%w(http https)),
              :allow_nil => true

    export_attributes :label, :provider, :url, :description,
                      :version, :info_url, :active, :unique_id, :extra

    import_attributes :label, :provider, :url, :description,
                      :version, :info_url, :active, :unique_id, :extra

    strip_attributes  :label, :provider

    def service_auth_token
      ServiceAuthToken.where(:label => label, :provider => provider).first
    end

    private

    def has_fallback_unique_id
      self.unique_id ||= "#{provider}_#{label}"
    end
  end
end
