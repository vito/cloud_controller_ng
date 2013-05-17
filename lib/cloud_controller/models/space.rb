# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::Models
  class SpacesDeveloper < ActiveRecord::Base
    belongs_to :space
    belongs_to :user
  end

  class SpacesManager < ActiveRecord::Base
    belongs_to :space
    belongs_to :user
  end

  class SpacesAuditor < ActiveRecord::Base
    belongs_to :space
    belongs_to :user
  end

  class Space < ActiveRecord::Base
    include CF::ModelGuid
    include CF::ModelRelationships

    class InvalidDeveloperRelation < InvalidRelation; end
    class InvalidAuditorRelation   < InvalidRelation; end
    class InvalidManagerRelation   < InvalidRelation; end
    class InvalidDomainRelation    < InvalidRelation; end

    has_many :apps, :dependent => :destroy
    has_many :service_instances, :dependent => :destroy
    has_many :routes, :dependent => :destroy
    has_many :app_events, :through => :apps
    has_and_belongs_to_many :domains, :before_add => :validate_domain
    belongs_to :organization

    has_many :default_users,
             :class_name => "VCAP::CloudController::Models::User",
             :foreign_key => "default_space_id"

    has_and_belongs_to_many :developers,
      :join_table => "spaces_developers",
      :association_foreign_key => "user_id",
      :class_name => "VCAP::CloudController::Models::User",
      :before_add => :validate_developer
    has_and_belongs_to_many :managers,
      :join_table => "spaces_managers",
      :association_foreign_key => "user_id",
      :class_name => "VCAP::CloudController::Models::User",
      :before_add => :validate_manager
    has_and_belongs_to_many :auditors,
      :join_table => "spaces_auditors",
      :association_foreign_key => "user_id",
      :class_name => "VCAP::CloudController::Models::User",
      :before_add => :validate_auditor

    validates :name, :organization, :presence => true

    validates :name, :uniqueness => {
      :scope => :organization_id,
      :case_sensitive => false
    }

    before_create :add_inheritable_domains

    export_attributes :name, :organization_guid

    import_attributes :name, :organization_guid, :developer_guids,
                      :manager_guids, :auditor_guids, :domain_guids

    strip_attributes  :name

    def in_organization?(user)
      organization && organization.users.include?(user)
    end

    def validate_developer(user)
      # TODO: unlike most other validations, is *NOT* being enforced by DB
      raise InvalidDeveloperRelation.new(user.guid) unless in_organization?(user)
    end

    def validate_manager(user)
      raise InvalidManagerRelation.new(user.guid) unless in_organization?(user)
    end

    def validate_auditor(user)
      raise InvalidAuditorRelation.new(user.guid) unless in_organization?(user)
    end

    def validate_domain(domain)
      return if domain && domain.owning_organization.nil? || organization.nil?

      unless domain.owning_organization_id == organization.id
        raise InvalidDomainRelation.new(domain.guid)
      end
    end

    def add_inheritable_domains
      return unless organization

      organization.domains.each do |d|
        add_domain(d) unless d.owning_organization
      end
    end

    def self.user_visibility_filter(user, set = self)
      set.where(:organization_id => user.organizations)
    end
  end
end
