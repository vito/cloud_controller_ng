# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::Models
  class AppStartEvent < BillingEvent
    validates :space_guid, :space_name, :app_guid, :app_name, :app_run_id,
      :app_plan_name, :app_memory, :app_instance_count,
      :presence => true

    validates :app_run_id, :uniqueness => true

    export_attributes :timestamp, :event_type, :organization_guid,
      :organization_name, :space_guid, :space_name, :app_guid, :app_name,
      :app_run_id, :app_plan_name, :app_memory, :app_instance_count

    def event_type
      "app_start"
    end

    def self.create_from_app(app)
      return unless app.space.organization.billing_enabled?

      create(
        :timestamp => Time.now,
        :organization_guid => app.space.organization.guid,
        :organization_name => app.space.organization.name,
        :space_guid => app.space.guid,
        :space_name => app.space.name,
        :app_guid => app.guid,
        :app_name => app.name,
        :app_run_id => SecureRandom.uuid,
        :app_plan_name => app.production ? "paid" : "free",
        :app_memory => app.memory,
        :app_instance_count => app.instances,
      )
    end
  end
end
