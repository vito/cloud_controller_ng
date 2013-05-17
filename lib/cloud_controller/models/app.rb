# Copyright (c) 2009-2012 VMware, Inc.

require "cloud_controller/active_record/json_hash_serializer"
require "cloud_controller/app_stager"
require "cloud_controller/dea/dea_client"

module VCAP::CloudController
  module Models
    class App < ActiveRecord::Base
      include CF::ModelGuid
      include CF::ModelRelationships

      class InvalidRouteRelation < InvalidRelation
        def to_s
          "The URL was not available [route ID #{super}]"
        end
      end

      class InvalidBindingRelation < InvalidRelation; end

      APP_STATES = %w[STOPPED STARTED].map(&:freeze).freeze
      PACKAGE_STATES = %w[PENDING STAGED FAILED].map(&:freeze).freeze

      belongs_to :space
      belongs_to :stack
      has_and_belongs_to_many :routes, :before_add => :validate_route,
                              :after_add => :mark_routes_changed,
                              :after_remove => :mark_routes_changed
      has_many :service_bindings, :dependent => :destroy
      has_many :service_instances, :through => :service_bindings
      has_many :app_events, :dependent => :destroy

      validates :name, :space, :presence => true

      validates :name, :uniqueness => {
        :scope => :space_id,
        :case_sensitive => false
      }

      validates :state, :inclusion => { :in => APP_STATES }
      validates :package_state, :inclusion => { :in => PACKAGE_STATES }

      serialize :metadata, CF::JsonHashSerializer
      serialize :environment_json, CF::JsonHashSerializer # TODO: rename to environment

      validates :buildpack, :format => URI.regexp(%w(http https git)),
        :allow_nil => true

      validate :metadata_must_be_a_hash
      validate :environment_json_must_be_hash_without_reserved_keys
      validate :memory_cannot_exceed_quota

      before_create :set_new_version
      before_save :check_app_staged
      before_save :fallback_stack_to_default
      before_save :update_version
      before_save :generate_billing_events
      after_destroy :generate_stop_billing_event
      after_commit :react_to_saved_changes, :on => :update
      after_commit :stop_droplet, :on => :destroy
      after_commit :clear_bits, :on => :destroy

      export_attributes :name, :production, :space_guid, :stack_guid,
        :buildpack, :detected_buildpack, :environment_json, :memory,
        :instances, :disk_quota, :state, :version, :command, :console,
        :debug, :staging_task_id

      import_attributes :name, :production, :space_guid, :stack_guid,
        :buildpack, :detected_buildpack, :environment_json, :memory,
        :instances, :disk_quota, :state, :command, :console, :debug,
        :staging_task_id, :service_binding_guids, :route_guids

      strip_attributes  :name


      # marked as true on changing the associated routes, and reset by
      # +DeaClient.start+
      attr_accessor :routes_changed

      attr_accessor :stage_async

      # Last staging response which might contain streaming log url
      attr_accessor :last_stager_response

      def command=(cmd)
        self.metadata ||= {}
        self.metadata["command"] = cmd
      end

      def command
        self.metadata && self.metadata["command"]
      end

      def console=(c)
        self.metadata ||= {}
        self.metadata["console"] = c
      end

      def console
        # without the == true check, this expression can return nil if
        # the key doesn't exist, rather than false
        self.metadata && self.metadata["console"] == true
      end

      def debug=(d)
        self.metadata ||= {}
        # We don't support sending nil through API
        self.metadata["debug"] = (d == "none") ? nil : d
      end

      def debug
        self.metadata && self.metadata["debug"]
      end

      # We need to overide this ourselves because we are really doing a
      # many-to-many with ServiceInstances and want to remove the relationship
      # to that when we remove the binding like sequel would do if the
      # relationship was explicly defined as such.  However, since we need to
      # annotate the join table with binding specific info, we manage the
      # many_to_one and one_to_many sides of the relationship ourself.  If there
      # is a sequel option that I couldn't see that provides this behavior, this
      # method could be removed in the future.  Note, the sequel docs explicitly
      # state that the correct way to overide the remove_bla functionality is to
      # do so with the _ prefixed private method like we do here.
      def _remove_service_binding(binding)
        binding.destroy
      end

      def self.user_visibility_filter(user, set = self)
        set.where(:space_id => user.spaces)
      end

      def needs_staging?
        self.package_hash && !self.staged?
      end

      def staged?
        self.package_state == "STAGED"
      end

      def failed?
        self.package_state == "FAILED"
      end

      def pending?
        self.package_state == "PENDING"
      end

      def started?
        self.state == "STARTED"
      end

      def stopped?
        self.state == "STOPPED"
      end

      def uris
        routes.map { |r| r.fqdn }
      end

      def after_remove_binding(binding)
        mark_for_restaging
      end

      def mark_as_failed_to_stage
        self.package_state = "FAILED"
        save
      end

      def mark_for_restaging(opts={})
        self.package_state = "PENDING"
        save! if opts[:save]
      end

      def package_hash=(hash)
        super(hash)
        mark_for_restaging if package_hash_changed?
      end

      def stack=(stack)
        mark_for_restaging unless new_record?
        super(stack)
      end

      def droplet_hash=(hash)
        self.package_state = "STAGED"
        super(hash)
      end

      def running_instances
        return 0 unless started?
        HealthManagerClient.healthy_instances(self)
      end

      # returns True if we need to update the DEA's with
      # associated URL's.
      # We also assume that the relevant methods in +DeaClient+ will reset
      # this app's routes_changed state
      # @return [Boolean, nil]
      def dea_update_pending?
        staged? && started? && @routes_changed
      end

      private

      def metadata_must_be_a_hash
        unless metadata.is_a?(Hash)
          errors.add(:metadata)
        end
      end

      def environment_json_must_be_hash_without_reserved_keys
        unless environment_json.is_a?(Hash)
          errors.add(:environment_json)
          return
        end

        environment_json.keys.each do |k|
          if k =~ /^(vcap|vmc)/i
            errors.add(:environment_json, "reserved_key:#{k}")
          end
        end
      end

      def validate_route(route)
        unless space.domains.include?(route.domain) && route.space == space
          raise InvalidRouteRelation.new(route.guid)
        end
      end

      def memory_cannot_exceed_quota
        if space && (space.organization.memory_remaining < additional_memory_requested)
          errors.add(:memory, :quota_exceeded)
        end
      end

      def additional_memory_requested
        total_requested_memory = memory * instances
        return total_requested_memory if new_record?

        app_from_db = self.class.find_by_guid(guid)
        total_existing_memory = app_from_db.memory * app_from_db.instances
        additional_memory = total_requested_memory - total_existing_memory
        return additional_memory if additional_memory > 0

        0
      end

      def set_new_version
        self.version = SecureRandom.uuid unless version_changed?
      end

      def check_app_staged
        if generate_start_event? && !package_hash
          raise VCAP::Errors::AppPackageInvalid.new(
            "bits have not been uploaded")
        end
      end

      def fallback_stack_to_default
        self.stack ||= Stack.default
      end

      def update_version
        # The reason this is only done on a state change is that we really only
        # care about the state when we transitioned from stopped to running.  The
        # current semantics of changing memory or bindings is that they don't
        # take effect until after the app is restarted.  This allows clients to
        # batch a bunch of changes without having their app bounce.  If we were
        # to change the version on every metadata change, the hm would cause them
        # to get restarted prematurely.
        #
        # The dirty check on version allows a higher level to set the version.
        # We might start populating this with the vcap request guid of an api
        # request.
        if (state_changed? || memory_changed?) && started?
          set_new_version
        end
      end

      def generate_billing_events
        AppStopEvent.create_from_app(self) if generate_stop_event?
        AppStartEvent.create_from_app(self) if generate_start_event?
      end

      def generate_stop_billing_event
        unless stopped? || has_stop_event_for_latest_run?
          AppStopEvent.create_from_app(self)
        end
      end

      def generate_start_event?
        # Change to app state is given priority over change to footprint as
        # we would like to generate only either start or stop event exactly
        # once during a state change. Also, if the app is not in started state
        # and/or is new, then the changes to the footprint shouldn't trigger a
        # billing event.
        started? && (state_changed? || (!new_record? && footprint_changed?))
      end

      def generate_stop_event?
        # If app is not in started state and/or is new, then the changes
        # to the footprint shouldn't trigger a billing event.
        !new_record? &&
          (being_stopped? || (footprint_changed? && started?)) &&
          !has_stop_event_for_latest_run?
      end

      def being_stopped?
        state_changed? && stopped?
      end

      def has_stop_event_for_latest_run?
        latest_start =
          AppStartEvent
            .select(:app_run_id)
            .where(:app_guid => guid)
            .order("id DESC")
            .limit(1).first

        return false unless latest_start

        !!AppStopEvent.exists?(:app_run_id => latest_start.app_run_id)
      end

      def footprint_changed?
        production_changed? || memory_changed? || instances_changed?
      end

      def stop_droplet
        DeaClient.stop(self) if started?
      end

      def clear_bits
        AppStager.delete_droplet(self)
        AppPackage.delete_package(self.guid)
      end

      def stage_if_needed(&success_callback)
        if needs_staging? && started?
          self.last_stager_response = \
            AppStager.stage_app(self, {:async => stage_async}, &success_callback)
        else
          success_callback.call
        end
      end

      def react_to_saved_changes
        changes = previous_changes

        if changes.has_key?("state")
          react_to_state_change
        elsif changes.has_key?("instances")
          before, after = changes["instances"]
          react_to_instances_change(after - before)
        end
      end

      def react_to_state_change
        if started?
          stage_if_needed do
            DeaClient.start(self)
            send_droplet_updated_message
          end
        elsif stopped?
          DeaClient.stop(self)
          send_droplet_updated_message
        end
      end

      def react_to_instances_change(delta)
        if started?
          stage_if_needed do
            DeaClient.change_running_instances(self, delta)
            send_droplet_updated_message
          end
        end
      end

      def send_droplet_updated_message
        MessageBus.instance.publish("droplet.updated", Yajl::Encoder.encode(
          :droplet => guid,
          :cc_partition => MessageBus.instance.config[:cc_partition]
        ))
      end

      def mark_routes_changed(_)
        @routes_changed = true
      end
    end
  end
end
