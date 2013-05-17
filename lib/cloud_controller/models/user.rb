# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::Models
  class User < ActiveRecord::Base
    include CF::ModelRelationships

    has_and_belongs_to_many :organizations

    has_and_belongs_to_many :managed_organizations,
      :join_table => "organizations_managers",
      :association_foreign_key => "organization_id",
      :class_name => "VCAP::CloudController::Models::Organization"

    has_and_belongs_to_many :billing_managed_organizations,
      :join_table => "organizations_billing_managers",
      :association_foreign_key => "organization_id",
      :class_name => "VCAP::CloudController::Models::Organization"

    has_and_belongs_to_many :audited_organizations,
      :join_table => "organizations_auditors",
      :association_foreign_key => "organization_id",
      :class_name => "VCAP::CloudController::Models::Organization"

    belongs_to :default_space,
      :foreign_key => "default_space_id",
      :class_name => "VCAP::CloudController::Models::Space"

    has_and_belongs_to_many :spaces,
      :join_table => "spaces_developers",
      :foreign_key => "user_id"

    has_and_belongs_to_many :managed_spaces,
      :join_table => "spaces_managers",
      :association_foreign_key => "space_id",
      :class_name => "VCAP::CloudController::Models::Space"

    has_and_belongs_to_many :audited_spaces,
      :join_table => "spaces_auditors",
      :association_foreign_key => "space_id",
      :class_name => "VCAP::CloudController::Models::Space"

    validates :guid, :presence => true, :uniqueness => true

    export_attributes :admin, :active, :default_space_guid

    import_attributes :guid, :admin, :active,
                      :organization_guids,
                      :managed_organization_guids,
                      :billing_managed_organization_guids,
                      :audited_organization_guids,
                      :space_guids,
                      :managed_space_guids,
                      :audited_space_guids,
                      :default_space_guid

    def admin?
      admin
    end

    def active?
      active
    end

    def can_access_non_public_plans?
      organizations.exists?(:can_access_non_public_plans => true)
    end
  end
end
