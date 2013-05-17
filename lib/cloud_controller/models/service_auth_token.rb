# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::Models
  class ServiceAuthToken < ActiveRecord::Base
    include CF::ModelGuid
    include CF::ModelRelationships

    validates :label, :provider, :token, :presence => true

    validates :label, :uniqueness => {
      :scope => :provider,
      :case_sensitive => false
    }

    export_attributes :label, :provider
    import_attributes :label, :provider, :token

    strip_attributes  :label, :provider

    def token_matches?(unencrypted_token)
      token == unencrypted_token
    end

    def token=(value)
      generate_salt
      super(VCAP::CloudController::Encryptor.encrypt(value, salt))
    end

    def token
      return unless super
      VCAP::CloudController::Encryptor.decrypt(super, salt)
    end

    def generate_salt
      self.salt ||= VCAP::CloudController::Encryptor.generate_salt
    end
  end
end
