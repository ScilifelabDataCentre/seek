class ExternalAsset < ActiveRecord::Base

  self.inheritance_column = 'class_type'
  attr_accessor :sync_options

  enum sync_state: [ :synchronized, :refresh, :failed ]


  belongs_to :seek_entity, polymorphic: true
  belongs_to :seek_service, polymorphic: true

  has_one :content_blob, as: :asset, dependent: :destroy

  validates :external_id, uniqueness: { scope: :external_service }
  validates :external_service, uniqueness: { scope: :external_id }

  before_save :save_content_blob
  before_save :options_to_json

  after_initialize :options_from_json



  def content=(content_object)
    json = serialize_content(content_object)
    @local_content = content_object

    self.local_content_json = json
    self.synchronized_at = DateTime.now
    self.sync_state = :synchronized
    self.external_mod_stamp = extract_mod_stamp(content_object)
    self.version = self.version ? self.version+1 : 1
  end

  def content
    synchronize_content unless synchronized?
    load_local_content unless @local_content
    @local_content
  end

  def serialize_content(content_object)
    return content_object.json if (defined? content_object.json) &&  content_object.json.is_a?(String)
    return content_object.json.to_json if (defined? content_object.json) &&  content_object.json.is_a?(Hash)
    return content_object.to_json if defined? content_object.to_json
    raise 'Not implemented json serialization for external content'
  end

  def deserialize_content(serial)
    return nil if serial.nil?
    JSON.parse serial
  end

  def load_local_content
    @local_content = deserialize_content(local_content_json)
  end

  def synchronize_content

    obj = fetch_externally
    if (obj) then
      self.content = obj
    else
      self.sync_state = :failed
    end

    save!

  end

  def fetch_externally
    raise 'Remote sync not implemented'
  end

  def extract_mod_stamp(content_object)
    return nil
  end

  def local_content_json=(content)
    raise 'Content must be a String' unless content.is_a? String
    init_content_holder
    content_blob.data = content
  end

  def local_content_json
    return nil if content_blob.nil?
    content_blob.read
  end

  def init_content_holder()
    if content_blob.nil?
      build_content_blob({
                             url: (external_service ? external_service: '') + '#' + external_id,
                             content_type: 'application/json',
                             original_filename: external_id,
                             make_local_copy: false,
                             external_link: false })
    end
  end

  def save_content_blob
    content_blob.save! unless content_blob.nil?
  end

  def options_to_json
    self.sync_options_json = @sync_options ? @sync_options.to_json : {}.to_json
  end

  def options_from_json
    @sync_options = self.sync_options_json ? JSON.parse(self.sync_options_json) : {}
  end
end
