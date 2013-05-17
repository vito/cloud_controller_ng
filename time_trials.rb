#!/usr/bin/env ruby

require 'benchmark'
require 'cfoundry'
require 'yaml'

def print_info(time, description)
  puts description
  time.each do |name, info|
    printf "%s: %02.3f total, %02.3f min, %02.3f max, %02.3f average\n",
           name.inspect, info[:total], info[:min], info[:max], info[:avg]
  end
  puts
end

def calculate_stats(iterations, timing_hash)
  timing_hash[:min] = timing_hash[:times].min
  timing_hash[:max] = timing_hash[:times].max
  timing_hash[:total] = timing_hash[:times].inject(&:+)
  timing_hash[:avg] = timing_hash[:total] / iterations
end

def request(client, params)
  client.base.get("v2", "organizations", :accept => :json, :params => CFoundry::V2::ModelMagic.params_from(params))
rescue
  $stderr.puts "request failed"
end

active_record = CFoundry::Client.new("https://api.pasadena.cf-app.com")
active_record.login("admin", "Timon0{sickeningly")
active_record.trace = ENV["TRACE"]

sequel = CFoundry::Client.new("https://api.bliss.cf-app.com")
sequel.login("admin", "ep+76WTj7fvGHdGP23D5HQ==")
sequel.trace = ENV["TRACE"]

iterations = 10

active_record_times = Hash.new { |h, k| h[k] = { :times => [] } }
sequel_times = Hash.new { |h, k| h[k] = { :times => [] } }

[0, 1, 2].each do |depth|
  iterations.times do
    mark = Benchmark.realtime do
      request active_record, :depth => depth
    end
    puts "active record run: depth => #{depth}, time: #{mark}"
    active_record_times[depth][:times] << mark
  end

  calculate_stats(iterations, active_record_times[depth])
  print_info active_record_times, "pasadena"

  iterations.times do
    mark = Benchmark.realtime do
      request sequel, :depth => depth
    end
    puts "sequel run:        depth => #{depth}, time: #{mark}"
    sequel_times[depth][:times] << mark
  end

  calculate_stats(iterations, sequel_times[depth])
  print_info sequel_times, "sequel"
end


File.open(ARGV[0] || "trials.yml", "a+") do |f|
  f.puts(YAML.dump({ :active_record => active_record_times, :sequel => sequel_times }))
  f.puts
end