module CF::ModelRelationships
  module ClassMethods
    def has_many(name, *args)
      singular = name.to_s.singularize

      define_method(:"#{singular}_guids") do
        send(name).collect(&:guid)
      end

      define_method(:"#{singular}_guids=") do |guids|
        reflection = reflections[name].klass
        send(:"#{name}=",
             guids.collect { |guid| reflection.find_by_guid(guid) })
      end

      define_method(:"add_#{singular}") do |x|
        objs = send(name)
        objs << x unless objs.include?(x)
        x
      end

      define_method(:"remove_#{singular}") do |x|
        send(name).delete(x)
      end

      super
    end

    def has_and_belongs_to_many(name, *args)
      singular = name.to_s.singularize

      define_method(:"#{singular}_guids") do
        send(name).collect(&:guid)
      end

      define_method(:"#{singular}_guids=") do |guids|
        reflection = reflections[name].klass
        send(:"#{name}=",
             guids.collect { |guid| reflection.find_by_guid(guid) })
      end

      define_method(:"add_#{singular}") do |x|
        objs = send(name)
        objs << x unless objs.include?(x)
        x
      end

      define_method(:"remove_#{singular}") do |x|
        send(name).delete(x)
      end

      super
    end

    def has_one(name, *args)
      define_method(:"#{name}_guid") do
        if val = send(name)
          val.guid
        end
      end

      super
    end

    def belongs_to(name, *args)
      define_method(:"#{name}_guid") do
        if val = send(name)
          val.guid
        end
      end

      define_method(:"#{name}_guid=") do |guid|
        reflection = reflections[name].klass
        send(:"#{name}=", reflection.find_by_guid(guid))
      end

      super
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end
end
