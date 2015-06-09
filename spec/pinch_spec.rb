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
  describe "when calling get on a compressed ZIP file" do
    it "should return the contents of the file" do
      VCR.use_cassette('squeak') do
        @url  = 'http://ftp.sunet.se/pub/lang/smalltalk/Squeak/current_stable/Squeak3.8-6665-full.zip'
        @file = 'ReadMe.txt'

        data = Pinch.get @url, @file
        data.must_match(/Morphic graphics architecture/)
        data.size.must_equal 26431
      end
    end
  end

  describe "when calling get on a ZIP file that is not compressed" do
    it "should return the contents of the file" do
      VCR.use_cassette('canabalt') do
        @url  = 'http://memention.com/ericjohnson-canabalt-ios-ef43b7d.zip'
        @file = 'ericjohnson-canabalt-ios-ef43b7d/README.TXT'

        data = Pinch.get @url, @file
        data.must_match(/Daring Escape/)
        data.size.must_equal 2288
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
        data.must_equal @data
        data.size.must_equal 114
      end
    end

    it "should yield to the block with PinchResponse object similar to HTTPResponse" do
      body = ''
      VCR.use_cassette('test_zip_with_block') do
        Pinch.get(@url, @file) do |response|
          response.must_be_kind_of PinchResponse
          response.read_body do |chunk|
            body << chunk
          end
        end
      end
      body.must_equal @data
    end

    it "should retrieve the contents of the file data.json when passed a HTTPS url" do
      VCR.use_cassette('ssl_test') do
        @url  = 'https://dl.dropboxusercontent.com/u/2230186/pinch_test.zip'

        data = Pinch.get @url, @file
        data.must_equal @data
        data.size.must_equal 114
      end
    end

    it "should contain three files" do
      VCR.use_cassette('test_file_count') do
        Pinch.file_list(@url).size.must_equal 3
      end
    end
  end

  describe "when calling get on the example ZIP file behind HTTP Basic Authentication" do
    before do
      @url  = 'http://assets.c7.se/data/pinch/auth/pinch_test.zip'
      @file = 'data.json'
      @data = "{\"gem\":\"pinch\",\"authors\":[\"Peter Hellberg\",\"Edward Patel\"],\"github_url\":\"https://github.com/peterhellberg/pinch\"}\n"
    end

    it "should retrieve the contents of the file data.json with valid authentication" do
      VCR.use_cassette('valid_basic_auth') do
        data = Pinch.get @url, @file, 'pinch_test', 'thisisjustatest'
        data.must_equal @data
        data.size.must_equal 114
      end
    end

    it "should not retrieve the contents of the file data.json with invalid authentication" do
      VCR.use_cassette('invalid_basic_auth') do
        lambda {
          Pinch.get @url, @file, 'invalid_username', 'invalid_password'
        }.must_raise Net::HTTPServerException
      end
    end
  end

  describe "Pinch.file_list" do
    it "should return a list with all the file names in the ZIP file" do
      VCR.use_cassette('file_list') do
        @url = 'http://memention.com/ericjohnson-canabalt-ios-ef43b7d.zip'

        file_list = Pinch.file_list(@url)
        file_list.size.must_equal 491
      end
    end
  end

  describe "Pinch.content_length" do
    before do
      @url  = 'http://peterhellberg.github.io/pinch/test.zip'
    end

    it "should return the size of the ZIP file" do
      VCR.use_cassette('content_length') do
        Pinch.content_length(@url).must_equal 2516612
      end
    end

    it "should raise an exception if the file doesn't exist" do
      VCR.use_cassette('content_length_404') do
        lambda {
          Pinch.content_length(@url+'404')
        }.must_raise Net::HTTPServerException
      end
    end
  end
end
