begin
  require "paperclip"
rescue LoadError
  puts "Mongoid::PaperclipQueue requires that you install the Paperclip gem."
  exit
end

module Mongoid::PaperclipQueue

  class Queue

    @queue = :paperclip

    def self.enqueue(klass,field,id,*parents)
      ::Resque.enqueue(self,klass,field,id,*parents)
    end
    def self.perform(klass,field,id,*parents)
      if parents.empty?
        klass = klass.constantize
      else
        p = parents.shift
        parent = p[0].constantize.find(p[2])
        parents.each do |p|
          parent = parent.send(p[1].to_sym).find(p[2])
        end
        klass = parent.send(klass.to_sym)
      end
      klass.find(id).do_reprocessing_on field
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

  def has_mongoid_attached_file(field, options = {}, &block)
    # Include Paperclip and Paperclip::Glue for compatibility
    unless self.ancestors.include?(::Paperclip)
      include ::Paperclip
      include ::Paperclip::Glue
    end

    #send :include, InstanceMethods
    include InstanceMethods

    # Invoke Paperclip's #has_attached_file method and passes in the
    # arguments specified by the user that invoked Mongoid::Paperclip#has_mongoid_attached_file
    if options[:logger].nil? && Mongoid::Config.logger.present?
      options[:logger] = Mongoid::Config.logger
    end
    has_attached_file(field, options)

    yield block if block_given?
    ##
    # Define the necessary collection fields in Mongoid for Paperclip
    field(:"#{field}_file_name", :type => String)
    field(:"#{field}_content_type", :type => String)
    field(:"#{field}_file_size", :type => Integer)
    field(:"#{field}_updated_at", :type => DateTime)
  end

  def has_queued_mongoid_attached_file(field, options = {})
    has_mongoid_attached_file(field, options) do
      # halt processing initially, but allow override for reprocess!
      self.send :"before_#{field}_post_process", :halt_processing

      define_method "#{field}_processing!" do
        true
      end

      self.send :after_save do
        if self.changed.include? "#{field}_updated_at"
          # add a Redis key for the application to check if we're still processing
          # we don't need it for the processing, it's just a helpful tool
          Mongoid::PaperclipQueue::Redis.server.sadd(self.class.name, "#{field}:#{self.id.to_s}")

          # check if the document is embedded. if so, we need that to find it later
          if self.embedded?
            parents = []
            path = self
            associations = path.reflect_on_all_associations(:embedded_in)
            until associations.empty?
              # there should only be one :embedded_in per model, correct me if I'm wrong
              association = associations.first
              path = path.send(association.name.to_sym)
              parents << [association.class_name,association.name, path.id.to_s]
              associations = path.reflect_on_all_associations(:embedded_in)

            end
            # we need the relation name, not the class name
            args = [ self.metadata.name, field, self.id.to_s] + parents.reverse
          else
            # or just use our default params like any other Paperclip model
            args = [self.class.name, field, self.id.to_s]
          end

          # then queue up our processing
          Mongoid::PaperclipQueue::Queue.enqueue(*args)
        end

      end

    end

  end

  module InstanceMethods

    def halt_processing
      false if @is_processing.nil?  # || false
    end

    def do_reprocessing_on(field)
      @is_processing=true
      self.send(field.to_sym).reprocess!
      Mongoid::PaperclipQueue::Redis.server.srem(self.class.name, "#{field}:#{self.id.to_s}")
    end

  end

end

module Paperclip

  class Attachment

    def processing?
      @instance.respond_to?(:"#{name}_processing!") && (@instance.new_record? || Mongoid::PaperclipQueue::Redis.server.sismember(@instance.class.name, "#{@name}:#{@instance.id.to_s}"))
    end

  end

end
