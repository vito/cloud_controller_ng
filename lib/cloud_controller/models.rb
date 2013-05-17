# Copyright (c) 2009-2012 VMware, Inc.

require "active_record"

ActiveModel::Errors.class_eval do
  # disable I18n
  def normalize_message(attribute, message, options)
    message
  end
end

module VCAP::CloudController::Models; end

require "cloud_controller/active_record/guid"
require "cloud_controller/active_record/relationships"

#require "sequel_plugins/vcap_validations"
require "sequel_plugins/vcap_serialization"
require "sequel_plugins/vcap_normalization"
#require "sequel_plugins/vcap_relations"
#require "sequel_plugins/update_or_create"

module VCAP::ModelUserGroups
  module ClassMethods
    def define_user_group(name, opts = {})
      opts = opts.merge(
        :class => "VCAP::CloudController::Models::User",
        :foreign_key => "user_id"
      )

      has_many name, :through => :"#{table_name}_#{name}"
    end
  end

  ActiveRecord::Base.class_eval do
    extend(ClassMethods)
  end
end

module VCAP::ModelVisibility
  module InstanceMethods
    def user_visible_relationship_dataset(name)
      associated_model = self.class.reflections[name].klass
      associated_model.user_visible(send(name))
    end
  end

  module ClassMethods
    def eager_load_associations
      []
    end

    def user_visible(set = self)
      if VCAP::CloudController::SecurityContext.current_user_is_admin?
        set.scoped
      elsif user = VCAP::CloudController::SecurityContext.current_user
        user_visibility_filter(user, set)
      else
        set.where(:id => nil)
      end.includes(set.eager_load_associations)
    end

    # overridden by models
    def user_visibility_filter(user, set = self)
      set.scoped
    end
  end

  ActiveRecord::Base.class_eval do
    extend(ClassMethods)
    include(InstanceMethods)
  end
end

module VCAP::CloudController::Models
  class InvalidRelation < StandardError; end
end

#Sequel::Model.plugin :vcap_validations
#Sequel::Model.plugin :vcap_serialization
#Sequel::Model.plugin :vcap_normalization
#Sequel::Model.plugin :vcap_relations
#Sequel::Model.plugin :vcap_guid
#Sequel::Model.plugin :vcap_user_group
#Sequel::Model.plugin :vcap_user_visibility
#Sequel::Model.plugin :update_or_create

#Sequel::Model.plugin :typecast_on_load,
                     #:name, :label, :provider, :description, :host

require "cloud_controller/models/billing_event"
require "cloud_controller/models/organization_start_event"
require "cloud_controller/models/app_start_event"
require "cloud_controller/models/app_stop_event"
require "cloud_controller/models/app_event"
require "cloud_controller/models/service_base_event"
require "cloud_controller/models/service_create_event"
require "cloud_controller/models/service_delete_event"

require "cloud_controller/models/app"
require "cloud_controller/models/domain"
require "cloud_controller/models/organization"
require "cloud_controller/models/route"
require "cloud_controller/models/service"
require "cloud_controller/models/service_auth_token"
require "cloud_controller/models/service_binding"
require "cloud_controller/models/service_instance"
require "cloud_controller/models/service_plan"
require "cloud_controller/models/space"
require "cloud_controller/models/stack"
require "cloud_controller/models/user"

require "cloud_controller/models/quota_definition"
