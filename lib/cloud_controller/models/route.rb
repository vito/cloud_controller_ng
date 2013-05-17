# Copyright (c) 2009-2012 VMware, Inc.

require "cloud_controller/dea/dea_client"

module VCAP::CloudController::Models
  class Route < ActiveRecord::Base
    include CF::ModelGuid
    include CF::ModelRelationships

    class InvalidDomainRelation < InvalidRelation; end
    class InvalidAppRelation < InvalidRelation; end

    belongs_to :domain
    belongs_to :space

    has_and_belongs_to_many :apps,
      :before_add => :validate_app,
      :after_add => :mark_app_routes_changed,
      :after_remove => :mark_app_routes_changed

    validates :domain, :space, :presence => true

    validates :host, :format => /^([\w\-]*)$/, :uniqueness => {
      :scope => :domain_id,
      :case_sensitive => false
    }

    validate :host_must_be_empty_if_domain_is_not_wildcard
    validate :host_cannot_be_empty_if_domain_is_shared
    validate :domain_must_be_in_same_space
    validate :host_must_not_be_nil

    export_attributes :host, :domain_guid, :space_guid
    import_attributes :host, :domain_guid, :space_guid, :app_guids

    def organization
      space.organization
    end

    def host_must_be_empty_if_domain_is_not_wildcard
      unless domain && domain.wildcard
        errors.add(:host, :host_not_empty) unless host && host.empty?
      end
    end

    def host_cannot_be_empty_if_domain_is_shared
      if domain && domain.owning_organization.nil? && host.empty?
        errors.add(:host, :empty_with_shared_domain)
      end
    end

    def host_must_not_be_nil
      errors.add(:host, :presence) if host.nil?
    end

    def domain_must_be_in_same_space
      if space && domain && !space.domains.exists?(:id => domain.id)
        errors.add(:domain, :invalid_relation)
      end
    end

    def validate_app(app)
      return unless (space && app && domain)

      unless app.space == space
        raise InvalidAppRelation.new(app.guid)
      end

      unless space.domains.include?(domain)
        raise InvalidDomainRelation.new(domain.guid)
      end
    end

    def fqdn
      !host.empty? ? "#{host}.#{domain.name}" : domain.name
    end

    def as_summary_json
      {
        :guid => guid,
        :host => host,
        :domain => {
          :guid => domain.guid,
          :name => domain.name
        }
      }
    end

    def self.user_visibility_filter(user, set = self)
      orgs =
        Organization.includes(:managers, :auditors).where("
          organizations_managers.user_id = :user OR
            organizations_auditors.user_id = :user
        ", :user => user.id).all

      spaces =
        Space.includes(:developers, :auditors, :managers).where("
          spaces_developers.user_id = :user OR
            spaces_auditors.user_id = :user OR
            spaces_managers.user_id = :user OR
            spaces.organization_id IN (:orgs)
        ", :user => user.id, :orgs => orgs).all

      set.where(:space_id => spaces)
    end

    private

    def around_destroy
      loaded_apps = apps
      super

      loaded_apps.each do |app|
        mark_app_routes_changed(app)
      end
    end

    def mark_app_routes_changed(app)
      app.routes_changed = true
      if app.dea_update_pending?
        VCAP::CloudController::DeaClient.update_uris(app)
      end
    end
  end
end
