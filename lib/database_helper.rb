require 'dotenv'
Dotenv.load

require 'dedent'
require 'sequel'
require 'shellwords'
require 'uri'

Sequel.extension :migration

module Citygram
  module DatabaseHelper
    PG_ERROR = /error|fail|fatal/i
    MIGRATION_TEMPLATE = <<-TEMPLATE.dedent.freeze
      Sequel.migration do
        up do
        end

        down do
        end
      end
    TEMPLATE

    def self.environment
      ENV['RACK_ENV'] ||= 'development'
    end

    def self.database_url
      ENV['DATABASE_URL'] ||= "postgres://localhost/citygram_#{environment}"
    end

    def self.database
      @database ||= Sequel.connect(database_url)
    end

    def self.app_root
      @app_root ||= Shellwords.shellescape(File.expand_path('../../', __FILE__))
    end

    def self.migration_path
      @migration_path ||= File.join(app_root, 'db/migrations')
    end

    def self.schema_path
      @schema_path ||= File.join(app_root, 'db/schema.sql')
    end

    def self.db_name
      @db_name ||= URI(database.url).path.gsub('/', '')
    end

    def self.db_version
      database.tables.include?(:schema_info) ? database[:schema_info].first[:version].to_i : 0
    end

    def self.migrate_db(version = nil)
      if version
        Sequel::Migrator.run(database, migration_path, target: version.to_i)
      else
        Sequel::Migrator.run(database, migration_path)
      end

      schema_dump
    rescue Sequel::Migrator::Error => e
      puts e
    end

    def self.generate_migration(name)
      next_version = format('%03d', db_version + 1)
      path = "db/migrations/#{next_version}_#{name}.rb"
      File.write(path, MIGRATION_TEMPLATE+"\n")
    end

    def self.create_db
      pg_command("createdb #{db_name} -w")
    end

    def self.drop_db
      database.disconnect
      pg_command("dropdb #{db_name}")
    end

    def self.schema_dump
      `rm #{schema_path}`
      pg_command("pg_dump -i -s -x -O -f #{schema_path} #{db_name}")
    end

    def self.rollback_db(version = nil)
      previous_version = version || db_version - 1
      migrate_db(previous_version)
    end

    def self.reset
      drop_db
      create_db
      migrate_db
    end

    def self.pg_command(command)
      res = system(command)
      raise res if PG_ERROR === res
    end

    def self.console(ctx = self)
      require File.expand_path('../../app', __FILE__)
      require 'irb'
      ARGV.clear
      IRB.start
    end
  end
end
