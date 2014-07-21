require 'colored'

# Layout structure
module CLIntegracon
  module Adapter
  end
end

# Define concrete adapter
module CLIntegracon::Adapter::Bacon
  module Context

    # Get or set the subject
    #
    # @param  [Block<() -> Subject>]
    #         this block, if given, will be evaluated on current value for
    #         subject or it is not set on the current context itself.
    #         the return value will be set as subject.
    #
    # @return [Subject]
    #         the subject
    #
    def subject &block
      return @subject if block.nil?
      @subject = (@subject || self).instance_eval &block
    end

    # Get or configure the current context
    #
    # @param  [Block<() -> ()>]
    #         this block, if given, will be evaluated on the current context.
    #
    # @return [FileTreeSpecContext]
    #         the spec context, will be lazily created if not already present.
    #
    def context &block
      @context ||= CLIntegracon.shared_config.context.dup
      return @context if block.nil?
      @context.instance_eval &block
    end

    # Works like `behaves_like`, but takes arguments for the shared example
    #
    # @param [String] name
    #        name of the shared context.
    #
    # @param [...] args
    #        params to pass to the shared context
    #
    def behaves_like_a(name, *args)
      instance_exec(*args, &Bacon::Shared[name])
    end

    # Ad-hoc defines a set of shared expectations to be consumed directly by `behaves_like`.
    # See the following example for usage:
    #
    #   behaves_like cli_spec('my_spec_dir') do
    #     subject.launch()
    #   end
    #
    # @note    This expects that a method `context` is defined, which is returning an
    #          instance of {FileTreeSpecContext}.
    #
    # @param   [String] spec_dir
    #          the concrete directory of the spec, see {file_spec}.
    #
    # @param   [String] args
    #          the additional arguments to pass on launch to {CLIntegracon::Subject}.
    #
    # @return  [String]
    #          name of the set of shared expectations
    #
    def cli_spec(spec_dir, args)
      file_spec spec_dir do
        output = subject.launch(args)
        status = $?

        it "$ #{subject.name} #{args}" do
          status.should.satisfy("Binary failed\n\n#{output}") do
            status.success?
          end
        end
      end
    end

    # Ad-hoc defines a set of shared expectations to be consumed directly by `behaves_like`.
    # See the following example for usage:
    #
    #   behaves_like file_spec('my_spec_dir') do
    #     # do some changes to the current dir
    #   end
    #
    # @note    This expects that a method `context` is defined, which is returning an
    #          instance of {FileTreeSpecContext}.
    #
    # @param   [String] spec_dir
    #          the concrete directory of the spec to be passed to
    #          {FileTreeSpecContext.spec}
    #
    # @param   [Block<() -> ()>] block
    #          the block which will be executed after the before state is laid out in the
    #          temporary directory, which normally will make modifications to file system,
    #          which will be compare to the state given in the after directory.
    #
    # @return  [String]
    #          name of the set of shared expectations
    #
    def file_spec(spec_dir, &block)
      raise ArgumentError.new("Spec directory is missing!") if spec_dir.nil?

      shared_name = spec_dir

      shared shared_name do
        context.spec(spec_dir).run do |spec|
          instance_eval &block

          spec.compare do |diff|
            it diff.expected.to_s do
              description = []
              description << "Missing file:"
              description << "  * #{diff.expected.to_s.red}"

              diff.produced.should.satisfy(description * "\n") do
                diff.produced.exist?
              end

              description = []
              description << "File comparison error `#{diff.expected}`"
              description << ""
              description << diff.pretty_print

              diff.produced.should.satisfy(description * "\n") do
                diff.is_equal?
              end
            end
          end

          spec.check_unexpected_files do |files|
            it "should not produce unexpected files" do
              description = []
              description << "Unexpected files:"
              description += files.map { |f| "  * #{f.to_s.green}" }

              files.should.satisfy(description * "\n") do
                files.size == 0
              end
            end
          end
        end
      end

      shared_name
    end

  end

  # Describe a command line interface
  # This method basically behaves like {Bacon::Context.describe}, but it provides
  # automatically the methods #subject, #context, #cli_spec and #file_spec.
  #
  # @param  [String] subject_name
  #         the subject name will be used as first argument to initialize
  #         a new {CLIntegracon::Subject}, which will be accessible in the
  #         spec by #subject.
  #
  # @param  [Hash<Symbol,String>] context_options
  #         the options to configure this spec context, could be one or more of:
  #         * :executable: the executable used to initialize {CLIntegracon::Subject}
  #           if not given, will fallback to param {subject_name}.
  #
  # @param  [Block<() -> ()>] block
  #         the block to provide further sub-specs or requirements, as
  #         known from {Bacon::Context.describe}
  #
  def describe_cli(subject_name, context_options = {}, &block)
    describe subject_name do
      # Make Context methods available
      # WORKAROUND: Bacon auto-inherits singleton methods to child contexts
      # by using the runtime and won't include methods in modules included
      # by the parent context. We have to ensure that the methods will be
      # accessible by the child contexts by defining them as singleton methods.
      extended = self.extend Context
      Context.instance_methods.each do |method|
        class << self; self end.instance_eval do
          unbound_method = extended.method(method).unbind

          send :define_method, method do |*args, &block|
            unbound_method.bind(self).call(*args, &block)
          end
        end
      end

      subject do
        CLIntegracon::Subject.new(subject_name, context_options[:executable] || subject_name)
      end

      instance_eval &block
    end
  end

end

# Make #describe_cli global available
extend CLIntegracon::Adapter::Bacon

# Patch Bacon::Context to support #describe_cli
module Bacon
  class Context
    include CLIntegracon::Adapter::Bacon
  end
end
