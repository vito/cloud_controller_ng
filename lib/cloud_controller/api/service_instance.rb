require 'services/api'
require 'cloud_controller/api/service_validator'

module VCAP::CloudController
  rest_controller :ServiceInstance do
    permissions_required do
      full Permissions::CFAdmin
      read Permissions::OrgManager
      full Permissions::SpaceDeveloper
      read Permissions::SpaceAuditor
    end

    define_attributes do
      attribute :name,  String
      to_one    :space
      to_one    :service_plan
      to_many   :service_bindings
      attribute :dashboard_url, String, exclude_in: [:create, :update]
    end

    query_parameters :name, :space_guid, :service_plan_guid, :service_binding_guid

    def before_create
      unless Models::ServicePlan.user_visible.exists?(
              :guid => request_attrs['service_plan_guid'])
        raise Errors::NotAuthorized
      end
    end

    def self.translate_validation_exception(e, attributes)
      name_errors = e.record.errors[:name]
      quota_errors = e.record.errors[:org]
      service_plan_errors = e.record.errors[:service_plan]

      if name_errors && name_errors.include?(:taken)
        Errors::ServiceInstanceNameTaken.new(attributes["name"])
      elsif quota_errors.include?(:free_quota_exceeded) ||
            quota_errors.include?(:trial_quota_exceeded)
        Errors::ServiceInstanceFreeQuotaExceeded.new
      elsif quota_errors.include?(:paid_quota_exceeded)
        Errors::ServiceInstancePaidQuotaExceeded.new
      elsif service_plan_errors.include?(:paid_services_not_allowed)
        Errors::ServiceInstanceServicePlanNotAllowed.new
      else
        Errors::ServiceInstanceInvalid.new(e.record.errors.full_messages)
      end
    end

    def update_instance(gateway_name)
      req = decode_message_body

      instance_handle = Models::ServiceInstance.where(:gateway_name => gateway_name).first
      raise Errors::ServiceInstanceNotFound, "gateway_name=#{gateway_name}" unless instance_handle

      plan_handle = Models::ServicePlan.find(instance_handle[:service_plan_id])
      service_handle = Models::Service.find(plan_handle[:service_id])

      ServiceValidator.validate_auth_token(req.token, service_handle)

      instance_handle.update_attributes(
        :gateway_data => req.gateway_data,
        :credentials => req.credentials)
    end

    put "/v2/service_instances/internal/:gateway_name", :update_instance
  end

  def decode_message_body
    VCAP::Services::Api::HandleUpdateRequestV2.decode(body)
  rescue
    raise Errors::InvalidRequest
  end
end
