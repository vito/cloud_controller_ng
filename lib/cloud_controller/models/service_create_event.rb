# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::Models
  class ServiceCreateEvent < BillingEvent
    validates :space_guid, :presence => true
    validates :space_name, :presence => true
    validates :service_instance_guid, :presence => true
    validates :service_instance_name, :presence => true
    validates :service_guid, :presence => true
    validates :service_label, :presence => true
    validates :service_provider, :presence => true
    validates :service_version, :presence => true
    validates :service_plan_guid, :presence => true
    validates :service_plan_name, :presence => true

    export_attributes :timestamp, :event_type, :organization_guid,
                      :organization_name, :space_guid, :space_name,
                      :service_instance_guid, :service_instance_name,
                      :service_guid, :service_label, :service_provider,
                      :service_version, :service_plan_guid,
                      :service_plan_name

    def event_type
      "service_create"
    end

    def self.create_from_service_instance(instance)
      plan = instance.service_plan
      svc = plan.service
      space = instance.space
      org = space.organization

      return unless org.billing_enabled?
      ServiceCreateEvent.create(
        :timestamp => Time.now,
        :organization_guid => org.guid,
        :organization_name => org.name,
        :space_guid => space.guid,
        :space_name => space.name,
        :service_instance_guid => instance.guid,
        :service_instance_name => instance.name,
        :service_guid => svc.guid,
        :service_label => svc.label,
        :service_provider => svc.provider,
        :service_version => svc.version,
        :service_plan_guid => plan.guid,
        :service_plan_name => plan.name,
      )
    end
  end
end
