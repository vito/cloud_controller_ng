# Copyright (c) 2009-2012 VMware, Inc.

require "active_record"

require "vcap/sequel_varz"

module VCAP::CloudController
  class DB
    # Setup a Sequel connection pool
    #
    # @param [Logger]  Logger to pass to Sequel
    #
    # @option opts [String]  :database Database connection string
    #
    # @option opts [Symbol]  :log_level Sval, teno log level
    #
    # @option opts  [Integer] :max_connections The maximum number of
    # connections the connection pool will open (default 4)
    #
    # @option opts [Integer]  :pool_timeout The amount of seconds to wait to
    # acquire a connection before raising a PoolTimeoutError (default 5)
    #
    # @return [Sequel::Database]
    def self.connect(logger, opts)
      return ActiveRecord::Base.connection if ActiveRecord::Base.connected?

      connection_options = { :sql_mode => [:strict_trans_tables, :strict_all_tables, :no_zero_in_date] }
      [:max_connections, :pool_timeout].each do |key|
        connection_options[key] = opts[key] if opts[key]
      end

      using_sqlite = opts[:database] =~ /^sqlite:/

      db = ActiveRecord::Base.establish_connection(opts[:database])

      ActiveRecord::Base.logger = logger
      # TODO: db.sql_log_level = opts[:log_level] || :debug2

      #if db.database_type == :mysql
        #Sequel::MySQL.default_collate = "latin1_general_cs"
      #end

      validate_sqlite_version(db) if using_sqlite

      VCAP::SequelVarz.start(db)

      ActiveRecord::Base.connection
    end

    # Apply migrations to a database
    #
    # @param [Sequel::Database]  Database to apply migrations to
    def self.apply_migrations(db)
      migrations_dir = File.expand_path("../../../db/migrations", __FILE__)
      ActiveRecord::Migration.verbose = false
      ActiveRecord::Migrator.up(migrations_dir)
    end

    private

    def self.validate_sqlite_version(db)
      return if @validated_sqlite
      @validate_sqlite = true

      min_version = "3.6.19"
      version = db.fetch("SELECT sqlite_version()").first[:"sqlite_version()"]
      unless validate_version_string(min_version, version)
        puts <<EOF
The CC models require sqlite version >= #{min_version} but you are
running #{version} On OSX, you will might to install the sqlite
gem against an upgraded sqlite (from source, homebrew, macports, etc)
and not the system sqlite. You can do so with a command
such as:

  gem install sqlite3 -- --with-sqlite3-include=/usr/local/include/ \
                         --with-sqlite3-lib=/usr/local/lib

EOF
        exit 1
      end
    end

    def self.validate_version_string(min_version, version)
      min_fields = min_version.split(".").map { |v| v.to_i }
      ver_fields = version.split(".").map { |v| v.to_i }

      (0..2).each do |i|
        return true  if ver_fields[i] > min_fields[i]
        return false if ver_fields[i] < min_fields[i]
      end

      return true
    end
  end
end

#Sequel.extension :pagination
#Sequel.extension :inflector
#Sequel::Model.raise_on_typecast_failure = false

#Sequel::Model.plugin :association_dependencies
#Sequel::Model.plugin :dirty
#Sequel::Model.plugin :timestamps
#Sequel::Model.plugin :validation_helpers

# monkey patch sequel to make it easier to map validation failures to custom
# exceptions, e.g.
#
# rescue Sequel::ValidationFailed => e
#   if e.errors.on(:some_attribute).include(:unique)
#     ...
#
#Sequel::Plugins::ValidationHelpers::DEFAULT_OPTIONS.each do |k, v|
  #Sequel::Plugins::ValidationHelpers::DEFAULT_OPTIONS[k][:message] = k
#end

# Helper to create migrations.  This was added because
# I wanted to add an index to all the Timestamps so that
# we can enumerate by :created_at.
#
# TODO: decide on a better way of mixing this in to whatever
# context Sequel.migration is running in so that we can call
# the migration methods.
module VCAP
  module Migration
    def self.timestamps(migration)
      migration.Timestamp :created_at, :null => false
      migration.Timestamp :updated_at

      migration.index :created_at
      migration.index :updated_at
    end

    def self.common(migration)
      migration.primary_key :id
      guid(migration)
      timestamps(migration)
    end

    def self.model(migration, table)
      migration.create_table(table) do |t|
        t.string :guid, :null => false

        t.timestamps

        yield t
      end

      migration.add_index(table, :guid, :unique => true)
    end

    def self.create_permission_table(migration, name, permission)
      name = name.to_s
      join_table = "#{name.pluralize}_#{permission}".to_sym

      migration.create_table(join_table) do |t|
        t.references name
        t.references :user
      end

      migration.add_index join_table, [:"#{name}_id", :user_id],
        :unique => true,
        :name => "index_#{join_table}"
    end
  end
end
