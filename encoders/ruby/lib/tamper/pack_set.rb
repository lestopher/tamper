module Tamper
  class PackSet

    attr_accessor :meta, :existence_pack

    def initialize(opts={})
      @existence_pack = ExistencePack.new 
      @attr_packs = {}
      @buffered_attrs = {}
      @meta = opts
    end

    def add_attribute(opts)
      opts = opts.dup
      [:attr_name, :possibilities, :max_choices].each do |required_opt|
        raise ArgumentError, ":#{required_opt} is required when adding an attribute!" if !opts.key?(required_opt)
      end

      name          = opts.delete(:attr_name)
      possibilities = opts.delete(:possibilities).compact
      max_choices   = opts.delete(:max_choices)

      pack      = Pack.build(name, possibilities, max_choices)
      pack.meta = opts
      @attr_packs[name.to_sym] = pack
      pack
    end


    # Buffered attributes will not be packed, but their metadata will be included in the PackSet's JSON
    # representation.  Clients will expect these attrs to be available via the <tt>buffer_url</tt>.
    def add_buffered_attribute(opts)
      opts = opts.dup
      raise ArgumentError, ":attr_name is required when adding a buffered attribute!" if !opts.key?(:attr_name)

      attr_name   = opts.delete(:attr_name)
      @buffered_attrs[attr_name.to_sym] = { attr_name: attr_name }.merge(opts)
    end

    def attributes
      @attr_packs.keys
    end

    def pack_for(attr)
      @attr_packs[attr]
    end

    def pack!(data, opts={})
      opts = opts.dup
      opts[:guid_attr] ||= 'id'
      opts[:max_guid]  ||= (data.last[opts[:guid_attr].to_sym] || data.last[opts[:guid_attr].to_s])
      opts[:num_items] ||= data.length

      build_pack(opts) do |p|
        data.each { |d| p << d }
      end
    end

    def build_pack(opts={}, &block)
      guid_attr = opts[:guid_attr] || 'id'
      packs = @attr_packs.values
      max_guid  = opts[:max_guid]
      num_items = opts[:num_items]

      [:num_items, :max_guid].each do |required_opt|
        raise ArgumentError, "You must specify :#{required_opt} to start building a pack!" if !opts.key?(required_opt)
      end

      existence_pack.initialize_pack!(max_guid, num_items)
      packs.each { |p| p.initialize_pack!(max_guid, num_items) }

      idx = 0
      packer = ->(d) {
        guid = d[guid_attr.to_sym] || d[guid_attr.to_s]
        existence_pack.encode(guid)
        packs.each { |p| p.encode(idx, d) }
        idx += 1
      }
      packer.instance_eval { alias :<< :call; alias :add :call }

      yield(packer)

      existence_pack.finalize_pack!
      packs.each { |p| p.finalize_pack! }
    end

    def build_unordered_pack(opts={}, &block)
      guid_attr = opts[:guid_attr] || 'id'
      data = {}

      extractor = ->(d) {
        guid = d[guid_attr.to_sym] || d[guid_attr.to_s]
        data[guid] = d
      }
      extractor.instance_eval { alias :<< :call; alias :add :call }

      yield(extractor)

      sorted_guids = data.keys.sort
      sorted_data = sorted_guids.map { |guid| data[guid] }
      pack!(sorted_data, opts)
    end

    def to_hash(opts={})
      output = {
        version: '2.1',
        existence: @existence_pack.to_h,
        attributes: @attr_packs.values.map { |p| p.to_h }
      }

      output[:attributes] += @buffered_attrs.values
      output.merge!(meta)
      output
    end

    def to_json(opts={})
      Oj.dump self, { mode: :compat }
    end
  end
end
