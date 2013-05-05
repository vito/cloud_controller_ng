module VCAP::CloudController::Models
  class AppEvent < ActiveRecord::Base
    include CF::ModelGuid
    include CF::ModelRelationships

    belongs_to :app

    validates :app, :instance_guid, :instance_index, :exit_status, :timestamp,
              :presence => true

    export_attributes :app_guid, :instance_guid, :instance_index,
      :exit_status, :exit_description, :timestamp

    import_attributes :app_guid, :instance_guid, :instance_index,
      :exit_status, :exit_description, :timestamp
  end
end
