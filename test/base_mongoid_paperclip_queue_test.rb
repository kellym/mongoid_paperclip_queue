module BaseMongoidPaperclipQueueTest
  def setup
    super
  end

  def test_normal_paperclip_functioning
    Paperclip::Attachment.any_instance.expects(:post_process)
    dummy = DummyPaperclip.new(:image => File.open("#{ROOT}/test/fixtures/12k.png"))
    assert !dummy.image.processing?, "Image should not be processing"
    assert dummy.image.post_processing, "Image should have post processing"
    assert dummy.save, "Image should save"
    assert File.exists?(dummy.image.path), "Path #{dummy.image.path} should exist"
  end

  def test_mongoid_paperclip_queue_functioning
    Paperclip::Attachment.any_instance.expects(:after_image_post_process).never
    dummy = Dummy.new(:image => File.open("#{ROOT}/test/fixtures/12k.png"))
    #assert !dummy.image.post_processing
    assert dummy.save
    assert File.exists?(dummy.image.path), "Path #{dummy.image.path} should exist"
  end

  def test_enqueue_job_if_source_changed
    dummy = Dummy.new(:image => File.open("#{ROOT}/test/fixtures/12k.png"))
    dummy.image = File.open("#{RAILS_ROOT}/test/fixtures/12k.png")
    original_job_count = jobs_count
    dummy.save
    assert_equal original_job_count + 1, jobs_count
  end

  def test_processing_column_kept_intact
    Paperclip::Attachment.any_instance.stubs(:reprocess!).raises(StandardError.new('oops'))
    dummy = Dummy.new(:image => File.open("#{RAILS_ROOT}/test/fixtures/12k.png"))
    dummy.save!
    assert dummy.image.processing?
    process_jobs
    assert dummy.image.processing?
    assert dummy.reload.image.processing?
  end

  def test_processing_true_when_new_image_added
    dummy = Dummy.new(:image => File.open("#{RAILS_ROOT}/test/fixtures/12k.png"))
    assert dummy.image.processing?, "Image should be processing"
    assert dummy.new_record?, "Image should be new record"
    dummy.save!
    assert dummy.reload.image.processing?, "Image should be processing again"
  end

  def test_processed_true_when_jobs_completed
    dummy = Dummy.new(:image => File.open("#{RAILS_ROOT}/test/fixtures/12k.png"))
    dummy.save!
    process_jobs
    dummy.reload
    assert !dummy.image.processing?, "Image should no longer be processing"
  end

  def test_unprocessed_image_returns_still_processing
    # we removed missing url functionality in MongoidPaperclipQueue
    dummy = Dummy.new(:image => File.open("#{RAILS_ROOT}/test/fixtures/12k.png"))
    dummy.save!
    assert dummy.image.processing?
    process_jobs
    dummy.reload
    assert_match /\/system\/images\/#{dummy.id}\/original\/12k.png/, dummy.image.url
  end

  def test_original_url_when_no_processing_column
    dummy = DummyPaperclip.new(:image => File.open("#{RAILS_ROOT}/test/fixtures/12k.png"))
    dummy.save!
    assert_match(/\/system\/images\/#{dummy.id}\/original\/12k.png/, dummy.image.url)
  end

  def test_original_url_if_image_changed
    dummy = Dummy.new(:image => File.open("#{RAILS_ROOT}/test/fixtures/12k.png"))
    dummy.save!
    dummy.image = File.open("#{RAILS_ROOT}/test/fixtures/12k.png")
    dummy.save!
    assert dummy.image.processing?
    process_jobs
    assert_match(/system\/images\/.*original.*/, dummy.reload.image.url)
  end

  def test_should_not_blow_up_if_dsl_unused
    dummy = DummyPaperclip.new(:image => File.open("#{RAILS_ROOT}/test/fixtures/12k.png"))
    assert dummy.image.url
  end

  def test_after_callback_is_functional_for_paperclip
    DummyPaperclip.send(:define_method, :done_processing) { puts 'done' }
    DummyPaperclip.after_image_post_process :done_processing
    DummyPaperclip.any_instance.expects(:done_processing)
    dummy = DummyPaperclip.new(:image => File.open("#{RAILS_ROOT}/test/fixtures/12k.png"))
    dummy.save!
  end

  def test_embedded_queued_attachments
    embeds_dummy = EmbedsDummy.new
    embeds_dummy.dummies.build(:image => File.open("#{RAILS_ROOT}/test/fixtures/12k.png"))
    assert embeds_dummy.dummies.first.image.processing?, "Embedded document should be processing"
    embeds_dummy.save!
    process_jobs
    embeds_dummy.reload
    assert !embeds_dummy.dummies.empty?, "Embedded dummy should still exist"
    assert !embeds_dummy.dummies.first.image.processing?, "Embedded document should be done processing"
  end

end
