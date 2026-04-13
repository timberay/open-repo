class PrepareExportJob < ApplicationJob
  queue_as :default

  def perform(export_id)
    export = Export.find(export_id)
    export.update!(status: 'processing')

    begin
      output_path = File.join(
        Rails.configuration.storage_path, 'tmp', 'exports', "#{export.id}.tar"
      )
      FileUtils.mkdir_p(File.dirname(output_path))

      ImageExportService.new.call(
        export.repository.name,
        export.tag_name,
        output_path: output_path
      )

      export.update!(status: 'completed', output_path: output_path)
    rescue => e
      export.update!(status: 'failed', error_message: e.message)
      raise
    end
  end
end
