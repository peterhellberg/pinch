# encoding: utf-8
require 'net/http'
require 'zlib'

class Pinch
  VERSION = "0.0.4"

  attr_reader :uri
  attr_reader :file_name

  def self.get(url, file_name)
    new(url).data(file_name)
  end

  def self.file_list(url)
    new(url).file_list
  end

  def initialize(url)
    @uri    = URI.parse(url)
    @files  = {}
  end

  def file_list
    file_headers.keys
  end

  def data(file_name)
    local_file(file_name)
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

    req = Net::HTTP::Get.new(uri.path)
    req.set_range(file_headers[file_name][16],
                  file_headers[file_name][16] +
                  file_headers[file_name][8]  +
                  file_headers[file_name][10] +
                  file_headers[file_name][11] +
                  file_headers[file_name][12] + 30)

    res = Net::HTTP.start(uri.host, uri.port) do |http|
      http.request(req)
    end


    local_file_header = res.body.unpack('VvvvvvVVVvv')
    file_data         = res.body[30+local_file_header[9]+local_file_header[10]..-1]

    if local_file_header[3] == 0
      # Uncompressed file
      offset = 30+local_file_header[9]+local_file_header[10]
      res.body[offset..(offset+local_file_header[8]-1)]
    else
      # Compressed file
      file_data = res.body[30+local_file_header[9]+local_file_header[10]..-1]
      Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(file_data)
    end
  end

  def file_headers
    @file_headers ||= begin
      raise RuntimeError, "Couldn’t find the central directory." if central_directory.nil?

      headers = {}
      tmp     = central_directory

      begin
        cd = tmp.unpack('VvvvvvvVVVvvvvvVV')
        break if cd[1] == 0

        length            = 46+cd[10]+cd[11]+cd[12]
        current_file_name = tmp[46...46+cd[10]]
        tmp               = tmp[length..-1]
        headers[current_file_name] = cd
      end while true

      headers
    end
  end

  def central_directory
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

    @central_directory ||= begin
      req = Net::HTTP::Get.new(uri.path)
      req.set_range(end_of_central_directory_record[5],
                    end_of_central_directory_record[5] +
                    end_of_central_directory_record[4])

      res = Net::HTTP.start(uri.host, uri.port) { |http|
        http.request(req)
      }

      if [200, 206].include?(res.code)
        raise RuntimeError, "Couldn’t find the ZIP file (HTTP: #{res.code})"
      else
        res.body
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
      request = Net::HTTP::Get.new(uri.path)
      offset = content_length >= 4096 ? content_length-4096 : 0

      request.set_range(offset, content_length)

      response = Net::HTTP.start(uri.host, uri.port) do |http|
        http.request(request)
      end

      # Unpack the body into a hex string
      hex = response.body.unpack("H*")[0]

      # Split on the end record signature, and unpack the last one
      [hex.split("504b0506").last].pack("H*").unpack("vvvvVVv")
    end
  end

  # Retrieve the content length of the file
  def content_length
    @content_length ||= Net::HTTP.start(@uri.host, @uri.port) { |http|
      http.head(@uri.path)
    }['Content-Length'].to_i
  end
end
