module TwitterCluster
  class Logger
    extend Forwardable
    def_delegators :@logger, :debug, :info, :warn, :error, :fatal, :level

    def initialize(options = {})
      path = options[:log_dir] || File.join('log')
      FileUtils.mkdir_p(path) unless File.exists?(path)

      @logger = ::Logger.new(File.join(path, 'twitter_cluster.log'))
      @logger.level = options[:log_level] || :debug
    end
  end
end