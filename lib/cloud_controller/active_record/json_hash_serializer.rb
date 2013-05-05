class CF::JsonHashSerializer
  def self.dump(hash)
    JSON.dump(hash)
  end

  def self.load(value)
    value ? JSON.load(value) : {}
  end
end