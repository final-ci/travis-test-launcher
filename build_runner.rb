#!/usr/bin/env ruby

require 'optparse'
require 'bundler/setup'
require 'travis'
require 'json'

options = {}
help = nil

OptionParser.new do |opts|
  opts.banner = "Usage: Builds executor"
  help = opts

  opts.on("-p PAYLOAD", "--payload PAYLOAD", "Payload to be sent to the worker via rabbitmq") do |p|
    options[:payload] = p
  end

  opts.on("-h", "--help", "Show this message") do |h|
    puts opts
    exit
  end

end.parse!

unless options[:payload]
  puts "Wrong aruments:\n\n";
  puts help
  exit
end

if options[:payload][0] == '@'
  payload_file = options[:payload][1..-1]
  options[:payload] = File.read(payload_file)
end


Travis::Database.connect

payload = JSON.parse(options[:payload]).to_hash

#add some specific fields
payload.deep_merge!({
  'uuid' => Travis.uuid,
  'credentials' => {
    'login' => 'travis'
  },
  'payload' => {
    'repository' => {
      'owner' => {
        'name' =>'travis',
        'email' =>'travis@example.com'
      }
    }
  }})

#search whether the specified user exists
user = User.where(name: "travis").first
user = User.create(name: "travis", login: "travis", github_id: "1113", is_admin: false, is_syncing: true) unless user

#search whether the specified repo exists
repository = Repository.where(name: payload['payload']['repository']['name'], url: payload['payload']['repository']['url']).first
repository = Repository.create(
  name: payload['payload']['repository']['name'],
  provider: 'stash',
  owner: user,
  owner_name: user.name,
  active: true,
  url: payload['payload']['repository']['url'],
  private: false) unless repository

#run the service
request = Travis.service(:receive_request, user, payload).run

puts request.inspect

exit(request.persisted? ? 0 : 1)

