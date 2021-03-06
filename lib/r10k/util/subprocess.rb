require 'r10k/logging'
require 'r10k/errors'

module R10K
  module Util

    # The subprocess namespace implements a subset of childprocess. It has
    # three # main differences.
    #
    #   1. child processes invoke setsid()
    #   2. there are no dependencies on C extensions (ffi)
    #   3. it only support unixy systems.
    class Subprocess

      require 'r10k/util/subprocess/runner'
      require 'r10k/util/subprocess/io'
      require 'r10k/util/subprocess/result'

      include R10K::Logging

      attr_accessor :raise_on_fail
      attr_accessor :cwd

      attr_writer :logger

      def initialize(argv)
        @argv = argv

        @raise_on_fail = false
      end

      def execute
        subprocess = R10K::Util::Subprocess::Runner.new(@argv)
        subprocess.cwd = @cwd

        stdout_r, stdout_w = attach_pipe(subprocess.io, :stdout, :reader)
        stderr_r, stderr_w = attach_pipe(subprocess.io, :stderr, :reader)

        logmsg = "Execute: #{@argv.join(' ')}"
        logmsg << "(cwd: #{@cwd})" if @cwd
        logger.debug1 logmsg

        subprocess.start
        stdout_w.close
        stderr_w.close
        subprocess.wait

        stdout = stdout_r.read
        stderr = stderr_r.read

        result = Result.new(@argv, stdout, stderr, subprocess.exit_code)

        logger.debug2 "[#{result.cmd}] STDOUT: #{result.stdout.chomp}" unless result.stdout.empty?
        logger.debug2 "[#{result.cmd}] STDERR: #{result.stderr.chomp}" unless result.stderr.empty?

        if @raise_on_fail and subprocess.crashed?
          raise SubprocessError.new(:result => result)
        end

        result
      end

      private

      # Attach a pipe to the given process, and return the requested end of the
      # pipe.
      #
      # @param subproc [Runner]
      # @param name [Symbol] The name of the setter method on the subproc
      # @param type [Symbol] One of (:reader, :writer) denoting the type to return
      #
      # @return [Array<IO>] The reader and writer endpoints of the pipe
      def attach_pipe(subproc, name, type)
        rd, wr = ::IO.pipe

        case type
        when :reader
          other = wr
        when :writer
          other = rd
        end

        subproc.send("#{name}=", other)

        [rd, wr]
      end

      class SubprocessError < R10KError

        attr_reader :result

        def initialize(mesg = nil, options = {})
          super
          @result = @options[:result]
        end

        def to_s
          if @mesg
            @mesg
          else
            "Command #{@result.cmd} exited with #{@result.exit_code}: #{@result.stderr}"
          end
        end
      end
    end
  end
end
