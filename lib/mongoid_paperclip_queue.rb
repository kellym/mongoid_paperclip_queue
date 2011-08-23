
begin
  require "paperclip"
rescue LoadError
  puts "Mongoid::PaperclipQueue requires that you install the Paperclip gem."
  exit
end

module Mongoid::PaperclipQueue
  
    class Queue
      
      @queue = :paperclip
      
      def self.enqueue(klass,field,id)
        ::Resque.enqueue(self,klass,field,id)
      end
      def self.perform(klass,field,id)
        klass.constantize.find(id).do_reprocessing_on field
      end
       
    end
    
    module Redis
      def server=(srv)
        case srv
        when String
          if srv =~ /redis\:\/\//
            server = ::Redis.connect(:url => srv, :thread_safe => true)
          else
            srv, namespace = srv.split('/', 2)
            host, port, db = srv.split(':')
            server = ::Redis.new(:host => host, :port => port,
              :thread_safe => true, :db => db)
          end
          namespace ||= :delayed
      
          @server = ::Redis::Namespace.new(namespace, :redis => redis)
        when ::Redis::Namespace
          @server = srv
        else
          @server = ::Redis::Namespace.new(:delayed, :redis => srv)
        end
      end
      
      def server
        return @server if @server
        self.server = ::Redis.respond_to?(:connect) ? ::Redis.connect : "localhost:6379"
        self.server
      end        
      extend self
    end
    
    def has_queued_attached_file(field, options = {})


      # Include Paperclip and Paperclip::Glue for compatibility
      unless self.ancestors.include?(::Paperclip)
        include ::Paperclip
        include ::Paperclip::Glue
      end
      
      include InstanceMethods
      

      # Invoke Paperclip's #has_attached_file method and passes in the
      # arguments specified by the user that invoked Mongoid::Paperclip#has_mongoid_attached_file
      if options[:logger].nil? && Mongoid::Config.logger.present?
        options[:logger] = Mongoid::Config.logger
      end
      has_attached_file(field, options)
      
      # halt processing initially, but allow override for reprocess!
      self.send :"before_#{field}_post_process", :halt_processing
      
      self.send :after_save do
        if self.changed.include? "#{field}_updated_at"
          # add a Redis key for the application to check if we're still processing
          # we don't need it for the processing, it's just a helpful tool
          Mongoid::PaperclipQueue::Redis.server.sadd(self.class.name, "#{field}:#{self.id}")
          
          # then queue up our processing
          Mongoid::PaperclipQueue::Queue.enqueue(self.class.name, field, self.id)
        end
      end
 
      ## 
      # Define the necessary collection fields in Mongoid for Paperclip
      field(:"#{field}_file_name", :type => String)
      field(:"#{field}_content_type", :type => String)
      field(:"#{field}_file_size", :type => Integer)
      field(:"#{field}_updated_at", :type => DateTime)
    end  

    module InstanceMethods
      
      def halt_processing
        @is_processing || false
      end
            
      def do_reprocessing_on(field)
        @is_processing=true
        self.send(field.to_sym).reprocess!
        Mongoid::PaperclipQueue::Redis.server.srem(self.class.name, "#{field}:#{self.id}")
      end
            
    end
end
module Paperclip
  class Attachment
    def processing?
      @instance.new_record? || Mongoid::PaperclipQueue::Redis.server.sismember(@instance.class.name, "#{@name}:#{@instance.id}")
    end    
  end
end