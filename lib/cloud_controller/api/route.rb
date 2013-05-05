# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController
  rest_controller :Route do
    permissions_required do
      full Permissions::CFAdmin
      full Permissions::OrgManager
      read Permissions::Auditor
      full Permissions::SpaceManager
      full Permissions::SpaceDeveloper
      read Permissions::SpaceAuditor
    end

    define_attributes do
      attribute :host, String, :default => ""
      to_one    :domain
      to_one    :space
      to_many   :apps
    end

    query_parameters :host, :domain_guid

    def self.translate_validation_exception(e, attributes)
      domain_errors = e.record.errors[:domain_id]
      if domain_errors && domain_errors.include?(:taken)
        Errors::RouteHostTaken.new(attributes["host"])
      else
        Errors::RouteInvalid.new(e.record.errors.full_messages)
      end
    end
  end
end
