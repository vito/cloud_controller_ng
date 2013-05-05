# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController
  rest_controller :Service do
    permissions_required do
      full Permissions::CFAdmin
      read Permissions::Authenticated
    end

    define_attributes do
      attribute :label,          String
      attribute :provider,       String
      attribute :url,            Message::URL
      attribute :description,    String
      attribute :version,        String
      attribute :info_url,       Message::URL, :default => nil
      attribute :acls,           {"users" => [String], "wildcards" => [String]}, :default => nil
      attribute :timeout,        Integer, :default => nil
      attribute :active,         Message::Boolean, :default => false
      attribute :extra,          String, :default => nil
      attribute :unique_id,      String, :default => nil, :exclude_in => [:update]
      to_many   :service_plans
    end

    query_parameters :active

    def self.translate_validation_exception(e, attributes)
      provider_errors = e.record.errors[:provider]
      if provider_errors && provider_errors.include?(:taken)
        Errors::ServiceLabelTaken.new("#{attributes["label"]}-#{attributes["provider"]}")
      else
        Errors::ServiceInvalid.new(e.record.errors.full_messages)
      end
    end
  end
end
