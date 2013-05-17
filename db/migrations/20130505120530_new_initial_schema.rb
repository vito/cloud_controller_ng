# TODO: foreign keys

class NewInitialSchema < ActiveRecord::Migration
  def change
    # rather than creating different tables for each type of events, we're
    # going to denormalize them into one table.
    #
    # We don't use foreign keys here because the objects may get deleted after
    # the billing records are generated, and that should be allowed.
    VCAP::Migration.model self, :billing_events do |t|
      t.datetime :timestamp, :null => false
      t.string :kind, :null => false
      t.string :organization_guid, :null => false
      t.string :organization_name, :null => false
      t.string :space_guid
      t.string :space_name
      t.string :app_guid
      t.string :app_name
      t.string :app_plan_name
      t.string :app_run_id
      t.integer :app_memory
      t.integer :app_instance_count
      t.string :service_instance_guid
      t.string :service_instance_name
      t.string :service_guid
      t.string :service_label
      t.string :service_provider
      t.string :service_version
      t.string :service_plan_guid
      t.string :service_plan_name
    end

    add_index :billing_events, :timestamp

    VCAP::Migration.model self, :quota_definitions do |t|
      t.string :name, :null => false
      t.boolean :non_basic_services_allowed, :null => false
      t.integer :total_services, :null => false
      t.integer :memory_limit, :null => false
      t.boolean :trial_db_allowed, :default => false
    end

    add_index :quota_definitions, :name, :unique => true

    VCAP::Migration.model self, :service_auth_tokens do |t|
      t.string :label,    :null => false
      t.string :provider, :null => false
      t.string :token,    :null => false
      t.string :salt
    end

    add_index :service_auth_tokens, [:label, :provider], :unique => true

    VCAP::Migration.model self, :services do |t|
      t.string :label,       :null => false
      t.string :provider,    :null => false
      t.string :url,         :null => false
      t.string :description, :null => false
      t.string :version,     :null => false
      t.text :extra, :limit => (2 ** 24 - 1) # MEDIUMTEXT limit
      t.string  :info_url
      t.string  :acls
      t.integer :timeout
      t.boolean :active, :default => false
      t.string :unique_id, :null => false
    end

    add_index :services, :label
    add_index :services, :unique_id, :unique => true
    add_index :services, [:label, :provider], :unique => true

    VCAP::Migration.model self, :organizations do |t|
      t.string :name, :null => false
      t.boolean :billing_enabled, :null => false, :default => false
      t.boolean :can_access_non_public_plans, :default => false

      t.belongs_to :quota_definition
    end

    add_index :organizations, :name, :unique => true

    VCAP::Migration.model self, :service_plans do |t|
      t.string :name,        :null => false
      t.string :description, :null => false
      t.boolean :free, :null => false
      t.text :extra, :limit => (2 ** 24 - 1) # MEDIUMTEXT limit
      t.string :unique_id, :null => false
      t.boolean :public, :default => true

      t.belongs_to :service
    end

    add_index :service_plans, :unique_id, :unique => true
    add_index :service_plans, [:service_id, :name], :unique => true

    VCAP::Migration.model self, :domains do |t|
      t.string :name, :null => false
      t.boolean :wildcard, :default => true, :null => false

      t.belongs_to :owning_organization
    end

    add_index :domains, :name, :unique => true

    VCAP::Migration.model self, :spaces do |t|
      t.string :name, :null => false

      t.belongs_to :organization, :null => false
    end

    add_index :spaces, [:organization_id, :name], :unique => true

    VCAP::Migration.model self, :apps do |t|
      t.string :name, :null => false

      # Do the bare miminum for now.  We'll migrate this to something
      # fancier later if we need it.
      t.boolean :production, :default => false

      # environment provided by the developer.
      # does not include environment from service
      # bindings.  those get merged from the bound
      # services
      t.text :environment_json

      # quota settings
      #
      # FIXME: these defaults are going to move out of here and into
      # the upper layers so that they are more easily run-time configurable
      #
      # This *MUST* be moved because we have to know up at the controller
      # what the actual numbers are going to be so that we can
      # send the correct billing events to the "money maker"
      t.integer :memory,           :default => 256
      t.integer :instances,        :default => 0
      t.integer :file_descriptors, :default => 16384
      t.integer :disk_quota,       :default => 2048

      # app state
      t.string :state,             :null => false, :default => "STOPPED"

      # package state
      t.string :package_state,     :null => false, :default => "PENDING"
      t.string :package_hash

      t.string :droplet_hash
      t.string :version
      t.string :metadata, :default => "{}", :null => false
      t.string :buildpack
      t.string :detected_buildpack

      t.string :staging_task_id

      t.belongs_to :space, :null => false
      t.belongs_to :stack, :null => false
    end

    add_index :apps, :name
    add_index :apps, [:space_id, :name], :unique => true

    create_table :domains_organizations, :id => false do |t|
      t.integer :domain_id
      t.integer :organization_id
    end

    add_index :domains_organizations, [:domain_id, :organization_id],
              :unique => true

    create_table :domains_spaces, :id => false do |t|
      t.integer :domain_id
      t.integer :space_id
    end

    add_index :domains_spaces, [:domain_id, :space_id], :unique => true

    VCAP::Migration.model self, :routes do |t|
      t.string :host, :null => false
      t.belongs_to :domain, :null => false
      t.belongs_to :space, :null => false
    end

    add_index :routes, [:host, :domain_id], :unique => true

    VCAP::Migration.model self, :service_instances do |t|
      t.string :name, :null => false
      t.text :credentials, :null => false
      t.string :gateway_name
      t.string :gateway_data, :size => 2048
      t.string :dashboard_url

      t.string :salt

      t.belongs_to :space
      t.belongs_to :service_plan
    end

    add_index :service_instances, :name
    add_index :service_instances, [:space_id, :name], :unique => true

    VCAP::Migration.model self, :users do |t|
      t.belongs_to :default_space

      t.boolean :admin,  :default => false
      t.boolean :active, :default => false
    end

    create_table :apps_routes do |t|
      t.integer :app_id
      t.integer :route_id
    end

    add_index :apps_routes, [:app_id, :route_id], :unique => true

    # Organization permissions
    [:users, :managers, :billing_managers, :auditors].each do |perm|
      VCAP::Migration.create_permission_table(self, :organization, perm)
    end

    VCAP::Migration.model self, :service_bindings do |t|
      t.text :credentials, :null => false
      t.string :binding_options

      t.string :gateway_name, :null => false, :default => ''
      t.string :configuration
      t.string :gateway_data

      t.string :salt

      t.belongs_to :app, :null => false
      t.belongs_to :service_instance, :null => false
    end

    add_index :service_bindings, [:app_id, :service_instance_id], :unique => true

    # App Space permissions
    [:developers, :managers, :auditors].each do |perm|
      VCAP::Migration.create_permission_table(self, :space, perm)
    end

    VCAP::Migration.model self, :stacks do |t|
      t.string :name, :null => false
      t.string :description, :null => false
    end

    add_index :stacks, :name, :unique => true

    VCAP::Migration.model self, :app_events do |t|
      t.datetime :timestamp, :null => false
      t.string :instance_guid, :null => false
      t.integer :instance_index, :null => false
      t.integer :exit_status, :null => false
      t.string :exit_description

      t.belongs_to :app, :null => false
    end

    add_index :app_events, :app_id
  end
end
