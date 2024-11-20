# encoding: utf-8
require 'net/https'
require 'zlib'
require 'pinch_response'

# @author Peter Hellberg
# @author Edward Patel
class Pinch
  VERSION = "0.3.3"

  attr_reader :get_uri, :user, :pass

  ##
  # Retrieve a file from inside a zip file, over the network!
  #
  # @param    [String] url        Full URL to the ZIP file
  # @param    [String] file_name  Name of the file inside the ZIP archive
  # @param    [String] user       (Optional) Username for Basic Authentication
  # @param    [String] pass       (Optional) Password for Basic Authentication
  # @return   [String]            File data, ready to be displayed/saved
  # @example
  #
  #  puts Pinch.get('http://peterhellberg.github.com/pinch/test.zip', 'data.json')
  #
  def self.get(url, file_name, user = nil, pass = nil, &block)
    new(url, user, pass).get(file_name, &block)
  end

  ##
  # List of files inside the zip file
  #
  # @param    [String] url        Full URL to the ZIP file
  # @param    [String] user       (Optional) Username for Basic Authentication
  # @param    [String] pass       (Optional) Password for Basic Authentication
  # @return   [Array]             List of all the files in the ZIP archive
  # @example
  #
  #  Pinch.file_list('http://peterhellberg.github.com/pinch/test.zip').first #=> "data.json"
  #
  def self.file_list(url, user = nil, pass = nil)
    new(url, user, pass).file_list
  end

  ##
  # Initializes a new Pinch object
  #
  # @param [String or Hash] url Full URL to the ZIP file or hash with different URLs for HTTP verbs, e.g.
  #    {
  #     :head => 'my-url-signed-for-head-verb'
  #     :get => 'my-url-signed-for-get-verb'
  #    }
  # @param    [String] user       (Optional) Username for Basic Authentication
  # @param    [String] pass       (Optional) Password for Basic Authentication
  # @param    [Fixnum] redirects  (Optional) Number of redirects to follow
  # @note You might want to use Pinch.get instead.
  #
  def initialize(url, user = nil, pass = nil, redirects = 5)
    if url.respond_to? :fetch
      @get_uri  = URI.parse(url.fetch(:get))
      @head_uri = URI.parse(url.fetch(:head))
    else
      @get_uri = @head_uri = URI.parse(url)
    end

    @user      = user
    @pass      = pass
    @files     = {}
    @redirects = redirects
  end

  ##
  # Set Username and Password for Basic Authentication
  #
  # @param    [String] username   (Optional) Username for Basic Authentication
  # @param    [String] password   (Optional) Password for Basic Authentication
  # @return   [Pinch]             Returns self to support chained calls
  # @example
  #
  #  puts Pinch.new('http://code.mrgossett.com/pinch_test.zip').auth('pinch_test','thisisjustatest').get('data.json')
  #
  def auth(username, password)
    @user = username
    @pass = password

    return self
  end

  ##
  # @note You might want to use Pinch.file_list instead.
  #
  def file_list
    file_headers.keys
  end

  ##
  # @example
  #
  #  puts Pinch.new('http://peterhellberg.github.com/pinch/test.zip').get('data.json')
  #
  # @note You might want to use Pinch.get instead
  #
  def get(file_name, &block)
    local_file(file_name, &block)
  end

private

  def local_file(file_name)
    #0  uint32 localFileHeaderSignature
    #1  uint16 versionNeededToExtract
    #2  uint16 generalPurposeBitFlag
    #3  uint16 compressionMethod
    #4  uint16 fileLastModificationTime
    #5  uint16 fileLastModificationDate
    #6  uint32 CRC32
    #7  uint32 compressedSize
    #8  uint32 uncompressedSize
    #9  uint16 fileNameLength
    #10 uint16 extraFieldLength

    raise Errno::ENOENT if file_headers[file_name].nil?

    padding = 16

    offset_start = file_headers[file_name][16]
    offset_end   = 30 + padding +
                   file_headers[file_name][16] +
                   file_headers[file_name][8]  +
                   file_headers[file_name][10] +
                   file_headers[file_name][11] +
                   file_headers[file_name][12]

    if block_given?
      fetch_data(offset_start..offset_end) do |response|
        yield PinchResponse.new(response)
      end
    else
      response = fetch_data(offset_start..offset_end)

      local_file_header = response.body.unpack('VvvvvvVVVvv')
      file_data         = response.body[30+local_file_header[9]+local_file_header[10]..-1]

      if local_file_header[3] == 0
        # Uncompressed file
        offset = 30+local_file_header[9]+local_file_header[10]
        response.body[offset..(offset+local_file_header[8]-1)]
      else
        # Compressed file
        file_data = response.body[30+local_file_header[9]+local_file_header[10]..-1]
        Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(file_data)
      end
    end
  end

  def file_headers
    #0  uint32 centralDirectoryFileHeaderSignature
    #1  uint16 versionMadeBy
    #2  uint16 versionNeededToExtract
    #3  uint16 generalPurposeBitFlag
    #4  uint16 compressionMethod
    #5  uint16 fileLastModificationTime
    #6  uint16 fileLastModificationDate
    #7  uint32 CRC32
    #8  uint32 compressedSize
    #9  uint32 uncompressedSize
    #10 uint16 fileNameLength
    #11 uint16 extraFieldLength
    #12 uint16 fileCommentLength
    #13 uint16 diskNumberWhereFileStarts
    #14 uint16 internalFileAttributes
    #15 uint32 externalFileAttributes
    #16 uint32 relativeOffsetOfLocalFileHeader

    @file_headers ||= begin
      raise RuntimeError, "Couldn’t find the central directory." if central_directory.nil?

      headers = {}

      central_directory.
        unpack("H*")[0].
        split("504b0102")[1..-1].
        each do |fh|
          data        = ["504b0102#{fh}"].pack('H*')
          file_header = data.unpack('VvvvvvvVVVvvvvvVV')
          file_name   = data[46...46+file_header[10]]
          headers[file_name] = file_header
      end

      headers
    end
  end

  def central_directory
    @central_directory ||= begin
      offset_start = end_of_central_directory_record[5]
      offset_end   = end_of_central_directory_record[5] + end_of_central_directory_record[4]

      response = fetch_data(offset_start..offset_end)

      if ['200', '206'].include?(response.code)
        response.body
      else
        raise RuntimeError, "Couldn’t find the ZIP file (HTTP: #{response.code})"
      end
    end
  end

  def end_of_central_directory_record
    #0  uint16 numberOfThisDisk;
    #1  uint16 diskWhereCentralDirectoryStarts;
    #2  uint16 numberOfCentralDirectoryRecordsOnThisDisk;
    #3  uint16 totalNumberOfCentralDirectoryRecords;
    #4  uint32 sizeOfCentralDirectory;
    #5  uint32 offsetOfStartOfCentralDirectory;
    #6  uint16 ZIPfileCommentLength;

    @end_of_central_directory_record ||= begin
      # Retrieve last 4k of data from the zip file
      response = fetch_data(-4096)

      # Unpack the body into a hex string then split on
      # the end record signature, and finally unpack the last one.
      [response.body.
        unpack("H*")[0].
        split("504b0506").
        last[0...36]].
        pack("H*").
        unpack("vvvvVVv")

      # Skipping the hex unpack and splitting on
      # PK\x05\x06 instead was for some reason slower.
    end
  end

  ##
  # Get range of data from URL
  def fetch_data(range, &block)
    request = Net::HTTP::Get.new(@get_uri.request_uri)
    request.basic_auth(@user, @pass) unless @user.nil? || @pass.nil?
    request.set_range(range) if range
    connection(@get_uri).request(request, &block)
  end

  ##
  # A connection that automatically enables SSL (No verification)
  def connection(uri)
    http = Net::HTTP.new(uri.host, uri.port)

    if uri.is_a?(URI::HTTPS)
      http.use_ssl      = true
      http.verify_mode  = OpenSSL::SSL::VERIFY_NONE
    end

    http
  end

  class TooManyRedirects < StandardError; end
end
