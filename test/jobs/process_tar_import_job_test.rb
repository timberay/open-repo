require "test_helper"

class ProcessTarImportJobTest < ActiveSupport::TestCase
  # Lightweight DI-compatible fake — captures every call for assertions.
  class RecordingService
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(*args, **kwargs)
      @calls << { args: args, kwargs: kwargs }
      nil
    end
  end

  setup do
    @tar_path = Rails.root.join("tmp/test-import-#{SecureRandom.hex(4)}.tar").to_s
    File.write(@tar_path, "dummy-tar-content")
    @import = Import.create!(
      tar_path: @tar_path,
      repository_name: "import-job-test-repo",
      tag_name: "v1",
      status: "pending",
      progress: 0
    )
  end

  teardown do
    FileUtils.rm_f(@tar_path) if @tar_path
  end

  test "perform with actor_email: forwards email to service as actor" do
    svc = RecordingService.new
    ProcessTarImportJob.new.perform(@import.id, actor_email: "tonny@timberay.com", service: svc)

    assert_equal 1, svc.calls.size
    call = svc.calls.first
    assert_equal [ @import.tar_path ], call[:args]
    assert_equal "tonny@timberay.com", call[:kwargs][:actor]
    assert_equal @import.repository_name, call[:kwargs][:repository_name]
    assert_equal @import.tag_name, call[:kwargs][:tag_name]
  end

  test "perform with nil actor_email falls back to 'system:import'" do
    svc = RecordingService.new
    ProcessTarImportJob.new.perform(@import.id, actor_email: nil, service: svc)

    assert_equal 1, svc.calls.size
    assert_equal "system:import", svc.calls.first[:kwargs][:actor]
  end

  test "perform marks import completed on success" do
    svc = RecordingService.new
    ProcessTarImportJob.new.perform(@import.id, service: svc)

    @import.reload
    assert_equal "completed", @import.status
    assert_equal 100, @import.progress
  end

  test "perform marks import failed and re-raises on service exception" do
    raising_svc = Class.new { def call(*, **); raise StandardError, "boom"; end }.new

    assert_raises(StandardError) do
      ProcessTarImportJob.new.perform(@import.id, service: raising_svc)
    end

    @import.reload
    assert_equal "failed", @import.status
    assert_equal "boom", @import.error_message
  end
end
