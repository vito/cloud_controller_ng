# Copyright (c) 2009-2012 VMware, Inc.

require "services/api"

module VCAP::CloudController
  class LegacyServiceGateway < LegacyApiBase
    # This endpoint does its own auth
    allow_unauthenticated_access

    include VCAP::Errors
    SERVICE_TOKEN_KEY = "HTTP_X_VCAP_SERVICE_TOKEN"
    DEFAULT_PROVIDER = "core"
    LEGACY_API_USER_GUID = "legacy-api"
    LEGACY_PLAN_OVERIDE = "100"

    def create_offering
      req = VCAP::Services::Api::ServiceOfferingRequest.decode(body)
      logger.debug("Update or create legacy service request: #{req.extract.inspect}")

      (label, version_from_label, label_dash_check) = req.label.split("-")
      if label_dash_check
        logger.warn("Unexpected dash in label: #{req.label} ")
        raise Errors::InvalidRequest
      end

      version = req.version_aliases["current"] || version_from_label

      provider = DEFAULT_PROVIDER
      validate_access(label, provider)

      VCAP::CloudController::SecurityContext.set(self.class.legacy_api_user)
      Models::Service.transaction do
        service = Models::Service.where(
          :label => label, :provider => provider
        ).first_or_create

        if service.new_record?
          logger.debug2("Creating service")
        else
          logger.debug2("Updating service #{service.guid}")
        end

        service.update_attributes(
          :url         => req.url,
          :description => req.description,
          :version     => version,
          :acls        => req.acls,
          :timeout     => req.timeout,
          :info_url    => req.info_url,
          :active      => req.active,
          :extra       => req.extra,
        )

        update_plans(req, service, label)
      end

      empty_json
    end

    def update_plans(req, service, label)
      if req.plan_details
        new_plan_attrs = req.plan_details
      else
        new_plan_attrs = Array(req.plans).map {|plan_name|
          {
            "name" => plan_name,
            "free" => !!(plan_name =~ /^1[0-9][0-9]$/), #only 100-level plans are free
          }
        }
      end

      new_plan_attrs.each {|attrs| attrs["description"] ||= "dummy description" }

      old_plan_names = Models::ServicePlan.joins(:service).
        where("services.label = :label AND services.provider = :provider",
              :label => label, :provider => DEFAULT_PROVIDER).collect(&:name)

      new_plan_attrs.each do |attrs|
        instance = Models::ServicePlan.where(
          service_id: service.id,
          name: attrs['name']
        ).first_or_create

        instance.attributes =
          %w(name free description extra).inject({}) do |h, k|
            h[k.to_sym] = attrs[k]
            h
          end

        instance.save!
      end

      missing = old_plan_names - new_plan_attrs.map {|attrs| attrs["name"]}
      if missing.any?
        logger.info("Attempting to remove old plans: #{missing.inspect}")
        service.service_plans.where(:name => missing).each do |plan|
          begin
            plan.destroy
          rescue ActiveRecord::StatementInvalid
            # If something is hanging on to this plan, let it live
          end
        end
      end
    end

    def list_handles(label_and_version, provider = DEFAULT_PROVIDER)
      (label, version) = label_and_version.split("-")

      service = Models::Service.where(:label => label, :provider => provider).first
      raise ServiceNotFound, "label=#{label} provider=#{provider}" unless service

      validate_access(label, provider)
      logger.debug("Listing handles for service: #{service.inspect}")

      handles = []

      plans = service.service_plans
      instances = Models::ServiceInstance.where(:service_plan_id => plans)

      handles += instances.map do |si|
        {
          :service_id => si.gateway_name,
          :credentials => si.credentials,
          :configuration => si.gateway_data,
        }
      end

      bindings = Models::ServiceBinding.where(:service_instance_id => instances)

      handles += bindings.map do |sb|
        {
          :service_id => sb.gateway_name,
          :credentials => sb.credentials,
          :configuration => sb.gateway_data,
        }
      end

      Yajl::Encoder.encode({:handles => handles})
    end

    def delete(label_and_version, provider = DEFAULT_PROVIDER)
      label = label_and_version.split("-")[0]

      validate_access(label, provider)

      VCAP::CloudController::SecurityContext.set(self.class.legacy_api_user)
      svc_guid = Models::Service.where(:label => label, :provider => provider).first.guid
      svc_api = VCAP::CloudController::Service.new(config, logger, env, params, body)
      svc_api.dispatch(:delete, svc_guid)

      empty_json
    end

    def validate_access(label, provider = DEFAULT_PROVIDER)
      raise NotAuthorized unless auth_token = env[SERVICE_TOKEN_KEY]

      svc_auth_token = Models::ServiceAuthToken.where(
        :label => label, :provider => provider
      ).first

      unless (svc_auth_token && svc_auth_token.token_matches?(auth_token))
        logger.warn("unauthorized service offering")
        raise NotAuthorized
      end
    end

    def get(label_and_version, provider = DEFAULT_PROVIDER)
      label = label_and_version.split("-")[0]

      validate_access(label, provider)

      service = Models::Service.where(:label => label, :provider => provider).first

      offering = {
        :label => label,
        :provider => provider,
        :url => service.url,
      }

      [
        :description,
        :info_url,
        # :tags,
        # :plans,
        # :cf_plan_id,
        # :plan_options,
        # :binding_options,
        :acls,
        :active,
        :timeout,
        :provider,
        # :supported_versions,
        # :version_aliases,
      ].each do |field|
        if val = service.attributes[field]
          offering[field] = val
        end
      end

      offering[:plans] = service.service_plans.map(&:name)
      Yajl::Encoder.encode(offering)
    end

    # NB: ambiguous API: the handle id appears in both URI and body.
    # We should only take the handle id from URI
    #
    # P.S. While I applaud Ruby for allowing this default parameter in the
    # middle, I'm really not wild for _any_ function overloading in Ruby
    def update_handle(label_and_version, provider=DEFAULT_PROVIDER, id)
      (label, version) = label_and_version.split("-")

      validate_access(label, provider)
      VCAP::CloudController::SecurityContext.set(self.class.legacy_api_user)

      req = VCAP::Services::Api::HandleUpdateRequest.decode(body)

      service = Models::Service.where(:label => label, :provider => provider).first
      raise ServiceNotFound, "label=#{label} provider=#{provider}" unless service

      plans = service.service_plans
      instances = Models::ServiceInstance.where(:service_plan_id => plans)
      bindings = Models::ServiceBinding.where(:service_instance_id => instances)

      if instance = instances.where(:gateway_name => id).first
        instance.attributes = {
          :gateway_data => req.configuration,
          :credentials => req.credentials,
        }

        instance.save!
      elsif binding = bindings.where(:gateway_name => id).first
        binding.attributes = {
          :configuration => req.configuration,
          :credentials => req.credentials,
        }

        binding.save!
      else
        # TODO: shall we add a HandleNotFound?
        raise ServiceInstanceNotFound, "label=#{label} provider=#{provider} id=#{id}"
      end
    end

    private

    def empty_json
      "{}"
    end

    def self.legacy_api_user
      user = Models::User.find_by_guid(LEGACY_API_USER_GUID)
      if user.nil?
        user = Models::User.create(
          :guid => LEGACY_API_USER_GUID,
          :admin => true,
          :active => true,
        )
      end
      user
    end

    def self.setup_routes
      get    "/services/v1/offerings/:label_and_version/handles",               :list_handles
      get    "/services/v1/offerings/:label_and_version/:provider/handles",     :list_handles
      get    "/services/v1/offerings/:label_and_version/:provider",             :get
      get    "/services/v1/offerings/:label_and_version",                       :get
      delete "/services/v1/offerings/:label_and_version",                       :delete
      delete "/services/v1/offerings/:label_and_version/:provider",             :delete
      post   "/services/v1/offerings",                                          :create_offering
      post   "/services/v1/offerings/:label_and_version/handles/:id",           :update_handle
      post   "/services/v1/offerings/:label_and_version/:provider/handles/:id", :update_handle
    end

    def self.translate_validation_exception(e, attributes)
      Steno.logger("cc.api.legacy_svc_gw").error "#{attributes} #{e}"
      Errors::InvalidRequest.new
    end

    setup_routes
  end
end
