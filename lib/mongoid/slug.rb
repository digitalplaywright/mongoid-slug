module Mongoid
  # Slugs your Mongoid model.
  module Slug
    extend ActiveSupport::Concern

    included do
      cattr_accessor :reserved_words,
                     :slug_scope,
                     :slugged_attributes,
                     :url_builder,
                     :history

      field :_slugs, type: Array, default: []
      alias_attribute :slugs, :_slugs
    end

    module ClassMethods


      # @overload slug(*fields)
      #   Sets one ore more fields as source of slug.
      #   @param [Array] fields One or more fields the slug should be based on.
      #   @yield If given, the block is used to build a custom slug.
      #
      # @overload slug(*fields, options)
      #   Sets one ore more fields as source of slug.
      #   @param [Array] fields One or more fields the slug should be based on.
      #   @param [Hash] options
      #   @param options [Boolean] :history Whether a history of changes to
      #   the slug should be retained. When searched by slug, the document now
      #   matches both past and present slugs.
      #   @param options [Boolean] :permanent Whether the slug should be
      #   immutable. Defaults to `false`.
      #   @param options [Array] :reserve` A list of reserved slugs
      #   @param options :scope [Symbol] a reference association or field to
      #   scope the slug by. Embedded documents are, by default, scoped by
      #   their parent.
      #   @yield If given, a block is used to build a slug.
      #
      # @example A custom builder
      #   class Person
      #     include Mongoid::Document
      #     include Mongoid::Slug
      #
      #     field :names, :type => Array
      #     slug :names do |doc|
      #       doc.names.join(' ')
      #     end
      #   end
      #
      def slug(*fields, &block)
        options = fields.extract_options!

        self.slug_scope         = options[:scope]
        self.reserved_words     = options[:reserve] || Set.new([:new, :edit])
        self.slugged_attributes = fields.map &:to_s
        self.history            = options[:history]

        if slug_scope
          scope_key = (metadata = self.reflect_on_association(slug_scope)) ? metadata.key : slug_scope
          index({scope_key => 1, _slugs: 1}, {unique: true})
        else
          index({_slugs: 1}, {unique: true})
        end

        #-- Why is it necessary to customize the slug builder?
        default_url_builder = lambda do |cur_object|
          cur_object.slug_builder.to_url
        end

        self.url_builder = block_given? ? block : default_url_builder

        #-- always create slug on create
        #-- do not create new slug on update if the slug is permanent
        if options[:permanent]
          set_callback :create, :before, :build_slug
        else
          set_callback :save, :before, :build_slug, :if => :slug_should_be_rebuilt?
        end


      end

      def look_like_slugs?(*args)
        with_default_scope.look_like_slugs?(*args)
      end



      # Find documents by slugs.
      #
      # A document matches if any of its slugs match one of the supplied params.
      #
      # A document matching multiple supplied params will be returned only once.
      #
      # If any supplied param does not match a document a Mongoid::Errors::DocumentNotFound will be raised.
      #
      # @example Find by a slug.
      #   Model.find_by_slug!('some-slug')
      #
      # @example Find by multiple slugs.
      #   Model.find_by_slug!('some-slug', 'some-other-slug')
      #
      # @param [ Array<Object> ] args The slugs to search for.
      #
      # @return [ Array<Document>, Document ] The matching document(s).
      def find_by_slug!(*args)
        with_default_scope.find_by_slug!(*args)
      end

      def queryable
        scope_stack.last || Criteria.new(self) # Use Mongoid::Slug::Criteria for slugged documents.
      end

    end

    # Builds a new slug.
    #
    # @return [true]
    def build_slug
      _new_slug = find_unique_slug
      self._slugs.delete(_new_slug)
      if self.history == true
        self._slugs << _new_slug
      else
        self._slugs = [_new_slug]
      end
      true
    end


    # Finds a unique slug, were specified string used to generate a slug.
    #
    # Returned slug will the same as the specified string when there are no
    # duplicates.
    #
    # @param [String] Desired slug
    # @return [String] A unique slug
    def find_unique_slug

      _slug = self.url_builder.call(self)

      # Regular expression that matches slug, slug-1, ... slug-n
      # If slug_name field was indexed, MongoDB will utilize that
      # index to match /^.../ pattern.
      pattern = /^#{Regexp.escape(_slug)}(?:-(\d+))?$/

      where_hash = {}
      where_hash[:_slugs.all] = [pattern]
      where_hash[:_id.ne]               = self._id

      if slug_scope && self.reflect_on_association(slug_scope).nil?
        # scope is not an association, so it's scoped to a local field
        # (e.g. an association id in a denormalized db design)
        where_hash[slug_scope]            = self.try(:read_attribute, slug_scope)

      end

      history_slugged_documents =
          uniqueness_scope.
              where(where_hash)

      existing_slugs = []
      existing_history_slugs = []
      last_entered_slug = []
      history_slugged_documents.each do |doc|
        history_slugs = doc._slugs
        next if history_slugs.nil?
        existing_slugs.push(*history_slugs.find_all { |cur_slug| cur_slug =~ pattern })
        last_entered_slug.push(*history_slugs.last) if history_slugs.last =~ pattern
        existing_history_slugs.push(*history_slugs.first(history_slugs.length() -1).find_all { |cur_slug| cur_slug =~ pattern })
      end

      #do not allow a slug that can be interpreted as the current document id
      existing_slugs << _slug unless self.class.look_like_slugs?([_slug])

      #make sure that the slug is not equal to a reserved word
      if reserved_words.any? { |word| word === _slug }
        existing_slugs << _slug
      end

      #only look for a new unique slug if the existing slugs contains the current slug
      # - e.g if the slug 'foo-2' is taken, but 'foo' is available, the user can use 'foo'.
      if existing_slugs.include? _slug
        # If the only conflict is in the history of a document in the same scope,
        # transfer the slug
        if slug_scope && last_entered_slug.count == 0 && existing_history_slugs.count > 0
          history_slugged_documents.each do |doc|
            doc._slugs -= existing_history_slugs
            doc.save
          end
          existing_slugs = []
        end

        if existing_slugs.count > 0
          # Sort the existing_slugs in increasing order by comparing the
          # suffix numbers:
          # slug, slug-1, slug-2, ..., slug-n
          existing_slugs.sort! do |a, b|
            (pattern.match(a)[1] || -1).to_i <=>
                (pattern.match(b)[1] || -1).to_i
          end
          max = existing_slugs.last.match(/-(\d+)$/).try(:[], 1).to_i

          _slug += "-#{max + 1}"
        end

      end

      _slug
    end


    # @return [Boolean] Whether the slug requires to be rebuilt
    def slug_should_be_rebuilt?
      new_record? or _slugs_changed? or slugged_attributes_changed?
    end

    def slugged_attributes_changed?
      slugged_attributes.any? { |f| attribute_changed? f.to_s }
    end

    # @return [String] A string which Action Pack uses for constructing an URL
    # to this record.
    def to_param
      unless _slugs.last
        build_slug
        save
      end

      _slugs.last
    end
    alias_method :slug, :to_param

    def slug_builder

      _cur_slug = nil
      if (new_record? and _slugs.present?) or (persisted? and _slugs_changed?)
        #user defined slug
        _cur_slug =  _slugs.last
      end

      #generate slug if the slug is not user defined or does not exist
      unless _cur_slug
        self.slugged_attributes.map { |f| self.send f }.join ' '
      else
        _cur_slug
      end
    end

    private

    def uniqueness_scope

      if slug_scope &&
          metadata = self.reflect_on_association(slug_scope)

        parent = self.send(metadata.name)

        # Make sure doc is actually associated with something, and that
        # some referenced docs have been persisted to the parent
        #
        # TODO: we need better reflection for reference associations,
        # like association_name instead of forcing collection_name here
        # -- maybe in the forthcoming Mongoid refactorings?
        inverse = metadata.inverse_of || collection_name
        return parent.respond_to?(inverse) ? parent.send(inverse) : self.class

      end

      if self.embedded?
        parent_metadata = reflect_on_all_associations(:embedded_in)[0]
        return self._parent.send(parent_metadata.inverse_of || self.metadata.name)
      end

      #unless embedded or slug scope, return the deepest document superclass
      appropriate_class = self.class
      while appropriate_class.superclass.include?(Mongoid::Document)
        appropriate_class = appropriate_class.superclass
      end
      appropriate_class

    end

  end
end

