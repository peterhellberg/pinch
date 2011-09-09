# encoding: utf-8
require 'net/https'
require 'zlib'

# @author Peter Hellberg
# @author Edward Patel
class Pinch
  VERSION = "0.2.1"

  attr_reader :uri

  ##
  # Retrieve a file from inside a zip file, over the network!
  #
  # @param    [String] url        Full URL to the ZIP file
  # @param    [String] file_name  Name of the file inside the ZIP archive
  # @return   [String]            File data, ready to be displayed/saved
  # @example
  #
  #  puts Pinch.get('http://peterhellberg.github.com/pinch/test.zip', 'data.json')
  #
  def self.get(url, file_name)
    new(url).get(file_name)
  end

  ##
  # List of files inside the zip file
  #
  # @param    [String] url        Full URL to the ZIP file
  # @return   [Array]             List of all the files in the ZIP archive
  # @example
  #
  #  Pinch.file_list('http://peterhellberg.github.com/pinch/test.zip').first #=> "data.json"
  #
  def self.file_list(url)
    new(url).file_list
  end

  ##
  # Retrieve the size of the ZIP file
  #
  # @param    [String] url        Full URL to the ZIP file
  # @return   [Fixnum]            Size of the ZIP file
  # @example
  #
  #  Pinch.content_length('http://peterhellberg.github.com/pinch/test.zip') #=> 2516612
  #
  def self.content_length(url)
    new(url).content_length
  end

  ##
  # Initializes a new Pinch object
  #
  # @param    [String] url        Full URL to the ZIP file
  # @param    [Fixnum] redirects  (Optional) Number of redirects to follow
  # @note You might want to use Pinch.get instead.
  #
  def initialize(url, redirects = 5)
    @uri       = URI.parse(url)
    @files     = {}
    @redirects = redirects
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
  def get(file_name)
    local_file(file_name)
  end

  ##
  # @note You might want to use Pinch.content_length instead
  #
  def content_length
    @content_length ||= begin
      response = connection(@uri).start { |http|
        http.head(@uri.path)
      }

      # Raise exception if the response code isn’t in the 2xx range
      response.error! unless response.kind_of?(Net::HTTPSuccess)

      # Raise exception if the server doesn’t support the Range header
      unless (response['Accept-Ranges'] or "").include?('bytes')
        raise RangeHeaderException,
              "Range HTTP header not supported on #{@uri.host}"
      end

      response['Content-Length'].to_i
    rescue Net::HTTPRetriableError => e
      @uri = URI.parse(e.response['Location'])

      if (@redirects -= 1) > 0
        retry
      else
        raise TooManyRedirects, "Gave up at on #{@uri.host}"
      end
    end
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

    response = fetch_data(offset_start, offset_end)

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

      response = fetch_data(offset_start, offset_end)

      if [200, 206].include?(response.code)
        raise RuntimeError, "Couldn’t find the ZIP file (HTTP: #{response.code})"
      else
        response.body
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
      # Retrieve a 4k of data from the end of the zip file
      offset = content_length >= 4096 ? content_length-4096 : 0

      response = fetch_data(offset, content_length)

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
  def fetch_data(offset_start, offset_end)
    request = Net::HTTP::Get.new(@uri.request_uri)
    request.set_range(offset_start, offset_end)
    connection(@uri).request(request)
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

  class RangeHeaderException < StandardError; end
  class TooManyRedirects < StandardError; end
end
