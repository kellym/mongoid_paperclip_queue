require 'rubygems'
require 'test/unit'
require 'mocha'
require 'mongoid'
require 'logger'
require 'paperclip/railtie'
require 'resque_unit'
#require 'redis-namespace'

#Paperclip::Railtie.insert

ROOT       = File.join(File.dirname(__FILE__), '..')
RAILS_ROOT = ROOT
$LOAD_PATH << File.join(ROOT, 'lib')

REDIS_PID = "#{ROOT}/test/tmp/redis-test.pid"
REDIS_CACHE_PATH = "#{ROOT}/test/tmp/cache/"

require 'mongoid_paperclip_queue'

class Test::Unit::TestCase
  def setup
    silence_warnings do
      Object.const_set(:Rails, stub('Rails', :root => ROOT, :env => 'test'))
    end

    redis_options = {
      "daemonize"     => 'yes',
      "pidfile"       => REDIS_PID,
      "port"          => 9736,
      "timeout"       => 300,
      "save 900"      => 1,
      "save 300"      => 1,
      "save 60"       => 10000,
      "dbfilename"    => "dump.rdb",
      "dir"           => REDIS_CACHE_PATH,
      "loglevel"      => "debug",
      "logfile"       => "stdout",
      "databases"     => 16
    }.map { |k, v| "#{k} #{v}" }.join('\n')
    `echo '#{redis_options}' | redis-server -`
  
  end
  
  def teardown
    %x{
      cat #{REDIS_PID} | xargs kill -QUIT
      rm -f #{REDIS_CACHE_PATH}dump.rdb
    }
  end

end

  
  
FIXTURES_DIR = File.join(File.dirname(__FILE__), "fixtures")
Mongoid.configure do |config|
  config.master = Mongo::Connection.new.db("mongoid_paperclip_queue_test")
end
Mongoid.logger = Logger.new(File.dirname(__FILE__) + "/debug.log")

class EmbedsDummy
  
  include Mongoid::Document  
  embeds_many :dummies, cascade_callbacks: true
  
end

class DummyPaperclip
  include Mongoid::Document
  include Paperclip::Glue
  field(:image_file_name, :type => String)
  field(:image_content_type, :type => String)
  field(:image_file_size, :type => Integer)
  field(:image_updated_at, :type => DateTime)
            
  has_attached_file :image
end

class Dummy
  include Mongoid::Document
  extend Mongoid::PaperclipQueue
  has_queued_attached_file :image
end

