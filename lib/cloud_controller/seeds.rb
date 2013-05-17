module VCAP::CloudController
  module Seeds
    class << self
      def write_seed_data(config)
        create_seed_quota_definitions(config)
        create_seed_stacks(config)
        system_org = create_seed_organizations(config)
        create_seed_domains(config, system_org)
      end

      def create_seed_quota_definitions(config)
        config[:quota_definitions].each do |k, v|
          qd = Models::QuotaDefinition.where(:name => k.to_s).first_or_create
          qd.attributes = v
          qd.save!
        end
      end

      def create_seed_stacks(config)
        Models::Stack.populate
      end

      def create_seed_organizations(config)
        quota_definition = Models::QuotaDefinition.find_by_name("paid")

        unless quota_definition
          raise ArgumentError, "Missing 'paid' quota definition in config file"
        end

        org = Models::Organization.where(:name => config[:system_domain_organization]).first_or_create
        org.quota_definition = quota_definition
        org.save :validate => false
        org
      end

      def create_seed_domains(config, system_org)
        Models::Domain.populate_from_config(config, system_org)
      end
    end
  end
end
