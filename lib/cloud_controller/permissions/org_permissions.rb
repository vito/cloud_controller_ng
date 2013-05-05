# Copyright (c) 2009-2012 VMware Inc.

module VCAP::CloudController::Permissions
  class OrgPermissions
    include VCAP::CloudController

    def self.granted_to_via_org?(obj, user, relation)
      return false if user.nil?

      if obj.kind_of?(Models::Organization)
        obj.send(relation).include?(user)
      elsif obj.kind_of?(Models::App)
        if obj.space && obj.space.organization &&
            obj.space.organization.send(relation).exists?(user.id)
          return true
        end
      elsif !obj.new_record?
        if obj.respond_to?(:owning_organization)
          return false unless obj.owning_organization
        end

        if obj.respond_to?(:organizations) &&
            obj.organizations.any? { |o| o.send(relation).exists?(user.id) }
          return true
        end

        if obj.respond_to?(:organization) && obj.organization &&
            obj.organization.send(relation).exists?(user.id)
          return true
        end
      end
    end
  end
end
