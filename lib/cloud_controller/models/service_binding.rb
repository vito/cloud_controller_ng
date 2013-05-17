module VCAP::CloudController::Models
  class ServiceBinding < ActiveRecord::Base
    include CF::ModelGuid
    include CF::ModelRelationships

    class InvalidAppAndServiceRelation < StandardError; end

    belongs_to :app
    belongs_to :service_instance

    validates :app, :service_instance, :presence => true

    validates :service_instance_id, :uniqueness => { :scope => :app_id }

    validate :app_and_service_instance_must_be_in_same_space

    before_create :bind_on_gateway
    after_create :mark_app_for_restaging
    after_update :mark_app_for_restaging
    before_destroy :unbind_on_gateway, :mark_app_for_restaging
    after_rollback :unbind_on_gateway, :if => proc { @bound_on_gateway }
    after_commit { @bound_on_gateway = false }

    export_attributes :app_guid, :service_instance_guid, :credentials,
                      :binding_options, :gateway_data, :gateway_name

    import_attributes :app_guid, :service_instance_guid, :credentials,
                      :binding_options, :gateway_data

    def space
      service_instance.space
    end

    def app_and_service_instance_must_be_in_same_space
      if app && service_instance
        unless service_instance.space == app.space
          raise InvalidAppAndServiceRelation.new(
            "'#{app.space.name}' '#{service_instance.space.name}'")
        end
      end
    end

    def mark_app_for_restaging
      app.mark_for_restaging(:save => true) if app
    end

    def self.user_visibility_filter(user, set = self)
      set.where(
        :service_instance_id => ServiceInstance.user_visibility_filter(user))
    end

    def credentials=(val)
      json = Yajl::Encoder.encode(val)
      generate_salt
      encrypted_string = VCAP::CloudController::Encryptor.encrypt(json, salt)
      super(encrypted_string)
    end

    def credentials
      encrypted_string = super
      return unless encrypted_string
      json = VCAP::CloudController::Encryptor.decrypt(encrypted_string, salt)
      Yajl::Parser.parse(json) if json
    end

    def gateway_data=(val)
      val = Yajl::Encoder.encode(val)
      super(val)
    end

    def gateway_data
      val = super
      val = Yajl::Parser.parse(val) if val
      val
    end

    def service_gateway_client
      # this shouldn't happen under normal circumstances, but will if we are
      # running tests that bypass validations
      return unless service_instance
      service_instance.service_gateway_client
    end

    def bind_on_gateway
      client = service_gateway_client

      # TODO: see service_gateway_client
      unless client
        self.gateway_name = ""
        self.gateway_data = nil
        self.credentials = {}
        return
      end

      logger.debug "binding service on gateway for #{guid}"

      service = service_instance.service_plan.service
      gw_attrs = client.bind(
        :service_id => service_instance.gateway_name,
        # TODO: we shouldn't still be using this compound label
        :label      => "#{service.label}-#{service.version}",
        :email      => VCAP::CloudController::SecurityContext.
                             current_user_email,
        :binding_options => {}
      )

      logger.debug "binding response for #{guid} #{gw_attrs.inspect}"

      self.gateway_name = gw_attrs.service_id
      self.gateway_data = gw_attrs.configuration
      self.credentials  = gw_attrs.credentials

      @bound_on_gateway = true
    end

    def unbind_on_gateway
      client = service_gateway_client
      return unless client # TODO see service_gateway_client
      client.unbind(
        :service_id      => service_instance.gateway_name,
        :handle_id       => gateway_name,
        :binding_options => {}
      )
    rescue => e
      logger.error "unbind failed #{e}"
    end

    def logger
      @logger ||= Steno.logger("cc.models.service_binding")
    end

    def generate_salt
      self.salt ||= VCAP::CloudController::Encryptor.generate_salt
    end
  end
end
