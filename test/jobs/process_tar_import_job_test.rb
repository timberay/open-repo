require "test_helper"

class ProcessTarImportJobTest < ActiveSupport::TestCase
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
    FileUtils.rm_f(@tar_path)
  end

  # Temporarily redefine ImageImportService.new to return a fake for the block.
  def with_stubbed_service(fake_service)
    original_method = ImageImportService.singleton_class.instance_method(:new)
    ImageImportService.define_singleton_method(:new) { |*_args| fake_service }
    yield
  ensure
    ImageImportService.singleton_class.define_method(:new, original_method)
  end

  test "perform forwards actor: 'anonymous' to ImageImportService" do
    recorder = Struct.new(:args, :kwargs).new(nil, nil)
    fake_service = Class.new do
      define_method(:initialize) { |r| @recorder = r }
      define_method(:call) do |*args, **kwargs|
        @recorder.args = args
        @recorder.kwargs = kwargs
        nil
      end
    end.new(recorder)

    with_stubbed_service(fake_service) do
      ProcessTarImportJob.new.perform(@import.id)
    end

    assert_equal [ @import.tar_path ], recorder.args
    assert_equal "anonymous", recorder.kwargs[:actor]
    assert_equal @import.repository_name, recorder.kwargs[:repository_name]
    assert_equal @import.tag_name, recorder.kwargs[:tag_name]
  end

  test "perform marks import completed on success" do
    fake_service = Class.new do
      def call(*, **); end
    end.new

    with_stubbed_service(fake_service) do
      ProcessTarImportJob.new.perform(@import.id)
    end
    @import.reload
    assert_equal "completed", @import.status
    assert_equal 100, @import.progress
  end
end
