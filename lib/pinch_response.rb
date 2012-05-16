# This class only implements read_body
# The rest can be implemented when required
class PinchResponse
  def initialize(http_response)
    @http_response = http_response
    @zstream = Zlib::Inflate.new(-Zlib::MAX_WBITS)
  end

  def read_body(dest=nil)
    if block_given?
      @http_response.read_body(dest) do |chunk|
        yield @zstream.inflate(chunk)
      end
    elsif dest
      dest << @zstream.inflate(@http_response.read_body)
    else
      @zstream.inflate @http_response.read_body
    end
  end
end
