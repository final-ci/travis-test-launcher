#!/usr/bin/env ruby

require 'optparse'
require 'bundler/setup'
require 'travis'
require 'json'

options = {
  event_type: 'stash_push'
}
help = nil

OptionParser.new do |opts|
  opts.banner = "Usage: Builds executor"
  help = opts

  opts.on(
    "-p",
    "--payload PAYLOAD",
    "Payload containing push request, use prefix @ for payload stored in file"
  ) do |p|
    options[:payload] = p
  end

  opts.on(
    "-g",
    "--git-provider-event [GIT_PROVIDER_EVENT]",
    "Git provider, should be stash_push (default) or push, pull, api for github"
  ) do |g|
    options[:event_type] = g
  end

  opts.on_tail("-h", "--help", "Show this message") do |h|
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

user_name = payload['repository']['slug'].split('/').first
repo_name = payload['repository']['slug'].split('/').last

#payload.deep_merge!({
#  'repository' => {
#    'owner' => {
#      'name' => user_name
#    }
#  }
#});

#add some specific fields
queue_payload = {
  event_type: 'stash_push',
  credentials: {
    'login' => user_name
  },
  payload: payload,
  uuid: Travis.uuid
}

#search whether the specified user exists
user = User.where(name: user_name).first
user = User.create!(
  name: user_name,
  login: user_name,
  github_id: Time.now.to_i,
  is_admin: false,
  is_syncing: true) unless user

#search whether the specified repo exists
repository = Repository.where(
  name: payload['repository']['name'],
  url: payload['repository']['url']
).first

repository = Repository.create!(
  name: payload['repository']['name'],
  provider: 'stash',
  owner: user,
  owner_name: user.name,
  active: true,
  url: payload['repository']['url'],
  private: false) unless repository


unless repository.settings.ssh_key
  repository.settings.ssh_key = {
    descriptin: 'auto added ssh key',
    value: File.read('/home/travis/.ssh/travis')
  }
  unless repository.settings.vaild?
    STDERR.put "Cannot add repository key!"
    exit 2
  end
  repository.settings.save
end


queue_payload[:payload]['repository']['repository_id'] = repository.id

#run the service
request = Travis.service(:receive_request, user, queue_payload).run

puts
puts request.inspect

exit(request ? 0 : 1)

