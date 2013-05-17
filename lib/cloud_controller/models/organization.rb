# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::Models
  class OrganizationManager < ActiveRecord::Base
    belongs_to :organization
    belongs_to :user
  end

  class OrganizationBillingManager < ActiveRecord::Base
    belongs_to :organization
    belongs_to :user
  end

  class OrganizationAuditor < ActiveRecord::Base
    belongs_to :organization
    belongs_to :user
  end

  class Organization < ActiveRecord::Base
    include CF::ModelGuid
    include CF::ModelRelationships

    class InvalidDomainRelation < InvalidRelation; end

    has_many :spaces, :dependent => :destroy
    has_many :service_instances, :through => :spaces
    has_many :apps, :through => :spaces
    has_many :app_events, :through => :apps
    has_many :owned_domains,
             :class_name => "VCAP::CloudController::Models::Domain",
             :foreign_key => "owning_organization_id",
             :dependent => :destroy
    has_and_belongs_to_many :domains, :before_add => :validate_domain
    belongs_to :quota_definition

    has_and_belongs_to_many :users
    has_and_belongs_to_many :managers,
      :join_table => "organizations_managers",
      :association_foreign_key => "user_id",
      :class_name => "VCAP::CloudController::Models::User"
    has_and_belongs_to_many :billing_managers,
      :join_table => "organizations_billing_managers",
      :association_foreign_key => "user_id",
      :class_name => "VCAP::CloudController::Models::User"
    has_and_belongs_to_many :auditors,
      :join_table => "organizations_auditors",
      :association_foreign_key => "user_id",
      :class_name => "VCAP::CloudController::Models::User"

    validates :name, :presence => true
    validates :name, :uniqueness => { :case_sensitive => false }

    before_create :add_inheritable_domains, :add_default_quota
    after_save :register_start_events

    strip_attributes  :name

    default_order_by  :name

    export_attributes :name, :billing_enabled, :quota_definition_guid
    import_attributes :name, :billing_enabled,
                      :user_guids, :manager_guids, :billing_manager_guids,
                      :auditor_guids, :domain_guids, :quota_definition_guid,
                      :can_access_non_public_plans

    validate :only_admin_can_change_quota, :only_admin_can_enable_billing,
             :only_admin_can_enable_private_plans

    validate :only_admin_can_create_with_private_plans

    def self.eager_load_associations
      [:quota_definition]
    end

    def billing_enabled?
      billing_enabled
    end

    def only_admin_can_change_quota
      only_admin_can_update(:quota_definition_id)
    end

    def only_admin_can_enable_billing
      only_admin_can_update(:billing_enabled)
    end

    def only_admin_can_enable_private_plans
      only_admin_can_update(:can_access_non_public_plans)
    end

    def only_admin_can_create_with_private_plans
      only_admin_can_enable_on_new(:can_access_non_public_plans)
    end

    def only_admin_can_enable_on_new(field_name)
      if new_record? && !!public_send(field_name)
        require_admin_for(field_name)
      end
    end

    def only_admin_can_update(field_name)
      if !new_record? && send(:"#{field_name}_changed?")
        require_admin_for(field_name)
      end
    end

    def require_admin_for(field_name)
      unless VCAP::CloudController::SecurityContext.current_user_is_admin?
        errors.add(field_name, :not_authorized)
      end
    end

    def validate_domain(domain)
      return if domain && domain.owning_organization.nil?
      unless (domain &&
              domain.owning_organization_id &&
              domain.owning_organization_id == id)
        raise InvalidDomainRelation.new(domain.guid)
      end
    end

    def add_inheritable_domains
      # TODO AR: optimize
      Domain.shared_domains.each do |d|
        add_domain(d)
      end
    end

    def add_default_quota
      unless quota_definition_id
        self.quota_definition_id = QuotaDefinition.default.id
      end
    end

    def service_instance_quota_remaining?
      quota_definition.total_services == -1 || # unlimited
        service_instances.count < quota_definition.total_services
    end

    def check_quota?(service_plan)
      return check_quota_for_trial_db if service_plan.trial_db?
      check_quota_without_trial_db(service_plan)
    end

    def check_quota_for_trial_db
      if trial_db_allowed?
        return {:type => :org, :name => :trial_quota_exceeded} if trial_db_allocated?
      elsif paid_services_allowed?
        return {:type => :org, :name => :paid_quota_exceeded} unless service_instance_quota_remaining?
      else
        return {:type => :service_plan, :name => :paid_services_not_allowed }
      end

      {}
    end

    def check_quota_without_trial_db(service_plan)
      if paid_services_allowed?
        return {:type => :org, :name => :paid_quota_exceeded } unless service_instance_quota_remaining?
      elsif service_plan.free
        return {:type => :org, :name => :free_quota_exceeded } unless service_instance_quota_remaining?
      else
        return {:type => :service_plan, :name => :paid_services_not_allowed }
      end

      {}
    end

    def paid_services_allowed?
      quota_definition.non_basic_services_allowed
    end

    def trial_db_allowed?
      quota_definition.trial_db_allowed
    end

    # Does any service instance in any space have a trial DB plan?
    def trial_db_allocated?
      service_instances.each do |svc_instance|
        return true if svc_instance.service_plan.trial_db?
      end

      false
    end

    def memory_remaining
      memory_used = apps.inject(0) do |sum, app|
        sum + app.memory * app.instances
      end

      quota_definition.memory_limit - memory_used
    end

    def self.user_visibility_filter(user, set = self)
      set.joins(:users, :managers, :billing_managers, :auditors).where("
        organizations_users.user_id = :user or
          organizations_managers.user_id = :user or
          organizations_billing_managers.user_id = :user or
          organizations_auditors.user_id = :user
      ", :user => user.id).uniq
    end

    private

    def register_start_events
      # We cannot start billing events without the guid being assigned to the org.
      if billing_enabled_changed? && billing_enabled?
        OrganizationStartEvent.create_from_org(self)

        # retroactively emit start events for services
        spaces.map(&:service_instances).flatten.each do |si|
          ServiceCreateEvent.create_from_service_instance(si)
        end

        spaces.map(&:apps).flatten.each do |app|
          AppStartEvent.create_from_app(app) if app.started?
        end
      end
    end
  end
end
