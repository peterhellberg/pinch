require 'minitest/pride'
require 'minitest/autorun'
require 'minitest/spec'

require File.dirname(__FILE__) + '/../lib/pinch'

describe Pinch do
  describe "when calling get" do
    it "should return the contents of the file" do
      url  = 'http://ftp.sunet.se/pub/lang/smalltalk/Squeak/current_stable/Squeak3.8-6665-full.zip'
      file = 'ReadMe.txt'
      data = Pinch.get url, file
      data.must_match /Morphic graphics architecture/
    end

    it "should not pinch from a zip file that is not deflated (for now)" do
      lambda {
        url  = 'http://memention.com/ericjohnson-canabalt-ios-ef43b7d.zip'
        file = 'ericjohnson-canabalt-ios-ef43b7d/README.TXT'
        data = Pinch.get url, file
      }.must_raise NotImplementedError
    end
  end
end
