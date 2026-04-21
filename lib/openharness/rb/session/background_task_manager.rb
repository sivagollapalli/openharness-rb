# frozen_string_literal: true

module Openharness
  module Rb
    module Session
      class BackgroundTaskManager
        def initialize
          @tasks = {}
          @outputs = {}
          @pids = {}
          @threads = {}
        end

        def start(name:, command:, cwd: Dir.pwd)
          raise DuplicateTaskError, name if @tasks.key?(name)

          @outputs[name] = +""

          read_out, write_out = IO.pipe
          read_err, write_err = IO.pipe

          pid = Process.spawn(
            command,
            chdir: cwd,
            out: write_out,
            err: write_err
          )

          write_out.close
          write_err.close

          @pids[name] = pid
          @tasks[name] = :running

          # Background thread to capture output
          @threads[name] = Thread.new do
            begin
              while (line = read_out.gets)
                @outputs[name] << line
              end
            rescue IOError
              # pipe closed
            ensure
              read_out.close unless read_out.closed?
            end
          end

          # Background thread to capture stderr
          Thread.new do
            begin
              while (line = read_err.gets)
                @outputs[name] << line
              end
            rescue IOError
              # pipe closed
            ensure
              read_err.close unless read_err.closed?
            end
          end

          # Monitor process completion
          Thread.new do
            Process.wait(pid)
            @tasks[name] = :stopped if @tasks.key?(name)
          rescue Errno::ECHILD
            # already reaped
          end

          name
        end

        def stop(name)
          raise TaskNotFoundError, name unless @tasks.key?(name)

          pid = @pids[name]
          if pid && @tasks[name] == :running
            begin
              Process.kill("TERM", pid)
              Process.wait(pid)
            rescue Errno::ESRCH, Errno::ECHILD
              # process already gone
            end
          end

          @tasks.delete(name)
          @pids.delete(name)
          @threads.delete(name)
          # Keep output available after stop? No — clean up fully.
          @outputs.delete(name)
        end

        def list
          @tasks.map { |name, status| { name: name, status: status } }
        end

        def output(name)
          raise TaskNotFoundError, name unless @tasks.key?(name)

          @outputs[name]
        end
      end
    end
  end
end
