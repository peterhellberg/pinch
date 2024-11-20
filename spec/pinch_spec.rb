# encoding: utf-8

# Require psych under MRI to remove warning messages
if Object.const_defined?(:RUBY_ENGINE) && RUBY_ENGINE == "ruby"
  begin
    require 'psych'
  rescue LoadError
    # Psych isn’t installed
  end
end

begin
  gem 'minitest'
rescue LoadError
  # Run the tests with the built in minitest instead
  # if the gem isn’t installed.
end

require 'minitest/pride'
require 'minitest/autorun'
require 'minitest/spec'
require 'vcr'

VCR.configure do |c|
  c.allow_http_connections_when_no_cassette = true
  c.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  c.hook_into :webmock
end

require File.dirname(__FILE__) + '/../lib/pinch'

describe Pinch do
  describe "when calling get on a ZIP file that is not compressed" do
    it "should return the contents of the file" do
      VCR.use_cassette('canabalt') do
        @url  = 'http://memention.com/ericjohnson-canabalt-ios-ef43b7d.zip'
        @file = 'ericjohnson-canabalt-ios-ef43b7d/README.TXT'

        data = Pinch.get @url, @file
        assert_match(/Daring Escape/, data)
        assert_equal(2288, data.size)
      end
    end
  end

  describe "when calling get on the example ZIP file" do
    before do
      @url  = 'http://peterhellberg.github.io/pinch/test.zip'
      @file = 'data.json'
      @data = "{\"gem\":\"pinch\",\"authors\":[\"Peter Hellberg\",\"Edward Patel\"],\"github_url\":\"https://github.com/peterhellberg/pinch\"}\n"
    end

    it "should retrieve the contents of the file data.json" do
      VCR.use_cassette('test_zip') do
        data = Pinch.get @url, @file
        assert_equal @data, data
        assert_equal 114, data.size
      end
    end

    it "should yield to the block with PinchResponse object similar to HTTPResponse" do
      body = ''
      VCR.use_cassette('test_zip_with_block') do
        Pinch.get(@url, @file) do |response|
          assert_kind_of PinchResponse, response
          response.read_body do |chunk|
            body << chunk
          end
        end
      end
      assert_equal @data, body
    end

    it "should retrieve the contents of the file data.json when passed a HTTPS url" do
      VCR.use_cassette('ssl_test') do
        @url  = 'https://peterhellberg.github.io/pinch/test.zip'

        data = Pinch.get @url, @file
        assert_equal @data, data
        assert_equal 114, data.size
      end
    end

    it "should contain three files" do
      VCR.use_cassette('test_file_count') do
        assert_equal 3, Pinch.file_list(@url).size
      end
    end
  end

  # This location is no longer protected by basic auth.
  #
  # describe "when calling get on the example ZIP file behind HTTP Basic Authentication" do
  #   before do
  #     @url  = 'https://assets.c7.se/data/pinch/auth/pinch_test.zip'
  #     @file = 'data.json'
  #     @data = "{\"gem\":\"pinch\",\"authors\":[\"Peter Hellberg\",\"Edward Patel\"],\"github_url\":\"https://github.com/peterhellberg/pinch\"}\n"
  #   end

  #   it "should retrieve the contents of the file data.json with valid authentication" do
  #     VCR.use_cassette('valid_basic_auth') do
  #       data = Pinch.get @url, @file, 'pinch_test', 'thisisjustatest'
  #       assert_equal @data, data
  #       assert_equal 114, data.size
  #     end
  #   end

  #   it "should not retrieve the contents of the file data.json with invalid authentication" do
  #     VCR.use_cassette('invalid_basic_auth') do
  #       assert_raises(Net::HTTPClientException) do
  #         Pinch.get @url, @file, 'invalid_username', 'invalid_password'
  #       end
  #     end
  #   end
  # end

  describe "Pinch.file_list" do
    it "should return a list with all the file names in the ZIP file" do
      VCR.use_cassette('file_list') do
        @url = 'http://memention.com/ericjohnson-canabalt-ios-ef43b7d.zip'

        file_list = Pinch.file_list(@url)
        assert_equal 491, file_list.size
      end
    end
  end
end
