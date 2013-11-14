module UnitTestHelper
  def should_save(content, file)
    f = double(:file)
    expect(File).to receive(:open).with(file, "w").and_yield(f)
    expect(f).to receive(:puts).with(content)
  end
end

RSpec.configure { |c| c.include UnitTestHelper }
