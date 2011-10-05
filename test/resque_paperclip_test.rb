require 'test_helper'
require 'base_mongoid_paperclip_queue_test'
require 'resque'

class ResquePaperclipTest < Test::Unit::TestCase
  include BaseMongoidPaperclipQueueTest

  def setup
    super
    # Make sure that we just test Resque in here
    Resque.remove_queue(:paperclip)
  end

  def process_jobs
    worker = Resque::Worker.new(:paperclip)
    worker.process
  end

  def jobs_count
    Resque.size(:paperclip)
  end

  def test_perform_job
    dummy = Dummy.new(:image => File.open("#{RAILS_ROOT}/test/fixtures/12k.png"))
    dummy.image = File.open("#{RAILS_ROOT}/test/fixtures/12k.png")
    Paperclip::Attachment.any_instance.expects(:reprocess!)
    dummy.save!
    Mongoid::PaperclipQueue::Queue.perform(dummy.class.name, :image, dummy.id)
  end

end
