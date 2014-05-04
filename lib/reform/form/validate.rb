# Mechanics for writing to forms in #validate.
module Reform
  class Form < Validation
  module Validate
    module Writer
      def from_hash(*)
        nested_forms do |attr|
          attr.delete(:prepare)
          attr.delete(:extend)

          attr.merge!(
            :collection => attr[:collection], # TODO: Def#merge! doesn't consider :collection if it's already set in attr YET.
            :parse_strategy => :sync, # just use nested objects as they are.
            :deserialize => lambda { |object, params, args|

              options = args.user_options.dup
              options[:prefix] = options[:prefix].dup # TODO: implement Options#dup.
              options[:prefix] << args.binding.name # FIXME: should be #as.

              # puts "======= user_options: #{args.user_options.inspect}"

              object.validate!(params, options)
            },
          )
        end

        super
      end
    end


    module Populator
      class PopulateIfEmpty
        def initialize(*args)
          @form, @fragment, args = args
          @index = args.first
          @args = args.last
        end

        def call
          binding = @args.binding
          form    = binding.get

          return if binding.array? and form and form[@index] # TODO: this should be handled by the Binding.
          return if !binding.array? and form
          # only get here when above form is nil.

          if binding[:populate_if_empty].is_a?(Proc)
            model = @form.instance_exec(@fragment, @args, &binding[:populate_if_empty]) # call user block.
          else
            model = binding[:populate_if_empty].new
          end

          form  = binding[:form].new(model) # free service: wrap model with Form. this usually happens in #setup.

          if binding.array?
            @form.model.send("#{binding.getter}") << model # FIXME: i don't like this, but we have to add the model to the parent object to make associating work. i have to use #<< to stay compatible with AR's has_many API. DISCUSS: what happens when we get out-of-sync here?
            @form.send("#{binding.getter}")[@index] = form
          else
            @form.model.send("#{binding.setter}", model) # FIXME: i don't like this, but we have to add the model to the parent object to make associating work.
            @form.send("#{binding.setter}", form) # :setter is currently overwritten by :parse_strategy.
          end
        end
      end


      def from_hash(params, *args)
        populated_attrs = []

        nested_forms do |attr|
          next unless attr[:populate_if_empty]

          attr.merge!(
            # DISCUSS: it would be cool to move the lambda block to PopulateIfEmpty#call.
            :populator => lambda do |fragment, *args|
              PopulateIfEmpty.new(self, fragment, args).call
            end
          )
        end


        nested_forms do |attr|
          next unless attr[:populator]

          attr.merge!(
            :parse_strategy => attr[:populator],
            :representable  => false
            )
          populated_attrs << attr.name.to_sym
        end

        super(params, {:include => populated_attrs})
      end
    end


    def errors
      @errors ||= Validation::Errors.new(self)
    end

    def validate(params)
      options = {:errors => errs = Validation::Errors.new(self), :prefix => []}

      validate!(params, options)

      self.errors = errs # if the AM valid? API wouldn't use a "global" variable this would be better.

      errors.valid?
    end


    def validate!(params, options)
      # puts "validate! in #{self.class.name}: #{params.inspect}"
      populate!(params)

      # populate nested properties
      # update attributes of forms (from_hash)
      # run validate(errors) for all forms (no 1-level limitation anymore)

      # here it would be cool to have a validator object containing the validation rules representer-like and then pass it the formed model.


      prefix = options[:prefix]

      # sets scalars and recurses #validate.
      mapper.new(self).extend(Writer).from_hash(params, options)

      res = valid?  # this validates on <Fields> using AM::Validations, currently.

      options[:errors].merge!(self.errors, prefix)
    end

  private


    def populate!(params)
      mapper.new(self).extend(Populator).from_hash(params)
    end

  end
end
end