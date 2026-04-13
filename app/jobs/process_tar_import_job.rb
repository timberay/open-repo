class ProcessTarImportJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    import = Import.find(import_id)
    import.update!(status: 'processing', progress: 10)

    begin
      ImageImportService.new.call(
        import.tar_path,
        repository_name: import.repository_name,
        tag_name: import.tag_name
      )
      import.update!(status: 'completed', progress: 100)
    rescue => e
      import.update!(status: 'failed', error_message: e.message)
      raise
    end
  end
end
