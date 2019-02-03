require "twitter_cluster/version"
require "twitter_cluster/logger"
require "twitter_cluster/hash_tag"
require "twitter_cluster/list"
require "twitter_cluster/tweet"

module TwitterCluster
  module_function

  def list_clusters(*args, &block)
    options = extract_options(args)
    options[:client] = api_client unless options[:client]
    ListCluster.new(Logger.new).list_clusters(*args, options, &block)
  end

  def api_client
    TwitterFriendly::Client.new(
        consumer_key: ENV['CK'],
        consumer_secret: ENV['CS'],
        access_token: ENV['AT'],
        access_token_secret: ENV['ATS']
    )
  end

  def extract_options(args)
    if args.last.is_a?(Hash)
      args.pop
    else
      {}
    end
  end

  class Error < StandardError; end
end
