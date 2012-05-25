# This class only implements read_body
# The rest can be implemented when required
class PinchResponse
  def initialize(http_response)
    @http_response = http_response
    @zstream = Zlib::Inflate.new(-Zlib::MAX_WBITS)
    @first_chunk = true
  end

  def read_body
    if block_given?
      @http_response.read_body do |chunk|
        if @first_chunk
          local_file_header = chunk.unpack('VvvvvvVVVvv')
          @offset_start = 30+local_file_header[9]+local_file_header[10]
          @compressed = (local_file_header[3] != 0)
          @length = @compressed ? local_file_header[7] : local_file_header[8]

          @cursor_start = @offset_start
          @to_be_read = @length
          @first_chunk = false
        end

        cursor_start = [@cursor_start, 0].max
        cursor_end   = [@to_be_read, chunk.length].min
        data = chunk[cursor_start, cursor_end]
        @cursor_start -= chunk.length

        if data
          @to_be_read -= data.length
          if @compressed
            yield @zstream.inflate(data)
          else
            yield data
          end
        end
      end
    else
      @zstream.inflate @http_response.read_body
    end
  end
end
