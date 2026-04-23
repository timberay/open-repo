require "test_helper"

class DigestCalculatorTest < ActiveSupport::TestCase
  test "compute computes sha256 digest of a string" do
    digest = DigestCalculator.compute("hello world")
    assert_equal "sha256:#{Digest::SHA256.hexdigest("hello world")}", digest
  end

  test "compute computes sha256 digest of an IO stream" do
    io = StringIO.new("hello world")
    digest = DigestCalculator.compute(io)
    assert_equal "sha256:#{Digest::SHA256.hexdigest("hello world")}", digest
  end

  test "compute computes sha256 digest of a file" do
    Tempfile.create("test") do |f|
      f.write("hello world")
      f.rewind
      digest = DigestCalculator.compute(f)
      assert_equal "sha256:#{Digest::SHA256.hexdigest("hello world")}", digest
    end
  end

  test "compute handles large data in chunks" do
    large_data = SecureRandom.random_bytes(1024 * 1024)
    io = StringIO.new(large_data)
    digest = DigestCalculator.compute(io)
    assert_equal "sha256:#{Digest::SHA256.hexdigest(large_data)}", digest
  end

  test "verify! passes when digest matches" do
    data = "hello world"
    expected = "sha256:#{Digest::SHA256.hexdigest(data)}"
    assert_nothing_raised { DigestCalculator.verify!(StringIO.new(data), expected) }
  end

  test "verify! raises DigestMismatch when digest does not match" do
    err = assert_raises(Registry::DigestMismatch) do
      DigestCalculator.verify!(StringIO.new("hello"), "sha256:wrong")
    end
    assert_match(/digest mismatch/, err.message)
  end
end
