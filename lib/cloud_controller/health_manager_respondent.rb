# Copyright (c) 2009-2012 VMware, Inc.

require "steno"

require File.expand_path("../message_bus.rb", __FILE__)
require File.expand_path("../dea/dea_client", __FILE__)

module VCAP::CloudController
  class << self
    attr_accessor :health_manager_respondent
  end

  class HealthManagerRespondent
    attr_reader :logger, :config
    attr_reader :message_bus, :dea_client

    # Semantically there should only be one such thing, although
    # I'm hesitant about making singletons
    # - Jesse
    def initialize(config)
      @logger = config.fetch(:logger, Steno.logger("cc.hm"))
      @dea_client = config.fetch(:dea_client, DeaClient)
      @message_bus = dea_client.message_bus

      @config = config

      subject = "cloudcontrollers.hm.requests.#{config[:cc_partition]}"
      message_bus.subscribe(subject, :queue => "cc") do |decoded_msg|
        process_hm_request(decoded_msg)
      end
    end

    # @param [Hash] payload the decoded request message
    def process_hm_request(payload)
      logger.debug("hm request: #{payload.inspect}")
      case payload[:op]
      when "START"
        process_hm_start(payload)
      when "STOP"
        process_hm_stop(payload)
      when "SPINDOWN"
        process_hm_spindown(payload)
      else
        logger.warn("Unknown operated requested: #{payload[:op]}, payload: #{payload.inspect}")
      end
    end

    private
    def process_hm_start(payload)
      # TODO: Ideally we should validate the message here with Membrane
      begin
        app_id = payload.fetch(:droplet)
        indices = payload.fetch(:indices)
        last_updated = payload.fetch(:last_updated).to_i
        version = payload.fetch(:version)
      rescue KeyError => e
        logger.error("Malformed start request: #{payload}, #{e.message}")
        return
      end

      app = Models::App.find_by_guid(app_id)

      return unless app
      return unless app.started?
      return unless version == app.version
      return unless last_updated == app.updated_at.to_i

      message_override = {}
      if payload[:flapping]
        message_override[:flapping] = true
      end
      dea_client.start_instances_with_message(app, indices, message_override)
    end

    def process_hm_stop(payload)
      # TODO: Ideally we should validate the message here with Membrane
      begin
        app_id = payload.fetch(:droplet)
        indices = payload.fetch(:instances)
        last_updated = payload.fetch(:last_updated).to_i
      rescue KeyError => e
        logger.error("Malformed stop request: #{payload}, #{e.message}")
        return
      end

      app = Models::App.find_by_guid(app_id)

      return if stop_runway_app(app, app_id)
      return if last_updated != app.updated_at.to_i
      return if hm_sent_wrong_command(app, indices)

      dea_client.stop_instances(app, indices)
    end

    def process_hm_spindown(payload)
      # TODO: Ideally we should validate the message here with Membrane
      begin
        app_id = payload.fetch(:droplet)
      rescue KeyError => e
        logger.error("Malformed spindown request: #{payload}, #{e.message}")
        return
      end

      app = Models::App.find_by_guid(app_id)

      return if stop_runway_app(app, app_id)

      stop_app(app)
    end

    def stop_app(app)
      dea_client.stop(app) unless app.stopped?
    end

    def stop_runway_app(app, app_id)
      unless app
        dea_client.stop(Models::App.new(:guid => app_id))
        true
      end
    end

    def hm_sent_wrong_command(app, indices)
      instances_remaining = app.instances - indices.size
      if instances_remaining <= 0
        stop_app(app)
        logger.error(
          instances_remaining == 0 ?
            "HM scales down to 0 -- should have sent a SPINDOWN request" :
            "HM scaling down to negative number of instances"
        )
        true
      end
    end
  end
end
