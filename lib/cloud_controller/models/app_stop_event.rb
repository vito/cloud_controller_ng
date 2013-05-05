# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::Models
  class MissingAppStartEvent < StandardError; end

  class AppStopEvent < BillingEvent
    validates :space_guid, :space_name, :app_guid, :app_name, :app_run_id,
      :presence => true
    validates :app_run_id, :uniqueness => true

    export_attributes :timestamp, :event_type, :organization_guid,
      :organization_name, :space_guid, :space_name, :app_guid, :app_name,
      :app_run_id 

    def event_type
      "app_stop"
    end

    def self.create_from_app(app)
      return unless app.space.organization.billing_enabled?

      app_start_event =
        AppStartEvent.where(:app_guid => app.guid).order("id DESC").first

      raise MissingAppStartEvent.new(app.guid) if app_start_event.nil?

      create(
        :timestamp => Time.now,
        :organization_guid => app.space.organization.guid,
        :organization_name => app.space.organization.name,
        :space_guid => app.space.guid,
        :space_name => app.space.name,
        :app_guid => app.guid,
        :app_name => app.name,
        :app_run_id => app_start_event.app_run_id,
      )
    end
  end
end
