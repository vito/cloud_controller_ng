# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController
  rest_controller :ServiceAuthToken do
    permissions_required do
      full Permissions::CFAdmin
    end

    define_attributes do
      attribute :label,    String
      attribute :provider, String
      attribute :token,    String,  :exclude_in => :response
    end

    def self.translate_validation_exception(e, attributes)
      provider_errors = e.record.errors[:provider]
      if provider_errors && provider_errors.include?(:taken)
        Errors::ServiceAuthTokenLabelTaken.new("#{attributes["label"]}-#{attributes["provider"]}")
      else
        Errors::ServiceAuthTokenInvalid.new(e.record.errors.full_messages)
      end
    end
  end
end
