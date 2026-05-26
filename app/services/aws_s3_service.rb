class AwsS3Service
  def initialize(bucket_name)
    access_key_id = ENV['AWS_ACCESS_KEY_ID']
    secret_access_key = ENV['AWS_SECRET_ACCESS_KEY']
    region = ENV['AWS_REGION']

    @s3_client = Aws::S3::Client.new(
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
      region: region
    )
    @bucket_name = bucket_name
  end

  def upload_file(file_path, object_key)
    File.open(file_path, 'rb') do |file|
      @s3_client.put_object(bucket: @bucket_name, key: object_key, body: file)
    end
    object_key
  end

  def delete_file(object_key)
    @s3_client.delete_object(bucket: @bucket_name, key: object_key)
  end

  def get_file_url(object_key)
    signer = Aws::S3::Presigner.new(client: @s3_client)
    signer.presigned_url(:get_object, bucket: @bucket_name, key: object_key, expires_in: 1.hour.to_i)
  end

  def upload_uploaded_file(uploaded_file, prefix: 'audio_files')
    object_key = "#{prefix}/#{SecureRandom.uuid}/#{uploaded_file.original_filename}"
    upload_file(uploaded_file.path, object_key)

    {
      key: object_key,
      url: get_file_url(object_key)
    }
  end
end
