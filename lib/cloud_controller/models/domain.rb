# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::Models
  class Domain < ActiveRecord::Base
    include CF::ModelGuid
    include CF::ModelRelationships

    class InvalidSpaceRelation < VCAP::Errors::InvalidRelation; end
    class InvalidOrganizationRelation < VCAP::Errors::InvalidRelation; end

    DOMAIN_REGEX = /^[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}$/ix.freeze

    belongs_to :owning_organization,
      :class_name => "VCAP::CloudController::Models::Organization"
    has_and_belongs_to_many :organizations, :before_add => :validate_organization
    has_and_belongs_to_many :spaces, :before_add => :validate_space
    has_many :routes, :dependent => :destroy

    default_order_by  :name

    after_create :add_owning_organization

    validates :name, :presence => true
    validates :name, :uniqueness => { :case_sensitive => false }

    validate :i_dunno_man

    validates :name, :format => DOMAIN_REGEX

    export_attributes :name, :owning_organization_guid, :wildcard
    import_attributes :name, :owning_organization_guid, :wildcard,
                      :space_guids
    strip_attributes  :name

    scope :shared_domains, where(:owning_organization_id => nil)

    def add_owning_organization
      add_organization(owning_organization) if owning_organization
    end

    # TODO AR
    def i_dunno_man
      if !new_record? && wildcard_changed? && !wildcard && \
          routes.any? { |r| r.host.present? }
        errors.add(:wildcard, :wildcard_routes_in_use)
      end

      if new_record? || owning_organization_id_changed?
        unless VCAP::CloudController::SecurityContext.current_user_is_admin?
          unless owning_organization.present?
            errors.add(:owning_organization, :presence)
          end
        end
      end

      errors.add(:name, :overlapping_domain) if overlaps_domain_in_other_org?
    end

    def validate_space(space)
      unless space && owning_organization && owning_organization.spaces.include?(space)
        raise InvalidSpaceRelation.new(space.guid)
      end
    end

    def validate_organization(org)
      return unless owning_organization
      unless org && owning_organization.id == org.id
        raise InvalidOrganizationRelation.new(org.guid)
      end
    end

    # For permission checks
    def organization
      owning_organization
    end

    def overlaps_domain_in_other_org?
      domains_to_check = intermediate_domains
      return unless domains_to_check
      overlapping_domains = Domain.where(
        :name => domains_to_check
      ).where(Domain.arel_table[:id].not_eq(id))

      if owning_organization
        overlapping_domains = overlapping_domains.where(
          Domain.arel_table[:owning_organization_id].not_eq(
            owning_organization.id)
        )
      end

      overlapping_domains.count != 0
    end

    def as_summary_json
      {
        :guid => guid,
        :name => name,
        :owning_organization_guid => (owning_organization ? owning_organization.guid : nil)
      }
    end

    def intermediate_domains
      self.class.intermediate_domains(name)
    end

    def self.intermediate_domains(name)
      return unless name and name =~ DOMAIN_REGEX

      name.split(".").reverse.inject([]) do |a, e|
        a.push(a.empty? ? e : "#{e}.#{a.last}")
      end
    end

    def self.user_visibility_filter(user, set = self)
      orgs = Organization.joins(:managers, :auditors).where("
          organizations_managers.user_id = :user OR
            organizations_auditors.user_id = :user
        ", :user => user.id).all

      spaces = Space.joins(:developers, :managers, :auditors).where("
          spaces_developers.user_id = :user OR
            spaces_managers.user_id = :user OR
            spaces_auditors.user_id = :user
        ", :user => user.id).all

      spaces_domains =
        joins(:spaces).where(:domains_spaces => { :space_id => spaces })

      set.where("
        domains.owning_organization_id IS NULL OR
          domains.owning_organization_id IN (:organizations) OR
          domains.id IN (:spaces_domains)
        ", :spaces_domains => spaces_domains, :organizations => orgs)
    end

    def self.default_serving_domain
      @default_serving_domain
    end

    def self.default_serving_domain_name=(name)
      @default_serving_domain_name = name
      if name
        @default_serving_domain = find_or_create_shared_domain(name)
      else
        @default_serving_domain = nil
      end
      name
    end

    def self.default_serving_domain_name
      @default_serving_domain_name
    end

    def self.find_or_create_shared_domain(name)
      logger = Steno.logger("cc.db.domain")
      d = nil

      Domain.transaction do
        d = Domain.find_by_name(name)
        if d
          logger.info "reusing default serving domain: #{name}"
        else
          logger.info "creating shared serving domain: #{name}"
          d = Domain.new(:name => name, :wildcard => true)
          d.save(:validate => false)
        end
      end

      d
    end

    def self.populate_from_config(config, organization)
      config[:app_domains].each do |domain|
        find_or_create_shared_domain(domain)
      end

      unless config[:app_domains].include?(config[:system_domain])
        where(
          :name => config[:system_domain],
          :wildcard => true,
          :owning_organization_id => organization
        ).first_or_create
      end
    end
  end
end
