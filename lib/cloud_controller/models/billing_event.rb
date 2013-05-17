# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::Models
  class BillingEvent < ActiveRecord::Base
    include CF::ModelGuid
    include CF::ModelRelationships

    def self.inheritance_column
      "kind"
    end

    validates :timestamp, :organization_guid, :organization_name,
              :presence => true

    def self.user_visibility_filter(user, set = self)
      # don't allow anyone to enumerate other than the admin
      set.where(:id => nil)
    end
  end
end
