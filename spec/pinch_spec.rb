require 'minitest/pride'
require 'minitest/autorun'
require 'minitest/spec'

require File.dirname(__FILE__) + '/../lib/pinch'

describe Pinch do
  describe "when calling get on a compressed zip file" do
    before do
      @url  = 'http://ftp.sunet.se/pub/lang/smalltalk/Squeak/current_stable/Squeak3.8-6665-full.zip'
      @file = 'ReadMe.txt'
    end

    it "should return the contents of the file" do
      data = Pinch.get @url, @file
      data.must_match /Morphic graphics architecture/
      data.size.must_equal 26424
    end
  end

  describe "when calling get on a zip file that is not compressed" do
    before do
      @url  = 'http://memention.com/ericjohnson-canabalt-ios-ef43b7d.zip'
      @file = 'ericjohnson-canabalt-ios-ef43b7d/README.TXT'
    end

    it "should return the contents of the file" do
      data = Pinch.get @url, @file
      data.must_match /Daring Escape/
      data.size.must_equal 2288
    end
  end

  describe "#file_list" do
    before do
      @url = 'http://memention.com/ericjohnson-canabalt-ios-ef43b7d.zip'
    end

    it "should return a list with all the file names in the zip" do
      file_list = Pinch.file_list(@url)
      file_list.size.must_equal 491
    end
  end
end
